#!/usr/bin/env node
// tools/cmdsshadow.js — ZK 命令帧的跨语言差分 (第一百七十三批新增，判失败)
//
// 和 zotpshadow 同一个道理，但面更大：`fixtures/golden.json` 的 `cmds.*` 是**要发给锁的字节**，
// 由 vendor JS 基线生成；Swift 侧对应 `ZKProtocol` + `ZKCmdBuilder`。
// 原验证手段是 `GoldenDiffTests` 里那 40 条逐条 `XCTAssertEqual` —— 而 XCTest 在本仓从未执行过 (§10.2)，
// 也就是说"App 组出来的帧和当年那条走通生产链的帧是否逐字节相同"这件事，从来没有机器证据。
// 这一支把 Swift 侧逐行复刻进 node 重算一遍，再与夹具整帧比对。
//
// 覆盖：40 条里复刻 33 条。剩下 7 条**没纳入**（`withToken` 要 `injectToken` 的整帧改写、
// `buildEkeyShare` 走本地时区窗口、网关 5 条 `30/31/32/35/38` 在 Swift 侧另成一段），
// 未覆盖清单由本文件末尾打印出来，别让它变成"看起来全验过了"。
//
// 时区：夹具是按 Asia/Shanghai 烘焙的 (`tools/golden.js:12` 无条件钉 TZ)，
// 因为 validFrom/To 这类"无时区的日期串"两边都按设备本地解释。这里同样钉死，
// 否则在 UTC runner 上会从 `from=-28800` 变成 `from=0` ⇒ 差分假红 (比对的是字节，不是语义)。
process.env.TZ = process.env.CMDS_SHADOW_TZ || 'Asia/Shanghai';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const golden = JSON.parse(fs.readFileSync(path.join(ROOT, 'fixtures/golden.json'), 'utf8')).cmds;
const MAC = 'aabbccddeeff';
const SKEY = '00112233445566778899aabbccddeeff';
const EP_MS = 1262304000000n;                       // ZKProtocol.epochMs
const protoFromMs = (ms) => (BigInt(ms) - EP_MS) / 1000n;

// ---------------- HexKit ----------------
const hexPair = (v) => (v & 0xff).toString(16).padStart(2, '0');
const u16leHex = (v) => hexPair(v & 0xff) + hexPair((v >>> 8) & 0xff);
const u32leHex = (v) => hexPair(v & 0xff) + hexPair((v >>> 8) & 0xff) + hexPair((v >>> 16) & 0xff) + hexPair((v >>> 24) & 0xff);
const hexBytes = (h) => { const o = []; for (let i = 0; i + 1 < h.length; i += 2) { const n = Number.parseInt(h.substr(i, 2), 16); o.push(Number.isNaN(n) ? 0 : n & 0xff); } return o; };
const bytesHex = (b) => b.map((x) => (x & 0xff).toString(16).padStart(2, '0')).join('');
function reversePairs(hex) {                        // HexKit.reversePairs: 奇数长度直接判失败返回 ""
  if (hex.length % 2 !== 0) return '';
  return bytesHex(hexBytes(hex).reverse());
}
function fillZeroLeft(s, chars) {                   // HexKit.fillZeroLeft: 先大写再左补 0
  let t = s.toUpperCase();
  while (t.length < chars) t = '0' + t;
  return t.slice(0, Math.max(chars, t.length));
}
function asciiHex(s, nBytes) {                      // 按 UTF-16 码元，低 8 位，右补零不截断
  let h = '';
  for (const u of s) h += (u.charCodeAt(0) & 0xff).toString(16).padStart(2, '0');
  while (h.length < nBytes * 2) h += '0';
  return h;
}

// ---------------- AESKit ----------------
function encryptHex(plainHex, keyHex) {
  let plain = Buffer.from(hexBytes(plainHex));
  const rem = plain.length % 16;
  if (rem !== 0) plain = Buffer.concat([plain, Buffer.alloc(16 - rem, 0)]);
  const key = Buffer.from(hexBytes(keyHex));
  if (key.length !== 16) return '';
  const c = crypto.createCipheriv('aes-128-ecb', key, null);
  c.setAutoPadding(false);
  return bytesHex([...Buffer.concat([c.update(plain), c.final()])]);
}

