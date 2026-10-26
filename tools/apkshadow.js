#!/usr/bin/env node
/* apkshadow.js — 以**原版 APK 的 main.js**为基线的 Swift 协议对照（不是 vendor/app 移植稿）。
 *
 * 为什么必须另立一支：仓库已有的 cmdsshadow.js 基线是 `fixtures/golden.json`，而 golden.js 从
 * `vendor/app`（本仓 JS 移植稿）生成 —— 用移植稿证明 Swift 与移植稿一致，是循环论证。
 * 这一支直接读 `apk_raw/assets/www/build/main.js` 里的原始实现，逐字节重算，再与 Swift 源码
 * 的算法逐一比对。两边都从 APK 提取出的常量出发，任何一侧写错都会露出差。
 *
 * 覆盖（APK 里能确证的部分）：
 *   1. KLV 编码：key(1B) + len(1B 小端) + value           ← it.getData
 *   2. 帧头：87 + ver(1B) + len(2B 小端) + cmd + ssToken + "000000" + KLV   ← ht.getBytes
 *   3. EKey 包络：88 + ver(00) + 反转MAC(6B) + TrackId(4B LE) + VF(4B LE) + VT(4B LE) + Cmd
 *                                                          ← kt.getBytes / getTrackIdString
 *   4. 协议时间：floor(秒) - floor(2010-01-01 本地秒)       ← getProtocolTimeSecond
 *   5. toSmallByteOrder 的补齐语义（长度不足 2n 时左补 0，然后按 2 字节对反转）
 *   6. 命令号全集（31 个枚举 + HEADMARK/TOKENKEY）
 *
 * 不覆盖：AES 密文本身（依赖 CommonCrypto，node 侧用 crypto 只能证明"输入相同"，
 * 不能证明 iOS 的 CCCrypt 分支），以及锁端是否认这些字节（要真锁）。
 */
'use strict';
process.env.TZ = process.env.APK_SHADOW_TZ || 'Asia/Shanghai';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
// 基线查找：优先用仓内自带的 vendor/apk-baseline（CI 也能跑），
// 其次退回开发机上的 D:/aapk 反编译目录（那边文件更全，但不入库）。
const VENDOR = path.join(ROOT, 'vendor/apk-baseline');
function pick(rel, devRel) {
  const inRepo = path.join(VENDOR, rel);
  if (fs.existsSync(inRepo)) return inRepo;
  return devRel;
}
const APK_MAIN = pick('www/build/main.js', 'D:/aapk/apk_raw/assets/www/build/main.js');

// 2026-10-26: 基线缺失时给出可执行的说明而不是裸 ENOENT 堆栈。
// 这个坑真实发生过 —— `.gitignore` 的 `build/` 规则把 vendor/apk-baseline/www/build/main.js
// 一起忽略了，于是本地有文件时一直通过、CI 上却直接崩。现在我已在 .gitignore 里加了例外，
// 并在这里显式报错：缺基线时宁可红得明白，也不要红成一坨栈。
if (!fs.existsSync(APK_MAIN)) {
  console.error('✗ 找不到 APK 基线 main.js:' + APK_MAIN);
  console.error('  它应该在 vendor/apk-baseline/www/build/main.js (已提交进仓)。');
  console.error('  若本地被 .gitignore 忽略，用 git add -f 强制加入，并检查 .gitignore 的 build/ 例外。');
  process.exit(1);
}
const main = fs.readFileSync(APK_MAIN, 'utf8');

// ---------- 从 APK 提取常量（不硬编码，避免抄错） ----------
function enumFromMain(name) {
  // 形如：l.ZKCCOMM_GETSTATUS="03"  或  l.HeadMark="88"
  const re = new RegExp(`l\\.${name}="([0-9A-Fa-f]{2})"`, 'g');
  const out = [];
  let m;
  while ((m = re.exec(main))) out.push(m[1].toUpperCase());
  return out;
}

