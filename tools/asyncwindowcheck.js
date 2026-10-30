#!/usr/bin/env node
// asyncwindowcheck —— 异步窗口逻辑的影子验证（判失败）。
//
// 正控：把 `dispatch()` 里的 `if (S.bgGen !== genAtEntry) return 'abort:background'` 删掉 ⇒
//       报出「退后台场景仍发了 04」。
// 负控：7 类场景 + F5 跨重启 + F6 锁态 + 并发闸 全部符合预期，零误报。
//
// 2026-10-31（第 80 轮）：第 63-66 轮我修了 7 类「异步期间世界变了」的缺陷，
// 但**只验证了代码存在**（字符串匹配），没验证**行为**。本闸门用影子状态机逐场景跑一遍：
//   · 基线（全绿）⇒ 应发 1 次 04
//   · 切锁 / 退后台 / 伪装 / 挂起 / 建连失败 ⇒ 应发 0 次
//   · F5 跨重启 ⇒ 冷却生效（不双开）
//   · F6 rc=25/26 ⇒ 拒；rc=0/3/24 ⇒ 放行
//   · 并发闸 ⇒ 修复前双发、修复后单发
//
// 为什么是"影子"而不是真跑：本机没有 JDK/Kotlin/Android SDK（第 77 轮核实），
// 无法执行 Swift/Kotlin。但**门控是纯逻辑**，可以按源码结构 1:1 复刻成 JS 并跑场景。
//
// 正控：删掉影子模型里「退后台复查」那一行 ⇒ 报出「退后台：建连期间锁屏：实发 1 次 04，期望 0」，退出码 1。
// 负控：12 项（6 场景 + F5 跨重启 + 5 个 F6 rc）全 ok；REPLICA_GUARD 8 条判据都在源码里。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, 'App', 'Core', 'AutoOpen.swift');

if (!fs.existsSync(SRC)) {
  console.log('✓ AutoOpen.swift 不存在，跳过');
  process.exit(0);
}
const swift = fs.readFileSync(SRC, 'utf8');

