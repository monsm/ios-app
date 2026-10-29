// 金标向量生成器 — 用已通过 25 套测试的 JS 核心, 为 Swift 重写生成字节级差分基准
// 输出 fixtures/golden.json (Swift XCTest 逐项断言)。
// 用法: node tools/golden.js          重新生成 fixtures/golden.json
//       node tools/golden.js --check  只校验 committed 金标是否与 JS 核心输出一致 (CI 用, 不写盘)
'use strict';
// 时区钉定: cmds 0A/0B/14 与 buildEkeyShare 的有效期是**无 Z 后缀**的本地时间串 (如 '2026-01-01 00:00:00'),
// new Date(str) 按运行机时区解析。UTC runner 重生成会产出不同字节 (实测 cmd0ASyncPwd_add 尾部
// 7517c8 vs f137, buildEkeyShare 整体不同) → 差分测试跨时区必假失败。
// committed 夹具按 Asia/Shanghai 烘焙。这里**无条件**钉死, 否则 runner 的 TZ 会改变 cmds/parse 的字节
// (实测 TZ=UTC 时 cmd0ASyncPwd_add 尾部从 …7517c8 变成 …f137) → 跨机器复现不了, 漂移校验形同虚设。
// 确需别的口径时用 GOLDEN_TZ 显式覆盖 (并同步重生成夹具)。
process.env.TZ = process.env.GOLDEN_TZ || 'Asia/Shanghai';
const CHECK = process.argv.includes('--check');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const CORE = path.resolve(__dirname, '../vendor/app');
const P = require(CORE + '/utils/kernel/protocol.js');
const CM = require(CORE + '/utils/kernel/cmds.js');
const C = require(CORE + '/utils/crypto.js');
const Z = require(CORE + '/utils/zotp.js');
const ST = require(CORE + '/utils/status.js');
const BLE = require(CORE + '/services/ble.js');
const T = require(CORE + '/utils/time.js');

const MAC = 'aabbccddeeff';
const SKEY = '00112233445566778899aabbccddeeff';
const g = {};

// ---------- AES-128-ECB (ZeroPadding) ----------
g.aes = {
  encrypt_16: C.encryptHex('00112233445566778899aabbccddeeff'.slice(0, 32), SKEY),
  encrypt_padded: C.encryptHex('8800aabbccddeeff', SKEY),
  decrypt_roundtrip: C.decryptHex(C.encryptHex('8800aabbccddeeff' + '0102030405060708', SKEY), SKEY),
  nist_vector: C.encryptHex('00112233445566778899aabbccddeeff', '000102030405060708090a0b0c0d0e0f')
};