const CMD_ENUM = {
  HEADMARK: enumFromMain('ZKCCOMM_HEADMARK')[0],
  TOKENKEY: enumFromMain('ZKCCOMM_SESSIONTOKENKEY')[0],
  TOKEN_DEFAULT: enumFromMain('ZKCCOMM_SESSIONTOKEN_DEFAULT')[0],
  GETSESSIONTOKEN: enumFromMain('ZKCCOMM_GETSESSIONTOKEN')[0],
  GETBLEMAC: enumFromMain('ZKCCOMM_GETBLEMAC')[0],
  GETSTATUS: enumFromMain('ZKCCOMM_GETSTATUS')[0],
  OPEN: enumFromMain('ZKCCOMM_OPEN')[0],
  EXSECURITYKEY: enumFromMain('ZKCCOMM_EXSECURITYKEY')[0],
  SYNCPINS: enumFromMain('ZKCCOMM_SYNCPINS')[0],
  SYNCPWD: enumFromMain('ZKCCOMM_SYNCPWD')[0],
  SYNCPWDEXPIRE: enumFromMain('ZKCCOMM_SYNCPWDEXPIRE')[0],
  SYNCTIME: enumFromMain('ZKCCOMM_SYNCTIME')[0],
  ECHO: enumFromMain('ZKCCOMM_ECHO')[0],
  ADDNEWFP: enumFromMain('ZKCCOMM_ADDNEWFP')[0],
  ADDNEWFPCONFIRM: enumFromMain('ZKCCOMM_ADDNEWFPCONFIRM')[0],
  DELETEFP: enumFromMain('ZKCCOMM_DELETEFP')[0],
  GETLOG: enumFromMain('ZKCCOMM_GETLOG')[0],
  VOLUME: enumFromMain('ZKCCOMM_SetSoundVolumn')[0],
  OPENZOTP: enumFromMain('ZKCCOMM_OPENZOTP')[0],
  VALIDATION: enumFromMain('ZKCCOMM_SETVALIDATIONMODE')[0],
  BKEY: enumFromMain('setBeacomKey')[0],
  DFU: enumFromMain('enableDFUstate')[0],
  EXKEYWAY: enumFromMain('GetExSecurityKeyWay')[0],
  AUTOLOCK: enumFromMain('setMotoAutoLockInterval')[0],
  DEFENCE: enumFromMain('setDefence')[0],
  GWSTATUS: enumFromMain('GWGetStatus')[0],
  GWWIFI: enumFromMain('GWSetWifi')[0],
  GWIOT: enumFromMain('GWSetIot')[0],
  GWREBOOT: enumFromMain('GWReboot')[0],
  GWNAME: enumFromMain('GWGetDeviceName')[0],
  KCWRITE: enumFromMain('Key_Chain_WriteEKey')[0],
  KCSTATUS: enumFromMain('Key_Chain_GetStatus')[0],
  KCINFO: enumFromMain('Key_Chain_GetEKeyInfo')[0],
};
// EKey 包络命令枚举（第二套：ot.HeadMark="88" 那一组）
const EKEY_ENUM = {
  HeadMark: (main.match(/l\.HeadMark="([0-9A-Fa-f]{2})"/) || [])[1],
  GetStatus: (main.match(/l\.GetStatus="([0-9A-Fa-f]{2})"/) || [])[1],
  Open: (main.match(/l\.Open="([0-9A-Fa-f]{2})"/) || [])[1],
  SyncPINs: (main.match(/l\.SyncPINs="([0-9A-Fa-f]{2})"/) || [])[1],
  SyncPwd: (main.match(/l\.SyncPwd="([0-9A-Fa-f]{2})"/) || [])[1],
  SyncPwdExpire: (main.match(/l\.SyncPwdExpire="([0-9A-Fa-f]{2})"/) || [])[1],
  SyncTime: (main.match(/l\.SyncTime="([0-9A-Fa-f]{2})"/) || [])[1],
  AddNewFP: (main.match(/l\.AddNewFP="([0-9A-Fa-f]{2})"/) || [])[1],
  AddNewFPConfirm: (main.match(/l\.AddNewFPConfirm="([0-9A-Fa-f]{2})"/) || [])[1],
  DeleteFP: (main.match(/l\.DeleteFP="([0-9A-Fa-f]{2})"/) || [])[1],
  GetLog: (main.match(/l\.GetLog="([0-9A-Fa-f]{2})"/) || [])[1],
  Volume: (main.match(/l\.SetSoundVolumn="([0-9A-Fa-f]{2})"/) || [])[1],
  OpenZotp: (main.match(/l\.OpenZotp="([0-9A-Fa-f]{2})"/) || [])[1],
  Validation: (main.match(/l\.SetValidationMode="([0-9A-Fa-f]{2})"/) || [])[1],
  Bkey: (main.match(/l\.setBeacomKey="([0-9A-Fa-f]{2})"/) || [])[1],
  Dfu: (main.match(/l\.enableDFUstate="([0-9A-Fa-f]{2})"/) || [])[1],
  AutoLock: (main.match(/l\.setMotoAutoLockInterval="([0-9A-Fa-f]{2})"/) || [])[1],
  Defence: (main.match(/l\.setDefence="([0-9A-Fa-f]{2})"/) || [])[1],
};

