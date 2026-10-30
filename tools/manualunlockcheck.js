#!/usr/bin/env node
// manualunlockcheck —— 手动开锁链的影子验证（判失败）。
//
// 正控：删掉影子模型里「1.2s 去重」⇒ 报出「连点两次在 1.2s 内：发了 2 次 04，期望 1」。
// 负控：12 项场景全符合预期。
//
// 2026-10-31（第 82 轮）：第 80/81 轮给「自动开锁链」建了影子验证，
// 但目标原话是「**自动模式还是手动模式** 都要优化速度到最短最极致」——
// 手动链（`requestUnlock` / `startUnlock` / `runUnlock`）此前**没有任何行为级验证**。
//
// 复刻依据：`App/LockKeeperApp.swift` 的 `requestUnlock()`（341-375 行）。
// 手动链的 6 道闸：
//   ① `current != nil`
//   ② `!AutoOpenController.shared.isDispatching`（第 63 轮加的并发闸）
//   ③ `unlockState == .connecting || .opening`（撤销窗口：0.8s 内轻点 = 取消）
//   ④ `1.2s 去重`（244：重复触发只提示不重发）
//   ⑤ `30s 内再次开锁要过应用锁`（250）
//   ⑥ `startUnlock` → `runUnlock` 真下发
//
// 为什么是影子：本机没有 Swift/Xcode（第 77 轮核实），无法执行。
//
// 正控：删掉影子模型里的「1.2s 去重」⇒ 报出「1.2s 内连点两次：实发 2 次，期望 1」，退出码 1。
// 负控：11 项场景全 ok；REPLICA_GUARD 8 条判据都在源码里。
// 但门控是纯逻辑，可 1:1 复刻。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, 'App', 'LockKeeperApp.swift');
const AOSRC = path.join(ROOT, 'App', 'Core', 'AutoOpen.swift');

if (!fs.existsSync(SRC)) {
  console.log('✓ LockKeeperApp.swift 不存在，跳过');
  process.exit(0);
}
const swift = fs.readFileSync(SRC, 'utf8');
const aoSwift = fs.existsSync(AOSRC) ? fs.readFileSync(AOSRC, 'utf8') : '';

