#!/usr/bin/env node
// tools/zotpshadow.js — ZOTP 的**跨语言差分** (第一百七十二批新增，判失败)
//
// 这条为什么值得单独跑：`ZOTP.generate` 是"走近门锁掏出手机输的 6 位码"的算术，
// 而它唯一的验证手段是 `Tests/GoldenDiffTests.testZOTP` —— 那条 XCTest 从未执行过 (§10.2)。
// 金标 `fixtures/golden.json` 的 zotp 四格出自 vendor JS 基线 (`utils/zotp.js`)，
// 所以这里把 **Swift 侧** (`ZOTP.swift` + `AESKit.encryptHex` + `HexKit.reversePairs/bytes`) 逐行复刻成 node，
// 再用 node 自带的 AES 跑同一批输入 —— 对不上就说明 Swift 移植与基线在算术上分家了。
//
// ⚠ 边界照实说：这证明的是"Swift 源码写出来的算法"与"基线算法"在这四个向量上一致，
//   不是"Swift 在真机上跑出来一致"。它替代不了 XCTest，也替代不了拿真锁试一次临时码。
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert');

const ROOT = path.resolve(__dirname, '..');
const golden = JSON.parse(fs.readFileSync(path.join(ROOT, 'fixtures/golden.json'), 'utf8')).zotp;
const MAC = 'aabbccddeeff';
const SKEY = '00112233445566778899aabbccddeeff';
const FIXED_SEC = golden.fixedSec;                    // 1800000000

// ---- HexKit.bytes(hex): 非 hex 落 0x00 且保长度 (这里输入都是合法 hex) ----
function hexBytes(hex) {
  const out = [];
  for (let i = 0; i + 1 < hex.length; i += 2) {
    const pair = hex.slice(i, i + 2);
    const n = Number.parseInt(pair, 16);
    out.push(Number.isNaN(n) ? 0 : n & 0xff);         // 复刻 parseInt 的前缀语义由 bytes 承担
  }
  return out;
}
const bytesHex = (b) => b.map((x) => x.toString(16).padStart(2, '0')).join('').toUpperCase();

// ---- HexKit.reversePairs: 整节序反转 (名字叫 pairs，实现就是 bytes().reversed()) ----
function reversePairs(hex) {
  if (hex.length % 2 !== 0) return '';
  return bytesHex(hexBytes(hex).reverse());
}

// ---- AESKit.encryptHex: ZeroPadding (已对齐则不补) + ECB ----
function encryptHex(plainHex, keyHex) {
  let plain = Buffer.from(hexBytes(plainHex));
  const rem = plain.length % 16;
  if (rem !== 0) plain = Buffer.concat([plain, Buffer.alloc(16 - rem, 0)]);
  const key = Buffer.from(hexBytes(keyHex));
  if (key.length !== 16) return '';
  const c = crypto.createCipheriv('aes-128-ecb', key, null);
  c.setAutoPadding(false);
  const out = Buffer.concat([c.update(plain), c.final()]);
  return bytesHex([...out]);
}

// ---- ZOTP.le2be2: 低 16 位按普通十六进制写 ----
const le2be2 = (v) => ((v >>> 0) & 0xffff).toString(16).padStart(4, '0').toUpperCase();

// ---- ZOTP.generate 逐行复刻 ----
function generate({ macHex, skeyHex, periodSec, idx, nowSec }) {
  const t = periodSec > 0 ? periodSec : 30;
  const now = nowSec === undefined || nowSec === null ? null : nowSec;
  const u = (Math.floor(now / (60 * t))).toString(16).toUpperCase();
  const uPadded = '0'.repeat(Math.max(0, 8 - u.length)) + u;
  const r = macHex.split(':').join('').toUpperCase();
  // Swift 侧第一百七十二批补的 guard (跨语言两边要一起改，否则这份差分就是在验旧代码)
  if (r.length !== 12 || !/^[0-9A-F]{12}$/.test(r)) return '';
  const a = idx > 0 ? le2be2(idx) : '0000';
  const c = uPadded + reversePairs(r) + a + '00000000';
  const p = encryptHex(c, skeyHex).toUpperCase();
  if (p.length !== 32) return '';
  const body = p.slice(0, p.length - 8);
  const bytes = hexBytes(body);
  let m = '';
  for (let i = 0; i + 1 < bytes.length; i += 2) m += String((bytes[i] ^ bytes[i + 1]) % 10);
  return m;
}

