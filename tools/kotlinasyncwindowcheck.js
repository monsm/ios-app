#!/usr/bin/env node
// kotlinasyncwindowcheck —— Android 门控逻辑的影子验证（判失败）。
//
// 正控：把影子模型里「退后台复查」删掉 ⇒ 报出「退后台场景仍发了 04」。
// 负控：6 场景 + F4 布防 3 个时段 + F5 跨重启 + F6 3 个 rc 全符合预期。
//
// 2026-10-31（第 81 轮）：第 80 轮给 iOS 建了影子验证（`asyncwindowcheck`），
// Android 侧**没有对应的**。而 Android 的门控同样有 7 道：
//   F0 前台（`!foreground` 提前 return）
//   F3 距离（`rssiArmedByMedian` 中值武装 + 回差解除）
//   F4 布防（时段内否决）
//   F5 冷却（`coolReady`，第 53 轮改成跨重启持久化）
//   F6 锁态（`lastRc == 25/26` 拒）
//   一次性闩锁（`fired`，走远 3dB 才放开）
//   并发（`busy`）
//
// 复刻依据：`MainActivity.kt` 的 `maybeAutoUnlock()`（329-390 行）。
//
// 为什么是影子：本机没有 JDK/Kotlin/Android SDK（第 77 轮核实），无法执行 Kotlin。
// 但门控是纯逻辑，可 1:1 复刻。
//
// 正控：删掉影子模型里 `doUnlock` 的「退后台复查」⇒ 报出
//       「退后台：建连期间锁屏：实发 1 次 04，期望 0」，退出码 1。
// 负控：17 项（11 场景 + F5 跨重启 + 5 个 F4 时段）全 ok；REPLICA_GUARD 15 条判据都在源码里。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const MAIN = path.join(ROOT, 'android-app', 'app', 'src', 'main', 'java', 'com', 'aapk', 'kfkey', 'MainActivity.kt');
const KIT = path.join(ROOT, 'android-app', 'app', 'src', 'main', 'java', 'com', 'aapk', 'kfkey', 'AutoOpenKit.kt');

if (!fs.existsSync(MAIN) || !fs.existsSync(KIT)) {
  console.log('✓ 无 android-app 工程，跳过');
  process.exit(0);
}