// ---------- 帧构造 (全部命令, 定输入) ----------
g.cmds = {};
g.cmds.cmd01Session = CM.cmd01Session().hex;
g.cmds.cmd03StatusPlain = CM.cmd03StatusPlain(MAC).hex;
g.cmds.cmd03StatusWrap = CM.cmd03StatusWrap(MAC, SKEY).hex;
g.cmds.cmd04Open_klv01 = CM.cmd04Open('cafebabe'.repeat(4), '0000').hex;
g.cmds.cmd05Exchange = CM.cmd05Exchange(SKEY, { timeSec: 0x5a }).hex;
g.cmds.cmd08SyncPins = CM.cmd08SyncPinsBatch(MAC, SKEY, ['11223344', '55667788'], { delPins: ['ffffffff'] }).hex;
g.cmds.cmd0ASyncPwd_add = CM.cmd0ASyncPwd(MAC, SKEY, { addPwd: '123456', validFrom: '2010-01-01 00:00:00', validTo: '2118-01-01 00:00:00' }).hex;
g.cmds.cmd0ASyncPwd_modify = CM.cmd0ASyncPwd(MAC, SKEY, { delAlias: 5, addPwd: '654321', validFrom: '2026-01-01 00:00:00', validTo: '2118-01-01 00:00:00' }).hex;
g.cmds.cmd0ASyncPwd_del = CM.cmd0ASyncPwd(MAC, SKEY, { delAlias: 0xFFFF, validFrom: '2010-01-01 00:00:00', validTo: '2118-01-01 00:00:00' }).hex;
g.cmds.cmd0BExpire = CM.cmd0BSyncPwdExpire(MAC, SKEY, 5, '2026-01-01 00:00:00', '2118-01-01 00:00:00').hex;
g.cmds.cmd0ESyncTime = CM.cmd0ESyncTime(MAC, SKEY, 530000000).hex;
g.cmds.cmd12Echo = CM.cmd12Echo('123456').hex;
g.cmds.cmd13AddFp = CM.cmd13AddFp(MAC, SKEY, 8, 15).hex;
g.cmds.cmd14FpConfirm = CM.cmd14FpConfirm(MAC, SKEY, 77, '2010-01-01 00:00:00', '2118-01-01 00:00:00').hex;
g.cmds.cmd15DeleteFp = CM.cmd15DeleteFp(MAC, SKEY, 77).hex;
g.cmds.cmd16GetLog = CM.cmd16GetLog(MAC, SKEY, { orderType: 0, startIdx: 0xFFFFFFFF, pageSize: 5 }).hex;
g.cmds.cmd18Volume = CM.cmd18Volume(MAC, SKEY, 1).hex;
g.cmds.cmd19OpenZotp = CM.cmd19OpenZotp(MAC, SKEY, 1).hex;
g.cmds.cmd20Validation = CM.cmd20ValidationMode(MAC, SKEY, 1).hex;
g.cmds.cmd21SetBkey = CM.cmd21SetBkey(MAC, SKEY, 'aabbccddeeff00112233445566778899').hex;
g.cmds.cmd22EnableDfu = CM.cmd22EnableDfu(MAC, SKEY, 0).hex;
g.cmds.cmd23ExKeyWay = CM.cmd23ExKeyWay().hex;
g.cmds.cmd24AutoLock = CM.cmd24AutoLock(MAC, SKEY, 3).hex;
g.cmds.cmd25Defence_aperiodic = CM.cmd25Defence(MAC, SKEY, 1, 0, 0).hex;
g.cmds.cmd25Defence_period = CM.cmd25Defence(MAC, SKEY, 2, 21600, 43200).hex;
// 令牌注入
g.cmds.withToken = CM.withToken(CM.cmd12Echo('123456').hex, 'beef');
// ekey (开锁凭证, 定 TrackId/窗口)
// 2118 用**本地**解析 (无 Z): 与 ZKProtocol.VALID_TO_2118 / APK `getProtocolTimeSecond('2118-01-01 00:00:00')` 同口径
// (两侧同墙钟相减 ⇒ 与机器时区无关, 恒 3408134400)。旧夹具写的是 `Date.parse('…T00:00:00Z')`, 与本地基准
// 混用会凭空多出一个时区偏移 (东八区 +28800s) —— cmdsshadow 的两条 ekey 向量就是被这一处带红的。
g.cmds.buildEkeyOpen = CM.buildEkeyOpen(SKEY, MAC, 123456, { trackId: 12345, validFromSec: 0, validToSec: T.protoSecondsFromMs(new Date('2118-01-01T00:00:00').getTime()) });
// 确定性 share 向量 (App buildEkeyShare 的本地窗口 + 固定 TrackId=7; Swift 侧用相同输入复算)
g.cmds.buildEkeyShare = CM.buildEkeyOpen(SKEY, MAC, 654321, { trackId: 7, validFromSec: T.protoSecondsFromMs(new Date('2010-01-01T00:00:00').getTime()), validToSec: T.protoSecondsFromMs(new Date('2118-01-01T00:00:00').getTime()) });
// 钥匙串 41/43/44
g.cmds.cmd41WriteEkey = CM.cmd41WriteEkey(MAC, 16289, g.cmds.buildEkeyOpen).hex;
g.cmds.cmd41WriteEkey_del = CM.cmd41WriteEkey(MAC, 16289, '').hex;
g.cmds.cmd44GetEkeyInfo_all = CM.cmd44GetEkeyInfo('').hex;
g.cmds.cmd44GetEkeyInfo_one = CM.cmd44GetEkeyInfo(MAC).hex;
g.cmds.cmd43KeychainStatus_empty = CM.cmd43KeychainStatus([]).hex;
g.cmds.cmd43KeychainStatus_two = CM.cmd43KeychainStatus([MAC, '112233445566']).hex;
// 网关 30/31/32/35/38
g.cmds.cmd38GWStatus = CM.cmd38GWStatus().hex;
g.cmds.cmd31GWSetWifi = CM.cmd31GWSetWifi('HomeWiFi', 'pass1234').hex;
g.cmds.cmd31GWSetWifi_cn = CM.cmd31GWSetWifi('客厅网关', '密码88').hex;
g.cmds.cmd32GWSetIot = CM.cmd32GWSetIot('aabb', 'cc', 'dd').hex;
g.cmds.cmd35GWReboot = CM.cmd35GWReboot().hex;
g.cmds.cmd30GWDeviceName = CM.cmd30GWDeviceName().hex;

