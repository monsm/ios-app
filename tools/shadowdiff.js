// 影子对拍 (shadowdiff.js) —— 编译前差分：把 Swift 侧纯函数的**语义**逐条重写成 JS，与 vendor JS 权威核心对拍。
// 为什么需要它：本仓库至今没跑过编译器，XCTest 里的 GoldenDiffTests 也就从未执行过 (docs/AUDIT-CODE.md §10.2)。
// 这份脚本能在此之前抓到"Swift 与 JS 对同一串输入算出不同结果"的那类缺陷 (字节面不一致 = 锁端读到不同密码)。
//
// 它**不是**编译产物：下面每个 swift* 函数都是手抄 App/Core/*.swift 的判断写的，
// 抄错就会与 vendor 结果"一致地错"或"不一致地报"。所以它的绿只能说明"我读到的一致性成立"，
// 不能替代 xcodebuild test；输出末尾也会把这句话打出来。
'use strict';
const path = require('path');
const cmds = require(path.join(__dirname, '..', 'vendor/app/utils/kernel/cmds.js'));
const proto = require(path.join(__dirname, '..', 'vendor/app/utils/kernel/protocol.js'));

// ---------- Swift 侧端口 (每条注明抄的源位置) ----------
const seg = new Intl.Segmenter('en', { granularity: 'grapheme' });
// HexKit.bytes (App/Core/HexKit.swift:7-34) —— 遍历 **Character (字素簇)**，非 ASCII 首字符→0x00，
// 次字符非 hex 只取首位 ("1g"→0x01)；奇长末字符两边同丢。
function swiftHexBytes(hex) {
  const gs = Array.from(seg.segment(hex), s => s.segment);
  const nib = c => {
    if (Array.from(c).length !== 1 || c.codePointAt(0) > 0x7f) return null; // asciiValue 只对 ASCII 存在
    const a = c.codePointAt(0);
    if (a >= 0x30 && a <= 0x39) return a - 0x30;
    if (a >= 0x61 && a <= 0x66) return a - 0x61 + 10;
    if (a >= 0x41 && a <= 0x46) return a - 0x41 + 10;
    return null;
  };
  const out = [];
  for (let i = 0; i + 1 < gs.length; i += 2) {
    const n1 = nib(gs[i]);
    if (n1 === null) { out.push(0); continue }
    const n2 = nib(gs[i + 1]);
    out.push(n2 === null ? n1 : ((n1 << 4) | n2));
  }
  return out;
}
const swiftBytesToHex = b => b.map(x => x.toString(16).padStart(2, '0')).join('');   // HexKit.swift:35-38
const swiftHexPair = v => ((v & 0xff).toString(16).padStart(2, '0'));                 // HexKit.swift:48-50
const swiftU32leHex = v => [0, 8, 16, 24].map(s => swiftHexPair((v >>> s) & 0xff)).join(''); // HexKit.swift:44-47
const swiftU16leHex = v => swiftHexPair(v & 0xff) + swiftHexPair((v >> 8) & 0xff);    // HexKit.swift:40-43
const swiftReversePairs = h => (h.length % 2 ? '' : swiftBytesToHex(swiftHexBytes(h).reverse())); // HexKit.swift:63-67
const swiftFillZeroLeft = (s, chars) => {                                             // HexKit.swift:70-75
  let t = (s || '').toUpperCase();
  while (t.length < chars) t = '0' + t;
  return t.slice(0, Math.max(chars, t.length));
};
// HexKit.asciiHex (App/Core/HexKit.swift:84-89) —— 按 **UTF-16 码元** 迭代 (JS charCodeAt 同口径)，右补 '0' 到 n 字节
function swiftAsciiHex(s, nBytes) {
  let h = '';
  for (let i = 0; i < s.length; i++) h += (s.charCodeAt(i) & 0xff).toString(16).padStart(2, '0');
  while (h.length < nBytes * 2) h += '0';
  return h;
}
// StatusParser.leHexToU32 (App/Core/StatusParser.swift:44-49) —— 从末字节向前折成大端读
const swiftLeHexToU32 = val => swiftHexBytes(val).reduceRight((acc, b) => (acc * 256 + b) >>> 0, 0);
// ZKCmdBuilder.protoSecOrNil 的纯数字档 (App/Core/ZKCmdBuilder.swift:22) —— >1e12 当毫秒
function swiftProtoSecNumber(raw) {
  if (!/^-?\d+$/.test(raw)) return null;
  const n = Number(raw);
  if (!Number.isSafeInteger(n)) return 'unsafe';       // Swift Int64 能吃下, JS 不能精确表示 → 单独标
  return n > 1000000000000 ? Math.floor(n / 1000) : n;
}

// ---------- 语料 (含故意难看的输入) ----------
const HEX = ['', '00', 'a1b2c3d4', 'A1B2', '0', 'abc', '1g2h', 'zz', '00112233445566778899aabbccddeeff',
  '1⃣23', 'é1', '🙂x', '  ', 'a1b', 'ffff', '0d0a'];
const ASC = ['', 'A', '123456', '钥匙', '🙂', 'é', 'a\u0000b', 'PIN-01', 'x'.repeat(40)];
const NUM = ['0', '1', '1760000000', '1760000000000', '999999999999999', '-5', '000123'];

