// 协议时间 (2010-01-01 00:00:00 UTC 基准, 4B LE 秒) — 与 kernel/protocol EPOCH 一致
const EPOCH_MS = Date.parse('2010-01-01T00:00:00Z');

function protoSecondsFromMs(ms) {
  return Math.floor((ms - EPOCH_MS) / 1000);
}
function nowProtoSeconds() {
  return protoSecondsFromMs(Date.now());
}
function protoSecondsToMs(sec) {
  return EPOCH_MS + sec * 1000;
}
function protoSecondsToDateStr(sec) {
  const d = new Date(protoSecondsToMs(sec));
  const p = (n) => ('0' + n).slice(-2);
  return `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())}`;
}
// 人类可读的本地时区显示 (2026-09-03 勘误: 此前记录页/设备页锁钟用 UTC 串, 国内时区整体早 8 小时)
// 存储/序列化仍用 UTC (protoSecondsToDateStr/ISO), 显示一律走本地版。
function protoSecondsToLocalStr(sec) {
  const d = new Date(protoSecondsToMs(sec));
  const p = (n) => ('0' + n).slice(-2);
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}
// ISO 时间串 (toISOString, UTC) → 'YYYY-MM-DD HH:mm' 本地显示
function isoToLocalText(iso) {
  if (!iso) return '';
  const t = new Date(String(iso)).getTime();
  if (!Number.isFinite(t)) return String(iso).replace('T', ' ').slice(0, 16);
  const d = new Date(t);
  const p = (n) => ('0' + n).slice(-2);
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}
module.exports = { EPOCH_MS, protoSecondsFromMs, nowProtoSeconds, protoSecondsToMs, protoSecondsToDateStr, protoSecondsToLocalStr, isoToLocalText };
