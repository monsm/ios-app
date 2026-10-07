// 固件升级服务 (Nordic DFU) — App checkfirmwareupdate 页离线移植
//   流程 (与 App 一致, 固件包来源由云端下载改为本机导入 — 厂商云已停服):
//     1. 导入固件 zip (wx.chooseMessageFile) → utils/dfu/zip.js 解析 {manifest, .bin 固件, .dat init packet}
//     2. BLE 读锁内版本 (cmd 03, KLV#31) 对比包版本 (文件名 KX_V5.2.9_*.zip → 5.2.9)
//     3. cmd 22 enableDFUstate (App sendDFUCmd: $t 包络 + AES(skey) → KLV#02, needToken) → 锁重启进 bootloader
//     4. 扫描 DFU 设备: 广播 pid 一致 && dfuState 位==1 && (MAC==原 || MAC==原+1) (App scanDevice 启发式;
//        名称含 ZkDFU 兜底) — 15s 超时文案与 App 一致
//     5. Nordic DFU 上传 (utils/dfu/nordic.js: Secure FE59 优先, Legacy 1530 回退) → 进度 0-7/百分比
//   进度状态语义与 App H5 一致: 0 连接 / 1 启动 / 2 切换DFU / 3 传输 / 4 校验 / 5 断开 / 6 完成 / 7 中止
const ZIP = require('../utils/dfu/zip.js');
const NORDIC = require('../utils/dfu/nordic.js');
const BLE = require('./ble.js');
const P = require('../utils/kernel/protocol.js');
const TRACE = require('../utils/trace.js');

// ---------- 固件包解析 ----------
// 输入 ArrayBuffer → {binHex, datHex, binSize, datSize, names, version|null, crcOk}
// 对抗上限: manifest ≤ 4KB, init packet ≤ 4KB, 固件 ≤ 8MB (真实包 74KB), 且 CRC 必须匹配
const LIMITS = { manifest: 4096, dat: 4096, bin: 8 * 1024 * 1024 };
function parseDfuZip(buf, fileName) {
  const entries = ZIP.zipParse(buf);
  const manifestE = ZIP.zipFind(entries, 'manifest.json');
  if (!manifestE) throw new Error('固件包缺少 manifest.json');
  if (manifestE.data.length > LIMITS.manifest) throw new Error('manifest.json 异常过大 (' + manifestE.data.length + 'B)');
  let manifest = null;
  try {
    manifest = JSON.parse(Buffer_ishToText(manifestE.data));
  } catch (e) {
    throw new Error('manifest.json 不是有效 JSON');
  }
  const app = manifest && manifest.manifest && (manifest.manifest.application || manifest.manifest.bootloader);
  if (!app) throw new Error('manifest 缺少 application 段');
  const binName = app.bin_file || app.binFilename || null;
  const datName = app.dat_file || app.data_file || null;
  const binE = binName ? ZIP.zipFind(entries, binName) : null;
  const datE = datName ? ZIP.zipFind(entries, datName) : null;
  if (!binE) throw new Error('固件包缺少固件文件 (' + (binName || 'bin') + ')');
  if (!datE) throw new Error('固件包缺少 init packet (' + (datName || 'dat') + ')');
  if (!binE.crcOk) throw new Error('固件文件 CRC 校验失败 (包损坏)');
  if (!datE.crcOk) throw new Error('init packet CRC 校验失败 (包损坏)');
  if (binE.data.length < 512 || binE.data.length > LIMITS.bin) {
    throw new Error('固件尺寸异常 (' + binE.data.length + 'B, 应在 512B~8MB)');
  }
  if (datE.data.length < 16 || datE.data.length > LIMITS.dat) {
    throw new Error('init packet 尺寸异常 (' + datE.data.length + 'B)');
  }
  return {
    manifest: app,
    binHex: NORDIC.bytesToHex(binE.data),
    datHex: NORDIC.bytesToHex(datE.data),
    binSize: binE.data.length,
    datSize: datE.data.length,
    names: entries.map(e => e.name),
    version: versionFromFileName(fileName),
    sourceName: fileName || ''
  };
}
function Buffer_ishToText(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return s;
}
// KX_V5.2.9_180503183402.zip → '5.2.9'; 无匹配 → null
function versionFromFileName(name) {
  const m = /_?V?(\d+\.\d+\.\d+)_/.exec(String(name || ''));
  return m ? m[1] : null;
}
// App compareVersion(a,b): a<b 返回 true (a 为锁内版本); 仅比较数值段
function versionLt(a, b) {
  const pa = String(a || '').split('.').map(x => parseInt(x, 10) || 0);
  const pb = String(b || '').split('.').map(x => parseInt(x, 10) || 0);
  for (let i = 0; i < 3; i++) {
    if ((pa[i] || 0) < (pb[i] || 0)) return true;
    if ((pa[i] || 0) > (pb[i] || 0)) return false;
  }
  return false;
}