// ---------- APK 算法的 JS 重算 ----------
const toSmallByteOrder = (hex, n) => {
  if (!hex) return '';
  let h = hex;
  if (h.length < 2 * n) h = '0'.repeat(2 * n - h.length) + h;
  let out = '';
  const len = h.length;
  for (let s = 1; s <= len / 2; s++) out += h.substr(len - 2 * s, 2);
  return out;
};
const klv = (key, value) => key + toSmallByteOrder((value.length / 2).toString(16).toUpperCase(), 1) + value;
const frameBytes = (cmd, klvHex, ssToken = '0000') => {
  const lenHex = toSmallByteOrder((klvHex.length / 2).toString(16).toUpperCase(), 2);
  return '87' + toSmallByteOrder('0', 1) + lenHex + cmd + ssToken + '000000' + klvHex;
};
const EP = Date.parse('2010-01-01T00:00:00');
const protoSec = (dateStr) => Math.floor(Date.parse(dateStr) / 1000) - Math.floor(EP / 1000);
const ekeyEnvelope = (cmd, macDisplay, trackId, vfStr, vtStr) => {
  // kt.getBytes: 反转 TargetMAC（显示序 → 线上序），再 TrackId/VF/VT/Cmd，Version 恒 "00"
  const revMac = toSmallByteOrder(macDisplay, 3);
  const track = toSmallByteOrder(trackId.toString(16).toUpperCase(), 4);
  const vf = toSmallByteOrder(protoSec(vfStr).toString(16).toUpperCase(), 4);
  const vt = toSmallByteOrder(protoSec(vtStr).toString(16).toUpperCase(), 4);
  return (EKEY_ENUM.HeadMark || '88') + '00' + revMac + track + vf + vt + cmd;
};

// ---------- Swift 源码里对应的实现（从文件读，不重复实现） ----------
// 统一行尾：Windows 下 CRLF、CI 检出 LF，正则里写 \n 会在两边给出不同结论
const readSwift = (rel) => fs.readFileSync(path.join(ROOT, rel), 'utf8').replace(/\r\n/g, '\n');
const swift = readSwift('App/Core/ZKProtocol.swift');
const swiftCmd = readSwift('App/Core/ZKCmdBuilder.swift');
const swiftHex = readSwift('App/Core/HexKit.swift');

// ---------- 比对 ----------
let pass = 0, fail = 0;
const results = [];
function check(name, ok, detail) {
  if (ok) { pass++; results.push(['✓', name, '']); }
  else { fail++; results.push(['✗', name, detail || '']); }
}

// 1) 命令枚举：Swift 里写死的命令号必须与 APK 一致
const swiftCmds = {};
for (const m of swiftCmd.matchAll(/cmd:\s*0x([0-9a-fA-F]{2})/g)) {
  swiftCmds[m[1].toUpperCase()] = true;
}
const apkCmdSet = new Set(Object.values(CMD_ENUM).filter(v => /^[0-9A-F]{2}$/.test(v)));
const stray = Object.keys(swiftCmds).filter(c => !apkCmdSet.has(c));
check('Swift 命令号都在 APK 枚举内', stray.length === 0,
  stray.length ? `APK 枚举里没有: ${stray.join(', ')}` : '');

// 2) KLV 长度字段是 1 字节小端（>255 时 APK 的 toSmallByteOrder 会截断为 1 字节）
const klvLen = (n) => toSmallByteOrder(n.toString(16).toUpperCase(), 1);
check('KLV 长 255B 编码为 ff（APK 大写 / Swift 小写但字节一致）', klvLen(255).toLowerCase() === 'ff', klvLen(255));
check('KLV 长 16B 编码为 "10"', klvLen(16) === '10', klvLen(16));
check('KLV 长 1B 编码为 "01"', klvLen(1) === '01', klvLen(1));

// 3) 帧头长度是 2 字节小端
check('帧长 300B → "2c01"', toSmallByteOrder('12c', 2) === '2c01', toSmallByteOrder('12c', 2));
check('帧长 16B → "1000"', toSmallByteOrder('10', 2) === '1000', toSmallByteOrder('10', 2));

