// 03 状态 / 16 日志 响应解析
// 依据: _t.parseKlv @ main.pretty.js 行 9423 (字符级, 2026-09-03 实测脚本
//   output/memory/verify-status-parseklv.js 逐键执行验证) + 16 日志 Je/Ge 类 (行 11552/11583)。
// ⚠ 勘误 (V75): 早前 §4/status.js 表把键表整体错位 (01=rc、03=sKeyStatus、05=keyboardFreeze…),
//   真实键映射为: 01=sKeyStatus, 03=rc, 05=zotpPeriod, 06=keyboardFreeze, 07=keyboardErrCount,
//   08=securityLevel, 11=powerLevel, 14=soundVolumn, 21..29=容量族, 31..35=版本族。
const TIME = require('./time.js');
const PID = require('./pidmap.js');

// KLV key(=线上 tag 字节) → 字段 (03 状态, _t.parseKlv 实测)
const STATUS_KEYS = {
  0x01: 'sKeyStatus', 0x03: 'rc', 0x04: 'lockTime', 0x05: 'zotpPeriod',
  0x06: 'keyboardFreeze', 0x07: 'keyboardErrCount', 0x08: 'securityLevel',
  0x11: 'powerLevel', 0x14: 'soundVolumn',
  0x21: 'pinInfoCapacity', 0x22: 'pinInfoStock', 0x23: 'pinInfoBinding',
  0x24: 'pwdInfoCapacity', 0x25: 'pwdInfoStock', 0x26: 'pwdInfoMaxLen',
  0x27: 'fpInfoCapacity', 0x28: 'fpInfoStock', 0x29: 'fpInfoBatchNumber',
  0x31: 'verFirmware', 0x32: 'verDFU', 0x33: 'verKeyboard', 0x34: 'pid', 0x35: 'eCtrlVer'
};
function intHex(val) { return parseInt(val || '0', 16) || 0; }
// 字符串 LE 解码 (等价 App: En.toNormalByteOrder → parseInt; 字节序反转后按 BE 读 == LE 原值)
function leHexToU32(val) {
  const b = (val || '').match(/.{2}/g) || [];
  let v = 0;
  for (let i = b.length - 1; i >= 0; i--) v = v * 256 + parseInt(b[i], 16);
  return v >>> 0;
}
// En.toNormalByteOrder 副本 (字节对反转; 奇数长度返回 '')
function reversePairs(hex) {
  if (!hex || hex.length % 2 !== 0) return '';
  let out = '';
  for (let i = hex.length - 2; i >= 0; i -= 2) out += hex.substr(i, 2);
  return out;
}
function parseStatus(klvs) {
  const s = {
    rc: -1, sKeyStatus: -1, powerLevel: -1, lockTime: null, pid: 0, pidName: '未知',
    firmware: '', keyboardFreeze: 0, keyboardErrCount: 0, securityLevel: 0,
    verifyMode: 0, broadcastMode: 0, tempPwdMode: 0, zotpPeriod: 0, soundVolumn: 0,
    pinInfoCapacity: 0, pinInfoStock: 0, pinInfoBinding: 0,
    pwdInfoCapacity: 0, pwdInfoStock: 0, pwdInfoMaxLen: 0,
    fpInfoCapacity: 0, fpInfoStock: 0, fpInfoBatchNumber: 0,
    verDFU: 0, verKeyboard: 0, eCtrlVer: '', raw: {}
  };
  for (const k of klvs || []) {
    const name = STATUS_KEYS[k.key];
    if (!name) continue;
    const vlen = k.vlen !== undefined ? k.vlen : (k.val || '').length / 2;
    s.raw[name] = k.val === '' ? '' : k.val;
    switch (name) {
      case 'lockTime': // 4B LE 协议秒 (App: toNormalByteOrder+parseInt → getProtocolSec)
        s.lockTime = leHexToU32(k.val) || null;
        break;
      case 'zotpPeriod': // u16 LE (App: toNormalByteOrder+parseInt)
        s[name] = vlen >= 2 ? leHexToU32(k.val) : intHex(k.val);
        break;
      case 'verFirmware': { // 3B; App: toNormalByteOrder 后逆位读回 == 字节直读 p0.p1.p2
        const o = reversePairs(k.val);
        if (vlen === 3 && o.length === 6) {
          const e = parseInt(o.substr(0, 2), 16);
          const i = parseInt(o.substr(2, 2), 16);
          const u = parseInt(o.substr(4, 2), 16);
          s.firmware = u + '.' + i + '.' + e;
          s[name] = s.firmware;
        }
        break;
      }
      case 'verKeyboard': // u16 LE (App: toNormalByteOrder+parseInt)
      case 'pid': // u32 LE
        s[name] = leHexToU32(k.val);
        if (name === 'pid') s.pidName = PID.modelName(s.pid);
        break;
      case 'eCtrlVer': // ASCII (App: 逐字节 fromCharCode)
        if (vlen > 0) {
          let t = '';
          for (let i = 0; i < vlen; i++) t += String.fromCharCode(parseInt(k.val.substr(i * 2, 2), 16));
          s[name] = t;
        }
        break;
      case 'securityLevel': // bit0=verifyMode bit1=broadcastMode bit2=tempPwdMode
        s[name] = intHex(k.val);
        s.verifyMode = s.securityLevel & 0x01;
        s.broadcastMode = (s.securityLevel >> 1) & 0x01;
        s.tempPwdMode = (s.securityLevel >> 2) & 0x01;
        break;
      case 'pinInfoStock': { s.pinStock = intHex(k.val); s[name] = s.pinStock; break; }
      case 'pwdInfoStock': { s.pwdStock = intHex(k.val); s[name] = s.pwdStock; break; }
      case 'fpInfoStock': { s.fpStock = intHex(k.val); s[name] = s.fpStock; break; }
      default: // 其余全为 App parseInt 直读 (含 fpInfoBatchNumber 不做 LE 反转)
        s[name] = intHex(k.val);
    }
  }
  if (s.pidName === '未知' && s.pid) s.pidName = PID.modelName(s.pid);
  return s;
}
// rc 速查: 03 状态响应 rc 在 KLV#03 (实测; 旧 0x01 误读已勘误)
function getStatusRc(klvs) { return intHex((klvs || []).find(k => k.key === 0x03)?.val); }