// ---------------- ZKProtocol ----------------
const VALID_TO_2118 = Number(protoFromMs(4670438400000)) >>> 0;
function buildKLV(key, valHex) { return hexPair(key) + hexPair(valHex.length / 2) + valHex; }
function buildFrame(cmd, klvHex, header = 8) {
  const len = klvHex.length / 2;
  const head = '8700' + hexPair(len & 0xff) + hexPair((len >> 8) & 0xff) + hexPair(cmd);
  return (header === 8 ? head + '000000' + klvHex : head + '0000' + '000000' + klvHex).toUpperCase();
}
function buildEkey(cmd, macHex, validFromSec = 0, validToSec = null, trackIdVal = 0) {
  const vt = validToSec === null ? VALID_TO_2118 : validToSec;
  let mac = macHex.toLowerCase().split(':').join('');
  if (!mac) mac = '000000000000';
  return ('8800' + reversePairs(mac) + u32leHex(trackIdVal) + u32leHex(validFromSec) + u32leHex(vt) + hexPair(cmd)).toUpperCase();
}
function wrapEnc(cmd, macHex, skeyHex, bodyHex, klvKey) {
  const cipher = encryptHex(buildEkey(cmd, macHex) + bodyHex, skeyHex);
  return cipher === '' ? '' : buildKLV(klvKey, cipher);
}
function wrapFrame(cmd, macHex, skeyHex, bodyHex, klvKey) {
  const enc = wrapEnc(cmd, macHex, skeyHex, bodyHex, klvKey);
  return enc === '' ? '' : buildFrame(cmd, enc, 8);
}

// ---------------- ZKCmdBuilder: 时间串 → 协议秒 ----------------
// Swift protoSecOrNil: 纯数字(秒/毫秒) / ISO8601 / 'yyyy-MM-dd HH:mm:ss' 按**设备本地**时区
function protoSecOrNil(s) {
  if (s === null || s === undefined) return null;
  const raw = String(s).trim();
  if (!raw) return null;
  if (/^-?\d+$/.test(raw)) { const n = BigInt(raw); return Number(n > 1000000000000n ? n / 1000n : n); }
  const m = raw.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/);
  if (m) return Number(protoFromMs(new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime()));
  const d = raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (d) return Number(protoFromMs(Date.UTC(+d[1], +d[2] - 1, +d[3])));   // JS 侧对日期-only 追加 T00:00:00Z
  const p = Date.parse(raw);
  return Number.isNaN(p) ? null : Number(protoFromMs(p));
}
const protoSec = (v) => { const x = protoSecOrNil(v); return x === null ? Number(protoFromMs(Date.now())) : x; };
function pinToLEOrNil(pin) {
  let h = String(pin).trim().toLowerCase();
  if (h.startsWith('0x')) h = h.slice(2);
  if (h.length === 8 && /^[0-9a-f]{8}$/.test(h)) return h;
  if (!h || !/^\d+$/.test(h)) return null;
  return u32leHex(Number(BigInt(h) & 0xffffffffn));
}
function buildEkeyOpen(skeyHex, macHex, pin, validFromSec = 0, validToSec = null, trackId = 0) {
  const p = pinToLEOrNil(pin);
  if (p === null) return '';
  return encryptHex(buildEkey(0x04, macHex, validFromSec, validToSec, trackId) + p + '00' + '00', skeyHex);
}

// ---------------- 逐条向量 (输入与 tools/golden.js 完全一致) ----------------
const V = [];
const add = (key, got) => V.push([key, golden[key], got]);
const U = (v) => Number(BigInt.asIntN(32, BigInt(v))) >>> 0;      // Swift UInt32(truncatingIfNeeded:)