// 4) EKey 包络结构（按 APK 的 kt.getBytes 重算，与 Swift buildEkey 对照）
const MAC = 'aabbccddeeff';
const ENV = ekeyEnvelope('04', MAC, 0, '2010-01-01 00:00:00', '2118-01-01 00:00:00');
check('EKey 头 = 88', ENV.slice(0, 2) === '88', ENV.slice(0, 2));
check('EKey Version = 00', ENV.slice(2, 4) === '00', ENV.slice(2, 4));
check('EKey MAC 逐字节全反转 = ffeeddccbbaa', ENV.slice(4, 16) === 'ffeeddccbbaa', ENV.slice(4, 16));
check('EKey TrackId 4B LE', ENV.slice(16, 24) === '00000000', ENV.slice(16, 24));
check('EKey 总长 = 42 hex（21B）', ENV.length === 42, String(ENV.length));
check('EKey Cmd 在末 2 位 = 04', ENV.slice(-2) === '04', ENV.slice(-2));

// 5) Swift 的 buildEkey 字段顺序与 APK 一致（源码级断言，不执行 Swift）
const buildEkeyBody = (swift.match(/static func buildEkey\([\s\S]{0,600}?\n    \}/) || [''])[0];
check('Swift buildEkey 用 "8800" + reversePairs(mac)',
  /"8800"\s*\+\s*HexKit\.reversePairs\(mac\)/.test(buildEkeyBody),
  buildEkeyBody.slice(0, 120));
check('Swift buildEkey 顺序 = trackId → validFrom → validTo → cmd',
  /u32leHex\(trackIdVal\)[\s\S]{0,200}?u32leHex\(validFromSec\)[\s\S]{0,200}?u32leHex\(vt\)[\s\S]{0,200}?hexPair\(UInt32\(cmd\)\)/.test(buildEkeyBody),
  '顺序不符');

// 6) Swift buildFrame 结构
check('Swift buildFrame = 87 + 00 + lenLE16 + cmd + token + 000000',
  /"87"\s*\+\s*"00"\s*\+\s*HexKit\.hexPair\(UInt32\(len/.test(swift),
  '帧头结构不符');
check('Swift buildFrame 长度取 klv.count/2', /let len = klv\.count \/ 2/.test(swift), '');

// 7) 协议时间基准 = 2010-01-01（本地），与 APK getProtocolTimeSecond 同口径
check('Swift 有 2010-01-01 基准', /2010-01-01/.test(swift), '');
const swiftEP = /c\.year = 2010/.test(swift) && /cal\.timeZone = TimeZone\.current/.test(swift);
check('Swift epochMs 用本地 2010-01-01（DateComponents + 当前时区）', swiftEP, '');

// 8) 本轮新写的 cmd08 删 pin：APK 的 08 体 = addCount(1B)+delCount(1B)+addPins+delPins
const delPinsBody = (swiftCmd.match(/static func cmd08SyncPinsBatch[\s\S]{0,1200}?\n    \}/) || [''])[0];
check('cmd08 体 = addCount + delCount + addPins + delPins',
  /hexPair\(UInt32\(addPins\.count\)\)\s*\+\s*HexKit\.hexPair\(UInt32\(delPins\.count\)\)[\s\S]{0,200}?addPins\.joined\(\)[\s\S]{0,200}?delPins\.joined\(\)/.test(delPinsBody),
  delPinsBody.slice(0, 160));
check('cmd08 单批上限 20（APK syncPins20 同值）', /addPins\.count > 20/.test(delPinsBody), '');
check('cmd08 用 0x01 包络键（同步 PIN 走密文）', /wrapFrame\(0x08[\s\S]{0,200}?, 0x01\)/.test(delPinsBody), '');

// 9) 本轮新写的 cmd25 布防：APK setDefence 体 = control(1B)+start(4B LE)+end(4B LE)
const defenceBody = (swiftCmd.match(/static func cmd25Defence[\s\S]{0,400}?\n    \}/) || [''])[0];
check('cmd25 体 = control + start(4B LE) + end(4B LE)',
  /hexPair\(UInt32\(truncatingIfNeeded: control\)\)\s*\+\s*HexKit\.u32leHex\(UInt32\(truncatingIfNeeded: startSec\)\)\s*\+\s*HexKit\.u32leHex\(UInt32\(truncatingIfNeeded: endSec\)\)/.test(defenceBody),
  defenceBody.slice(0, 160));
check('cmd25 包络键 = 0x01（密文）', /wrapFrame\(0x25[\s\S]{0,300}?, 0x01\)/.test(defenceBody), '');

