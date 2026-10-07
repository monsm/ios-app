// 每锁离线快照 (2026-09-03) — "云端曾存、随时读"的另一半:
//   锁端不可回读/不常连时, 把最近一次成功读到/写成的状态本地留档:
//   - kf_snap_{mac}    最近一次 cmd03 实时状态 (电量/音量/安全位/容量/版本/锁钟…) — lock.js 真机成功路径写入
//   - kf_logcache_{mac}最近一次 cmd16 日志翻页结果 (换机/重启后可离线浏览) — records 页成功路径写入
// 键族已在 utils/schema.js MANIFEST.perMac 登记; 不随备份包跨机迁移 (属缓存, 真机可重读)。
// 本模块纯 Node 可测。
const ST = require('../utils/store.js');

const LOG_CAP = 300; // 每锁缓存日志上限 (cmd16 翻页 ≤100/次)

function normMac(m) { return String(m || '').replace(/:/g, '').toLowerCase(); }
function snapKey(mac) { return 'kf_snap_' + normMac(mac); }
function logKey(mac) { return 'kf_logcache_' + normMac(mac); }

// ---- 状态快照 ----
function writeStatus(mac, status) {
  const m = normMac(mac);
  if (!m || m.length !== 12 || !status) return null;
  ST.set(snapKey(m), { at: Date.now(), status });
  return true;
}
function readStatus(mac) {
  const s = ST.get(snapKey(mac), null);
  return (s && typeof s === 'object' && s.status) ? s : null;
}

// ---- 日志缓存 (翻页片段累积, 按 idx 去重, 保序) ----
function writeLogs(mac, entries) {
  const m = normMac(mac);
  if (!m || !Array.isArray(entries) || !entries.length) return null;
  const cached = readLogs(m);
  const seen = {};
  const acc = [];
  for (const e of cached) {
    const k = (e && e.idxRaw !== undefined) ? e.idxRaw : (e && e.idx);
    if (k === undefined || seen[k]) continue;
    seen[k] = 1;
    acc.push(e);
  }
  for (const e of entries) {
    const k = (e && e.idxRaw !== undefined) ? e.idxRaw : (e && e.idx);
    if (k === undefined || seen[k]) continue;
    seen[k] = 1;
    acc.push(e);
  }
  const all = acc.slice(-LOG_CAP);
  ST.set(logKey(m), { at: Date.now(), logs: all });
  return all.length;
}
function readLogs(mac) {
  const s = ST.get(logKey(mac), null);
  return (s && Array.isArray(s.logs)) ? s.logs : [];
}
function readLogsAt(mac) {
  const s = ST.get(logKey(mac), null);
  return (s && s.at) ? s.at : null;
}

function clear(mac) {
  ST.remove(snapKey(mac));
  ST.remove(logKey(mac));
}

module.exports = { writeStatus, readStatus, writeLogs, readLogs, readLogsAt, clear };