add('cmd01Session', buildFrame(0x01, '', 8));
add('cmd23ExKeyWay', buildFrame(0x23, '', 8));
add('cmd12Echo', buildFrame(0x12, buildKLV(0x01, '123456'), 8));
add('cmd03StatusPlain', buildFrame(0x03, '', 8));
add('cmd03StatusWrap', (() => {
  const enc = encryptHex(buildEkey(0x03, MAC), SKEY);
  if (enc === '') return '';
  return buildFrame(0x03, buildKLV(0x01, enc) + buildKLV(0x02, ''), 8);
})());
add('cmd04Open_klv01', buildFrame(0x04, buildKLV(0x01, fillZeroLeft('0000', 32)) + buildKLV(0x02, 'cafebabe'.repeat(4)), 8));
add('cmd05Exchange', buildFrame(0x05, buildKLV(0x01, u32leHex(0x5a)) + buildKLV(0x02, '01') + buildKLV(0x03, SKEY), 8));
add('cmd08SyncPins', wrapFrame(0x08, MAC, SKEY, hexPair(2) + hexPair(1) + '11223344' + '55667788' + 'ffffffff', 0x01));
add('cmd0ASyncPwd_add', wrapFrame(0x0a, MAC, SKEY, u16leHex(0) + asciiHex('123456', 8) + u32leHex(U(protoSec('2010-01-01 00:00:00'))) + u32leHex(U(protoSec('2118-01-01 00:00:00'))), 0x01));
add('cmd0ASyncPwd_modify', wrapFrame(0x0a, MAC, SKEY, u16leHex(5) + asciiHex('654321', 8) + u32leHex(U(protoSec('2026-01-01 00:00:00'))) + u32leHex(U(protoSec('2118-01-01 00:00:00'))), 0x01));
add('cmd0ASyncPwd_del', wrapFrame(0x0a, MAC, SKEY, u16leHex(0xffff) + asciiHex('', 8) + u32leHex(U(protoSec('2010-01-01 00:00:00'))) + u32leHex(U(protoSec('2118-01-01 00:00:00'))), 0x01));
add('cmd0BExpire', wrapFrame(0x0b, MAC, SKEY, u16leHex(5) + u32leHex(U(protoSec('2026-01-01 00:00:00'))) + u32leHex(U(protoSec('2118-01-01 00:00:00'))), 0x01));
add('cmd0ESyncTime', wrapFrame(0x0e, MAC, SKEY, u32leHex(U(530000000)), 0x02));
add('cmd13AddFp', wrapFrame(0x13, MAC, SKEY, hexPair(8) + hexPair(15), 0x02));
add('cmd14FpConfirm', wrapFrame(0x14, MAC, SKEY, u32leHex(77) + u32leHex(U(protoSec('2010-01-01 00:00:00'))) + u32leHex(U(protoSec('2118-01-01 00:00:00'))), 0x02));
add('cmd15DeleteFp', wrapFrame(0x15, MAC, SKEY, u32leHex(77), 0x02));
add('cmd16GetLog', wrapFrame(0x16, MAC, SKEY, hexPair(0) + u32leHex(0xffffffff) + hexPair(5), 0x01));
add('cmd18Volume', wrapFrame(0x18, MAC, SKEY, hexPair(1), 0x02));   // 夹具传的是已换算过的 1 (静音)：vendor lock.js:412 与 Swift 同为 on ? 1 : 0
add('cmd19OpenZotp', wrapFrame(0x19, MAC, SKEY, hexPair(1), 0x02));
add('cmd20Validation', wrapFrame(0x20, MAC, SKEY, hexPair(1), 0x02));
add('cmd21SetBkey', wrapFrame(0x21, MAC, SKEY, '10' + 'aabbccddeeff00112233445566778899', 0x02));
add('cmd22EnableDfu', wrapFrame(0x22, MAC, SKEY, hexPair(0), 0x02));
add('cmd24AutoLock', wrapFrame(0x24, MAC, SKEY, hexPair(3), 0x01));
add('cmd25Defence_aperiodic', wrapFrame(0x25, MAC, SKEY, hexPair(1) + u32leHex(0) + u32leHex(0), 0x01));
add('cmd25Defence_period', wrapFrame(0x25, MAC, SKEY, hexPair(2) + u32leHex(21600) + u32leHex(43200), 0x01));
add('buildEkeyOpen', buildEkeyOpen(SKEY, MAC, 123456, 0, Number(protoFromMs(Date.parse('2118-01-01T00:00:00Z'))), 12345));
add('cmd41WriteEkey', buildFrame(0x41, buildKLV(0x01, reversePairs(MAC)) + buildKLV(0x02, hexPair(1)) + buildKLV(0x03, u16leHex(16289)) + buildKLV(0x04, V.find((x) => x[0] === 'buildEkeyOpen')[2]), 8));
add('cmd41WriteEkey_del', buildFrame(0x41, buildKLV(0x01, reversePairs(MAC)) + buildKLV(0x02, hexPair(1)) + buildKLV(0x03, u16leHex(16289)) + buildKLV(0x04, ''), 8));
add('cmd44GetEkeyInfo_all', buildFrame(0x44, buildKLV(0x01, ''), 8));
add('cmd44GetEkeyInfo_one', buildFrame(0x44, buildKLV(0x01, reversePairs(MAC)), 8));
add('cmd43KeychainStatus_empty', buildFrame(0x43, buildKLV(0x01, ''), 8));
add('cmd43KeychainStatus_two', buildFrame(0x43, buildKLV(0x01, reversePairs('aabbccddeeff') + reversePairs('112233445566')), 8));

