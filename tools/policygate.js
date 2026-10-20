#!/usr/bin/env node
// policygate — 命令安全表与上链入口的静态对账 (判失败)
//
// 它回答四个问题:
//   1. ZKCmdBuilder 里每一条 `cmd: 0xNN` 是否都在 LockCommand 表里登记了动作族?
//   2. LockService.request / HardwareService.send 这两个上链入口是否都调了 requireAllowed?
//   3. DFU (不走 87 帧) 的 runUpgrade / runUpgradeQueue 是否都挡了 .dfu?
//   4. 每条 LockAction 是否都有拒因文案; 每个策略值是否是已声明的 LockAction?
//   5. 411 二维码载荷是否只能走口令信封 (函数必须收 password 且调用点都传了)?
//
// 为什么这条能判失败: 上面全是**结构事实**, 不依赖运行时, 也不依赖 Swift 编译器。
// 它替代不了编译, 但能保证"新增一条写命令却忘了声明安全族"这件事不会静默发生。
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const fail = [];
const bad = m => fail.push(m);

// ---------- 1. 命令表 ----------
const lockCmdSrc = read('App/Core/LockCommand.swift');
const cases = [...lockCmdSrc.matchAll(/case\s+(\w+)\s*=\s*0x([0-9A-Fa-f]{2})/g)]
  .map(m => ({ name: m[1], cmd: parseInt(m[2], 16) }));
if (cases.length === 0) bad('LockCommand.swift 里没有解析到任何 case');
const byCmd = new Map(cases.map(c => [c.cmd, c]));
const dup = cases.filter((c, i) => cases.findIndex(x => x.cmd === c.cmd) !== i);
if (dup.length) bad('LockCommand 有重复命令号: ' + dup.map(c => c.name).join(', '));

// 策略块解析 (case .a, .b: return .x)
const policyBlock = lockCmdSrc.split('var policy: LockAction? {')[1];
if (!policyBlock) bad('LockCommand 缺少 policy 计算属性');
const policyOf = new Map();
if (policyBlock) {
  const body = policyBlock.split('var label: String {')[0];
  for (const chunk of body.split('case ').slice(1)) {
    const head = chunk.split(':')[0];
    const names = [...head.matchAll(/\.(\w+)/g)].map(m => m[1]);
    const ret = chunk.match(/return\s+(?:\.(\w+)|nil)/);
    const value = ret ? (ret[1] || null) : undefined;
    if (value === undefined) { bad('policy 分支读不出返回值: ' + head.trim()); continue; }
    for (const n of names) policyOf.set(n, value);
  }
}
for (const c of cases) {
  if (!policyOf.has(c.name)) bad(`LockCommand.${c.name} 没有声明 policy (只读也要显式 return nil)`);
}

// 构建器覆盖
const builder = read('App/Core/ZKCmdBuilder.swift');
const built = new Set([...builder.matchAll(/cmd:\s*0x([0-9A-Fa-f]{2})/g)].map(m => parseInt(m[1], 16)));
for (const cmd of [...built].sort((a, b) => a - b)) {
  if (!byCmd.has(cmd)) bad(`ZKCmdBuilder 会构造 cmd 0x${cmd.toString(16).padStart(2, '0')}, 但 LockCommand 表里没有它`);
}

