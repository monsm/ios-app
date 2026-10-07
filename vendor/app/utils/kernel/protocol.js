// ZKLKX 0x87 帧协议层 (逆向自 App main.js + 固件 V5.2.9 反汇编)
//
// 请求帧 (App/JS 与固件解析器一致):
//   [0x87][0x00][len:2 LE][cmd:1][ssToken:2][0x00 0x00 0x00] [KLV...]
//   10 字节头, len = KLV 载荷长度 (不含 10 字节头); 固件 parser body = frame+10
// 兼容变体 (旧 Java 插件 8 字节头):
//   [0x87][0x10][len:2 LE][cmd:1][0x00 0x00 0x00] [KLV...]
//
// KLV: [key:1][len:1][value:len]
// 会话令牌: 请求 KLV#0xEE(Java 侧) ; 响应 KLV#1=安全类型(bit1=1→Token) #2=token #3=有效期秒(u16 LE)
// 状态请求: KLV#01 = 0x88-EKey 结构(TargetMAC反转+trackId+有效期+cmd), KLV#02 = 空
// 0x88-EKey: [0x88][0x00][MAC:6 反转][trackId:4 LE][validFrom:4 LE][validTo:4 LE][cmd:1][body]

const EPOCH = Date.parse('2010-01-01T00:00:00Z') / 1000; // 协议时间基准

// 只读命令白名单 — 试验模式硬护栏: 任何写入命令 (包含 05 换钥/08 PIN/04 开门等) 一律拦截
// 为什么 05 必须永禁: 固件 05 处理器 (@0x258A0) 会擦除 flash 区域 7+8 (skey 密钥域) 并写新密钥条目,
// 一旦执行旧钥匙即作废; 尽管固件审计证实密码/指纹存储域不在擦除范围内, 仍不允许在小程序里触发。
const READONLY_CMDS = { 0x01: 1, 0x02: 1, 0x03: 1, 0x12: 1, 0x16: 1, 0x23: 1, 0x30: 1, 0x38: 1 };
const WRITE_CMDS_BLOCKED = [0x04, 0x05, 0x08, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x13, 0x14, 0x15,
  0x18, 0x19, 0x20, 0x21, 0x22, 0x24, 0x25, 0x31, 0x32, 0x35, 0x41, 0x43, 0x44];
function assertReadOnly(cmd) {
  if (!READONLY_CMDS[cmd]) {
    throw new Error('护栏拦截: cmd 0x' + cmd.toString(16) + ' 是写入/危险命令, 试验模式禁止发送!');
  }
}

