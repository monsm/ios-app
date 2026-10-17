// 协议时间 (4B LE 秒) — 基准是 **本地时区的 2010-01-01 00:00:00**, 不是 UTC!
//   逐字对齐 APK: En.getProtocolTimeSecond(x) = An.getDate(x) − An.getDate('2010-01-01 00:00:00'),
//   而 An.getDate 是 new Date(y,m,d,...) —— 两个被减数都在**本地墙钟**上, 时区自己消掉。
//   于是同一时刻的协议秒 = (UTC 基准的秒差) + 本机时区偏移 (东八区 +28800): 这是锁钟、0E 校时、
//   0A/0B/14 有效期窗口与 13/16 回帧时间的统一口径; 用 UTC 基准会让每一处都差一个时区。
const EPOCH_MS = new Date(2010, 0, 1, 0, 0, 0).getTime();   // 本地 2010-01-01 00:00:00

function protoSecondsFromMs(ms) {
  return Math.floor((ms - EPOCH_MS) / 1000);
}
function nowProtoSeconds() {
  return protoSecondsFromMs(Date.now());
}
function protoSecondsToMs(sec) {
  return EPOCH_MS + sec * 1000;
}
// 协议秒 → 'YYYY-MM-DD HH:mm:ss' **本地**串。
//   2026-10-17 全量盘点: 基准换成"本地 2010"之后, 协议秒本身就是墙钟秒 —— 再按 UTC 格式化会
//   整体早 8 小时 (旧实现是 UTC 基准 + UTC 格式化, 两个偏移自相抵消才看着对)。两个函数现在
//   口径相同: protoSecondsToDateStr 保留为存储/序列化出口, protoSecondsToLocalStr 为显示出口。
function protoSecondsToDateStr(sec) {
  const d = new Date(protoSecondsToMs(sec));
  const p = (n) => ('0' + n).slice(-2);
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}
// 人类可读的本地时区显示 (2026-09-03 勘误: 此前记录页/设备页锁钟用 UTC 串, 国内时区整体早 8 小时)
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
