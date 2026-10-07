// AES-128-ECB + ZeroPadding 纯 JS 实现 (零依赖,可运行于微信小程序运行时与 node)
// 依据: App 使用 crypto-js mode.ECB / pad.ZeroPadding; 固件侧 AES (SBOX 池地址 0x2AD04 区)。
// ZeroPadding 语义: 明文补齐 0x00 至 16 倍数; 若已是 16 倍数则不加块; 解密不剥尾 0 (由上层按长度截取)。
// 正确性由 tests/aes.test.js 对照 NIST 向量与 node:crypto 验证。

// ---------- S-Box (AES 标准表) ----------
const SBOX = [
  0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
  0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
  0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
  0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
  0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
  0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
  0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
  0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
  0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
  0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
  0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
  0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
  0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
  0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
  0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
  0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
];
const INV_SBOX = new Array(256);
for (let i = 0; i < 256; i++) INV_SBOX[SBOX[i]] = i;
const RCON = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36];

function xtime(x) { return ((x << 1) ^ ((x & 0x80) ? 0x1b : 0)) & 0xff; }

// GF(2^8) 乘法 (AES 多项式 0x11b)
function gm(a, b) {
  let p = 0;
  for (let i = 0; i < 8; i++) {
    if (b & 1) p ^= a;
    const hi = a & 0x80;
    a = (a << 1) & 0xff;
    if (hi) a ^= 0x1b;
    b >>= 1;
  }
  return p;
}

// ---------- 密钥扩展 (AES-128 → 44 words) ----------
function keyExpansion(keyBytes) {
  const w = new Array(44);
  for (let i = 0; i < 4; i++) {
    w[i] = (keyBytes[4 * i] << 24) | (keyBytes[4 * i + 1] << 16) | (keyBytes[4 * i + 2] << 8) | keyBytes[4 * i + 3];
  }
  for (let i = 4; i < 44; i++) {
    let t = w[i - 1];
    if (i % 4 === 0) {
      t = ((SBOX[(t >>> 24) & 0xff] << 24) | (SBOX[(t >>> 16) & 0xff] << 16) |
           (SBOX[(t >>> 8) & 0xff] << 8) | SBOX[t & 0xff]) >>> 0;
      t = (((t << 8) | (t >>> 24)) ^ (RCON[i / 4 - 1] << 24)) >>> 0;
    }
    w[i] = (w[i - 4] ^ t) >>> 0;
  }
  return w;
}

function addRoundKey(state, w, round) {
  for (let c = 0; c < 4; c++) {
    const word = w[round * 4 + c];
    state[0][c] ^= (word >>> 24) & 0xff;
    state[1][c] ^= (word >>> 16) & 0xff;
    state[2][c] ^= (word >>> 8) & 0xff;
    state[3][c] ^= word & 0xff;
  }
}

function encryptBlock(inp, w) {
  const s = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]];
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) s[r][c] = inp[r + 4 * c];
  addRoundKey(s, w, 0);
  for (let round = 1; round <= 10; round++) {
    for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) s[r][c] = SBOX[s[r][c]];
    for (let r = 1; r < 4; r++) {
      for (let k = 0; k < r; k++) { // 行 r 循环左移 r 位
        const t = s[r][0];
        for (let c = 0; c < 3; c++) s[r][c] = s[r][c + 1];
        s[r][3] = t;
      }
    }
    if (round < 10) {
      for (let c = 0; c < 4; c++) {
        const a = s[0][c], b = s[1][c], d = s[2][c], e = s[3][c];
        s[0][c] = xtime(a) ^ (xtime(b) ^ b) ^ d ^ e;
        s[1][c] = a ^ xtime(b) ^ (xtime(d) ^ d) ^ e;
        s[2][c] = a ^ b ^ xtime(d) ^ (xtime(e) ^ e);
        s[3][c] = (xtime(a) ^ a) ^ b ^ d ^ xtime(e);
      }
    }
    addRoundKey(s, w, round);
  }
  const out = new Uint8Array(16);
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) out[r + 4 * c] = s[r][c];
  return out;
}

function decryptBlock(inp, w) {
  const s = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]];
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) s[r][c] = inp[r + 4 * c];
  addRoundKey(s, w, 10);
  for (let round = 9; round >= 0; round--) {
    for (let r = 1; r < 4; r++) {
      for (let k = 0; k < r; k++) { // 行 r 循环右移 r 位
        const t = s[r][3];
        for (let c = 3; c > 0; c--) s[r][c] = s[r][c - 1];
        s[r][0] = t;
      }
    }
    for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) s[r][c] = INV_SBOX[s[r][c]];
    addRoundKey(s, w, round);
    if (round > 0) {
      // InvMixColumns: 通用 GF(2^8) 乘法, 系数 9/11/13/14 (无法算错)
      for (let c = 0; c < 4; c++) {
        const a = s[0][c], b = s[1][c], d = s[2][c], e = s[3][c];
        s[0][c] = gm(a, 14) ^ gm(b, 11) ^ gm(d, 13) ^ gm(e, 9);
        s[1][c] = gm(a, 9) ^ gm(b, 14) ^ gm(d, 11) ^ gm(e, 13);
        s[2][c] = gm(a, 13) ^ gm(b, 9) ^ gm(d, 14) ^ gm(e, 11);
        s[3][c] = gm(a, 11) ^ gm(b, 13) ^ gm(d, 9) ^ gm(e, 14);
      }
    }
  }
  const out = new Uint8Array(16);
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) out[r + 4 * c] = s[r][c];
  return out;
}

// ---------- ECB + ZeroPadding ----------
function padZeros(inp) {
  const n = 16 - (inp.length % 16);
  if (n === 16) return inp; // ZeroPadding: 已是整块不再补
  const out = new Uint8Array(inp.length + n);
  out.set(inp);
  return out;
}

function ecbEncrypt(plainBytes, keyBytes) {
  if (keyBytes.length !== 16) throw new Error('AES-128 key 必须 16 字节');
  const w = keyExpansion(keyBytes);
  const padded = padZeros(plainBytes);
  const out = new Uint8Array(padded.length);
  for (let off = 0; off < padded.length; off += 16) {
    out.set(encryptBlock(padded.subarray(off, off + 16), w), off);
  }
  return out;
}

function ecbDecrypt(cipherBytes, keyBytes) {
  if (keyBytes.length !== 16) throw new Error('AES-128 key 必须 16 字节');
  if (cipherBytes.length % 16 !== 0) throw new Error('密文长度必须是 16 倍数');
  const w = keyExpansion(keyBytes);
  const out = new Uint8Array(cipherBytes.length);
  for (let off = 0; off < cipherBytes.length; off += 16) {
    out.set(decryptBlock(cipherBytes.subarray(off, off + 16), w), off);
  }
  return out; // ZeroPadding 解密不剥尾 0
}

// ---------- hex 层 ----------
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

function encryptHex(plainHex, keyHex) {
  return bytesToHex(ecbEncrypt(hexToBytes(plainHex), hexToBytes(keyHex)));
}
function decryptHex(cipherHex, keyHex) {
  return bytesToHex(ecbDecrypt(hexToBytes(cipherHex), hexToBytes(keyHex)));
}

module.exports = { SBOX, ecbEncrypt, ecbDecrypt, encryptHex, decryptHex, hexToBytes, bytesToHex };