function hexToBytes(hex) {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}
function bytesToHex(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += (bytes[i] < 16 ? '0' : '') + bytes[i].toString(16);
  return s;
}
function u16le(v) { return [v & 0xff, (v >> 8) & 0xff]; }
function u32le(v) {
  v = v >>> 0;
  return [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
}
function readU16LE(hex, off) {
  const b = hex.substr(off * 2, 4).match(/.{2}/g) || ['0', '0'];
  return parseInt(b[0], 16) | (parseInt(b[1], 16) << 8);
}
function readU32LE(hex, off) {
  const b = hex.substr(off * 2, 8).match(/.{2}/g) || [];
  let v = 0;
  for (let i = b.length - 1; i >= 0; i--) v = (v * 256) + parseInt(b[i], 16);
  return v >>> 0;
}
function protoTime(dateStr) {
  return Math.floor((Date.parse(dateStr) / 1000) - EPOCH);
}
function reversePairs(hex) {
  let out = '';
  for (let i = hex.length - 2; i >= 0; i -= 2) out += hex.substr(i, 2);
  return out;
}

// ---------- 帧构造 ----------
function buildKLV(key, valHex) {
  const v = valHex || '';
  const len = v.length / 2;
  return ('00' + key.toString(16)).slice(-2) + ('00' + len.toString(16)).slice(-2) + v;
}

// header10: App/JS 现行格式; header8: 旧 Java 插件格式
function buildFrame(cmd, klvHex, ssTokenHex, header) {
  ssTokenHex = ssTokenHex || '0000';
  const klv = klvHex || '';
  const len = klv.length / 2;
  const lb = u16le(len);
  let head;
  if (header === 8) {
    // 生产链 Java LockCommBase.getBytes: writeByte(0|256)=0x00 → 87 00 len:2 cmd 000000 (8B, 无 ssToken)
    head = '87' + '00' + hexPair(lb[0]) + hexPair(lb[1]) + hexPair(cmd) + '000000';
  } else {
    head = '87' + '00' + hexPair(lb[0]) + hexPair(lb[1]) + hexPair(cmd) + ssTokenHex + '000000';
  }
  return head + klv;
}
function hexPair(v) { return ('00' + v.toString(16)).slice(-2); }

// 0x88 EKey 封装 (TargetMAC 需 12 位 hex, 会按字节对反转)
function buildEkey(cmd, macHex, validFromSec, validToSec, trackIdVal) {
  const trackId = u32le(trackIdVal === undefined ? 0 : trackIdVal);
  const vf = u32le(validFromSec === undefined ? 0 : validFromSec);
  const vt = u32le(validToSec === undefined ? protoTime('2118-01-01T00:00:00Z') : validToSec);
  let mac = (macHex || '000000000000').toLowerCase();
  if (mac.indexOf(':') >= 0) mac = mac.replace(/:/g, '');
  return '8800' + reversePairs(mac) + b2h(trackId) + b2h(vf) + b2h(vt) + hexPair(cmd) + '';
}
function b2h(arr) {
  let s = '';
  for (let i = 0; i < arr.length; i++) s += hexPair(arr[i]);
  return s;
}

// ---------- 响应解析 (多格式兼容) ----------
// 尝试三种候选头: 10B(现行)/8B(旧)/及 7B([87][01][len][cmd][dlen:2]).
// 选择 KLV 结构能完整解析的一种; 返回 {ok, cmd, header, klvs:[{key,val}], raw}
function parseResponse(hex) {
  if (!hex || hex.length < 14) return { ok: false };
  const versionByte = parseInt(hex.substr(2, 2), 16);
  // V80 (F4): 8B 帧设首选 — 全新反编译 Java LockCommBase.parse() 不看版本字节、恒按 8B 头消费;
  //   7B(旧固件)/10B(旧 JS) 仅作长度守卫下的失败后备, 不再按 vb 先行试 7/10。
  let orders;
  if (versionByte === 0x01) orders = [8, 7, 10];
  else if (versionByte === 0x10) orders = [8, 10, 7];
  else orders = [8, 10, 7];
  const results = [];
  for (const bodyOff of orders) {
    const len = readU16LE(hex, 2);
    if (bodyOff === 7 && hex.length < (7 + len) * 2) continue;
    if (bodyOff === 8 && hex.length < (8 + len) * 2) continue;
    if (bodyOff === 10 && hex.length < (10 + len) * 2) continue;
    const klvHex = hex.substr(bodyOff * 2, len * 2);
    const klvs = parseKLV(klvHex);
    if (klvs === null) continue;
    // cmd 字节位置: 三种帧头 (7B/8B/10B) 均为字节4 (固件 TX 构造器 0x2a670: strb cmd,[r4,#4])
    results.push({ header: bodyOff, cmd: parseInt(hex.substr(8, 2), 16), klvs, full: hex.length / 2 });
  }
  if (!results.length) return { ok: false };
  const r = results[0];
  return { ok: true, cmd: r.cmd, header: r.header, klvs: r.klvs, raw: hex, meta: results.length };
}

function parseKLV(hex) {
  const klvs = [];
  let off = 0;
  const L = hex.length;
  while (off < L) {
    if (off + 4 > L) return null;
    const key = parseInt(hex.substr(off, 2), 16);
    const len = parseInt(hex.substr(off + 2, 2), 16);
    if (off + 4 + len * 2 > L) return null;
    klvs.push({ key, val: hex.substr(off + 4, len * 2), vlen: len });
    off += 4 + len * 2;
  }
  return klvs;
}

// 向 0x87 请求帧追加 KLV 令牌 — 固件会话模块对 KLV key 0xEE 有特判 (0x253FE),
// 令牌通道 = KLV#0xEE (与 Java 插件 mKLVList.add(0xEE, ssToken) 追加末尾一致)。
// 2026-09-03 勘误 (见 02-帧协议 §4): 旧实现固定按 8B 头取体 (substr 16) — 传入 10B 帧会
// 把 8B 头对齐的末 2 头字节当体首并丢真实 KLV 前 2 字节 → 帧损坏。头型可按帧总长确定性判别:
//   10B 头总长 = len+10 (hex 字符 20+2·len); 8B 头总长 = len+8 (hex 字符 16+2·len)
// 现按头型自适应: 8B 输入字节级不变 (生产链全部请求, 历史行为不变); 10B 输入保留 ssToken 重建。
function injectToken(hex, tokenHex) {
  if (!tokenHex || typeof hex !== 'string' || hex.length < 16) return hex;
  const len = readU16LE(hex, 2);
  const cmd = parseInt(hex.substr(8, 2), 16);
  const header10 = hex.length >= 20 + len * 2;
  const body = hex.substr(header10 ? 20 : 16, len * 2);
  const klv = body + buildKLV(0xee, tokenHex);
  return header10 ? buildFrame(cmd, klv, hex.substr(10, 4), 10) : buildFrame(cmd, klv, '0000', 8);
}

// ---------- 探测命令 ----------
function cmd01Session(header) {
  return { name: '01 会话令牌', cmd: 0x01, hex: buildFrame(0x01, '', '0000', header), header };
}
function cmd03Status(header, macHex, wrap) {
  let klv = '';
  if (wrap) {
    klv += buildKLV(0x01, buildEkey(0x03, macHex)) + buildKLV(0x02, '');
  }
  return { name: '03 状态', cmd: 0x03, hex: buildFrame(0x03, klv, '0000', header), header, wrap };
}
function cmd12Echo(header, valHex) {
  // 官方值 = hex '123456' (main.pretty.js:9851 `new ft("123456")`; 3B 魔数, 非 ASCII 编码)
  return { name: '12 回声', cmd: 0x12, hex: buildFrame(0x12, buildKLV(0x01, valHex || '123456'), '0000', header), header };
}
function cmd23ExKeyWay(header, macHex, wrap) {
  let klv = '';
  if (wrap) klv = buildKLV(0x01, buildEkey(0x23, macHex));
  return { name: '23 交换方式', cmd: 0x23, hex: buildFrame(0x23, klv, '0000', header), header, wrap };
}

module.exports = {
  EPOCH, hexToBytes, bytesToHex, readU16LE, readU32LE, hexPair, u16le, u32le,
  buildKLV, buildFrame, buildEkey, reversePairs,
  injectToken, parseResponse, parseKLV, protoTime,
  cmd01Session, cmd03Status, cmd12Echo, cmd23ExKeyWay,
  READONLY_CMDS, WRITE_CMDS_BLOCKED, assertReadOnly
};