// ── REPLICA_GUARD：确认复刻的判据在 Kotlin 源码里确实存在 ──
const mainSrc = fs.readFileSync(MAIN, 'utf8');
const kitSrc = fs.readFileSync(KIT, 'utf8');
const GUARDS = [
  ['F0 前台', mainSrc, /if \(!foreground\) return/],
  ['F3 中值武装', mainSrc, /armed = AutoOpenKit\.rssiArmedByMedian\(/],
  ['F3 走远解除（基准一致）', mainSrc, /if \(r < AutoOpenKit\.disarmThreshold\(armBase\) - 3\) \{ fired = false \}/],
  ['F4 布防时段', mainSrc, /val inWindow = if \(st <= en\) hour in st until en else \(hour >= st \|\| hour < en\)/],
  ['F5 冷却', mainSrc, /if \(!AutoOpenKit\.coolReady\(lastAuto, now\)\) return/],
  ['F5 持久化落盘', mainSrc, /LockStore\.save\(ctx, l\.copy\(lastAutoMs = now\)\)/],
  ['F5 初值读回', mainSrc, /mutableStateOf\(lock\?\.lastAutoMs \?: 0L\)/],
  ['F6 rc=25', mainSrc, /if \(lastRc == 25\) \{/],
  ['F6 rc=26', mainSrc, /if \(lastRc == 26\) \{/],
  ['并发 busy', mainSrc, /if \(busy\) return/],
  ['退后台取消在途', mainSrc, /if \(!foreground\) \{[\s\S]{0,120}?return@launch/],
  ['切锁竞态', mainSrc, /if \(lock\?\.mac != l\.mac\) \{/],
  ['coolReady 定义', kitSrc, /fun coolReady\(/],
  ['rssiBase 标定', kitSrc, /fun rssiBase\(/],
  ['disarmThreshold 定义', kitSrc, /fun disarmThreshold\(/],
];
const guardBad = GUARDS.filter(([, src, re]) => !re.test(src)).map(([n]) => n);
if (guardBad.length) {
  console.log(`✗ REPLICA_GUARD: 以下判据在 Kotlin 源码里已不存在 — ${guardBad.join('、')}`);
  console.log('\n修法：源码结构变了，先更新本闸门的 GUARDS 与影子模型。');
  process.exit(1);
}
console.log(`ok    REPLICA_GUARD ${GUARDS.length} 条判据都在 Kotlin 源码里`);

// ── 复刻 AutoOpenKit 的纯函数（对齐源码）──
const BASE = -40;
const rssiBase = (p95) => p95 !== 0 ? Math.round(p95) : BASE;
const disarmThreshold = (base) => Math.round(base + 10 * Math.log10(0.5));
const COOLDOWN_MS = 6000;

// 中值武装（对齐 rssiArmedByMedian：>=3 样本取中值，否则单样本）
function rssiArmedByMedian(prevArmed, history, base) {
  if (history.length >= 3) {
    const s = [...history].sort((a, b) => a - b);
    const med = s[Math.floor(s.length / 2)];
    if (!prevArmed) return med >= base;
    return med >= disarmThreshold(base);
  }
  const r = history[0];
  return prevArmed ? r >= disarmThreshold(base) : r >= base;
}

const coolReady = (lastAuto, now) => lastAuto === 0 || now - lastAuto > COOLDOWN_MS;

// 布防时段（对齐源码的 inWindow）
function inDefendWindow(hour, st, en) {
  return st <= en ? (hour >= st && hour < en) : (hour >= st || hour < en);
}

// ── 影子状态机（对齐 maybeAutoUnlock + doUnlock）──
const now = () => 10000;
function makeModel() {
  return {
    foreground: true, busy: false, warming: false, prewarmStarted: false,
    armed: false, fired: false, lastAuto: 0, persistedLastAuto: 0,
    lastRc: 0, rssiP95: 0, defendOn: false, defendStartHour: 22, defendEndHour: 7,
    hour: 12, rssiHistory: [], lock: { mac: 'A', rssiP95: 0, lastAutoMs: 0 },
    dispatched04: 0, connectAttempts: 0, rejects: [], weakRssi: -70, feedRssi: -35,
  };
}

function maybeAutoUnlock(S, r) {
  if (!S.foreground) return 'skip:f0';
  // 预热（不影响 04 判定）
  const base = rssiBase(S.lock?.rssiP95 ?? 0);
  const prewarmLine = base - 24;
  if (!S.prewarmStarted && !S.busy && !S.warming && r >= prewarmLine && S.lock != null) S.prewarmStarted = true;
  // 中值武装
  S.rssiHistory.unshift(r);
  while (S.rssiHistory.length > 3) S.rssiHistory.pop();
  S.armed = rssiArmedByMedian(S.armed, S.rssiHistory, base);
  if (!S.armed) S.prewarmStarted = false;
  if (r < disarmThreshold(base) - 3) S.fired = false;
  if (!S.armed || S.fired) return 'skip:f3-or-latch';
  // F4
  if (S.lock?.defendOn) {
    const st = S.lock.defendStartHour ?? 22, en = S.lock.defendEndHour ?? 7;
    if (inDefendWindow(S.hour, st, en)) { S.rejects.push('F4'); return 'skip:f4'; }
  }
  // F6
  if (S.lastRc === 25) { S.rejects.push('F6-25'); return 'skip:f6'; }
  if (S.lastRc === 26) { S.rejects.push('F6-26'); return 'skip:f6'; }
  // F5 冷却（内存 + 落盘回落）
  const last = S.lastAuto !== 0 ? S.lastAuto : S.persistedLastAuto;
  if (!coolReady(last, now())) { S.rejects.push('F5'); return 'skip:f5'; }
  if (S.busy) return 'skip:busy';
  // 采纳
  S.fired = true;
  S.lastAuto = now();
  S.persistedLastAuto = now();
  S.lock.lastAutoMs = now();
  return 'dispatch';
}

function doUnlock(S, worldChanges) {
  const l = S.lock;
  S.busy = true;
  worldChanges?.duringConnect?.(S);
  // 切锁复查（64 轮）
  if (S.lock?.mac !== l.mac) { S.busy = false; return 'abort:switch'; }
  // 退后台复查（65 轮）
  if (!S.foreground) { S.busy = false; return 'abort:background'; }
  S.connectAttempts++;
  if (worldChanges?.connectFails) { S.busy = false; return 'abort:connect'; }
  S.dispatched04++;
  S.busy = false;
  return 'unlock04';
}

// ── 场景 ──
const bad = [];
const okList = [];

function scenario(name, setup, worldChanges, expect04) {
  const S = makeModel();
  setup(S);
  // 2026-10-31（第 81 轮，场景驱动）：
  // 单样本路径下**第 1 个强样本就会武装并下发**，所以不能在循环里只记最后一步 ——
  // 那样 `doUnlock` 永远不会被调（前两次已把 `fired` 置位）。
  // 正确做法：循环里一旦某步返回 dispatch，立刻调 doUnlock 并停止。
  let step = "skip";
  for (let i = 0; i < 3; i++) {
    step = maybeAutoUnlock(S, S.feedRssi);
    if (step === "dispatch") { doUnlock(S, worldChanges); break; }
  }
  if (S.dispatched04 !== expect04) {
    bad.push(name + "：实发 " + S.dispatched04 + " 次 04，期望 " + expect04 + "（step=" + step + "）");
  } else {
    okList.push(name + " ⇒ " + expect04 + " 次 04");
  }
}

// 1. 基线：站门口信号达标 ⇒ 应发 1 次
scenario('基线（前台 + 信号达标）', S => { S.feedRssi = -35; }, null, 1);

// 2. F0 后台
scenario('后台：不判定', S => { S.foreground = false; S.feedRssi = -35; }, null, 0);

// 3. F3 信号不足
scenario('信号不足（-60 < 武装线 -40）', S => { S.feedRssi = -60; }, null, 0);

// 4. F4 布防时段内
scenario('布防时段内（22-07，当前 23 点）', S => {
  S.feedRssi = -35; S.lock.defendOn = true; S.hour = 23;
}, null, 0);

// 5. F4 布防时段外
scenario('布防时段外（22-07，当前 12 点）', S => {
  S.feedRssi = -35; S.lock.defendOn = true; S.hour = 12;
}, null, 1);

// 6. F6 rc=25
scenario('F6 rc=25（锁忙）', S => { S.feedRssi = -35; S.lastRc = 25; }, null, 0);

// 7. F6 rc=26
scenario('F6 rc=26（被撬）', S => { S.feedRssi = -35; S.lastRc = 26; }, null, 0);

// 8. 并发 busy
scenario('并发：busy 为真', S => { S.feedRssi = -35; S.busy = true; }, null, 0);

// 9. 切锁竞态
scenario('切锁：建连期间切到 B', S => { S.feedRssi = -35; }, {
  duringConnect: S => { S.lock = { ...S.lock, mac: 'B' }; },
}, 0);

// 10. 退后台（建连期间）
scenario('退后台：建连期间锁屏', S => { S.feedRssi = -35; }, {
  duringConnect: S => { S.foreground = false; },
}, 0);

// 11. 建连失败
scenario('建连失败', S => { S.feedRssi = -35; }, { connectFails: true }, 0);

// ── F5 跨重启 ──
{
  const S = makeModel();
  S.feedRssi = -35;
  for (let i = 0; i < 3; i++) maybeAutoUnlock(S, S.feedRssi);
  maybeAutoUnlock(S, S.feedRssi);
  doUnlock(S, null);
  // App 被杀：内存清零，落盘保留
  S.lastAuto = 0; S.fired = false; S.busy = false; S.rssiHistory = [];
  const last = S.persistedLastAuto;
  const ready = coolReady(last, now());
  if (ready) bad.push('F5 跨重启：冷却未生效（会立刻双开）');
  else okList.push('F5 跨重启：冷却生效（不双开）');
}

// ── F4 时段边界 ──
for (const [st, en, h, want] of [[22, 7, 23, true], [22, 7, 3, true], [22, 7, 12, false], [8, 20, 10, true], [8, 20, 21, false]]) {
  const got = inDefendWindow(h, st, en);
  if (got !== want) bad.push(`F4 时段 ${st}-${en} @${h}点：${got}，期望 ${want}`);
  else okList.push(`F4 时段 ${st}-${en} @${h}点 ⇒ ${got}`);
}

// ── 汇总 ──
if (bad.length) {
  console.log(`\n✗ Android 门控逻辑 ${bad.length} 处不符合预期：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：门控若只验证"代码存在"，改坏逻辑也不会被发现。');
  console.log('修法：按 MainActivity.kt 的结构同步更新影子模型；若行为确实该变，改本闸门的 CASES 并写明理由。');
  process.exit(1);
}
okList.forEach(x => console.log('ok    ' + x));
console.log(`\n✓ Android 门控逻辑 ${okList.length} 项全部符合预期`);
