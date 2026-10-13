#!/usr/bin/env node
// 备份包校验和跨语言差分 (第一百七十八批新增, 判失败)
//   权威侧 = miniprogram-app/utils/storage.js 的 fnv1a32，其现跑输出已烘成 fixtures/canonical.json
//   (vendor/ 里没有 storage.js —— 这一族此前 22 道闸门一道都覆盖不到)
//   Swift 侧 = App/Services/BackupCanonical.swift 的 fnv1a32Hex，下面按源码逐行复刻。
// 边界: 它证明"复刻出的算术"与权威向量一致；**不证明**复刻与 Swift 源码逐行一致 (那仍靠人读)，
//       也不证明真机能解真锁导出的包。改 Swift 那侧任何一个字符，这里要同步改，否则差分在验旧代码。
'use strict';
const fs = require('fs');
const FIX = 'fixtures/canonical.json';
if (!fs.existsSync(FIX)) { console.error('✗ 缺 fixtures/canonical.json (向量夹具)'); process.exit(2); }
const fx = JSON.parse(fs.readFileSync(FIX, 'utf8'));
if (!Array.isArray(fx.vectors) || !fx.vectors.length) { console.error('✗ 夹具里没有向量'); process.exit(2); }

// ---- Swift fnv1a32Hex 的逐行复刻 ----
function swiftChecksum(s, opts) {
  const o = opts || {};
  const MOD = 4294967296, HALF = 2147483648, PRIME = BigInt(o.prime !== undefined ? o.prime : 16777619);
  // UTF-16 码元序列 (与 Swift 的 s.utf16 / JS 的 charCodeAt 同一条链)；探针可切到 UTF-8 字节
  const feed = o.bytes === 'utf8' ? Array.from(Buffer.from(s, 'utf8'))
    : Array.from({ length: s.length }, (_, i) => s.charCodeAt(i));
  let h = o.init !== undefined ? o.init : 0x811c9dc5;
  for (const unit of feed) {
    const signed = (o.unsignedXor === false) ? h : (h >= HALF ? h - MOD : h);
    const xored = BigInt(Math.trunc(signed)) ^ BigInt(unit & 0xff);
    let u;
    if (o.exact) {                       // 探针: 不丢双精度 ⇒ 精确模乘
      let m = ((xored % 4294967296n) + 4294967296n) % 4294967296n;
      m = (m * PRIME) % 4294967296n;
      u = Number(m);
    } else {                             // 与 Swift/JS 同一次双精度舍入
      const prod = Number(xored) * Number(PRIME);
      u = prod % MOD;
      if (u < 0) u += MOD;
    }
    h = u;
  }
  return (o.pad === false ? h.toString(16) : ('00000000' + h.toString(16)).slice(-8));
}
// ---- 旧实现 (本仓 178 批之前的语义) —— 用来证明差异真实存在, 不是"夹具写错了" ----
function legacyChecksum(s) {
  let h = 0x811c9dc5 >>> 0;
  for (const b of Buffer.from(s, 'utf8')) { h ^= b; h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16);
}

let bad = 0;
for (const v of fx.vectors) {
  const got = swiftChecksum(v.s);
  if (got !== v.sum) { console.log(`✗ 向量不一致: ${JSON.stringify(v.s).slice(0, 40)} 期望 ${v.sum} 得到 ${got}`); bad++; }
}
console.log(`校验和差分: ${fx.vectors.length - bad}/${fx.vectors.length} 条与小程序权威侧一致`);

// ---- 正控: 每一处 JS 语义都必须"改了它就红" (没见过自己开火的尺子不算尺子)。
//       探针是实测挑出来的：ASCII 串分不出 UTF-16/UTF-8，短串分不出补零，所以各挑各的输入。
const PROBE_BYTES = '家门锁给保洁阿姨·今晚10点前';   // 非 ASCII ⇒ 喂 UTF-8 字节就会漂
const PROBE_SIGN = 'abc';                            // 高位为 1 的 h ⇒ ^ 的符号参与双精度舍入
const PROBE_EXACT = 'x'.repeat(40);                  // 积超 2^53 ⇒ 精确模乘就会漂
const PROBE_PAD = 'lockkeeper';                      // 权威侧这条以 0 开头 ⇒ 不补零就少一位
const fires = [
  ['喂 UTF-8 字节而不是 UTF-16 码元', swiftChecksum(PROBE_BYTES, { bytes: 'utf8' }) !== swiftChecksum(PROBE_BYTES)],
  ['^ 不做有符号 int32 转换', swiftChecksum(PROBE_SIGN, { unsignedXor: false }) !== swiftChecksum(PROBE_SIGN)],
  ['乘法不丢双精度 (精确模乘)', swiftChecksum(PROBE_EXACT, { exact: true }) !== swiftChecksum(PROBE_EXACT)],
  ['不补零到 8 位', swiftChecksum(PROBE_PAD, { pad: false }) !== swiftChecksum(PROBE_PAD)],
];
for (const [name, fired] of fires) {
  if (!fired) { console.log(`✗ 正控没开火: ${name}`); bad++; }
  else console.log(`  正控 ✓ 开火: ${name}`);
}
// ---- 反控: 旧实现必须与权威向量不同 —— 否则"这条差分没在测任何东西" ----
const legacyMatches = fx.vectors.filter(v => legacyChecksum(v.s) === v.sum).length;
console.log(`  反控: 旧 (UTF-8+精确模乘+不补零) 语义命中权威向量 ${legacyMatches}/${fx.vectors.length} 条`);
if (legacyMatches === fx.vectors.length) { console.log('✗ 反控失效: 旧语义与权威完全一致, 说明向量或复刻有问题'); bad++; }

if (bad) { console.log(`✗ bundleshadow 失败 ${bad} 项`); process.exit(2); }
console.log('bundleshadow ✓ 备份包校验和与小程序权威侧一致');