// ---------- 响应解析 ----------
// 8B 头样例: 87 00 len cmd 000000 + KLV
function frame8(cmd, klvHex) { return '87' + '00' + P.hexPair((klvHex.length / 2) & 0xff) + P.hexPair(((klvHex.length / 2) >> 8) & 0xff) + P.hexPair(cmd) + '000000' + klvHex; }
function klv(key, valHex) { return P.buildKLV(key, valHex); }
const stKlvs =
  klv(0x01, '01') +
  klv(0x03, '00') +
  klv(0x04, P.u32leHex ? '40e20100' : '') + // 兼容
  klv(0x04, '40e20100') +
  klv(0x11, '55') +
  klv(0x08, '01') +
  klv(0x14, '00') +
  klv(0x21, '14') + klv(0x22, '0a') + klv(0x23, '0a') +
  klv(0x24, '14') + klv(0x25, '06') + klv(0x26, '08') +
  klv(0x27, '0a') + klv(0x28, '03') + klv(0x29, '02') +
  klv(0x31, '090205') +
  klv(0x32, '04') +
  klv(0x33, '2000') +
  klv(0x34, 'a13f0000') +
  klv(0x35, Buffer.from('V5.2', 'ascii').toString('hex'));
g.parse = {
  status_frame: frame8(0x03, stKlvs),
  status: ST.parseStatus(P.parseResponse(frame8(0x03, stKlvs)).klvs),
  // 16 日志: 每条 KLV#05 = [type][len][idx 4B LE][lockTime 4B LE][diffBody...]
  // 2026-10-29：类型号改用 APK `We` 表的真实值（4/10/11/17/19），并保留 02/07 两条
  // 作为「表外类型 → 未知(N)」的回退用例（02/07 只在消息中心枚举 Rn 里，日志不会发）。
  // len 按 APK `Ge.parseData` 的严格校验 `2*len == body.length` 填（body = 去掉前 2 字节）。
  log_frame: frame8(0x16,
    klv(0x03, '00') +
    klv(0x04, '02000000') +
    // type 17 (0x11) 密码开门：diffBody = pwdIdx(4) + preLogIdx(8) = 12 hex，总 16 字节 ⇒ len 0x0e
    klv(0x05, '110e' + '01000000' + '803aa101' + '0100' + '02000000') +
    // type 19 (0x13) 指纹开门：diffBody = fpBatchNo(8) + fpIdx(8) + 8 = 24 hex，总 22 字节 ⇒ len 0x14
    klv(0x05, '1314' + '02000000' + '203bb101' + '01000000' + '02000000' + '03000000') +
    // type 11 (0x0b) 数字钥匙开门：diffBody = track(8) + pin(8) + uuid(32) + 8 = 56 hex，总 38 字节 ⇒ len 0x24
    klv(0x05, '0b24' + '03000000' + '403cb101' + '00000000' + '00000000' + '00112233445566778899aabbccddeeff' + '00000000') +
    // type 4 (0x04) 静态电量：diffBody = pwdLv(4) = 4 hex，总 12 字节 ⇒ len 0x0a
    klv(0x05, '040a' + '04000000' + '503db101' + '0300') +
    // 表外类型回退：02 / 07 应显示 未知(2) / 未知(7)
    klv(0x05, '020e' + '05000000' + '603eb101' + '3031323334') +
    klv(0x05, '070c' + '06000000' + '703fb101' + 'aabb')),
  log_parsed: null,
  // 8B/7B/10B 三头解析兼容
  header8: frame8(0x03, klv(0x03, '00')),
  header7: '87' + '01' + P.hexPair(2) + P.hexPair(0x03) + P.hexPair(2) + '0000' + klv(0x03, '00'),
  header10: '87' + '00' + P.hexPair(2) + P.hexPair(0x03) + 'beef' + '000000' + klv(0x03, '00')
};
g.parse.log_parsed = ST.parseLogs(P.parseResponse(g.parse.log_frame).klvs);
g.parse.status_parse_headers = {
  h8: ST.parseStatus(P.parseResponse(g.parse.header8).klvs),
  h7: ST.parseStatus(P.parseResponse(g.parse.header7).klvs),
  h10: ST.parseStatus(P.parseResponse(g.parse.header10).klvs)
};

// ---------- 广播解析 (parseAdv) ----------
// 98ed + fc(0x0C) + vendor byte + pid u16 LE (8098=22 1F) + MAC 6B
const advPayload = '98ed' + '0d' + '00' + '221f' + 'aabbccddeeff';
g.parseAdv = {
  input: advPayload,
  out: BLE.parseAdv(advPayload)
};
// DFU 态广播 (frameCtrl bit5)
const advDfu = '98ed' + '2d' + '00' + '221f' + '112233445566';
g.parseAdv.dfumode_input = advDfu;
g.parseAdv.dfumode = BLE.parseAdv(advDfu);