let hard = 0, soft = 0, cased = 0, intent = 0, checked = 0;
// 判定分三档, 免得工具变成"永远红"或"永远绿"的装饰：
//   hard   = 合法输入域内的差异 → 判失败 (这才是会写进锁的字节不一致)
//   soft   = 仅大小写差异 → 只报不判失败 (Swift 侧统一小写, JS 保留原样; 我们自产的一律小写)
//   domain = 输入本就不在域内 (非 hex 字符 / 奇数长度 / 字节不够) → 报数不判失败, 但必须看得见
function cmp(name, got, want, opt = {}) {
  checked++;
  const a = JSON.stringify(got), b = JSON.stringify(want);
  if (a === b) return;
  if (opt.domain) { soft++; console.log(`  ⚠ 域外差异 ${name}\n      Swift: ${a}\n      JS   : ${b}\n      ${opt.note || ''}`); return }
  // 有意分歧: 两边都"对", 但选择不同 —— 单列一档并写清理由, 不混进"差异"里让人以为抓到了 bug。
  if (opt.intentional) { intent++; console.log(`  ↷ 有意分歧 ${name}\n      Swift: ${a}\n      JS   : ${b}\n      ${opt.note || ''}`); return }
  // 仅大小写: 单列一档。判它"不致害"的证据是帧构造处统一转大写 ——
  // `ZKProtocol.swift:54/57` 的 buildFrame/wrapFrame 结尾都有 `.uppercased()`，
  // 所以 asciiHex/reversePairs 的大小写差异不会走到锁的字节面上。逐条仍列出来，便于核对新调用点。
  if (typeof got === 'string' && typeof want === 'string' && a.toLowerCase() === b.toLowerCase()) {
    cased++; console.log(`  △ 仅大小写 ${name}\n      Swift: ${a}\n      JS   : ${b}`);
    return;
  }
  hard++; console.log(`  ✗ 差异 ${name}\n      Swift: ${a}\n      JS   : ${b}\n      ${opt.note || ''}`);
}
const isHex = s => /^[0-9a-fA-F]*$/.test(s);
console.log('影子对拍：Swift 端口 vs vendor JS 权威核心');
for (const h of HEX) {
  const okHex = isHex(h) && h.length % 2 === 0;
  cmp(`hexToBytes(${JSON.stringify(h)})`, swiftHexBytes(h), Array.from(proto.hexToBytes(h)),
      { domain: !okHex, note: 'HexKit.bytes' });
  cmp(`reversePairs(${JSON.stringify(h)})`, swiftReversePairs(h), proto.reversePairs(h),
      { domain: !okHex, caseOnly: true, note: 'HexKit.reversePairs' });
  const b = swiftHexBytes(h);
  cmp(`readU32LE(${JSON.stringify(h)},0)`, b.length >= 4 ? (b[0] | b[1] * 256 + b[2] * 65536 + b[3] * 16777216) >>> 0 : 0,
      proto.readU32LE(h, 0),
      { domain: !(okHex && b.length >= 4), note: 'HexKit.readU32LE (JS 不查长度, Swift 越界返 0)' });
}
for (const s of ASC) {
  cmp(`asciiHex(${JSON.stringify(s)},8)`, swiftAsciiHex(s, 8), cmds.asciiHex(s, 8), { note: 'HexKit.asciiHex' });
  cmp(`asciiHex(${JSON.stringify(s)},4)`, swiftAsciiHex(s, 4), cmds.asciiHex(s, 4), { note: '补齐位数不同' });
  cmp(`utf8Hex(${JSON.stringify(s)})`, Buffer.from(s, 'utf8').toString('hex'), cmds.utf8Hex(s), { note: 'HexKit.utf8Hex' });
}
for (const v of [0, 1, 255, 256, 65535, 65536, 4294967295]) {
  cmp(`u32leHex(${v})`, swiftU32leHex(v), cmds.u32leHex(v), { note: 'HexKit.u32leHex' });
  cmp(`hexPair(${v})`, swiftHexPair(v), proto.hexPair(v), { note: 'HexKit.hexPair' });
}
for (const v of [0, 1, 300, 65535, -1]) cmp(`u16leHex(${v})`, swiftU16leHex(v), cmds.u16leHex(v), { note: 'HexKit.u16leHex' });
for (const [s, n] of [['1', 4], ['ab', 4], ['ABCDEF', 2], ['', 2], ['ff', 8]]) {
  cmp(`fillZeroLeft(${JSON.stringify(s)},${n})`, swiftFillZeroLeft(s, n), cmds.fillZeroLeft(s, n), { note: 'HexKit.fillZeroLeft' });
}
for (const n of NUM) {
  const js = cmds.protoSec(n);
  const sw = swiftProtoSecNumber(n);
  if (sw === 'unsafe') { console.log(`  ⚠ 输入 ${n}: 超出 JS 安全整数, 端口不做比较 (Swift 侧用 Int64)`); continue }
  cmp(`protoSec(数字 ${n})`, sw, typeof js === 'number' ? js : Number(js), {
    intentional: /^-?\d+$/.test(n),
    note: 'ZKCmdBuilder.protoSecOrNil 纯数字档 —— JS 的 protoSec 只认 number 类型, 数字**字符串**会 Date.parse 失败后静默回落"现在";'
      + ' Swift 多认这一档 (台账导入的 from/to 常是 epoch 字符串), 属有意分歧, 理由写在源码注释里'
  });
}
console.log(`\n共比对 ${checked} 项：判失败 ${hard} 项 · 域外差异 ${soft} 项 · 仅大小写 ${cased} 项 · 有意分歧 ${intent} 项。`);
console.log('后三档都逐条列出但不判失败：域外=输入本就不在合法域内 (非 hex/奇长/字节不够)；');
console.log('仅大小写=帧构造处统一 .uppercased() (ZKProtocol.swift:54/57)，走不到锁的字节面；有意分歧=两边各有道理，理由在源码注释。');
console.log('注意：这是"手抄语义"的差分，不能替代编译与 XCTest —— 它绿了只说明我读到的两边一致。');
process.exit(hard ? 1 : 0);
