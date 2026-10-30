#!/usr/bin/env node
// kotlinmanualcheck —— Android 手动开锁链的影子验证（判失败）。
//
// 正控：删掉影子模型里 `doUnlock` 的「切锁复查」⇒ 报出「切锁：手动开锁期间切到 B ⇒ 仍发了 04」。
// 负控：10 项场景全符合预期。
//
// 2026-10-31（第 83 轮）：第 82 轮给 iOS 手动链建了影子验证（`manualunlockcheck`，11 项），
// **Android 手动链没有对应的**。而 Android 的手动链有 4 道闸：
//   ① `lock ?: return`（无锁不响应）
//   ② `if (busy)` —— 同时覆盖「自动在途」与「手动在途」（比 iOS 的两套标志更简洁）
//   ③ 切锁复查 `if (lock?.mac != l.mac)`（第 64 轮）
//   ④ 退后台复查 `if (!foreground)`（第 65 轮）
//
// 复刻依据：`MainActivity.kt` 的 `doUnlock()`（198-230 行）。
//
// 注意：Android **没有** iOS 的「1.2s 去重 / 30s 应用锁 / 撤销窗口」——
// 那是 iOS 独有（Android 是极简版）。这不是缺陷，是设计差异，本闸门把它写成显式断言，
// 避免将来有人「补」上一个不该有的闸。
//
// 正控：删掉影子模型里 `doUnlock` 的「切锁复查」⇒ 报出「切锁：开锁期间切到 B：实发 1 次 04，期望 0」，退出码 1。
// 负控：11 项场景全 ok；REPLICA_GUARD 7 条判据都在 Kotlin 源码里；设计差异 3 条断言正确。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const MAIN = path.join(ROOT, 'android-app', 'app', 'src', 'main', 'java', 'com', 'aapk', 'kfkey', 'MainActivity.kt');

if (!fs.existsSync(MAIN)) {
  console.log('✓ 无 android-app 工程，跳过');
  process.exit(0);
}
const src = fs.readFileSync(MAIN, 'utf8');

