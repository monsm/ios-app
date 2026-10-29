// tools/regresscheck.js — 已修问题的回归防线（判失败）
//
// 背景：这轮审计修了 30+ 处性能与缺陷。每一项的修法都很小（加缓存 / 加世代号 / 加节流），
// 而这类改动最容易被后续重构「顺手改回去」—— 改回去之后行为仍是「能跑」的，
// 只是性能或竞态回来了，静态闸门看不出来。
//
// 这里逐条断言「修法的关键构件仍在位」，缺失即失败。
//
// 用法：node tools/regresscheck.js
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// 回归扫描：逐条检查前 31 轮修过的关键点是否仍然成立
const checks = [
  {
    name: 'R1 Store 解码缓存',
    file: 'App/Core/Store.swift',
    must: ['valueCache.withLock', 'invalidateCache(k)'],
  },
  {
    name: 'R4 两处损坏标记清除（set/setCodable/remove）',
    file: 'App/Core/Store.swift',
    must: ['corruptKeys.withLock { $0.remove(k) }'],
    countMust: 'corruptKeys.withLock { $0.remove(k) }',
    minCount: 3,
  },
  {
    name: 'R5 容错解码（LedgerPwd/LedgerFp/Ledger/Lossy）',
    file: 'App/Core/StoreModels.swift',
    must: ['struct Lossy<', 'init(from decoder: Decoder) throws'],
    countMust: 'init(from decoder: Decoder) throws',
    minCount: 2,
  },
  {
    name: 'R11 keychain 内存缓存 + 失效',
    file: 'App/Core/StoreKeychain.swift',
    must: ['keychainCache.withLock', 'private let keychainCache'],
  },
  {
    name: 'R12 HardwareService 取消陈旧定时器',
    file: 'App/Services/HardwareService.swift',
    must: ['w.timer?.cancel()'],
  },
  {
    name: 'R14 BleTelemetry 缓存 + flush',
    file: 'App/Core/DiagKit.swift',
    must: ['eventCache', 'static func flush()', 'scheduleFlush'],
  },
  {
    name: 'R15 取消开锁的三处判取消',
    file: 'App/LockKeeperApp.swift',
    must: ['if Task.isCancelled { return }'],
    countMust: 'if Task.isCancelled { return }',
    minCount: 3,
  },
  {
    name: 'R16 AutoOpen.audit 节流',
    file: 'App/Core/AutoOpen.swift',
    must: ['autoOpenAuditLast', 'if skip { return }'],
  },
  {
    name: 'R22 derivedCache（members / allExt）',
    file: 'App/Core/Store.swift',
    must: ['derivedCache', '$0["members"] = nil'],
  },
  {
    name: 'R23 fetchTicket',
    file: 'App/UI/RecordsRows.swift',
    must: ['fetchTicket', 'guard !running else { return }'],
  },
  {
    name: 'R24 statusTicket',
    file: 'App/LockKeeperApp.swift',
    must: ['statusTicket', 'currentMac == kc.mac'],
  },
  {
    name: 'R25 scheduleAlerts 串行化',
    file: 'App/Core/CredentialOrgState.swift',
    must: ['scheduleAlertsOrdered', 'scheduleAlertsNow'],
  },
  {
    name: 'R28 时间线旗标一次取',
    file: 'App/UI/RecordsTimelineRows.swift',
    must: ['allFlags', 'flagged.contains'],
  },
  {
    name: 'R29 alertTable',
    file: 'App/Core/CredentialOrg.swift',
    must: ['static func alertTable', 'alerts["pwd:"'],
  },
];

let bad = 0;
for (const c of checks) {
  const p = path.join(__dirname, '..', c.file);
  if (!fs.existsSync(p)) { console.log(`✗ ${c.name}  —— 文件不存在 ${c.file}`); bad++; continue; }
  const t = fs.readFileSync(p, 'utf8');
  const miss = c.must.filter(m => !t.includes(m));
  if (miss.length) {
    console.log(`✗ ${c.name}  —— ${c.file} 缺少: ${miss.join(' / ')}`);
    bad++;
    continue;
  }
  if (c.minCount && c.countMust) {
    const n = t.split(c.countMust).length - 1;
    if (n < c.minCount) { console.log(`✗ ${c.name}  —— ${c.countMust} 只出现 ${n} 次（应 ≥${c.minCount}）`); bad++; continue; }
  }
  console.log(`✓ ${c.name}`);
}
console.log(`\n回归扫描: ${checks.length - bad}/${checks.length} 通过`);
process.exit(bad ? 1 : 0);
