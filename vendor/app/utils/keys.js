// 配网密钥族生成器 (蓝本: 06-pairing-flow §2)
//   skey  = 4× random32 → 16B hex (32 字符)
//   pins  = 64× 4B LE 随机; 首批 delPins=[0xFFFFFFFF] 清哨兵
//   bkey  = 16B 随机 + 相邻字节约束变换 (|a-prev|<=2 → a+=6; >255 → a=6)
//   trackId = 随机 ≤ 2^31
const DEL_PIN_SENTINEL = 'ffffffff';

// 同步随机源 — 只用于「无 wx 的环境 (Node 测试)」与「演示假数据」:
//   真机 wx 无同步 CSPRNG (wx.getRandomValues 是异步回调 API, 见下), 需要真实密钥材料必须走 *Async 版。
// 2026-09-03 勘误: 曾在此同步调用 wx.getRandomValues(out) — 该 API 签名是 {length,success},
//   用 Uint8Array 当参数调用会静默丢弃结果 → 数组全零 → genPins 去重 while 永不退出 → 主线程占死 + 内存爬升 → 微信报「内存不足」杀进程。
function randomBytes(n) {
  const out = new Uint8Array(n);
  const c = (typeof crypto !== 'undefined') ? crypto : null;
  if (c && c.getRandomValues) {
    try { c.getRandomValues(out); return out; } catch (e) {}
  }
  for (let i = 0; i < n; i++) out[i] = Math.floor(Math.random() * 256);
  return out;
}
// 异步 CSPRNG — 真机正确取随机: 全局 crypto (部分环境) → wx.getRandomValues({length,success}) → 兜底 Math.random。
// 带 2s 看门狗: wx 回调极端不触发时也不挂死, 回退 Math.random 继续。
function randomBytesAsync(n) {
  return new Promise(resolve => {
    const c = (typeof crypto !== 'undefined') ? crypto : null;
    if (c && c.getRandomValues) {
      const out = new Uint8Array(n);
      try { c.getRandomValues(out); resolve(out); return; } catch (e) {}
    }
    if (typeof wx !== 'undefined' && wx.getRandomValues) {
      let done = false;
      let wd = null;
      const finish = u8 => {
        if (done) return;
        done = true;
        if (wd) { clearTimeout(wd); wd = null; }
        if (u8 && u8.length === n) resolve(u8);
        else { // 失败/形状不对 → Math.random 兜底 (绝不返回空, 绝不挂起)
          const out = new Uint8Array(n);
          for (let i = 0; i < n; i++) out[i] = Math.floor(Math.random() * 256);
          resolve(out);
        }
      };
      try {
        wx.getRandomValues({
          length: n,
          success: res => {
            try {
              const ab = res && (res.randomValues || res.randomBytes || res);
              const u8 = ab instanceof ArrayBuffer ? new Uint8Array(ab)
                : (ab && ab.byteLength !== undefined) ? new Uint8Array(ab.buffer || ab, ab.byteOffset || 0, ab.byteLength)
                  : null;
              finish(u8);
            } catch (e) { finish(null); }
          },
          fail: () => finish(null),
          complete: () => finish(null)
        });
        wd = setTimeout(() => finish(null), 2000); // 看门狗: wx 回调极端不触发时兜底
      } catch (e) { finish(null); }
      return;
    }
    const out = new Uint8Array(n);
    for (let i = 0; i < n; i++) out[i] = Math.floor(Math.random() * 256);
    resolve(out);
  });
}
function bytesToHex(b) {
  let s = '';
  for (let i = 0; i < b.length; i++) s += (b[i] < 16 ? '0' : '') + b[i].toString(16);
  return s;
}
function randomU32Hex() {
  const b = randomBytes(4);
  return bytesToHex(b);
}

// skey: 4× random32 → 32 hex 字符 (16B)
function genSkey() {
  return randomU32Hex() + randomU32Hex() + randomU32Hex() + randomU32Hex();
}
// bkey: 16B + 相邻字节约束变换
function genBkey() {
  const b = Array.from(randomBytes(16));
  for (let i = 1; i < b.length; i++) {
    if (Math.abs(b[i] - b[i - 1]) <= 2) {
      b[i] += 6;
      if (b[i] > 255) b[i] = 6;
    }
  }
  return bytesToHex(Uint8Array.from(b));
}
// pins: n× 4B LE hex; App 语义 (generateRandomNumbers): 值 < 2^31 且池内互不重复 (06-配网 §2)
//   顶字节 &0x7F → 与 App 上限 2147483647 一致 (避免固件侧 int32 符号歧义)
function _pinFromBytes(b4) {
  const b = Array.from(b4);
  b[0] &= 0x7f; // 数值最高字节 (LE 序列化后落在末字节) → 值 < 2^31
  return bytesToHex(Uint8Array.from([b[3], b[2], b[1], b[0]]));
}
function genPin() { return _pinFromBytes(randomBytes(4)); }
// 去重 while 带预算闸 (2026-09-03): 随机源异常 (如曾误用异步 wx API → 全零) 时不再永转占死主线程,
// 预算耗尽即抛错 — 调用方拿到明确失败而不是「整屏无响应 + 内存不足被微信杀」
function _pinPoolGuard(n) { return n * 512 + 256; }
function genPins(n) {
  const out = [];
  const seen = {};
  let guard = _pinPoolGuard(n);
  while (out.length < n) {
    if (--guard < 0) throw new Error('随机源异常: 无法生成 ' + n + ' 个唯一 PIN (已中止, 不会死循环)');
    const p = genPin();
    if (seen[p]) continue;
    seen[p] = 1;
    out.push(p);
  }
  return out;
}
// 异步版 (真机密钥族: skey/bkey/PIN 池) — 走 wx CSPRNG, 供 services/lock.pair 等真实密钥场景
async function genPinsAsync(n) {
  const out = [];
  const seen = {};
  let guard = _pinPoolGuard(n);
  while (out.length < n) {
    if (--guard < 0) throw new Error('随机源异常: 无法生成 ' + n + ' 个唯一 PIN (已中止, 不会死循环)');
    const p = _pinFromBytes(await randomBytesAsync(4));
    if (seen[p]) continue;
    seen[p] = 1;
    out.push(p);
  }
  return out;
}
async function genSkeyAsync() { return bytesToHex(await randomBytesAsync(16)); }
async function genBkeyAsync() {
  const b = Array.from(await randomBytesAsync(16));
  for (let i = 1; i < b.length; i++) {
    if (Math.abs(b[i] - b[i - 1]) <= 2) {
      b[i] += 6;
      if (b[i] > 255) b[i] = 6;
    }
  }
  return bytesToHex(Uint8Array.from(b));
}
function genTrackId() {
  return Math.floor(Math.random() * 0x7fffffff) >>> 0;
}
module.exports = {
  DEL_PIN_SENTINEL, randomBytes, randomBytesAsync, bytesToHex, randomU32Hex,
  genSkey, genBkey, genPin, genPins, genTrackId,
  genSkeyAsync, genBkeyAsync, genPinsAsync
};
