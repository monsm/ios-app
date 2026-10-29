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

  // ---------- 第二轮补录（第 32 轮盘点时确认已修、此前未入防线）----------
  {
    name: 'R2 RSSI 节流 + 骤变通道',
    file: 'App/Core/LinkSenseKit.swift',
    must: ['lastRssiPublishAt', 'bigJump'],
  },
  {
    name: 'R3 syncBtOn 只在变化时发',
    file: 'App/Core/LinkSenseKit.swift',
    must: ['if btOn != on { btOn = on }', 'if btDenied != denied { btDenied = denied }'],
  },
  {
    name: 'R6 ToastCenter 独立',
    file: 'App/Core/ToastCenter.swift',
    must: ['final class ToastCenter', 'ToastBannerHost'],
  },
  {
    name: 'R7 DiagLogs 缓存 + flush',
    file: 'App/Core/DiagKit.swift',
    must: ['entryCache', 'savePending', 'static func flush()'],
  },
  {
    name: 'R8 writeStatus 的 60s 窗口',
    file: 'App/Core/StoreState.swift',
    must: ['nowMs - old.at < 60_000'],
  },
  {
    name: 'R9 搜索 180ms 防抖',
    file: 'App/UI/RecordsView.swift',
    must: ['searchDebounce'],
  },
  {
    name: 'R10 统计 CSV 一次建表',
    file: 'App/Core/StatsKit.swift',
    must: ['memberNames'],
  },
  {
    name: 'R13 DF.cached (DateFormatter 缓存)',
    file: 'App/Core/DateFormats.swift',
    must: ['static func cached('],
  },
  {
    name: 'R17 批量操作一次建存在集',
    file: 'App/Core/CredentialOrgBatch.swift',
    must: ['let existing = Set(DB.ledger(mac).pwds.map'],
  },
  {
    name: 'R18 allExt 整表入口',
    file: 'App/Core/MemberHub.swift',
    must: ['static func allExt()', 'ext(_ id: String, in table'],
  },
  {
    name: 'R19 MemberExt 容错',
    file: 'App/Core/MemberHub.swift',
    must: ['decodeIfPresent(String.self, forKey: .role) ?? "member"'],
  },
  {
    name: 'R20 StatusSnapshot 容错',
    file: 'App/Core/StoreModels.swift',
    must: ['struct StatusSnapshotData: Codable, Equatable'],
  },
  {
    name: 'R21 LogCache/CachedLog 容错',
    file: 'App/Core/StoreModels.swift',
    must: ['struct CachedLog: Codable', 'Lossy<CachedLog>'],
  },
  {
    name: 'R26 凭证页 seq 一次取',
    file: 'App/UI/CredentialActions.swift',
    must: ['let seqAll = CredentialOrg.seq(mac)', 'order: orderP'],
  },
  {
    name: 'R27 日志落盘一次化',
    file: 'App/UI/RecordsRows.swift',
    must: ['if !events.isEmpty { DB.writeLogs(kc.mac, events) }'],
    countMust: 'if !events.isEmpty { DB.writeLogs(kc.mac, events) }',
    minCount: 2,
  },
  {
    name: 'R30 QuickPool.selected 建表',
    file: 'App/Core/QuickPool.swift',
    must: ['let byID = Dictionary(all.map'],
  },
  {
    name: 'R31 viewdbcheck 轻重分级 + task 排除',
    file: 'tools/viewdbcheck.js',
    must: ['inAsync(k)'],
  },
  {
    name: 'R32 布防摘要一次读',
    file: 'App/UI/DeviceHomeView.swift',
    must: ['let defend = DB.defend(kc.mac)'],
  },
  {
    name: 'R33 RSSI 从广播级发布改节流（第 10 轮）',
    file: 'App/Core/LinkSenseKit.swift',
    must: ['lastRssiPublishAt'],
  },
  {
    name: 'R34 buildRecs memberName 建表（第 34 轮）',
    file: 'App/Core/RecordSearchBuild.swift',
    must: ['let memberNames = Dictionary(members.map', 'return memberNames[id]'],
  },
  {
    name: 'R35 viewdbcheck 排除写侧（第 36 轮）',
    file: 'tools/viewdbcheck.js',
    must: ['setInt|setDouble|setCodable|remove'],
  },
  {
    name: 'R36 DongleView 一次取（第 35 轮）',
    file: 'App/UI/DongleView.swift',
    must: ['let allDongles = DB.dongles()'],
  },
  {
    name: 'R37 冷启动链路（第 37 轮复核，无改动 —— 断言放在有实体改动的文件）',
    file: 'App/Core/LinkSenseReconnect.swift',
    must: ['AutoOpenController.shared.tickDwell(mac: mac)', 'reconnectAttempt = min(kind + 1, LinkSense.ladderSeconds.count)'],
  },
  {
    name: 'R39 扫描引用计数两个出口都还票（第 38 轮）',
    file: 'App/Services/BLEService.swift',
    must: ['scanRefLock.withLock { n -> Int in', 'scanRefLock.withLock { $0 = max(0, $0 - 1) }', 'scanRefLock.withLock { $0 += 1 }'],
  },
  {
    name: 'R40 DST：快捷档 N 天走 WeekCal.shifted（第 40 轮）',
    file: 'App/UI/TempCodeStudio.swift',
    must: ['WeekCal.shifted(from, days: 7)', 'WeekCal.shifted(from, days: 30)'],
  },
  {
    name: 'R41 校时页 syncTicket 世代号（第 41 轮）',
    file: 'App/UI/DeviceHomeSupport.swift',
    must: ['syncTicket', 'guard ticket == syncTicket, app.currentMac == m else { return }'],
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
