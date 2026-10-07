// 最小 ZIP 读取器 (DFU 固件包解析) — 零依赖
//   * 输入 ArrayBuffer/Uint8Array → entries [{name, method, data, crcOk}]
//   * 支持 method 0 (Stored) 与 8 (Deflate, RFC 1951 原生 inflate — 固定+动态 Huffman)
//   * CRC32 (IEEE 802.3, 与 zlib 一致) — Nordic DFU 校验和同款多项式
//   * nrfutil 生成的固件包为 Stored; Deflate 支持兜底用户自行打包的场景
// 本模块纯 Node 可测 (tests/dfuzip.test.js 对照 node:zlib 与真实固件包)。

// ---------- CRC32 (IEEE, 反射多项式 0xEDB88320) ----------
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(bytes, initCrc, range) {
  let c = (initCrc === undefined) ? 0xFFFFFFFF : (~initCrc >>> 0);
  const start = (range && range.start) || 0;
  const end = (range && range.end !== undefined) ? range.end : bytes.length;
  for (let i = start; i < end; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
  return (~c) >>> 0;
}

// ---------- 原生 inflate (RFC 1951; 参考实现: Mark Adler puff) ----------
// maxOut: 输出字节上限 (zip 炸弹防护); 预期大小 expectedSize 仅作初始容量提示
function inflate(data, expectedSize, maxOut) {
  const cap = maxOut || 8 * 1024 * 1024;
  if (expectedSize > cap) throw new Error('inflate: 声称输出 ' + expectedSize + 'B 超上限');
  let pos = 0; // 位级游标用字节+bit 维护
  let bitBuf = 0, bitCnt = 0;
  const out = new Uint8Array(expectedSize || 0);
  let outLen = 0;
  const grow = n => {
    if (outLen + n <= outBuf.length) return; // 以当前缓冲为准 (扩张后不再逐字节重分配)
    if (outLen + n > cap) throw new Error('inflate: 输出超上限 (' + cap + 'B) — 疑似 zip 炸弹');
    let cap2 = outBuf.length || 1024;
    while (cap2 < outLen + n) cap2 *= 2;
    const o = new Uint8Array(cap2);
    o.set(outBuf.subarray(0, outLen));
    outBuf = o;
  };
  let outBuf = out;
  const bits = need => {
    let val = bitBuf;
    while (bitCnt < need) {
      if (pos >= data.length) throw new Error('inflate: 输入提前结束');
      val |= data[pos++] << bitCnt;
      bitCnt += 8;
    }
    bitBuf = val >>> need;
    bitCnt -= need;
    return val & ((1 << need) - 1);
  };
  const emit = b => { grow(1); outBuf[outLen++] = b; };
  // Huffman 解码表: 简化实现 — 逐位遍历码树 (counts/数组法, puff 风格 build + decode)
  function buildHuffman(lengths) {
    const counts = new Array(16).fill(0);
    for (const l of lengths) counts[l]++;
    counts[0] = 0;
    const offs = new Array(16).fill(0);
    let tot = 0;
    for (let i = 1; i < 16; i++) { offs[i] = tot; tot += counts[i]; }
    const symbols = new Array(tot);
    for (let s = 0; s < lengths.length; s++) if (lengths[s]) symbols[offs[lengths[s]]++] = s;
    return { counts, symbols };
  }
  function decode(h) {
    let code = 0, first = 0, index = 0;
    for (let len = 1; len < 16; len++) {
      code |= bits(1);
      const count = h.counts[len];
      if (code - first < count) return h.symbols[index + (code - first)];
      index += count;
      first = (first + count) << 1;
      code <<= 1;
    }
    throw new Error('inflate: 非法 Huffman 码');
  }
  const LEN_BASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
  const LEN_EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
  const DIST_BASE = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
  const DIST_EXTRA = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
  function codes(litH, distH) {
    for (;;) {
      const sym = decode(litH);
      if (sym < 256) emit(sym);
      else if (sym === 256) return;
      else {
        const si = sym - 257;
        if (si >= LEN_BASE.length) throw new Error('inflate: 非法长度符号');
        const len = LEN_BASE[si] + bits(LEN_EXTRA[si]);
        const ds = decode(distH);
        const dist = DIST_BASE[ds] + bits(DIST_EXTRA[ds]);
        if (dist > outLen) throw new Error('inflate: 距离越界');
        for (let i = 0; i < len; i++) { const b = outBuf[outLen - dist]; grow(1); outBuf[outLen++] = b; }
      }
    }
  }
  function stored() {
    bitBuf = 0; bitCnt = 0; // 丢弃位缓冲余数
    if (pos + 4 > data.length) throw new Error('inflate: stored 块越界');
    const len = data[pos] | (data[pos + 1] << 8);
    const nlen = data[pos + 2] | (data[pos + 3] << 8);
    pos += 4;
    if (len !== (~nlen & 0xFFFF)) throw new Error('inflate: stored LEN/NLEN 校验失败');
    grow(len);
    for (let i = 0; i < len; i++) outBuf[outLen++] = data[pos + i];
    pos += len;
  }
  function block(litH, distH) {
    if (litH) codes(litH, distH);
    else stored();
  }
  function fixedTables() {
    const lit = new Array(288);
    for (let i = 0; i < 144; i++) lit[i] = 8;
    for (let i = 144; i < 256; i++) lit[i] = 9;
    for (let i = 256; i < 280; i++) lit[i] = 7;
    for (let i = 280; i < 288; i++) lit[i] = 8;
    const dist = new Array(30).fill(5);
    return [buildHuffman(lit), buildHuffman(dist)];
  }
  function dynamicTables() {
    const ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
    const nlen = bits(5) + 257, ndist = bits(5) + 1, ncode = bits(4) + 4;
    const lens = new Array(19).fill(0);
    for (let i = 0; i < ncode; i++) lens[ORDER[i]] = bits(3);
    const codeH = buildHuffman(lens);
    const all = new Array(nlen + ndist).fill(0);
    let i = 0;
    while (i < nlen + ndist) {
      const sym = decode(codeH);
      if (sym < 16) { all[i++] = sym; continue; }
      let len = 0, val = 0;
      if (sym === 16) { if (i === 0) throw new Error('inflate: 重复无前值'); len = 3 + bits(2); val = all[i - 1]; }
      else if (sym === 17) { len = 3 + bits(3); val = 0; }
      else { len = 11 + bits(7); val = 0; }
      while (len--) all[i++] = val;
    }
    if (all[256] === 0) throw new Error('inflate: 缺少块结束符');
    return [buildHuffman(all.slice(0, nlen)), buildHuffman(all.slice(nlen))];
  }
  let last = 0;
  do {
    last = bits(1);
    const type = bits(2);
    if (type === 0) block(null, null);
    else if (type === 1) { const [l, d] = fixedTables(); block(l, d); }
    else if (type === 2) { const [l, d] = dynamicTables(); block(l, d); }
    else throw new Error('inflate: 非法块类型');
  } while (!last);
  return outBuf.subarray(0, outLen);
}

// ---------- ZIP 结构解析 ----------
// 对抗上限 (固件包是用户导入的外部文件 — 恶意/损坏的 zip 不得打爆内存):
//   单条目解压上限 8MB (真实固件 ~74KB, 富余百倍), 条目数 ≤ 64, inflate 输出越限即抛错
const MAX_ENTRY_SIZE = 8 * 1024 * 1024;
const MAX_ENTRIES = 64;
function u16le(b, o) { return b[o] | (b[o + 1] << 8); }
function u32le(b, o) { return (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0; }
function latin1(b, o, len) { let s = ''; for (let i = 0; i < len; i++) s += String.fromCharCode(b[o + i]); return s; }

// entries: [{name, method, data:Uint8Array, size, crc, crcOk}]
function zipParse(buf) {
  const b = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  // EOCD: 从尾部向前找 0x06054b50 (注释 ≤ 65KB + 22B 头)
  let eocd = -1;
  const minOff = Math.max(0, b.length - 22 - 65535);
  for (let i = b.length - 22; i >= minOff; i--) {
    if (b[i] === 0x50 && b[i + 1] === 0x4b && b[i + 2] === 0x05 && b[i + 3] === 0x06) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('ZIP: 未找到目录结尾 (不是有效的 zip 文件)');
  const count = u16le(b, eocd + 10);
  if (count > MAX_ENTRIES) throw new Error('ZIP: 条目数异常 (' + count + ')');
  let off = u32le(b, eocd + 16);
  const entries = [];
  for (let n = 0; n < count; n++) {
    if (off + 46 > b.length || u32le(b, off) !== 0x02014b50) throw new Error('ZIP: 中央目录损坏');
    const method = u16le(b, off + 10);
    const crcExpect = u32le(b, off + 16);
    const csize = u32le(b, off + 20);
    const usize = u32le(b, off + 24);
    const nameLen = u16le(b, off + 28);
    const extraLen = u16le(b, off + 30);
    const cmtLen = u16le(b, off + 32);
    const lho = u32le(b, off + 42);
    if (off + 46 + nameLen + extraLen + cmtLen > b.length) throw new Error('ZIP: 中央目录越界');
    const name = latin1(b, off + 46, nameLen);
    if (usize > MAX_ENTRY_SIZE || csize > b.length) throw new Error('ZIP: 条目解压尺寸异常 (' + name + ' 声称 ' + usize + 'B) — 已拒绝');
    // 本地头: 取 nameLen/extraLen 的本地值定位数据
    if (lho + 30 > b.length || u32le(b, lho) !== 0x04034b50) throw new Error('ZIP: 本地文件头损坏 (' + name + ')');
    const lNameLen = u16le(b, lho + 26);
    const lExtraLen = u16le(b, lho + 28);
    const dataOff = lho + 30 + lNameLen + lExtraLen;
    if (dataOff + csize > b.length) throw new Error('ZIP: 条目数据越界 (' + name + ')');
    const cdata = b.subarray(dataOff, dataOff + csize);
    let data;
    if (method === 0) data = cdata.slice();
    else if (method === 8) data = inflate(cdata, usize, MAX_ENTRY_SIZE).slice();
    else throw new Error('ZIP: 不支持的压缩方式 ' + method + ' (' + name + ')');
    if (usize && data.length !== usize) throw new Error('ZIP: 解压长度不符 (' + name + ')');
    entries.push({ name, method, data, size: data.length, crc: crcExpect, crcOk: crc32(data) === crcExpect });
    off += 46 + nameLen + extraLen + cmtLen;
  }
  return entries;
}
function zipFind(entries, name) {
  const n = String(name).split('/').pop().toLowerCase(); // 扩展: 按文件名(不含路径)匹配
  for (const e of entries) {
    if (e.name === name) return e;
    if (e.name.split('/').pop().toLowerCase() === n) return e;
  }
  return null;
}

module.exports = { crc32, inflate, zipParse, zipFind };
