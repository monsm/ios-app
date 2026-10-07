// 产品矩阵 (证据: output/memory/04-app-map.md §产品矩阵; main.pretty.js Nn 枚举/Hn 映射/zn.can*)
const PID = {
  K1: 8097, KX: 8098, V1: 7857, V1_Pro: 7858, JZ: 7873,
  Z3: 7891, Z3NFC: 7892, Z3AL: 7893, ZKBBV1: 16289,
  GW: 12193, GW_commercial: 12209, GW2_commercial: 12194
};
const NAME_BY_PID = {};
for (const k of Object.keys(PID)) NAME_BY_PID[PID[k]] = k;
const LOCKS = [PID.KX, PID.V1, PID.V1_Pro, PID.JZ];
const GWS = [PID.GW, PID.GW_commercial, PID.GW2_commercial];
// 实锁实测 pid=49408 (0xC100) 不在 App V5.2.9 枚举 → 锁上固件非 V5.2.9 (R1b 判决信号)。
// 服务器已停服, 云型号表不可查 → 枚举外 pid 一律按「未知型号」展示, 不编造型号名。
PID.auto = 0; // devicetype「自动识别」: 不按 pid 过滤, resetStatus 门为主

function modelName(pid) {
  if (!pid) return '自动识别';
  return NAME_BY_PID[pid] || ('未知型号(pid=' + pid + ')');
}
function isLock(pid) {
  if (!pid) return true; // 自动识别模式
  return LOCKS.indexOf(pid) >= 0;
}
// 未知 pid (含实锁 49408) 视为 KX 家族新品 → 放行全部锁管理功能 (adddevice auto 同原则;
// 若真是网关类 pid 已在 GWS 表内被拒)。App 原表不含 49408 恰因 App 版本落后于该批次固件。
function _known(pid) { return Object.prototype.hasOwnProperty.call(NAME_BY_PID, pid); }
function _isGW(pid) { return GWS.indexOf(pid) >= 0; }
// zn.can*: 布防/尾门仅 KX+V1_Pro; 清密码/设备信息/升级四锁皆有 (App zn@8778-8798)
function canDefend(pid) { return _isGW(pid) ? false : (pid === PID.KX || pid === PID.V1_Pro || !_known(pid)); }
// V82 (对拍审核): 文档 §9.5 明文 tailgate_defend_romtver="1.0.3"(尾门功能仅 V1_Pro 固件 ≥1.0.3 启用)。
//   → V1_Pro 且固件已知 <1.0.3 时拒绝尾门; 固件未知(未配对/导入旧钥匙串)按兼容放行;
//   其余型号维持 App 既有 canDefend 语义, 不误伤 KX/未知 pid。
function cmpFw(fw, min) {
  const a = String(fw || '').split('.').map(x => parseInt(x, 10) || 0);
  const b = String(min).split('.').map(x => parseInt(x, 10) || 0);
  for (let i = 0; i < 3; i++) {
    if ((a[i] || 0) !== (b[i] || 0)) return (a[i] || 0) > (b[i] || 0) ? 1 : -1;
  }
  return 0;
}
function canTailgate(pid, fw) {
  if (!canDefend(pid)) return false;
  if (pid === PID.V1_Pro && fw && cmpFw(fw, '1.0.3') < 0) return false;
  return true;
}
function canClearPwd(pid) { return _isGW(pid) ? false : (LOCKS.indexOf(pid) >= 0 || !_known(pid)); }
function canDeviceInfo(pid) { return canClearPwd(pid); }
function canDeviceUpgrade(pid) { return canClearPwd(pid); }
module.exports = { PID, NAME_BY_PID, modelName, isLock, canDefend, canTailgate, canClearPwd, canDeviceInfo, canDeviceUpgrade };