// ---------- 2. 上链入口 ----------
const lockSvc = read('App/Services/LockService.swift');
if (!/try\s+LockCommand\.requireAllowed\(cmd\)/.test(lockSvc)) {
  bad('LockService.request 没有调用 LockCommand.requireAllowed(cmd) —— 安全闸没接上');
}
// 13 录指纹是第二条**直写**路径 (多响应, 不走 request 的单 waiter), 必须自己过闸
const fpAt = lockSvc.indexOf('func fpStart(');
if (fpAt < 0) bad('找不到 LockService.fpStart');
else if (!/LockCommand\.requireAllowed\(0x13\)/.test(lockSvc.slice(fpAt, fpAt + 1600))) {
  bad('LockService.fpStart 直写 13, 但没有过 LockCommand 闸');
}
// 直写路径数量棘轮: 目前只允许 request + fpStart 两条。新增一条就必须在这里显式加一, 并说明它过了哪道闸。
const directWrites = [...lockSvc.matchAll(/ble\.writeFrameHex\(/g)].length;
if (directWrites !== 2) bad(`LockService 里直写 ble.writeFrameHex 有 ${directWrites} 处 (预期 2: request + fpStart)`);
const hw = read('App/Services/HardwareService.swift');
if (!/try\s+LockCommand\.requireAllowed\(cmdObj\.cmd\)/.test(hw)) {
  bad('HardwareService.send 没有调用 LockCommand.requireAllowed(cmdObj.cmd)');
}
const hwWrites = [...hw.matchAll(/ble\.writeFrameHex\(/g)].length;
if (hwWrites !== 1) bad(`HardwareService 里直写 ble.writeFrameHex 有 ${hwWrites} 处 (预期 1: send)`);
const dfu = read('App/Services/DFUKit.swift');
for (const fn of ['runUpgrade(', 'runUpgradeQueue(']) {
  const at = dfu.indexOf('static func ' + fn);
  if (at < 0) { bad('DFUKit 里找不到 ' + fn); continue; }
  const seg = dfu.slice(at, at + 2600);
  if (!/SecurityPolicy\.allows\(\.dfu\)/.test(seg)) bad(`DFUKit.${fn.replace('(', '')} 没有挡 .dfu`);
}

// ---------- 3. LockAction 文案与策略闭环 ----------
const guardSrc = read('App/Core/LockGuard.swift');
const actionEnum = guardSrc.split('enum LockAction {')[1]?.split('var blockedInReadOnly')[0] || '';
const actions = [...actionEnum.matchAll(/case\s+(\w+)/g)].map(m => m[1]);
if (actions.length < 7) bad('LockAction 解析异常 (cases=' + actions.length + ')');
const denialBlock = guardSrc.split('var denial: String {')[1]?.split('struct SudoTicket')[0] || '';
for (const a of actions) {
  if (!new RegExp(`case\\s+\\.${a}\\s*:`).test(denialBlock)) bad(`LockAction.${a} 没有拒因文案`);
}
for (const [name, action] of policyOf) {
  if (action !== null && !actions.includes(action)) bad(`LockCommand.${name} 的策略 .${action} 不是 LockAction 的 case`);
}
// 界面级动作 (不属于任何单条命令) 必须仍有真实调用点, 否则就是"只声明不接线"
for (const a of ['unlock', 'destroy', 'importExport']) {
  const hits = [...lockSvc.matchAll(new RegExp(`SecurityPolicy\\.allows\\(\\.${a}\\)`, 'g'))].length
    + [...read('App/LockKeeperApp.swift').matchAll(new RegExp(`SecurityPolicy\\.allows\\(\\.${a}\\)`, 'g'))].length
    + [...read('App/UI/SecurityCenterView.swift').matchAll(new RegExp(`SecurityPolicy\\.allows\\(\\.${a}\\)`, 'g'))].length;
  if (hits === 0) bad(`LockAction.${a} 没有任何 SecurityPolicy.allows 调用点`);
}
// 命令策略必须真的被某条命令使用 (防止策略族只剩声明)
for (const a of actions) {
  if (['destroy', 'importExport'].includes(a)) continue;
  if (![...policyOf.values()].includes(a)) bad(`LockAction.${a} 没有被任何命令使用`);
}

// ---------- 4. 411 二维码只许出口令信封 ----------
const studio = read('App/Services/BackupStudioKit.swift');
const qrFn = studio.split('static func credentialQRPayload')[1]?.split('// ---------- 412/431')[0] || '';
if (!qrFn) bad('找不到 credentialQRPayload');
if (!/password:\s*String/.test(qrFn)) bad('credentialQRPayload 必须要求 password 参数');
if (!/CryptoBox\.encryptText/.test(qrFn)) bad('credentialQRPayload 没有走 CryptoBox.encryptText —— 可能又退回了明文');
if (/return\s+t\b/.test(qrFn)) bad('credentialQRPayload 直接返回了 canonical 明文 t');
// 容量口径必须是 UTF-8 字节 (中文 1 字符 3 字节), 信封上限要对得上 QR 纠错档 M 的真实容量。
if (!/t\.utf8\.count\s*<=\s*900/.test(qrFn)) bad('credentialQRPayload 的容量闸不是 UTF-8 字节口径 (t.count 会把中文算小 3 倍)');
if (!/env\.count\s*<=\s*2200/.test(qrFn)) bad('credentialQRPayload 没有信封 ≤2200 的容量闸');
const ui = read('App/UI/BackupStudio.swift');
for (const m of ui.matchAll(/credentialQRPayload\(([^)]*)\)/g)) {
  if (!/password\s*:/.test(m[1])) bad('BackupStudio 有一处 credentialQRPayload 调用没传 password: ' + m[0]);
}

// ---------- 输出 ----------
if (fail.length) {
  console.log('✗ policygate: ' + fail.length + ' 条');
  for (const f of fail) console.log('  - ' + f);
  process.exit(1);
}
const writes = [...policyOf.values()].filter(Boolean).length;
console.log(`✓ policygate: ${cases.length} 条命令已登记 (写类 ${writes} / 只读 ${cases.length - writes}); 两个上链入口 + DFU 两处均已接闸; 二维码只走口令信封`);
