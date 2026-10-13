// ZOTP 临时密码生成器 — 字符级移植 App to.generateZOTPPwd (main.pretty.js @14960)
// 算法: 6 位数字密码 = AES-ECB(skey,ZeroPadding)( 时间计数器(8hex) + MAC反序(12hex) + idx(2B BE) + "00000000" )
//        → 密文 32hex, 取前 24hex 每 4hex 块 (字节1 ^ 字节2) % 10
//   u = floor(nowProtoSeconds / (60*period))  (period 默认 30分钟)
//   idx: App 走云端 otp_idx 自增; 离线端本地持久自增 (锁侧无法独立验证 idx, 详见记忆库 U6b)
// ⚠ 校准前提: 锁钟已同步 (0E), 否则手机与锁时间窗不同步 → 密码不匹配
const C = require('./crypto.js');
const T = require('./time.js');

function reversePairHex(hex) {
  let out = '';
  for (let i = hex.length - 2; i >= 0; i -= 2) out += hex.substr(i, 2);
  return out;
}
function le2be2(v) { // idx → 2B BE hex (App: toSmallByteOrder→toNormalByteOrder 双反转=恒等)
  return ('0000' + (v >>> 0).toString(16)).slice(-4).toUpperCase();
}
// 生成 6 位临时密码
// ⚠ 形参名 `periodSec` 是历史遗留：单位其实是**分钟**（下面 `60 * t`，t=30 ⇒ 30 分钟窗口，
//   金标 case 就叫 v30_*/v60_0）。2026-10-11 拍板**保留现名**——改名要同时动本基线 +
//   fixtures/golden.json 重生成 + 影子对拍端口，为一次命名付跨语言契约的代价不值。
//   Swift 侧同名保留并注明换算（App/Core/ZOTP.swift:15）；决策记录 docs/DECISION-NEEDED.md D-137。
function generate(macHex, skeyHex, periodSec, idx) {
  const t = periodSec || 30;
  let u = Math.floor(T.nowProtoSeconds() / (60 * t)).toString(16).toUpperCase();
  while (u.length < 8) u = '0' + u;
  const r = (macHex || '').replace(/:/g, '').toUpperCase();
  const a = idx > 0 ? le2be2(idx) : '0000';
  const c = u + reversePairHex(r) + a + '00000000';
  const p = C.encryptHex(c, skeyHex).toUpperCase();
  let m = '';
  if (p.length === 32) {
    const body = p.substr(0, p.length - 8);
    for (let i = 0; i < body.length; i += 4) {
      const y = parseInt(body.substr(i, 2), 16), b = parseInt(body.substr(i + 2, 2), 16);
      m += (y ^ b) % 10;
    }
    return m;
  }
  return '';
}
module.exports = { generate, reversePairHex, le2be2 };
