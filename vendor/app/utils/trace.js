// trace.js — 锁交互全量追踪 (调试用): 每笔 TX/RX 完整帧 hex + KLV 明细 + 生命周期事件
// 输出三通道: console 镜像 + 内存环形缓冲 + 持久化 (崩溃/超时后重启可恢复)
//   持久化: 尾段截断到 ~0.45MB 存 wx storage (key kf_trace_persist_v1), 600ms 防抖写;
//   warn/error 级事件 (超时/失败) 立即落盘, 降低进程被杀时的丢日志概率。
// 行前缀统一 'LOCK' + 序号; 数据含令牌/密钥等敏感 hex — 仅本机调试用途。
const store = require('./store.js');

const RING_MAX = 800;
const PERSIST_KEY = 'kf_trace_persist_v1';
const PERSIST_BUDGET = 450000; // 字符预算 (~<0.5MB, wx 单 key 上限 1MB)
const ring = [];
let seq = 0;
let _flushTimer = null;

function stamp() {
  const d = new Date();
  const p = n => ('0' + n).slice(-2);
  return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds()) + '.' + String(d.getMilliseconds()).padStart(3, '0');
}
function emit(line) {
  ring.push(line);
  if (ring.length > RING_MAX) ring.shift();
  try { console.log(line); } catch (e) {}
  scheduleFlush();
}
function scheduleFlush() {
  if (_flushTimer) clearTimeout(_flushTimer);
  _flushTimer = setTimeout(() => { _flushTimer = null; flush(); }, 600);
}
// 尾段截断持久化: 只保留最新且合计 ≤ 预算的行 (防单 key 超 1MB)
function flush() {
  if (_flushTimer) { clearTimeout(_flushTimer); _flushTimer = null; }
  try {
    if (!ring.length) return;
    const tail = [];
    let len = 0;
    for (let i = ring.length - 1; i >= 0; i--) {
      const add = ring[i].length + 1;
      if (len + add > PERSIST_BUDGET) break;
      tail.unshift(ring[i]);
      len += add;
    }
    store.set(PERSIST_KEY, { savedAt: Date.now(), count: tail.length, chars: len, lines: tail });
  } catch (e) {}
}
// 读取上次会话持久化日志 (崩溃/重启恢复)
function persisted() {
  try {
    const p = store.get(PERSIST_KEY, null);
    return (p && typeof p === 'object' && Array.isArray(p.lines) && p.lines.length) ? p : null;
  } catch (e) { return null; }
}
// 把上次会话日志并入当前缓冲 (合并后 flush 会覆盖持久化, 如需保留旧档请先导出)
function mergePersisted() {
  const p = persisted();
  if (!p) return 0;
  let added = 0;
  for (const l of p.lines) { ring.push(l); added++; }
  if (ring.length > RING_MAX) ring.splice(0, ring.length - RING_MAX);
  return added;
}
function hx(cmd) {
  return cmd !== undefined && cmd !== null ? ('0' + cmd.toString(16)).slice(-2).toUpperCase() : '--';
}
function kvDump(klvs, rxNo) {
  const lines = [];
  for (const k of klvs || []) {
    const key = k.key !== undefined ? ('0' + Number(k.key).toString(16)).slice(-2).toUpperCase() : '??';
    const val = (k.val || '');
    const vlen = k.vlen !== undefined ? k.vlen : (val.length / 2);
    lines.push('LOCK ' + stamp() + ' [RX#' + rxNo + ']   klv ' + key + ' (' + vlen + 'B) = ' + (val === '' ? '<空>' : val));
  }
  return lines;
}

// 发送一笔命令: name/cmd/最终帧 hex (+ 可选 meta 标志串)
function tx(name, cmd, hex, meta) {
  const n = ++seq;
  const label = name || ('cmd ' + hx(cmd));
  const flags = meta ? '  ' + meta : '';
  const bytes = (hex || '').length / 2;
  emit('LOCK ' + stamp() + ' [TX#' + n + '] ' + label + ' cmd=' + hx(cmd) + ' len=' + bytes + 'B' + flags + '\n      hex=' + (hex || '<空>'));
}
// 收到一帧: name/cmd/完整帧 hex/KLV 明细/可选 {header, rc}
function rx(name, cmd, hex, klvs, extra) {
  const n = ++seq;
  const label = name || ('cmd ' + hx(cmd));
  const o = extra || {};
  const flags = [];
  if (o.header !== undefined) flags.push('header=' + o.header + 'B');
  if (o.rc !== undefined) flags.push('rc=' + o.rc);
  const bytes = (hex || '').length / 2;
  emit('LOCK ' + stamp() + ' [RX#' + n + '] ' + label + ' cmd=' + hx(cmd) + ' len=' + bytes + 'B' + (flags.length ? '  ' + flags.join(' ') : '') + '\n      frame=' + (hex || '<空>'));
  for (const l of kvDump(klvs, n)) emit(l);
}
// 生命周期/流程事件 (连接/令牌/重试/超时/配网步骤…); warn/error 立即落盘
function evt(level, msg) {
  const n = ++seq;
  emit('LOCK ' + stamp() + ' [EVT#' + n + '][' + String(level).toUpperCase() + '] ' + msg);
  const lv = String(level || '').toLowerCase();
  if (lv === 'warn' || lv === 'error') flush();
}
// BLE 写分片: i=已发片数, total=总片数, hex=该片原始字节 (诊断 MTU/分片)
function bleTxChunk(i, total, hex, extra) {
  const n = ++seq;
  emit('LOCK ' + stamp() + ' [BLE-TX#' + n + '] 写分片 ' + i + '/' + total + ' len=' + ((hex || '').length / 2) + 'B' + (extra ? '  ' + extra : '') + '\n      hex=' + (hex || '<空>'));
}
// BLE notify 原始载荷 (粘包重组前逐片) — 诊断 MTU 协商/分片丢失
function bleRxChunk(hex) {
  const n = ++seq;
  emit('LOCK ' + stamp() + ' [BLE-RX#' + n + '] notify len=' + ((hex || '').length / 2) + 'B\n      hex=' + (hex || '<空>'));
}
// 导出内存缓冲最近 N 条 (整段复制发给开发者)
function dump(n) {
  const list = n ? ring.slice(-n) : ring.slice();
  return list.join('\n');
}
function clear() {
  ring.length = 0;
  try { store.remove(PERSIST_KEY); } catch (e) {}
}
module.exports = { tx, rx, evt, bleTxChunk, bleRxChunk, dump, clear, flush, persisted, mergePersisted };
