// 命令构造器 — 全量命令面 (阶段 0 明文 + 配网链 + 阶段 3/4 管理面)
// 蓝本: 01-命令字典 §1/§2/§6; 与 kernel/protocol.js 共用帧/KLV/EKey 原语。
// 密文面统一模式 (官方 App): body → EKey 包络(0x88) → AES-ECB(skey) → KLV#xx
//   ⚠ 开放点 (G7 尾): 固件 0x2a860 对 value[0]==0x88 校验 vs 密文首字节 — 待实机终裁。
// 0C/0D (冻结策略/OTP周期): 本代 App 无实现 (V26) — 不伪造字节, 调用方禁止下发。
const P = require('./protocol.js');
const C = require('../crypto.js');
const T = require('../time.js');

function u32leHex(v) {
  v = v >>> 0;
  return P.hexPair(v & 0xff) + P.hexPair((v >>> 8) & 0xff) + P.hexPair((v >>> 16) & 0xff) + P.hexPair((v >>> 24) & 0xff);
}
function u16leHex(v) {
  v = v >>> 0;
  return P.hexPair(v & 0xff) + P.hexPair((v >>> 8) & 0xff);
}
function fillZeroHex(s, chars) { return (s || '').toUpperCase().padEnd(chars, '0'); }
function fillZeroLeft(s, chars) { return (s || '').toUpperCase().padStart(chars, '0'); }
function asciiHex(s, n) {
  let h = '';
  for (let i = 0; i < s.length; i++) h += P.hexPair(s.charCodeAt(i) & 0xff);
  return fillZeroHex(h, n * 2);
}
// 日期字符串/ms/协议秒 → 协议秒; 缺省=现在
function protoSec(v) {
  if (typeof v === 'number') return v;
  if (typeof v === 'string') {
    const s = v.replace(' ', 'T');
    const ms = Date.parse(s + (s.indexOf('T') >= 0 ? '' : 'T00:00:00Z'));
    if (!isNaN(ms)) return T.protoSecondsFromMs(ms);
  }
  return T.nowProtoSeconds();
}
// 密文包络统一封装: body → EKey(cmd,mac) → AES(skey) → KLV#klvKey
function wrapEnc(cmd, macHex, skeyHex, bodyHex, klvKey) {
  const env = P.buildEkey(cmd, macHex) + bodyHex;
  const enc = C.encryptHex(env, skeyHex);
  return P.buildKLV(klvKey, enc);
}
// ---- 明文面 ----
function cmd05Exchange(skeyHex, opts) {
  const keyType = (opts && opts.keyType) || 1;
  const timeSec = (opts && opts.timeSec) || T.nowProtoSeconds();
  const klv = P.buildKLV(0x01, u32leHex(timeSec)) + P.buildKLV(0x02, P.hexPair(keyType)) + P.buildKLV(0x03, skeyHex);
  return { name: '05 换钥 (EXSECURITYKEY)', cmd: 0x05, hex: P.buildFrame(0x05, klv, '0000', 8) };
}
function cmd23ExKeyWay() { return P.cmd23ExKeyWay(8, '', false); }
function cmd01Session() { return P.cmd01Session(8); }
function cmd12Echo(valHex) { return P.cmd12Echo(8, valHex || '123456'); } // 官方值 hex '123456'
function cmd03StatusPlain(macHex) { return P.cmd03Status(8, macHex, false); }
// ---- 密文管理面 (全部 needSSToken; 令牌由 services/lock 注入 KLV#0xEE) ----
function cmd03StatusWrap(macHex, skeyHex) {
  const env = P.buildEkey(0x03, macHex);
  const enc = C.encryptHex(env, skeyHex);
  return { name: '03 加密状态', cmd: 0x03, hex: P.buildFrame(0x03, P.buildKLV(0x01, enc) + P.buildKLV(0x02, ''), '0000', 8) };
}
// cmd 04 OPEN — 生产版 `ae` 布局 (行 10508, 字符级):
//   KLV#01 = En.fillZero(第二参, 32) (左补零; openNext 传 "0000" → 32 个0)
//   KLV#02 = 第一参 (开锁凭证串)
// ⚠ U3 开放点: 锁接受的凭证语义 (skey?/AES($t)?) 待实机裁决 — 离线端自签发: cred=skey。
//   试验开关: klv01Hex 可注入非零占位 (探测对照 rc=6 vs rc=0)。
// cmd 04: App 生产版布局 (ae 类): KLV#01=fillZero(第二参,32), KLV#02=ekey(密文包络 hex)
//   ekey = hex(AES-ECB(skey)($t 包络)); $t 包络 = 88 00 MAC反转 TrackId LE VF LE VT LE 04 pinLE bind times
function cmd04Open(ekeyHex, klv01Hex) {
  const klv = P.buildKLV(0x01, fillZeroLeft(klv01Hex || '', 32)) + P.buildKLV(0x02, ekeyHex || '');
  return { name: '04 开锁 (OPEN)', cmd: 0x04, hex: P.buildFrame(0x04, klv, '0000', 8) };
}
// App addDevice 字符级移植: ekey = AES(skey).encrypt( $t(pin=pins[0], bind=0, times=0, TrackId, MAC) )
//   $t.getCmdBody = pin(4B LE) + bind(1B) + times(1B); TrackId=App 随机(<2^31), 自签发默认 0
//   自签发: 用锁内任一有效 PIN 即可生成合法开锁凭证 (锁侧解密校验 MAC+pin 池)
//   pin 参数双兼容: 数字 (如 123456) 或 LE 4B hex (如 '40e20100', keys.js genPin 格式)
function pinToLE(pin) {
  const h = String(pin).replace(/^0x/i, '');
  if (/^[0-9a-fA-F]{8}$/.test(h)) return h.toLowerCase();
  return u32leHex(parseInt('' + pin, 10) >>> 0);
}
function buildEkeyOpen(skeyHex, macHex, pin, opts) {
  const o = opts || {};
  const env = P.buildEkey(0x04, macHex, o.validFromSec, o.validToSec, o.trackId) + pinToLE(pin) + '00' + '00';
  return C.encryptHex(env, skeyHex);
}
// cmd 08: addCount(1B)+delCount(1B)+addPins(4B LE*N)+delPins(4B LE*M), 首批 delPins=[FFFFFFFF]
function cmd08SyncPinsBatch(macHex, skeyHex, addPins, opts) {
  const delPins = (opts && opts.delPins) || [];
  const addCount = addPins.length, delCount = delPins.length;
  if (addCount > 20) throw new Error('单批 addPins 最多 20');
  let body = P.hexPair(addCount) + P.hexPair(delCount);
  for (const p of addPins) body += p;
  for (const p of delPins) body += p;
  return { name: '08 PIN 批量', cmd: 0x08, hex: P.buildFrame(0x08, wrapEnc(0x08, macHex, skeyHex, body, 0x01), '0000', 8) };
}
// cmd 21: skeyLen(1B)+bkey(16B)
function cmd21SetBkey(macHex, skeyHex, bkeyHex) {
  const body = P.hexPair(0x10) + bkeyHex;
  return { name: '21 bkey', cmd: 0x21, hex: P.buildFrame(0x21, wrapEnc(0x21, macHex, skeyHex, body, 0x02), '0000', 8) };
}
// cmd 0A: delAlias(2B LE, 0xFFFF=清空) + addPwd(8B ASCII 右补零) + validFrom/To(4B LE)
function cmd0ASyncPwd(macHex, skeyHex, opts) {
  const delAlias = (opts && opts.delAlias !== undefined) ? opts.delAlias : 0;
  const addPwd = (opts && opts.addPwd) || '';
  if (addPwd.length > 8) throw new Error('密码最长 8 位');
  const vf = protoSec(opts && opts.validFrom), vt = protoSec(opts && opts.validTo);
  const body = u16leHex(delAlias) + asciiHex(addPwd, 8) + u32leHex(vf) + u32leHex(vt);
  return { name: '0A 同步密码', cmd: 0x0a, hex: P.buildFrame(0x0a, wrapEnc(0x0a, macHex, skeyHex, body, 0x01), '0000', 8) };
}
// cmd 0B: alias(2B LE) + validFrom/To(4B LE)
function cmd0BSyncPwdExpire(macHex, skeyHex, alias, validFrom, validTo) {
  const body = u16leHex(alias) + u32leHex(protoSec(validFrom)) + u32leHex(protoSec(validTo));
  return { name: '0B 密码有效期', cmd: 0x0b, hex: P.buildFrame(0x0b, wrapEnc(0x0b, macHex, skeyHex, body, 0x01), '0000', 8) };
}
// cmd 0E: syncTime(4B LE 协议秒), 先 03 读锁钟再校偏
function cmd0ESyncTime(macHex, skeyHex, timeSec) {
  const body = u32leHex(timeSec === undefined ? T.nowProtoSeconds() : timeSec);
  return { name: '0E 时间同步', cmd: 0x0e, hex: P.buildFrame(0x0e, wrapEnc(0x0e, macHex, skeyHex, body, 0x02), '0000', 8) };
}
// cmd 13: times(1B 按压次数, 官方默认 8) + timeout(1B, <=0 默认15)
function cmd13AddFp(macHex, skeyHex, times, timeout) {
  const t = times || 8;
  const to = (timeout === undefined || timeout <= 0) ? 15 : timeout;
  const body = P.hexPair(t) + P.hexPair(to);
  return { name: '13 录指纹', cmd: 0x13, hex: P.buildFrame(0x13, wrapEnc(0x13, macHex, skeyHex, body, 0x02), '0000', 8) };
}
// cmd 14: batchNumber(4B LE) + fpValidFrom/To(4B LE)
function cmd14FpConfirm(macHex, skeyHex, batchNumber, validFrom, validTo) {
  const body = u32leHex(batchNumber) + u32leHex(protoSec(validFrom)) + u32leHex(protoSec(validTo));
  return { name: '14 指纹确认', cmd: 0x14, hex: P.buildFrame(0x14, wrapEnc(0x14, macHex, skeyHex, body, 0x02), '0000', 8) };
}
// cmd 15: batchNumber(4B LE)
function cmd15DeleteFp(macHex, skeyHex, batchNumber) {
  const body = u32leHex(batchNumber);
  return { name: '15 删指纹', cmd: 0x15, hex: P.buildFrame(0x15, wrapEnc(0x15, macHex, skeyHex, body, 0x02), '0000', 8) };
}
// cmd 16: orderType(1B) + startIdx(4B LE) + pageSize(1B)
function cmd16GetLog(macHex, skeyHex, opts) {
  const orderType = (opts && opts.orderType) || 0;
  const startIdx = (opts && opts.startIdx) || 0;
  const pageSize = (opts && opts.pageSize) || 20;
  const body = P.hexPair(orderType) + u32leHex(startIdx) + P.hexPair(pageSize);
  return { name: '16 日志', cmd: 0x16, hex: P.buildFrame(0x16, wrapEnc(0x16, macHex, skeyHex, body, 0x01), '0000', 8) };
}
// cmd 18: vol(1B)
function cmd18Volume(macHex, skeyHex, vol) {
  const body = P.hexPair(vol);
  return { name: '18 音量', cmd: 0x18, hex: P.buildFrame(0x18, wrapEnc(0x18, macHex, skeyHex, body, 0x02), '0000', 8) };
}
// cmd 19: status(1B 0=关/1=开); 临时码*生成*仍依赖云 (U6), 本命令仅开通/关闭
function cmd19OpenZotp(macHex, skeyHex, status) {
  const body = P.hexPair(status ? 1 : 0);
  return { name: '19 ZOTP', cmd: 0x19, hex: P.buildFrame(0x19, wrapEnc(0x19, macHex, skeyHex, body, 0x02), '0000', 8) };
}
// cmd 20: mode(1B 0=A单验/1=B双验)
function cmd20ValidationMode(macHex, skeyHex, mode) {
  const body = P.hexPair(mode ? 1 : 0);
  return { name: '20 验证模式', cmd: 0x20, hex: P.buildFrame(0x20, wrapEnc(0x20, macHex, skeyHex, body, 0x02), '0000', 8) };
}
// cmd 24: interval(1B 档位1-6)
function cmd24AutoLock(macHex, skeyHex, interval) {
  const body = P.hexPair(interval);
  return { name: '24 自动上锁', cmd: 0x24, hex: P.buildFrame(0x24, wrapEnc(0x24, macHex, skeyHex, body, 0x01), '0000', 8) };
}
// cmd 25 布防: control(1B {0=关,1=不定期,2=时间段,3=readonly}) + start/end(4B LE 日内秒)
function cmd25Defence(macHex, skeyHex, control, startSec, endSec) {
  const body = P.hexPair(control) + u32leHex(startSec || 0) + u32leHex(endSec || 0);
  return { name: '25 布防', cmd: 0x25, hex: P.buildFrame(0x25, wrapEnc(0x25, macHex, skeyHex, body, 0x01), '0000', 8) };
}
// ---- 钥匙串硬件 (ZKBBV1 pid=16289, App Eu/Ru/Gu 类; 87 帧明文 KLV, needToken=false) ----
// App generateEKey (addkeychain 页) 字符级: ekey = AES(skey)($t 包络), $t = 88 帧 cmd=04 + pin(4B LE)+bind=0+times=0,
//   TrackId=随机 <2^31, ValidFrom/To = 本地时区解释的 "2010-01-01 00:00:00" / "2118-01-01 00:00:00"
//   (与 buildEkeyOpen 默认差异: VF 用本地 2010 而非 0, VT 用本地 2118 而非 UTC, TrackId 随机)
function buildEkeyShare(skeyHex, macHex, pin) {
  return buildEkeyOpen(skeyHex, macHex, pin, {
    trackId: Math.floor(Math.random() * 2147483647),
    validFromSec: T.protoSecondsFromMs(new Date('2010-01-01T00:00:00').getTime()),
    validToSec: T.protoSecondsFromMs(new Date('2118-01-01T00:00:00').getTime())
  });
}
// cmd 41 WRITEEKEY: KLV#01=锁MAC(6B 反转) #02=type(1B, App 恒 1) #03=pid(2B LE) #04=ekey 密文 hex
//   (ekey 本身已是 AES-ECB(skey)($t 包络); 空串 ekey = App delKeyChain 的删除语义)
function cmd41WriteEkey(lockMacHex, pid, ekeyHex, opts) {
  const type = (opts && opts.type) !== undefined ? opts.type : 1;
  const klv = P.buildKLV(0x01, P.reversePairs(lockMacHex)) +
    P.buildKLV(0x02, P.hexPair(type)) +
    P.buildKLV(0x03, u16leHex(pid)) +
    P.buildKLV(0x04, ekeyHex || '');
  return { name: '41 钥匙串写钥', cmd: 0x41, hex: P.buildFrame(0x41, klv, '0000', 8) };
}
// cmd 44 GETEKEYINFO: KLV#01=锁MAC(6B 反转) 或空 (空=全部钥匙; 带 mac=查该锁)
function cmd44GetEkeyInfo(lockMacHex) {
  const klv = P.buildKLV(0x01, lockMacHex ? P.reversePairs(lockMacHex) : '');
  return { name: '44 钥匙串查钥', cmd: 0x44, hex: P.buildFrame(0x44, klv, '0000', 8) };
}
// cmd 43 GETSTATUS: KLV#01=各锁 MAC 逐个 6B 反转拼接 (App 传空数组 → 空 KLV#01)
function cmd43KeychainStatus(lockMacList) {
  let v = '';
  for (const m of (lockMacList || [])) v += P.reversePairs(String(m).replace(/:/g, '').toLowerCase());
  return { name: '43 钥匙串状态', cmd: 0x43, hex: P.buildFrame(0x43, P.buildKLV(0x01, v), '0000', 8) };
}
// ---- 网关 (FE90 服务, 87 帧明文 KLV, needToken=false; App Io/ko/Do/Bo/Lo 类) ----
// cmd 38 GWGETSTATUS: 无 KLV → 响应 Oo: #01=wifimac #02=romVer #03=eCtrlVer #04=ssid #05=wifiIP #06=netState
function cmd38GWStatus() {
  return { name: '38 网关状态', cmd: 0x38, hex: P.buildFrame(0x38, '', '0000', 8) };
}
// cmd 31 GWSETWIFI: #01=SSID(Utf8 hex) #02=密码(Utf8 hex) #03=authMode(1B) #04=encryptType(1B) #05=(1B)
//   App setWifi: authMode=WIFI_AUTH_MODE_WPA_PSK_WPA2_PSK(8), encryptType=WIFI_ENCRYPT_TYPE_WEP_ENABLED(0), 0
// 响应 Co: errCode @ KLV#01
function cmd31GWSetWifi(ssid, password, opts) {
  const o = opts || {};
  const auth = o.authMode !== undefined ? o.authMode : 8;
  const enc = o.encryptType !== undefined ? o.encryptType : 0;
  const last = o.extra !== undefined ? o.extra : 0;
  const klv = P.buildKLV(0x01, utf8Hex(ssid)) + P.buildKLV(0x02, utf8Hex(password)) +
    P.buildKLV(0x03, P.hexPair(auth)) + P.buildKLV(0x04, P.hexPair(enc)) + P.buildKLV(0x05, P.hexPair(last));
  return { name: '31 网关配网', cmd: 0x31, hex: P.buildFrame(0x31, klv, '0000', 8) };
}
// cmd 32 GWSETIOT: #05=iotpKey #06=iotdSec #07=devAccToken (云端 IoT 档案; 厂商云已停服 → 保留构造器, 页面不调用)
function cmd32GWSetIot(iotpKeyHex, iotdSecHex, devAccTokenHex) {
  const klv = P.buildKLV(0x05, iotpKeyHex || '') + P.buildKLV(0x06, iotdSecHex || '') + P.buildKLV(0x07, devAccTokenHex || '');
  return { name: '32 网关 IoT', cmd: 0x32, hex: P.buildFrame(0x32, klv, '0000', 8) };
}
// cmd 35 GWREBOOT: 无 KLV → 响应 Mo: errCode @ KLV#01
function cmd35GWReboot() {
  return { name: '35 网关重启', cmd: 0x35, hex: P.buildFrame(0x35, '', '0000', 8) };
}
// cmd 30 GWGETDEVICENAME: 无 KLV → 响应 Lo: deviceName @ KLV#01
function cmd30GWDeviceName() {
  return { name: '30 网关名称', cmd: 0x30, hex: P.buildFrame(0x30, '', '0000', 8) };
}
// UTF8 → hex (CryptoJS.enc.Utf8.parse(...).toString() 等价; 中文 SSID/密码安全)
function utf8Hex(s) {
  const bytes = [];
  const str = String(s || '');
  for (let i = 0; i < str.length; i++) {
    let cp = str.codePointAt(i);
    if (cp > 0xffff) i++;
    if (cp < 0x80) bytes.push(cp);
    else if (cp < 0x800) bytes.push(0xc0 | (cp >> 6), 0x80 | (cp & 0x3f));
    else if (cp < 0x10000) bytes.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
    else bytes.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
  }
  return bytes.map(b => P.hexPair(b)).join('');
}
// cmd 22 enableDFUstate (App Oe/Be 类): $t 包络 cmd=22 + param(1B), AES(skey) → KLV#02, needToken=true
//   param=0 → 锁重启进入 bootloader (广播名 ZkDFU, MAC+1)
function cmd22EnableDfu(macHex, skeyHex, param) {
  const body = P.hexPair(param === undefined ? 0 : (param & 0xff));
  return { name: '22 DFU', cmd: 0x22, hex: P.buildFrame(0x22, wrapEnc(0x22, macHex, skeyHex, body, 0x02), '0000', 8) };
}
// 完整会话帧: 注入 KLV#0xEE 令牌 (固件 0x253FE 特判通道)
function withToken(hex, tokenHex) { return P.injectToken(hex, tokenHex); }

module.exports = {
  u32leHex, u16leHex, fillZeroHex, fillZeroLeft, asciiHex, protoSec,
  cmd01Session, cmd03StatusPlain, cmd03StatusWrap, cmd05Exchange, cmd12Echo, cmd23ExKeyWay,
  cmd04Open, buildEkeyOpen, buildEkeyShare, cmd08SyncPinsBatch, cmd21SetBkey,
  cmd0ASyncPwd, cmd0BSyncPwdExpire, cmd0ESyncTime, cmd13AddFp, cmd14FpConfirm, cmd15DeleteFp,
  cmd16GetLog, cmd18Volume, cmd19OpenZotp, cmd20ValidationMode, cmd24AutoLock, cmd25Defence,
  cmd41WriteEkey, cmd44GetEkeyInfo, cmd43KeychainStatus,
  cmd38GWStatus, cmd31GWSetWifi, cmd32GWSetIot, cmd35GWReboot, cmd30GWDeviceName, utf8Hex,
  cmd22EnableDfu,
  withToken
};