// ---------- DFU 设备扫描 (App scanDevice: pid 一致 + dfuState==1 + MAC==原/原+1; 15s 超时) ----------
function nextMac(macHex) {
  const m = String(macHex || '').replace(/:/g, '').toLowerCase();
  if (!/^[0-9a-f]{12}$/.test(m)) return m;
  const last = parseInt(m.substr(10, 2), 16);
  const inc = ((last + 1) & 0xFF).toString(16);
  return m.substr(0, 10) + ('00' + inc).slice(-2);
}
function scanDfuDevice(lockMac, pid, opts) {
  const o = Object.assign({ timeoutMs: 15000 }, opts);
  const wantA = String(lockMac || '').replace(/:/g, '').toLowerCase();
  const wantB = nextMac(wantA);
  return new Promise((resolve, reject) => {
    let done = false;
    const finish = (err, d) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      try { wx.offBluetoothDeviceFound(handler); } catch (e) {}
      try { wx.stopBluetoothDevicesDiscovery({ fail: () => {} }); } catch (e) {}
      err ? reject(err) : resolve(d);
    };
    const timer = setTimeout(() => finish(new Error('未发现门锁，请靠近门锁重试')), o.timeoutMs);
    const handler = res => {
      if (done) return;
      for (const d of (res.devices || [])) {
        let adv = null;
        try {
          if (d.advertisData && d.advertisData.byteLength) adv = BLE.parseAdv(P.bytesToHex(new Uint8Array(d.advertisData)));
        } catch (e) {}
        const name = String(d.localName || '');
        const macHit = adv && adv.macRaw && (adv.macRaw.toLowerCase() === wantA || adv.macRaw.toLowerCase() === wantB);
        const dfuHit = adv && adv.dfuState === 1 && adv.pid === pid;
        // 名称兜底仅当广播解析不出 pid 时放行 (广播可解析但 pid 不符 → 拒绝, 防误抓同名称的别家锁)
        const advReadable = adv && adv.pid;
        const nameHit = /ZkDFU/i.test(name) && (!advReadable || adv.pid === pid);
        if (!((macHit && dfuHit) || nameHit)) continue;
        done = true;
        const hit = { deviceId: d.deviceId, mac: adv && adv.macRaw ? adv.macRaw.toLowerCase() : '', name, rssi: d.RSSI, pid: adv ? adv.pid : pid };
        TRACE.evt('info', '发现 DFU 设备: ' + hit.deviceId + ' name=' + name);
        clearTimeout(timer);
        try { wx.offBluetoothDeviceFound(handler); } catch (e) {}
        try { wx.stopBluetoothDevicesDiscovery({ fail: () => {} }); } catch (e) {}
        resolve(hit);
        return;
      }
    };
    BLE.ensureOpen().then(err => {
      if (done) return;
      if (err) { finish(new Error('蓝牙未开启: 请到系统设置打开蓝牙后重试')); return; }
      try { wx.onBluetoothDeviceFound(handler); } catch (e) { finish(new Error('无法注册设备发现监听')); return; }
      wx.startBluetoothDevicesDiscovery({
        allowDuplicatesKey: false, interval: 500,
        success: () => {},
        fail: e => finish(new Error('启动扫描失败: ' + ((e && e.errMsg) || '未知')))
      });
    });
  });
}

// ---------- 升级编排 ----------
// lockService: 已配置 MAC/skey 的 LockService; firmware: parseDfuZip 输出
// onProgress({state, percent}); state 见文件头; 抛错 = 失败
async function runUpgrade(lockService, firmware, onProgress) {
  const prog = p => { try { if (onProgress) onProgress(p); } catch (e) {} TRACE.evt('info', 'DFU 进度 state=' + p.state + ' ' + (p.percent !== undefined ? p.percent + '%' : '')); };
  const mac = lockService.curMac;
  const kc = lockService.getKeychain(mac);
  if (!kc || !kc.skey) throw new Error('无钥匙串, 无法升级');
  // 1. cmd 22 enableDFUstate (锁重启进 bootloader; 连接会被锁主动断开)
  //    App 在 rc!=0 时硬失败; 这里对「指令已发但未确认」的场景软处理 — 若锁已处于 DFU 模式
  //    (广播 ZkDFU/MAC+1), 下一步扫描仍能命中, 与 App reCheck 路径语义一致; 扫描也失败时
  //    优先呈现 cmd 22 的原始错误 (真实原因), 而非扫描超时。
  let cmd22Err = null;
  prog({ state: 2, percent: 0 });
  lockService.log('info', '发送 cmd 22 (enableDFUstate) — 门锁即将重启进入升级模式');
  try {
    await lockService.enableDfu(0);
  } catch (e) {
    cmd22Err = e;
    lockService.log('warn', 'cmd 22 未确认 (' + e.message + ') — 将尝试直接搜索升级设备');
  }
  await new Promise(r => setTimeout(r, 1500)); // 等 bootloader 起播
  try { lockService.disconnect(); } catch (e) {}
  // 2. 扫描 DFU 设备
  prog({ state: 0, percent: 0 });
  let hit;
  try {
    hit = await scanDfuDevice(mac, kc.pid || 0);
  } catch (e) {
    throw cmd22Err || e;
  }
  // 3. 连接 + 上传
  const conn = await NORDIC.connectDfu(hit.deviceId, lockService.logFn);
  const session = new NORDIC.DfuSession(conn, lockService.logFn);
  try {
    prog({ state: 1, percent: 0 });
    if (conn.mode === 'secure') await session.uploadSecure(firmware.binHex, firmware.datHex, prog);
    else await session.uploadLegacy(firmware.binHex, firmware.datHex, prog);
    prog({ state: 6, percent: 100 });
  } catch (e) {
    prog({ state: 7, percent: 0 });
    session.close();
    throw e;
  }
  return { mode: conn.mode };
}

module.exports = { parseDfuZip, versionFromFileName, versionLt, nextMac, scanDfuDevice, runUpgrade, ZIP, NORDIC };