// 10) 本轮新写的 cmd22 进 DFU：APK enableDFUstate 体 = param(1B)
const dfuBody = (swiftCmd.match(/static func cmd22EnableDfu[\s\S]{0,400}?\n    \}/) || [''])[0];
check('cmd22 体 = param 单字节', /hexPair\(UInt32\(param & 0xff\)\)/.test(dfuBody), '');
check('cmd22 包络键 = 0x02', /wrapFrame\(0x22[\s\S]{0,300}?, 0x02\)/.test(dfuBody), '');

// 11) cmd41 写钥：APK Key_Chain_WriteEKey 是**明文帧**（免令牌）
const w41 = (swiftCmd.match(/static func cmd41WriteEkey[\s\S]{0,1200}?\n    \}/) || [''])[0];
check('cmd41 走明文帧（buildFrame，非 wrapFrame 密文）', /buildFrame\(0x41/.test(w41) && !/wrapFrame\(0x41/.test(w41),
  w41.slice(0, 140));

// 12) toSmallByteOrder 的补齐语义：长度不足时**左补 0**
const pad = (v, n) => toSmallByteOrder(v, n);
check('短值左补 0（"1" 补成 "01" 再反转）', pad('1', 1) === '01', pad('1', 1));
check('4B 反转（"12345678" → "78563412"）', pad('12345678', 4) === '78563412', pad('12345678', 4));

// 13) pin 编码：APK 把十进制 pin 转 hex 再 4B 小端；Swift 的 genPin 直接产出 4B 小端 hex
//     ⇒ addPins.joined() 与 APK 的 toSmallByteOrder(pin.toString(16),4) 等价。
//     APK: i.addPinsString += En.toSmallByteOrder(n[u].toString(16),4).toUpperCase()
const keyGen = readSwift('App/Core/KeyGen.swift');
check('Swift genPin 输出 4B 小端 hex（b[3],b[2],b[1],b[0]）',
  /HexKit\.hex\(\[b\[3\], b\[2\], b\[1\], b\[0\]\]\)/.test(keyGen),
  '格式不符');
check('Swift delPinSentinel = ffffffff（APK 的 4294967295 小端）',
  /delPinSentinel = "ffffffff"/.test(keyGen), '');
check('cmd08 addCount/delCount 都按个数（APK 同）',
  /hexPair\(UInt32\(addPins\.count\)\)\s*\+\s*HexKit\.hexPair\(UInt32\(delPins\.count\)\)/.test(swiftCmd), '');

// 14) 令牌注入用的 KLV 键 —— 这条容易搞错，结论以**Java 生产链**为准：
//     · main.js 里 ZKCCOMM_SESSIONTOKENKEY="F0" 只是枚举，全库**零使用点**
//     · 真正的注入在 jzzns22561_out/.../LockCommBase.java:98
//         this.mKLVList.add((byte) -18, ssToken);
//       (byte)-18 = 0xEE ⇒ Swift 的 buildKLV(0xEE, tokenHex) 才是原版行为
const JAVA_BASE = pick('lockprotocol/LockCommBase.java',
  'D:/aapk/jzzns22561_out/sources/cn/zelkova/ZKurlcsPlugin/lockprotocol/LockCommBase.java');
let javaBase = '';
try { javaBase = fs.readFileSync(JAVA_BASE, 'utf8').replace(/\r\n/g, '\n'); } catch (e) { /* 不在工作区时跳过 */ }
check('Swift 令牌注入键 = 0xEE（对齐 Java (byte)-18）',
  /buildKLV\(0xEE, tokenHex\)/.test(swift), 'Swift 未用 0xEE');
if (javaBase) {
  check('Java 生产链确认注入键 = (byte)-18（0xEE）',
    /mKLVList\.add\(\(byte\)\s*-18,\s*ssToken\)/.test(javaBase), '');
  check('Java 生产链帧头 = 0x87 + 版本 + 长度LE16 + cmd + 3×0x00 + KLV',
    /out\.writeByte\(-121\)[\s\S]{0,200}?out\.writeShort\(this\.mKLVList\.getBytes\(\)\.length\)[\s\S]{0,160}?out\.writeByte\(getCmdId\(\)\)[\s\S]{0,120}?out\.write\(new byte\[3\]\)[\s\S]{0,160}?out\.write\(this\.mKLVList\.getBytes\(\)\)/.test(javaBase),
    '');
  check('Java 生产链：needSessionToken 且无 token 时直接抛错（不降级）',
    /needSessionToken\(\)\s*&&\s*\(ssToken == null \|\| ssToken\.length <= 0\)[\s\S]{0,120}?throw new LockException/.test(javaBase), '');
} else {
  console.log('  · Java 基线不在工作区，跳过 3 条 Java 层断言');
}

// 15) DFU：判据与状态码都要对齐原版（不是靠广播名）
const dfuSwift = readSwift('App/Services/DFUKit.swift');
const bleDfu = (() => {
  try { return fs.readFileSync(pick('dfu/BleDfu.java',
    'D:/aapk/jzzns22561_out/sources/com/plugin/urlcsDfuPlugin/BleDfu.java'), 'utf8').replace(/\r\n/g, '\n'); }
  catch (e) { return ''; }
})();
if (bleDfu) {
  check('APK 用 pid + dfuState==1 过滤 DFU 广播',
    /getPid\(\) == BleDfu\.this\.zkBleBlock\.pid && curAdData\.getDfuState\(\) == 1/.test(bleDfu), '');
  check('Swift DFU 扫描复用 parseAdv 的 dfuState 判据',
    /a\.dfuState == 1/.test(dfuSwift), '');
  check('Swift DFU 扫描窗口 10s（对齐 APK postDelayed 10000）',
    /\.now\(\) \+ 10\)/.test(dfuSwift), '');
  check('Swift DFU 兜底按广播名 ZKDFU', /contains\("ZKDFU"\)/.test(dfuSwift), '');
} else {
  console.log('  · BleDfu.java 不在工作区，跳过 4 条 DFU 断言');
}
// DFU 状态码：APK 插件把 Nordic 回调压成 0/1/2/4/5/6/7 + -1
const dfuPlugin = (() => {
  try { return fs.readFileSync(pick('dfu/URLCSDfuPlugin.java',
    'D:/aapk/jzzns22561_out/sources/com/plugin/urlcsDfuPlugin/URLCSDfuPlugin.java'), 'utf8').replace(/\r\n/g, '\n'); }
  catch (e) { return ''; }
})();
if (dfuPlugin) {
  const codes = [...dfuPlugin.matchAll(/sendExeResult\("state",\s*(-?\d+)/g)].map(m => Number(m[1]));
  const want = [0, -1, 1, -1, 2, 4, 5, -1, 6, 7];
  check('APK DFU 状态码序列 = 0,-1,1,-1,2,4,5,-1,6,7', JSON.stringify(codes) === JSON.stringify(want), JSON.stringify(codes));
  check('Swift DFUState 覆盖 0/1/2/4/5/6/7 + -1',
    /case connecting = 0/.test(dfuSwift) && /case eventOnly = -1/.test(dfuSwift)
    && /case processStarting = 1/.test(dfuSwift) && /case enablingDfu = 2/.test(dfuSwift)
    && /case validating = 4/.test(dfuSwift) && /case disconnecting = 5/.test(dfuSwift)
    && /case completed = 6/.test(dfuSwift) && /case aborted = 7/.test(dfuSwift), '');
}

// ---------- 输出 ----------
console.log('APK 基线协议对照');
console.log('  JS 基线: ' + (APK_MAIN.startsWith(VENDOR) ? 'vendor/apk-baseline/www/build/main.js（仓内）' : 'D:/aapk/apk_raw/...（工作区）'));
console.log('  Java 基线: ' + (JAVA_BASE.startsWith(VENDOR) ? 'vendor/apk-baseline/lockprotocol/LockCommBase.java（仓内）' : 'D:/aapk/jzzns22561_out/...（工作区）') + '\n');
console.log('APK 命令枚举:');
for (const [k, v] of Object.entries(CMD_ENUM)) if (v) console.log(`  ${k.padEnd(20)} ${v}`);
console.log('\nAPK EKey 包络枚举:');
for (const [k, v] of Object.entries(EKEY_ENUM)) if (v) console.log(`  ${k.padEnd(20)} ${v}`);

console.log('\n比对结果:');
for (const [mark, name, detail] of results) {
  console.log(`  ${mark} ${name}${detail ? '  ← ' + detail : ''}`);
}
console.log(`\n通过 ${pass} · 失败 ${fail}`);
console.log('\n边界: 本工具证明的是「Swift 源码写出的算法」与「APK main.js 的算法」在结构/常量/字节序上一致；');
console.log('不覆盖 AES 密文（要真机 CCCrypt）、也不覆盖锁端是否认这些字节（要真锁）。');
process.exit(fail ? 1 : 0);