// ---- 四个向量 (与 GoldenDiffTests.testZOTP 的 periods/idxs 一致) ----
const CASES = [
  ['v30_0', 30, 0], ['v30_1', 30, 1], ['v30_99', 30, 99], ['v60_0', 60, 0],
];
let bad = 0;
for (const [name, period, idx] of CASES) {
  const want = golden[name];
  const got = generate({ macHex: MAC, skeyHex: SKEY, periodSec: period, idx, nowSec: FIXED_SEC });
  const ok = got === want;
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : '✗  '}zotp.${name}  基线=${want}  Swift复刻=${got}  (t=${period} idx=${idx})`);
}

// 中间量单独打一遍：窗口计数器与拼接的明文块，出问题时这两行就是定位点
const u30 = Math.floor(FIXED_SEC / 1800).toString(16).toUpperCase().padStart(8, '0');
const u60 = Math.floor(FIXED_SEC / 3600).toString(16).toUpperCase().padStart(8, '0');
console.log(`窗口计数器: t=30 ⇒ ${u30}   t=60 ⇒ ${u60}   MAC 反序 ⇒ ${reversePairs(MAC)}`);

// 真实调用点的形状：`kc.mac` 可能是冒号分隔的大写形式 (台账存法随导入来源而变)，
// 而金标用的是无冒号串 —— 两条必须算出同一个码，否则"金标验不到生产路径"。
const colonForm = generate({ macHex: 'AA:BB:CC:DD:EE:FF', skeyHex: SKEY, periodSec: 30, idx: 0, nowSec: FIXED_SEC });
console.log(`${colonForm === golden.v30_0 ? 'ok  ' : '✗  '}冒号形 mac 与无冒号形同一个码  (${colonForm} vs ${golden.v30_0})`);
// 畸形 mac 现在必须空串 (第一百七十二批补的 guard)：以前会吐出一个"看着能开、注定开不了"的六位码
const oddForm = generate({ macHex: 'AABBCCDDEE', skeyHex: SKEY, periodSec: 30, idx: 0, nowSec: FIXED_SEC });
console.log(`${oddForm === '' ? 'ok  ' : '✗  '}畸形 mac 返回空串而不是错码  (得到 "${oddForm}")`);
// periodSec 传 0 时两边都落到默认 30
const zeroPeriod = generate({ macHex: MAC, skeyHex: SKEY, periodSec: 0, idx: 0, nowSec: FIXED_SEC });
console.log(`${zeroPeriod === golden.v30_0 ? 'ok  ' : '✗  '}periodSec=0 ⇒ 按 30 分钟窗口  (${zeroPeriod})`);
bad += (colonForm === golden.v30_0 ? 0 : 1) + (oddForm === '' ? 0 : 1) + (zeroPeriod === golden.v30_0 ? 0 : 1);

// 反向不变式：复刻本身要真的会响 —— 若基线算法被换掉而这里没跟上，必须红
assert.notStrictEqual(generate({ macHex: MAC, skeyHex: SKEY, periodSec: 30, idx: 0, nowSec: FIXED_SEC + 1800 }), golden.v30_0,
  '影子自检: 跨一个窗口就该换码');
// idx 参与拼接的那 4 个十六进制位必须影响结果 (否则"逐人临时码"其实是同一个码)
assert.notStrictEqual(generate({ macHex: MAC, skeyHex: SKEY, periodSec: 30, idx: 1, nowSec: FIXED_SEC }),
  generate({ macHex: MAC, skeyHex: SKEY, periodSec: 30, idx: 2, nowSec: FIXED_SEC }),
  '影子自检: idx 不参与输出 ⇒ 所有成员的临时码会相同');

const total = CASES.length + 3;
console.log(bad ? `✗ ${bad}/${total} 条与基线/不变式分家` : `ZOTP 跨语言差分 ${total}/${total} 全过 ✓`);
console.log('边界: 证明的是"Swift 源码写出的算法"与基线在算术上一致；XCTest 仍未执行，真锁上没试过一次。');
process.exit(bad ? 1 : 0);
