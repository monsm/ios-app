// 状态响应 KLV 标签 → 名称 + 值格式化
// 依据: _t.parseKlv @ main.pretty.js 行 9423 (2026-09-03 实测 verify-status-parseklv.js;
//   旧误表 01=rc/03=sKey/05=keyboardFreeze… 已勘误, 见 01-命令字典 §4′)
const STATUS_LABELS = {
  0x01: 'sKeyStatus(密钥状态)',
  0x03: 'resultCode(总rc)',
  0x04: 'lockTime(协议秒,4B LE)',
  0x05: 'zotpPeriod(u16 LE)',
  0x06: 'keyboardFreeze',
  0x07: 'keyboardErrCount',
  0x08: 'securityLevel(bit0=verify bit1=broadcast bit2=tempPwd)',
  0x11: 'powerLevel(电量)',
  0x14: 'soundVolumn(音量)',
  0x21: 'pinInfoCapacity', 0x22: 'pinInfoStock', 0x23: 'pinInfoBinding',
  0x24: 'pwdInfoCapacity', 0x25: 'pwdInfoStock', 0x26: 'pwdInfoMaxLen',
  0x27: 'fpInfoCapacity', 0x28: 'fpInfoStock', 0x29: 'fpInfoBatchNumber',
  0x31: 'verFirmware(3B→a.b.c 直读)',
  0x32: 'verDFU',
  0x33: 'verKeyboard(u16 LE)',
  0x34: 'pid(u32 LE)',
  0x35: 'eCtrlVer(ASCII)',
  0xee: 'requestToken(回显)'
};

// 结果码 — 两类分表 (2026-09-09 按 main.js 逐字取证拆分):
//   A. TRANSPORT_CODES: H5 JS 帧解析器 ut 枚举 (main.js `ut.LENGTH_IS_NOT_ENOUGH="01"` 等),
//      即传输/解析层错误码 (hex 字符串), 非锁端业务码
//   B. LOCK_RESULT_CODES: main.js `resultCodeToMessage` 锁端业务码 1..27 (原文精确, 无 0/4 键)
const TRANSPORT_CODES = {
  0x01: 'LENGTH_IS_NOT_ENOUGH 长度不足',
  0x02: 'L1HEADMARK_IS_WRONG 帧头错误',
  0x03: 'UNABLE_PARSE_KLV 无法解析KLV',
  0xf0: 'NO_RESULTCODE 无结果码'
};
const LOCK_RESULT_CODES = {
  1: '解密失败', 2: '无效的PIN码', 3: '命令过期', 5: '次数使用完毕',
  6: '开锁指令已绑定其他设备', 7: '执行的操作不在指定的状态', 8: '溢出', 9: '时间误差过大',
  10: '未知错误', 11: '解密失败', 12: 'mac地址不正确', 13: '通讯过期',
  14: '不支持的秘钥交换方式', 15: '未知协议', 16: '参数不在范围内', 17: '丢包',
  18: '不能设置重复的值', 19: '找不到指定的值', 20: '指纹传感器错误', 21: '门锁处于反锁状态',
  22: '不能重复验证', 23: '无法获取有效的指纹图片', 24: '录入指纹超时', 25: '锁正忙，请稍后重试',
  26: '门锁被撬', 27: '您的门锁处于布防状态'
};
// BLE 层错误码 (bleCodeMsg 原文; 1007 曾误写 "ssToken错误/不匹配", 2026-09-09 勘误为超时)
const BLE_ERROR_CODES = {
  1001: '未发现门锁，请靠近门锁重试', 1003: '', 1004: '',
  1006: '获取ssToken失败', 1007: '超时未收到返回数据', 1008: '不支持的ssToken方式',
  2003: '连接设备超时', 5001: '解析数据失败', 6001: '超时未等到Rx写入确认',
  6002: '发送命令时线程中断', 6003: '连接时线程中断', 6004: '蓝牙底层失败', 6005: '未成功发送BLE指令'
};
// 兼容旧名 (调用方如果要的是锁端 rc 请改引 LOCK_RESULT_CODES)
const RESULT_CODES = Object.assign({}, TRANSPORT_CODES, LOCK_RESULT_CODES);

// 与 App 同源原语 (En.toNormalByteOrder = 字节对反转; LE 字符串直读=反转后按 BE 读)
function leVal(hex) {
  if (!hex) return 0;
  const b = hex.match(/.{2}/g) || [];
  let v = 0;
  for (let i = b.length - 1; i >= 0; i--) v = v * 256 + parseInt(b[i], 16);
  return v >>> 0;
}

function formatVal(key, hex) {
  try {
    switch (key) {
      case 0x31: { // firmware: App = 反转后逆位读回 ≡ 字节直读 p0.p1.p2
        if (hex.length >= 6) {
          const parts = hex.match(/.{2}/g).slice(0, 3).map(x => parseInt(x, 16));
          return parts[0] + '.' + parts[1] + '.' + parts[2];
        }
        break;
      }
      case 0x35: { // ASCII
        const bytes = hex.match(/.{2}/g) || [];
        return bytes.map(b => String.fromCharCode(parseInt(b, 16))).join('');
      }
      case 0x05: // zotpPeriod u16 LE
        return hex.length >= 4 ? String(leVal(hex)) : String(parseInt(hex, 16));
      case 0x33: // verKeyboard u16 LE
        return String(leVal(hex));
      case 0x34: // pid u32 LE
        return String(leVal(hex));
      case 0x08: { // security bits
        const v = parseInt(hex, 16) & 0xff;
        return v + ' (verify=' + (v & 1) + ' broadcast=' + ((v >> 1) & 1) + ' tempPwd=' + ((v >> 2) & 1) + ')';
      }
      case 0x04: { // protocol time (4B LE)
        const v = leVal(hex);
        if (v > 0) return v + ' → ' + new Date((v + require('./protocol').EPOCH) * 1000).toLocaleString();
        break;
      }
      case 0x11:
      case 0x14: {
        const v = parseInt(hex, 16);
        return v + (key === 0x11 ? '%' : '');
      }
      case 0x01: case 0x03: case 0x06: case 0x07:
      case 0x21: case 0x22: case 0x23:
      case 0x24: case 0x25: case 0x26: case 0x27: case 0x28: case 0x29:
      case 0x32:
        return parseInt(hex, 16);
      default:
        return hex;
    }
  } catch (e) { /* fallthrough */ }
  return hex;
}

function describeResult(code) {
  // 锁端业务码优先 (lock rc 1..27); 其次传输/解析层; BLE 层; 最后未知
  const v = LOCK_RESULT_CODES[code] !== undefined ? LOCK_RESULT_CODES[code]
    : (TRANSPORT_CODES[code] !== undefined ? TRANSPORT_CODES[code]
      : (BLE_ERROR_CODES[code] !== undefined ? BLE_ERROR_CODES[code] : null));
  return v !== null ? v : ('未知结果码 0x' + code.toString(16));
}

module.exports = { STATUS_LABELS, RESULT_CODES, TRANSPORT_CODES, LOCK_RESULT_CODES, BLE_ERROR_CODES, formatVal, describeResult };