// ---- 16 日志条目 ----
// Je 响应: rc@03, surplusLogs@04(4B LE), 每条日志 = 一个 KLV#05 (值=条目 hex)。
// Ge 条目 = 内层 KLV: [type 1B(=KLV key)][len 1B(=值字节数=总字节-2)][idx 4B LE][lockTime 4B LE][diffBody…]
//   App Ge (行 11583): idx 显示 = toNormalByteOrder+parseInt ≡ LE 直读 (旧“显示BE”勘误);
//   len 校验 2*len == 值hex长-4 (即 len == 总字节-2); diffBody 从字节 10 起。
// 日志类型 — V81 勘误: 类型 1/2/3/4/5/6/7/13/224 以 main.js 枚举为准 (报告 §9.5, 逐字:
//   DigitalKeyOpen=1/PasswordOpen=2/FPOpen=3/TempPwdOpen=4/NFCOpen=5/PowerLower=6/
//   Lockpicking=7/WarningFP=13/Thekeyboardislocked=224)。旧表把 4=静态电量、13=交换秘钥
//   与固件/App 语义冲突 (4=临时密码开门、13=指纹告警)。8..27 其余维持管理类日志命名。
//   V82 勘误 (audit): 11/16/17/19 是预研期旧枚举残片 (旧表 {11:key,16:temp,17:pwd,19:fp}
//   被文档 §9.5 判定为预研错误, 真实枚举无这些值) — 与 1/2/3/4 语义重复且会产生
//   重复文案, 已移除; 锁侧日志不会发这些类型, 若发则回退「未知(N)」。
const LOG_TYPES = {
  1: '数字钥匙开门', 2: '密码开门', 3: '指纹开门', 4: '临时密码开门', 5: 'NFC开门',
  6: '电量低', 7: '撬锁', 8: '重新上电', 9: 'DFU 后版本', 10: '多次密码失败锁定',
  12: '授时', 13: '指纹告警', 14: '同步PIN', 15: '同步密码',
  20: '添加指纹',
  21: '删除指纹', 22: '设置安全级别', 23: '状态广播开关', 24: '设置单双验',
  25: '开通临时密码', 26: '设置音量', 27: '设置beacom密钥', 224: '键盘被锁定'
};
function parseLogEntry(hex) {
  if (!hex || hex.length < 20) return null; // App Ge: 值 <10 字节直接报“日志长度不正确”
  const type = parseInt(hex.substr(0, 2), 16);
  const len = parseInt(hex.substr(2, 2), 16); // 值字节数
  const idx = leHexToU32(hex.substr(4, 8));    // App: toNormalByteOrder+parseInt ≡ LE 直读
  const lockTime = leHexToU32(hex.substr(12, 8));
  return {
    type, typeName: LOG_TYPES[type] || ('未知(' + type + ')'),
    len, idx, idxRaw: idx, // idxRaw 保留别名 (records 翻页用; 与 idx 同为 LE 值)
    lockTime, lockTimeStr: lockTime ? TIME.protoSecondsToLocalStr(lockTime) : '', // 2026-09-03: 显示用本地时区 (曾 UTC 早 8h)
    body: hex.substr(20), // diffBody (App Ge: substr(20, len-20))
    invalid: len !== hex.length / 2 - 2 // App 严格校验: len 必须 = 总字节-2
  };
}
function parseLogs(klvs) {
  const out = [];
  for (const k of klvs || []) {
    if (k.key === 0x05) { // Je: 每条日志一个 KLV#05
      const e = parseLogEntry(k.val);
      if (e) out.push(e);
    }
  }
  return out;
}
module.exports = { STATUS_KEYS, LOG_TYPES, parseStatus, getStatusRc, parseLogEntry, parseLogs, leHexToU32, intHex };