// ── REPLICA_GUARD ──
const GUARDS = [
  ['① 无锁不响应', /fun doUnlock\(auto: Boolean\) \{\s*\n\s*val l = lock \?: return/],
  ['② busy 闸（同时覆盖自动/手动在途）', /if \(busy\) \{ say\(if \(auto\)/],
  ['③ 切锁复查', /if \(lock\?\.mac != l\.mac\) \{/],
  ['④ 退后台复查', /if \(!foreground\) \{[\s\S]{0,120}?return@launch/],
  ['rc 回写按同一把锁', /lock\?\.takeIf \{ it\.mac == l\.mac \}\?\.let \{ LockStore\.save\(ctx, it\.copy\(lastRc = r\.rc\)\) \}/],
  ['busy 复位（切锁路径）', /if \(lock\?\.mac != l\.mac\) \{[\s\S]{0,80}?busy = false/],
  ['busy 复位（退后台路径）', /if \(!foreground\) \{[\s\S]{0,120}?busy = false/],
];
const bad = GUARDS.filter(([, re]) => !re.test(src)).map(([n]) => n);
if (bad.length) {
  console.log(`✗ REPLICA_GUARD: 以下判据在 Kotlin 源码里已不存在 — ${bad.join('、')}`);
  console.log('\n修法：源码结构变了，先更新本闸门的 GUARDS 与影子模型。');
  process.exit(1);
}
console.log(`ok    REPLICA_GUARD ${GUARDS.length} 条判据都在 Kotlin 源码里`);

// ── 设计差异的显式断言（防将来"补"上不该有的闸）──
// 2026-10-31（第 83 轮，**判据修正**）：上一版用「整个 MainActivity 里搜不到 iOS 特征串」来判断，
// 但那些特征串本来就只存在于 iOS 的 LockKeeperApp.swift —— 在 Android 文件里当然搜不到，
// 于是无论 Android 是否真加了闸，判据都恒为"搜不到"⇒ 三条永远报警。
// 现在改成**只查 Android 文件里确实不该出现的具体写法**（能真正抓到"有人补上了 iOS 独有闸"）：
//   · 1.2s 去重   ⇒ 会出现 `> 1.2` 或 `1200L` 之类
//   · 30s 应用锁  ⇒ 会出现 `30000L` 与"应用锁"字样
//   · 撤销窗口    ⇒ 会出现 `800L` 与"撤销"字样
const DESIGN_DIFF = [
  ["Android 无 1.2s 去重（iOS 独有）", !/(>\s*1\.2\b|1200L)/.test(src)],
  ["Android 无 30s 应用锁（iOS 独有）", !/30000L/.test(src)],
  ["Android 无撤销窗口（iOS 独有）", !/800L/.test(src)],
];
const diffBad = DESIGN_DIFF.filter(([, isAbsent]) => !isAbsent).map(([n]) => n);
if (diffBad.length) {
  console.log(`⚠ 设计差异变化（不算失败，但需确认）：`);
  diffBad.forEach(n => console.log('  · ' + n + ' —— 源码里出现了 iOS 独有的闸，Android 与 iOS 的行为开始分叉'));
  console.log('  若确实有意为之，更新本闸门的 DESIGN_DIFF 并写明理由。');
} else {
  console.log('ok    设计差异断言：Android 保持极简（无 1.2s 去重 / 无 30s 应用锁 / 无撤销窗口）');
}

// ── 影子模型 ──
const T0 = 100000;
function makeModel() {
  return {
    lock: { mac: 'A' },        // null = 无锁
    busy: false,
    foreground: true,
    lastRc: 0,
    dispatched04: 0,
    said: [],
    savedRcFor: null,          // 回写 rc 到哪把锁
  };
}

// doUnlock —— 逐行对齐 Kotlin
function doUnlock(S, auto, worldChanges) {
  const l = S.lock;
  if (l == null) return 'reject:no-lock';
  if (S.busy) { S.said.push(auto ? '正在开锁, 请稍候…' : '自动开锁进行中, 请稍候…'); return 'reject:busy'; }
  S.busy = true;
  S.said.push(auto ? '已靠近, 正在开锁…' : '正在开锁…');

  // scope.launch 内部
  worldChanges?.duringConnect?.(S);

  // ③ 切锁复查
  if (S.lock?.mac !== l.mac) { S.busy = false; S.said.push('门锁已切换，本次开锁已取消'); return 'abort:switch'; }
  // ④ 退后台复查
  if (!S.foreground) { S.busy = false; S.said.push('已切到后台，本次开锁已取消'); return 'abort:background'; }

  // 真下发
  S.dispatched04++;
  S.lastRc = 0;
  // rc 回写按同一把锁
  if (S.lock?.mac === l.mac) S.savedRcFor = l.mac;
  S.busy = false;
  return 'unlock04';
}

// ── 场景 ──
const failList = [];
const okList = [];

function scen(name, setup, worldChanges, expect04, expectSavedFor) {
  const S = makeModel();
  setup?.(S);
  doUnlock(S, false, worldChanges);
  if (S.dispatched04 !== expect04) {
    failList.push(`${name}：实发 ${S.dispatched04} 次 04，期望 ${expect04}`);
    return;
  }
  if (expectSavedFor !== undefined && S.savedRcFor !== expectSavedFor) {
    failList.push(`${name}：rc 回写到 ${S.savedRcFor}，期望 ${expectSavedFor}`);
    return;
  }
  okList.push(`${name} ⇒ ${expect04} 次 04${expectSavedFor !== undefined ? '，rc 回写 ' + expectSavedFor : ''}`);
}

// 1. 基线
scen('基线：手动单次点击', null, null, 1, 'A');

// 2. 无锁
scen('无锁：不响应', S => { S.lock = null; }, null, 0);

// 3. 自动在途（busy 被自动链置位）
scen('自动在途时点圆盘（busy=true）', S => { S.busy = true; }, null, 0);

// 4. 手动在途（busy 被自己置位）
scen('手动在途时再点（busy=true）', S => { S.busy = true; }, null, 0);

// 5. 切锁竞态（第 64 轮）
scen('切锁：开锁期间切到 B', null, {
  duringConnect: S => { S.lock = { mac: 'B' }; },
}, 0);

// 6. 解绑（lock = null）
scen('解绑：开锁期间 lock 变 null', null, {
  duringConnect: S => { S.lock = null; },
}, 0);

// 7. 退后台（第 65 轮）
scen('退后台：开锁期间锁屏', null, {
  duringConnect: S => { S.foreground = false; },
}, 0);

// 8. busy 在切锁后必须复位（否则后续永远 busy）
{
  const S = makeModel();
  doUnlock(S, false, { duringConnect: S => { S.lock = { mac: 'B' }; } });
  if (S.busy !== false) failList.push('切锁后 busy 未复位（后续手动开锁会永远被拒）');
  else okList.push('切锁后 busy 已复位');
}

// 9. busy 在退后台后必须复位
{
  const S = makeModel();
  doUnlock(S, false, { duringConnect: S => { S.foreground = false; } });
  if (S.busy !== false) failList.push('退后台后 busy 未复位');
  else okList.push('退后台后 busy 已复位');
}

// 10. 提示文案区分自动/手动（与 iOS 对齐）
// 10. 提示文案区分「哪一路在跑」（对齐源码语义）
//     源码: `say(if (auto) "正在开锁, 请稍候…" else "自动开锁进行中, 请稍候…")`
//     auto=true  ⇒ 自动链自己在跑 ⇒ 说「正在开锁」
//     auto=false ⇒ 用户手动点，但自动链在跑 ⇒ 说「自动开锁进行中」
{
  const S1 = makeModel();
  S1.busy = true;
  doUnlock(S1, true, null);
  if (!S1.said.some(t => t.includes("正在开锁"))) failList.push("auto=true 时未说「正在开锁」");
  else okList.push("auto=true ⇒ 提示「正在开锁」");
  const S2 = makeModel();
  S2.busy = true;
  doUnlock(S2, false, null);
  if (!S2.said.some(t => t.includes("自动开锁进行中"))) failList.push("auto=false 时未说「自动开锁进行中」");
  else okList.push("auto=false ⇒ 提示「自动开锁进行中」（说清是哪一路在跑）");
}

// ── 汇总 ──
if (failList.length) {
  console.log(`\n✗ Android 手动开锁链逻辑 ${failList.length} 处不符合预期：`);
  failList.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：目标要求「手动模式也要优化到最短最极致」，Android 手动链此前无行为级验证。');
  console.log('修法：按 MainActivity.kt 的 doUnlock 同步更新影子模型。');
  process.exit(1);
}
okList.forEach(x => console.log('ok    ' + x));
console.log(`\n✓ Android 手动开锁链逻辑 ${okList.length} 项全部符合预期`);