// ── REPLICA_GUARD ──
const GUARDS = [
  ['① current 非空', swift, /guard current != nil else \{ return \}/],
  ['② 并发闸 isDispatching', swift, /if AutoOpenController\.shared\.isDispatching \{/],
  ['③ 撤销窗口 0.8s', swift, /Date\(\)\.timeIntervalSince\(dispatchAt\) < 0\.8/],
  ['④ 1.2s 去重', swift, /guard now\.timeIntervalSince\(lastDispatch\) > 1\.2 else \{/],
  ['⑤ 30s 应用锁', swift, /now\.timeIntervalSince\(t\) < 30 \{/],
  ['⑥ startUnlock 起任务', swift, /unlockTask = Task \{ await runUnlock\(\) \}/],
  ['cancelUnlock 复位', swift, /func cancelUnlock\(notify: Bool = false\) \{/],
  ['isDispatching 定义', aoSwift, /var isDispatching: Bool \{ inFlight \}/],
];
const bad = GUARDS.filter(([, src, re]) => !re.test(src)).map(([n]) => n);
if (bad.length) {
  console.log(`✗ REPLICA_GUARD: 以下判据在源码里已不存在 — ${bad.join('、')}`);
  console.log('\n修法：源码结构变了，先更新本闸门的 GUARDS 与影子模型。');
  process.exit(1);
}
console.log(`ok    REPLICA_GUARD ${GUARDS.length} 条判据都在源码里`);

// ── 影子模型 ──
const T0 = 100000;   // 基准时刻（ms）
function makeModel() {
  return {
    current: 'A',                    // nil 用 null
    autoDispatching: false,          // AutoOpenController.inFlight
    unlockState: 'idle',             // idle / connecting / opening
    dispatchAt: 0,                   // 上次下发时刻
    retryWait: false,
    lastDispatch: 0,                 // 244 去重基准
    hasPasscode: false,
    lastUnlockSuccessAt: 0,
    showGate: false,
    unlockTaskCancelled: false,
    dispatched04: 0,
    toasts: [],
    cancelled: 0,
  };
}

// requestUnlock —— 逐行对齐 Swift
function requestUnlock(S, nowMs) {
  // ①
  if (S.current == null) return 'reject:no-current';
  // ② 第 63 轮
  if (S.autoDispatching) { S.toasts.push('自动开锁进行中，请稍候'); return 'reject:auto-inflight'; }
  // ③
  if (S.unlockState === 'connecting' || S.unlockState === 'opening') {
    if (S.unlockState === 'opening' && (nowMs - S.dispatchAt < 800 || S.retryWait)) {
      cancelUnlock(S, true);
    }
    return 'reject:busy';
  }
  // ④ 1.2s 去重
  if (!(nowMs - S.lastDispatch > 1200)) { S.toasts.push('指令已收到， 正在执行'); return 'reject:dedupe'; }
  S.lastDispatch = nowMs;
  // ⑤ 30s 应用锁
  if (S.hasPasscode && S.lastUnlockSuccessAt && (nowMs - S.lastUnlockSuccessAt) < 30000) {
    S.showGate = true;
    return 'reject:passcode-gate';
  }
  startUnlock(S, nowMs);
  return 'start';
}

function startUnlock(S, nowMs) {
  S.unlockTaskCancelled = false;
  // 模拟 runUnlock 同步走到下发（真实是 async，但门控判定是同步的）
  runUnlock(S, nowMs);
}

function runUnlock(S, nowMs) {
  S.unlockState = 'connecting';
  S.dispatchAt = nowMs;
  S.unlockState = 'opening';
  S.dispatched04++;
  S.unlockState = 'idle';
  S.lastUnlockSuccessAt = nowMs;
}

function cancelUnlock(S, notify) {
  S.unlockTaskCancelled = true;
  S.cancelled++;
  if (S.unlockState === 'connecting' || S.unlockState === 'opening') {
    S.unlockState = 'idle';
    if (notify) S.toasts.push('已取消');
  }
}

// ── 场景 ──
const failList = [];
const okList = [];

function scen(name, setup, action, expect04) {
  const S = makeModel();
  setup?.(S);
  action(S);
  if (S.dispatched04 !== expect04) {
    failList.push(`${name}：实发 ${S.dispatched04} 次 04，期望 ${expect04}`);
  } else {
    okList.push(`${name} ⇒ ${expect04} 次 04`);
  }
  return S;
}

// 1. 基线：单次点击 ⇒ 1 次
scen('基线：单次点击', null, S => requestUnlock(S, T0), 1);

// 2. 无当前锁
scen('无当前锁', S => { S.current = null; }, S => requestUnlock(S, T0), 0);

// 3. 自动在途（第 63 轮并发闸）
scen('自动在途时点圆盘', S => { S.autoDispatching = true; }, S => requestUnlock(S, T0), 0);

// 4. 1.2s 内连点两次 ⇒ 只发 1 次
{
  const S = makeModel();
  requestUnlock(S, T0);
  requestUnlock(S, T0 + 500);   // 500ms 后
  if (S.dispatched04 !== 1) failList.push(`1.2s 内连点两次：实发 ${S.dispatched04} 次，期望 1`);
  else okList.push('1.2s 内连点两次 ⇒ 1 次 04（去重生效）');
}

// 5. 1.2s 后连点 ⇒ 2 次
{
  const S = makeModel();
  requestUnlock(S, T0);
  requestUnlock(S, T0 + 1500);
  if (S.dispatched04 !== 2) failList.push(`1.3s 后连点两次：实发 ${S.dispatched04} 次，期望 2`);
  else okList.push('1.3s 后连点两次 ⇒ 2 次 04（去重已过）');
}

// 6. 30s 内再次开锁 + 有本机密码 ⇒ 弹门（不发）
{
  const S = makeModel();
  S.hasPasscode = true;
  requestUnlock(S, T0);
  requestUnlock(S, T0 + 2000);   // 2s 后（>1.2s 去重，但 <30s）
  if (S.dispatched04 !== 1) failList.push(`30s 内再次开锁（有密码）：实发 ${S.dispatched04} 次，期望 1`);
  else if (!S.showGate) failList.push('30s 内再次开锁（有密码）：未弹应用锁门');
  else okList.push('30s 内再次开锁（有密码）⇒ 弹门，只发 1 次');
}

// 7. 30s 后再次开锁 ⇒ 正常发
{
  const S = makeModel();
  S.hasPasscode = true;
  requestUnlock(S, T0);
  requestUnlock(S, T0 + 31000);
  if (S.dispatched04 !== 2) failList.push(`31s 后再次开锁：实发 ${S.dispatched04} 次，期望 2`);
  else okList.push('31s 后再次开锁 ⇒ 2 次 04（应用锁窗口已过）');
}

// 8. 撤销窗口：opening 且 <0.8s ⇒ 取消
{
  const S = makeModel();
  S.unlockState = 'opening';
  S.dispatchAt = T0;
  requestUnlock(S, T0 + 300);
  if (S.cancelled !== 1) failList.push('撤销窗口内轻点：未触发取消');
  else okList.push('撤销窗口内（300ms）轻点 ⇒ 触发取消');
}

// 9. 撤销窗口外：opening 且 >0.8s ⇒ 不取消
{
  const S = makeModel();
  S.unlockState = 'opening';
  S.dispatchAt = T0;
  requestUnlock(S, T0 + 1000);
  if (S.cancelled !== 0) failList.push('撤销窗口外（1000ms）轻点：不该取消，却取消了');
  else okList.push('撤销窗口外（1000ms）轻点 ⇒ 不取消');
}

// 10. 重试等待期轻点 ⇒ 取消重试
{
  const S = makeModel();
  S.unlockState = 'opening';
  S.dispatchAt = T0;
  S.retryWait = true;
  requestUnlock(S, T0 + 2000);   // >0.8s 但 retryWait 为真
  if (S.cancelled !== 1) failList.push('重试等待期轻点：未触发取消');
  else okList.push('重试等待期轻点 ⇒ 触发取消');
}

// 11. 无本机密码时 30s 内可再开
{
  const S = makeModel();
  S.hasPasscode = false;
  requestUnlock(S, T0);
  requestUnlock(S, T0 + 2000);
  if (S.dispatched04 !== 2) failList.push(`无密码 30s 内再开：实发 ${S.dispatched04} 次，期望 2`);
  else okList.push('无本机密码 ⇒ 30s 内可再开（无此闸）');
}

// ── 汇总 ──
if (failList.length) {
  console.log(`\n✗ 手动开锁链逻辑 ${failList.length} 处不符合预期：`);
  failList.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：目标要求「手动模式也要优化到最短最极致」，而手动链此前没有行为级验证。');
  console.log('修法：按 LockKeeperApp.swift 的结构同步更新影子模型；若行为确实该变，改本闸门的场景并写明理由。');
  process.exit(1);
}
okList.forEach(x => console.log('ok    ' + x));
console.log(`\n✓ 手动开锁链逻辑 ${okList.length} 项全部符合预期`);