// ---------- ZOTP (定输入 + 冻结时钟: 覆盖 time.js 模块对象的 nowProtoSeconds) ----------
const FIXED_SEC = 1800000000;
const origNow = T.nowProtoSeconds;
T.nowProtoSeconds = () => FIXED_SEC;
g.zotp = {
  fixedSec: FIXED_SEC,
  v30_0: Z.generate(MAC, SKEY, 30, 0),
  v30_1: Z.generate(MAC, SKEY, 30, 1),
  v30_99: Z.generate(MAC, SKEY, 30, 99),
  v60_0: Z.generate(MAC, SKEY, 60, 0)
};
T.nowProtoSeconds = origNow;

// ---------- rc/错误码词表 (Swift 侧断言一致性) ----------
g.rcMsgTable = require(CORE + '/services/lock.js').RC_MSG;
g.pidTable = require(CORE + '/utils/pidmap.js').PID;
g.capabilities = {
  canDefend_KX: require(CORE + '/utils/pidmap.js').canDefend(8098),
  canDefend_V1: require(CORE + '/utils/pidmap.js').canDefend(7857),
  canDefend_GW: require(CORE + '/utils/pidmap.js').canDefend(12193),
  canTailgate_V1Pro_oldFw: require(CORE + '/utils/pidmap.js').canTailgate(7858, '1.0.2'),
  canTailgate_V1Pro_newFw: require(CORE + '/utils/pidmap.js').canTailgate(7858, '1.0.3'),
  canDeviceUpgrade_KX: require(CORE + '/utils/pidmap.js').canDeviceUpgrade(8098)
};

// ---------- inflate/zip 基准 (Swift Compression 框架对照 node zlib) ----------
const rawSamples = [
  Buffer.from('hello hello hello hello world world world'),
  Buffer.from((() => { const b = []; for (let i = 0; i < 5000; i++) b.push((i * 31 + 7) % 251); return b; })())
];
g.inflate = rawSamples.map(b => ({
  raw: b.toString('base64'),
  deflated: zlib.deflateRawSync(b).toString('base64'),
  size: b.length
}));

// ---------- 网关 38 应答解析 ----------
const GW = require(CORE + '/services/gateway.js');
g.gwStatus = GW.parseGWStatus([
  { key: 0x01, val: 'aabbccddeeff' },
  { key: 0x02, val: '090205' },
  { key: 0x03, val: Buffer.from('V5.2', 'ascii').toString('hex') },
  { key: 0x04, val: Buffer.from('MyWiFi', 'ascii').toString('hex') },
  { key: 0x05, val: Buffer.from('192.168.1.3', 'ascii').toString('hex') },
  { key: 0x06, val: '01' }
]);
g.gwStatus_empty = GW.parseGWStatus([]);

// ---------- 钥匙串 43 应答解析 ----------
const KC = require(CORE + '/services/keychain.js');
g.kcStatus = KC.parseKCStatus([
  { key: 0x03, val: '00' },
  { key: 0x11, val: '55' },
  { key: 0x12, val: '3c' },
  { key: 0x24, val: '02' },
  { key: 0x25, val: '08' },
  { key: 0x31, val: '090205' },
  { key: 0x34, val: 'a13f0000' },
  { key: 0x35, val: '010203' },
  { key: 0x36, val: '82fa' }
]);
g.kcEkeyMacs = KC.parseEkeyMacs([{ key: 0x04, val: MAC + '112233445566' }]);

// ---------- DFU zip (真实固件包, Swift 解析对照) ----------
const zipPath = path.resolve(__dirname, '../vendor/fixture/KX_V5.2.9_180503183402.zip');
const zipBuf = fs.readFileSync(zipPath);
const DFU = require(CORE + '/services/dfu.js');
const fw = DFU.parseDfuZip(zipBuf.buffer.slice(zipBuf.byteOffset, zipBuf.byteOffset + zipBuf.byteLength), 'KX_V5.2.9_180503183402.zip');
g.dfuZip = {
  fileName: 'KX_V5.2.9_180503183402.zip',
  binSize: fw.binSize,
  datSize: fw.datSize,
  version: fw.version,
  binSha256: require('crypto').createHash('sha256').update(Buffer.from(fw.binHex, 'hex')).digest('hex'),
  datHex: fw.datHex,
  binCrc32: DFU.ZIP.crc32(Buffer.from(fw.binHex, 'hex')) >>> 0,
  nextMac: DFU.nextMac('aabbccddeeff'),
  nextMac_wrap: DFU.nextMac('aabbccddeeff0f'),
  versionLt_528_529: DFU.versionLt('5.2.8', '5.2.9'),
  versionLt_529_529: DFU.versionLt('5.2.9', '5.2.9')
};