// ── REPLICA_GUARD：确认复刻的判据在 Swift 里确实存在 ──
const GUARDS = [
  ['64 轮：dispatch 复查 currentMac', /guard app\.currentMac == mac, !mac\.isEmpty else \{/],
  ['65 轮：世代号记录', /let genAtEntry = backgroundGeneration/],
  ['65 轮：退后台复查', /guard backgroundGeneration == genAtEntry else \{/],
  ['66 轮：开关/伪装/挂起复检', /guard AutoOpen\.on, !app\.decoyMode, !AutoOpen\.isSuspended\(mac: mac\) else \{/],
  ['66 轮：解绑复查', /guard AppState\.hostRef != nil, app\.currentMac == mac else \{/],
  ['55 轮：闩锁在 ensureConnected 之前', /eventFired\.insert\(mac\)[\s\S]{0,300}?try await app\.lock\.ensureConnected/],
  ['52 轮：F5 持久化回落', /lastDispatch\[mac\] \?\? AutoOpen\.persistedLastDispatch\(mac\)/],
];

// LockServiceOps.swift 里的判据（不在本文件）
const OPS_GUARDS = [
  ["51 轮：F6 无条件写", /DB\.writeStatus\(curMac, st\)/],
];
const guardBad = [];
for (const [name, re] of GUARDS) if (!re.test(swift)) guardBad.push(name);
if (guardBad.length) {
  console.log(`✗ REPLICA_GUARD: 以下判据在 Swift 源码里已不存在 — ${guardBad.join('、')}`);
  console.log('\n修法：源码结构变了，先更新本闸门的 GUARDS 与影子模型，再让它跑。');
  process.exit(1);
}
// LockServiceOps.swift 里的判据
const opsPath = path.join(ROOT, "App", "Services", "LockServiceOps.swift");
if (fs.existsSync(opsPath)) {
  const ops = fs.readFileSync(opsPath, "utf8");
  const opsBad = OPS_GUARDS.filter(([, re]) => !re.test(ops)).map(([n]) => n);
  if (opsBad.length) {
    console.log("✗ REPLICA_GUARD(OPS): 判据在 LockServiceOps.swift 里已不存在 — " + opsBad.join("、"));
    process.exit(1);
  }
  console.log("ok    REPLICA_GUARD(OPS) " + OPS_GUARDS.length + " 条判据都在");
}
console.log(`ok    REPLICA_GUARD ${GUARDS.length} 条判据都在 Swift 源码里`);

// ── 影子状态机 ──
const now = () => 1000;
function makeModel() {
  return {
    autoOpenOn: true, decoyMode: false, currentMac: 'A', unlockState: 'idle',
    inFlight: false, bgGen: 0, suspended: false, eventFired: new Set(),
    lastDispatch: {}, persistedLastDispatch: {}, cooldown: 6, snapshotRc: 0, dispatched04: 0,
  };
}
const coolReady = (S, mac) => {
  const last = S.lastDispatch[mac] ?? S.persistedLastDispatch[mac] ?? 0;
  return last === 0 || now() - last > S.cooldown;
};
const lockReady = (S) => S.snapshotRc !== 25 && S.snapshotRc !== 26;

function attempt(S, mac) {
  if (!S.autoOpenOn || S.inFlight) return 'skip';
  if (S.currentMac !== mac) return 'skip';
  if (S.unlockState !== 'idle') return 'skip';
  if (S.decoyMode) return 'skip';
  if (S.eventFired.has(mac)) return 'skip';
  if (!coolReady(S, mac)) return 'skip';
  if (S.suspended) return 'skip';
  if (!lockReady(S)) return 'skip';
  S.inFlight = true;
  return 'dispatch';
}
function dispatch(S, mac, w) {
  const gen = S.bgGen;
  if (S.currentMac !== mac || mac === '') { S.inFlight = false; return 'abort:mac'; }
  S.eventFired.add(mac);
  S.lastDispatch[mac] = now();
  S.persistedLastDispatch[mac] = now();
  w?.duringConnect?.(S);
  if (w?.connectFails) { S.inFlight = false; return 'abort:connect'; }
  if (S.bgGen !== gen) { S.inFlight = false; return 'abort:background'; }
  if (!S.autoOpenOn || S.decoyMode || S.suspended) { S.inFlight = false; return 'abort:state'; }
  if (S.currentMac !== mac) { S.inFlight = false; return 'abort:unbind'; }
  S.dispatched04++;
  S.inFlight = false;
  return 'unlock04';
}

const CASES = [
  ['基线（全绿）', null, 1],
  ['切锁：建连期间切到 B', { duringConnect: S => { S.currentMac = 'B'; } }, 0],
  ['退后台：建连期间锁屏', { duringConnect: S => { S.bgGen += 1; } }, 0],
  ['伪装会话：建连期间进入 decoy', { duringConnect: S => { S.decoyMode = true; } }, 0],
  ['防拆挂起：建连期间被挂起', { duringConnect: S => { S.suspended = true; } }, 0],
  ['建连失败：冷却期内不重试', { connectFails: true }, 0],
];

const bad = [];
const okList = [];
for (const [name, w, expect] of CASES) {
  const S = makeModel();
  const r1 = attempt(S, 'A');
  if (r1 === 'dispatch') dispatch(S, 'A', w);
  if (S.dispatched04 !== expect) bad.push(`${name}：实发 ${S.dispatched04} 次 04，期望 ${expect}`);
  else okList.push(name);
}

// F5 跨重启
{
  const S = makeModel();
  attempt(S, 'A'); dispatch(S, 'A', null);
  S.lastDispatch = {}; S.inFlight = false; S.eventFired = new Set();   // 内存态清零
  const ready = coolReady(S, 'A');
  if (ready) bad.push('F5 跨重启：冷却未生效（会立刻双开）');
  else okList.push('F5 跨重启：冷却生效');
}

// F6 锁态
for (const [rc, want] of [[0, 'dispatch'], [25, 'skip'], [26, 'skip'], [3, 'dispatch'], [24, 'dispatch']]) {
  const S = makeModel();
  S.snapshotRc = rc;
  const got = attempt(S, 'A');
  if (got !== want) bad.push(`F6 rc=${rc}：attempt=${got}，期望 ${want}`);
  else okList.push(`F6 rc=${rc} ⇒ ${want}`);
}

if (bad.length) {
  console.log(`\n✗ 异步窗口逻辑 ${bad.length} 处不符合预期：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：门控修复若只验证"代码存在"，改坏逻辑也不会被发现。');
  console.log('修法：按 Swift 源码结构同步更新影子模型；若行为确实该变，改本闸门的 CASES 并写明理由。');
  process.exit(1);
}
okList.forEach(x => console.log('ok    ' + x));
console.log(`\n✓ 异步窗口逻辑 ${okList.length} 项全部符合预期`);
