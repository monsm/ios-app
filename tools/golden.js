// 金标向量生成器 — 用已通过 25 套测试的 JS 核心, 为 Swift 重写生成字节级差分基准
// 输出 fixtures/golden.json (Swift XCTest 逐项断言)。
// 用法: node tools/golden.js
'use strict';
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
g.cmds.buildEkeyOpen = CM.buildEkeyOpen(SKEY, MAC, 123456, { trackId: 12345, validFromSec: 0, validToSec: T.protoSecondsFromMs(Date.parse('2118-01-01T00:00:00Z')) });
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
  // 16 日志: 每条 KLV#05 = [type][len][idx 4B LE][lockTime 4B LE]...
  log_frame: frame8(0x16,
    klv(0x03, '00') +
    klv(0x04, '02000000') +
    klv(0x05, '020e' + '01000000' + '803aa101' + '3031323334') +
    klv(0x05, '070c' + '02000000' + '203bb101' + 'aabb')),
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

// ---------- 时间基准 ----------
g.time = {
  epochMs: T.EPOCH_MS,
  protoFromMs_zero: T.protoSecondsFromMs(Date.parse('2010-01-01T00:00:00Z'))
};

// ---------- 输出 ----------
const outPath = path.resolve(__dirname, '../fixtures/golden.json');
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(g, null, 1));
console.log('金标向量已生成:', outPath,
  '| cmds:', Object.keys(g.cmds).length,
  '| zotp:', Object.keys(g.zotp).length,
  '| inflate:', g.inflate.length,
  '| dfu binCrc32:', g.dfuZip.binCrc32);