// ---------- 归属推断 (attribution R1/R2) ----------
const ATT = require(CORE + '/services/attribution.js');
// 冻结时钟: 归属向量按"相对 now 的窗口"计算, 取实时钟会让 committed 夹具每次重生成都漂移
// (旧状态: 只有"金标向量时间戳同步"这类手工提交能勉强对上, CI 无法做漂移校验)。
// 测试侧 testAttribution 以 fixture 的 status.lockTime 为基准做相对偏移 → 与冻结值天然兼容。
const _protoNowReal = T.nowProtoSeconds;
T.nowProtoSeconds = () => 1800000000;
const nowStatus = { lockTime: T.nowProtoSeconds(), fpStock: 1, pwdStock: 1 };
g.attribution = ATT.classify([
  { idxRaw: 1, type: 4, lockTime: T.nowProtoSeconds() - 60 },      // 临时码窗口内
  { idxRaw: 2, type: 3, lockTime: T.nowProtoSeconds() - 120 },     // 唯一指纹 → R2
  { idxRaw: 3, type: 7, lockTime: T.nowProtoSeconds() - 30 }       // 撬锁 → 无法识别
], {
  pwds: [{ temp: true, owner: 'm1', from: '2026-01-01 00:00:00', to: '2118-01-01 00:00:00' }],
  fps: [{ owner: 'm2' }],
  status: nowStatus
});
g.attribution_status = nowStatus;
T.nowProtoSeconds = _protoNowReal;   // 还原实时钟, 后续向量不受影响

// ---------- 时间基准 ----------
g.time = {
  epochMs: T.EPOCH_MS,
  protoFromMs_zero: T.protoSecondsFromMs(new Date('2010-01-01T00:00:00').getTime())   // 本地基准 ⇒ 恰为 0 (与 APK 两侧同墙钟一致)
};

// ---------- 输出 / 漂移校验 ----------
const outPath = path.resolve(__dirname, '../fixtures/golden.json');
const text = JSON.stringify(g, null, 1);
if (CHECK) {
  // 与 committed 夹具逐字节比对 (vendor JS 核心改了但没重生成 → 这里红, 而不是让 Swift 悄悄偏离权威)
  let cur = null;
  try { cur = fs.readFileSync(outPath, 'utf8'); } catch (e) { cur = null; }
  if (cur === null) { console.error('CHECK FAIL: fixtures/golden.json 不存在'); process.exit(1); }
  if (cur.replace(/\r\n/g, '\n') !== text) {
    console.error('CHECK FAIL: committed 金标与 JS 核心输出不一致 — 请运行 `node tools/golden.js` 重生成并提交');
    const keys = Object.keys(g);
    let parsed = {};
    try { parsed = JSON.parse(cur); } catch (e) {}
    const diff = keys.filter(k => JSON.stringify(parsed[k]) !== JSON.stringify(g[k]));
    console.error('差异顶层键:', diff.join(', ') || '(结构同级无差, 可能仅格式/键序)');
    process.exit(1);
  }
  console.log('金标漂移校验通过 (与 JS 核心一致)');
  process.exit(0);
}
fs.mkdirSync(path.dirname(outPath), { recursive: true });
// 覆盖冻结向量前先报"改了哪些顶层键"：本仓的冻结件是跨语言契约，静默重写会把"我手滑跑了生成模式"
// 变成一次无人察觉的基线漂移 (第九十二批我自己就这么跑过一次，逐字节相同才算侥幸)。
let prev = null;
try { prev = fs.readFileSync(outPath, 'utf8'); } catch (e) { prev = null; }
if (prev !== null && prev.replace(/\r\n/g, '\n') !== text) {
  let parsed = {};
  try { parsed = JSON.parse(prev); } catch (e) {}
  const diff = Object.keys(g).filter(k => JSON.stringify(parsed[k]) !== JSON.stringify(g[k]));
  console.warn('⚠ 即将覆盖已存在金标，顶层键差异:', diff.join(', ') || '(仅格式/键序)');
}
fs.writeFileSync(outPath, text);
console.log('金标向量已生成:', outPath,
  '| cmds:', Object.keys(g.cmds).length,
  '| zotp:', Object.keys(g.zotp).length,
  '| inflate:', g.inflate.length,
  '| dfu binCrc32:', g.dfuZip.binCrc32);