// ---- 内部反向不变式：这几条不成立就说明复刻本身退化成"永远返回同一串"，比对将失去意义 ----
const assert = require('assert');
assert.notStrictEqual(wrapFrame(0x25, MAC, SKEY, hexPair(2) + u32leHex(21600) + u32leHex(43200), 0x01),
  wrapFrame(0x25, MAC, SKEY, hexPair(2) + u32leHex(21601) + u32leHex(43200), 0x01), '不变式: body 差一个刻度必须换帧');
assert.notStrictEqual(buildFrame(0x12, buildKLV(0x01, '123456'), 8), buildFrame(0x12, buildKLV(0x02, '123456'), 8),
  '不变式: KLV 键位变了必须换帧 (防"键写错看不出来")');
assert.strictEqual(reversePairs('ABC'), '', '不变式: 奇数长度 hex 走 HexKit 的失败分支返回空串');
assert.strictEqual(buildEkey(0x04, '').slice(0, 16), '8800000000000000', '不变式: 空 MAC 落占位串而不是短帧');
assert.strictEqual(buildFrame(0x01, '', 8).length, 16, '不变式: 无 KLV 的 8B 头帧固定 8 字节');
assert.strictEqual(wrapEnc(0x0a, MAC, '001122', '', 0x01), '', '不变式: 非法长度密钥 ⇒ 空密文 (由 wrapFrame 拦成空帧)');

let bad = 0, miss = 0;
for (const [key, want, got] of V) {
  if (want === undefined) { miss++; console.log(`? ${key} 夹具里没有这一条 (输入或键名对不上)`); continue; }
  const ok = String(want).toUpperCase() === String(got).toUpperCase();
  if (!ok) {
    bad++;
    console.log(`✗ ${key}\n    基线(JSS) ${String(want).toUpperCase()}\n    Swift复刻 ${String(got).toUpperCase()}`);
  }
}
const covered = V.length - miss;
console.log(`\nZK 命令帧跨语言差分: ${covered - bad}/${covered} 条逐字节一致 (夹具共 ${Object.keys(golden).length} 条, 本工具复刻 ${covered} 条)`);
const skipped = Object.keys(golden).filter((k) => !V.some((x) => x[0] === k));
console.log('未纳入差分的向量 (' + skipped.length + '): ' + (skipped.join(', ') || '无'));
console.log('边界: 整帧比对是**字节级**证据；不覆盖锁端固件是否认这些字节 (那要真锁), 也不覆盖 parseResponse 一侧。');
process.exit(bad || miss ? 1 : 0);
