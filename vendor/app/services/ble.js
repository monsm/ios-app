// BLE 传输层 (移植探测版 + Connection 化) — 扫描/连接/20B分片写/粘包重组/广播解析
// UUID 依据: Java 插件 BleLockConnector (SVC_MAIN/FE90 双轨) + 记忆库 02-帧协议
const proto = require('../utils/kernel/protocol.js');
const TRACE = require('../utils/trace.js');
const LABELS = require('../utils/kernel/labels.js'); // BLE_ERROR_CODES (main.js bleCodeMsg 词本)

const SVC_MAIN = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
const WRITE_CHAR = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
const NOTIFY_CHAR = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';
const SVC_GW = '0000FE90-0000-1000-8000-00805F9B34FB';

function open(cb) {
  wx.openBluetoothAdapter({
    mode: 'central',
    success: res => cb(null, res),
    fail: err => cb(err)   // 10001(蓝牙未开)等全部按失败处理 → 页面给中文引导
  });
}
function close(cb) { wx.closeBluetoothAdapter({ complete: () => cb && cb() }); }
function onState(cb) { wx.onBluetoothAdapterStateChange(r => cb && cb(r)); }

function onDeviceFound(cb) {
  wx.onBluetoothDeviceFound(res => {
    const list = (res.devices || []).map(d => {
      let adv = null;
      if (d.advertisData && d.advertisData.byteLength) {
        adv = parseAdv(proto.bytesToHex(new Uint8Array(d.advertisData)));
      }
      const svcs = (d.advertisServiceUUIDs || []).map(s => s.toUpperCase());
      const svcHit = svcs.indexOf(SVC_MAIN) >= 0 || svcs.indexOf('FE90') >= 0;
      const nameHit = /ZK|KX|JZ|JINGZAO|ZELKOVA|LOCK|SMART/i.test(d.localName || '');
      return {
        deviceId: d.deviceId, name: d.localName || '(未命名)', rssi: d.RSSI,
        adv, svcHit, nameHit,
        score: (svcHit ? 2 : 0) + (nameHit ? 2 : 0) + (adv ? 4 : 0)
      };
    });
    cb(list);
  });
}
// V80 (F5): 官方两扫描器 (BleScan.doScan / BleDfu.doScan) 均 10s 自动停扫 — 对齐。
//   opts.onStop 在自动停扫后回调 (页面收尾 UI); opts.autoStopMs 供测试注入短窗口。
let scanTimer = null;
function scheduleScanStop(onStop, ms) {
  clearScanTimer();
  scanTimer = setTimeout(() => {
    scanTimer = null;
    wx.stopBluetoothDevicesDiscovery({ complete: () => onStop && onStop() });
  }, ms);
}
function clearScanTimer() {
  if (scanTimer) { clearTimeout(scanTimer); scanTimer = null; }
}
function startScan(cb, opts) {
  cb = cb || (() => {});
  opts = opts || {};
  wx.startBluetoothDevicesDiscovery({
    allowDuplicatesKey: false, interval: 500,
    success: () => { cb(null); scheduleScanStop(opts.onStop, opts.autoStopMs || 10000); },
    fail: cb
  });
}
function stopScan(cb) { clearScanTimer(); wx.stopBluetoothDevicesDiscovery({ complete: () => cb && cb() }); }

// 广播厂商段解析 — V80 (F1) 依全新反编译 BLEAdData.java 修正为厂商布局:
//   公司段内绝对偏移 = [0..1]=98ed、[2]=frameCtrl、[3]=厂商未读字节、[4..5]=pid u16LE、[6..11]=MAC 6B
//   识别门禁与 Java 一致: 段以 98ed 开头且 fc >= 0x0C (含 pid bit2 + mac bit3 双位) 才算 ZK 锁帧
//   (旧实现读 pid@[3..4]/mac@[5..10] 各早 1 字节且无门禁 — 见 output/memory 05 V78/U7)
//   macRaw=按接收序 hex (直接供 EKey 包络, App 端 getBytes 会反转字节对)
function parseAdv(advHex) {
  const i = (advHex || '').indexOf('98ed');
  if (i < 0 || i + 24 > advHex.length) return null; // 需要 98ed+10B=24 hex 字符
  const seg = advHex.substr(i + 4); // seg[0]=fc seg[1]=b3 seg[2..3]=pid seg[4..9]=MAC
  const frameCtrl = parseInt(seg.substr(0, 2), 16);
  if ((frameCtrl & 0x0c) !== 0x0c) return null; // Java 门禁 fc>=0x0C ⟺ containPid(bit2)+containMac(bit3)
  const pid = parseInt(seg.substr(4, 2), 16) | (parseInt(seg.substr(6, 2), 16) << 8);
  const macRaw = seg.substr(8, 12) || null;
  return {
    frameCtrl, pid,
    macRaw,
    mac: macRaw, // 2026-09-03 勘误: 页面此前读 adv.mac — 真机广播解析从未在页面给出该字段 → 配网链拿到空 MAC。别名补齐 (真机广播段已按厂商布局读出 macRaw)
    macDisplay: macRaw ? proto.reversePairs(macRaw).replace(/(..)(?=.)/g, '$1:').toUpperCase() : null,
    resetStatus: (frameCtrl & 0x01) ? 1 : 0,
    containNotify: (frameCtrl & 0x02) ? 1 : 0,
    containPid: (frameCtrl & 0x04) ? 1 : 0,
    containMac: (frameCtrl & 0x08) ? 1 : 0,
    dfuState: (frameCtrl & 0x20) ? 1 : 0
  };
}

// 蓝牙适配器前置检查 (幂等): 未 open 直接 createBLEConnection 在 iOS 会 fail:not init
function ensureOpen() {
  return new Promise(resolve => {
    wx.openBluetoothAdapter({
      mode: 'central',
      success: () => resolve(),
      fail: err => {
        // 10001 = 蓝牙已关闭/不可用 (重复调用也返回该码) → 交页面引导用户开蓝牙
        resolve(err);
      }
    });
  });
}
function btErrMsg(err) {
  const c = err && err.errCode;
  const m = err && err.errMsg ? String(err.errMsg) : '';
  if (c === 10001 || /not available|not enabled|adapter/.test(m)) return '蓝牙未开启: 请到系统设置打开蓝牙后重试';
  if (c === 10000 || /not init/.test(m)) return '蓝牙未初始化, 请稍后重试';
  if (c === 10008 || /permission/.test(m)) return '未获得蓝牙权限: 请在系统设置中允许本小程序使用蓝牙';
  if (/not found/.test(m)) return '未找到该设备 (请靠近门锁并确认蓝牙已开)';
  if (/timeout/.test(m)) return '连接超时, 请靠近门锁重试';
  return (m.replace(/^.*?:fail:/, '') || '连接失败') + ' (请确认蓝牙已开启)';
}

// ===== BLE 错误码映射 (2026-09-09, gap#23) =====
// 传输层抛错统一携带 bleCode — 取自 main.js bleCodeMsg 词表 (labels.BLE_ERROR_CODES,
// 与 App 原生同一套编号: 1001 未发现门锁 / 2003 连接超时 / 5001 解析失败 / 6001 写确认超时 /
// 6004 蓝牙底层失败 / 6005 未成功发送)。页面/服务层展示 e.message 或 bleErrorMessage(e) 均可。
function withCode(err, code) {
  const e = err instanceof Error ? err : new Error(String(err));
  if (code && !e.bleCode) e.bleCode = code;
  return e;
}
// 未显式归类 (如 wx 原生回调) 时按文案兜底归类
function classifyError(err) {
  if (err && err.bleCode) return err.bleCode;
  const t = String((err && (err.message || err.errMsg)) || '');
  if (/扫描超时|未找到 MAC|未发现门锁|not found/i.test(t)) return 1001;
  if (/写入超时|未等到/.test(t)) return 6001;
  if (/未发现.*服务|未找到可写|解析|服务/i.test(t)) return 5001;
  if (/超时|timeout/i.test(t)) return 2003;
  if (/写入失败|发送失败|fail/i.test(t)) return 6005;
  return 0;
}
function bleErrorMessage(err) {
  const c = classifyError(err);
  return (c && LABELS.BLE_ERROR_CODES[c]) || (err && err.message) || '蓝牙操作失败';
}
// 扫描解析 BLE 设备号 (P0): 已知锁 MAC → 返回 WeChat deviceId (配对后重连用)
// 匹配兼容广播两种字节序 (macRaw 与反序 display); 8s 超时; 命中即停扫并注销监听
function resolveDeviceId(macHex, log) {
  const target = String(macHex || '').replace(/:/g, '').toLowerCase();
  if (!/^[0-9a-f]{12}$/.test(target)) return Promise.reject(new Error('MAC 格式异常: ' + macHex));
  return new Promise((resolve, reject) => {
    let done = false;
    const finish = (err, deviceId) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      try { wx.stopBluetoothDevicesDiscovery({ fail: () => {} }); } catch (e) {}
      try { wx.offBluetoothDeviceFound(handler); } catch (e) {}
      err ? reject(err) : resolve(deviceId);
    };
    const timer = setTimeout(() => finish(withCode(new Error('扫描超时: 8s 内未找到 MAC ' + macHex), 1001)), 8000);
    const handler = res => {
      if (done) return;
      for (const d of (res.devices || [])) {
        let adv = null;
        try {
          if (d.advertisData && d.advertisData.byteLength) {
            adv = parseAdv(proto.bytesToHex(new Uint8Array(d.advertisData)));
          }
        } catch (e) {}
        if (!adv || !adv.macRaw) continue;
        const candRaw = adv.macRaw.toLowerCase();
        const candDisp = adv.macDisplay ? adv.macDisplay.replace(/:/g, '').toLowerCase() : proto.reversePairs(candRaw);
        if (candRaw === target || candDisp === target) {
          log && log('info', '扫描命中 MAC=' + target + ' → deviceId=' + d.deviceId);
          finish(null, d.deviceId);
          return;
        }
      }
    };
    // 先确保适配器可用, 再起扫监听
    ensureOpen().then(err => {
      if (done) return;
      if (err) { finish(new Error(btErrMsg(err))); return; }
      try { wx.onBluetoothDeviceFound(handler); } catch (e) { finish(new Error('无法注册设备发现监听')); return; }
      wx.startBluetoothDevicesDiscovery({
        allowDuplicatesKey: false, interval: 500,
        success: () => log && log('info', '扫描解析 deviceId 启动 (target ' + target + ')'),
        fail: e => finish(new Error('启动扫描失败: ' + ((e && e.errMsg) || '未知')))
      });
    });
  });
}

// 连接 → {deviceId, serviceId, writeChar, notifyChar, write, onFrame, close}
function connect(deviceId, log) {
  return new Promise((resolve, reject) => {
    ensureOpen().then(openErr => {
      if (openErr) { reject(new Error(btErrMsg(openErr))); return; }
      wx.createBLEConnection({
        deviceId, timeout: 15000,
        success: () => {
          if (wx.setBLEMTU) wx.setBLEMTU({ deviceId, mtu: 185, fail: () => {} });
          // G6: discover/notify 失败时先断开已建立的 BLE 连接再 reject — 否则连接泄漏
          discover(deviceId, log).then(resolve).catch(err => {
            wx.closeBLEConnection({ deviceId, fail: () => {} });
            reject(err);
          });
        },
        fail: err => reject(withCode(new Error(btErrMsg(err)), /timeout|超时/.test(String((err && err.errMsg) || '')) ? 2003 : 0))
      });
    });
  });
}
function discover(deviceId, log) {
  return new Promise((resolve, reject) => {
    wx.getBLEDeviceServices({
      deviceId,
      success: res => {
        const svcs = (res.services || []).map(s => s.uuid.toUpperCase());
        const useMain = svcs.indexOf(SVC_MAIN) >= 0;
        const useGw = !useMain && svcs.indexOf(SVC_GW.replace(/^0000/, '')) >= 0;
        const svc = useMain ? SVC_MAIN : (useGw ? SVC_GW : null);
        if (!svc) {
          reject(withCode(new Error('未发现 6E400001/FE90 服务, 已知=' + svcs.join(',')), 1001));
          return;
        }
        const wrUuid = (useMain ? WRITE_CHAR : '0000FE92-0000-1000-8000-00805F9B34FB').toUpperCase();
        const ntUuid = (useMain ? NOTIFY_CHAR : '0000FE91-0000-1000-8000-00805F9B34FB').toUpperCase();
        wx.getBLEDeviceCharacteristics({
          deviceId, serviceId: svc,
          success: r2 => {
            const wr = [], nt = [];
            for (const c of r2.characteristics || []) {
              const u = c.uuid.toUpperCase();
              if (u === wrUuid && (c.properties.write || c.properties.writeNoResponse)) wr.push(u);
              if (u === ntUuid && (c.properties.notify || c.properties.indicate)) nt.push(u);
            }
            if (!wr.length) {
              reject(withCode(new Error('未找到可写特征, 已知=' + (r2.characteristics || []).map(c => c.uuid.toUpperCase()).join(',')), 5001));
              return;
            }
            enableNotify(deviceId, svc, nt[0] || ntUuid, log)
              .then(() => finishConnection(deviceId, svc, wr[0], nt[0] || ntUuid, log))
              .then(resolve).catch(reject);
          },
          fail: reject
        });
      },
      fail: reject
    });
  });
}
function enableNotify(deviceId, serviceId, charUuid, log) {
  return new Promise((resolve, reject) => {
    wx.notifyBLECharacteristicValueChange({
      deviceId, serviceId, characteristicId: charUuid, state: true,
      success: () => {
        log && log('info', 'notify 已开启: ' + charUuid);
        resolve();
      },
      fail: err => reject(withCode(err, 6004))
    });
  });
}
// 20B 上限分片发送 (固件解析器支持分片重组)
// wxWrite 可注入 (单测用): 默认 wx.writeBLECharacteristicValue
function writeFrame(conn, hex, log, wxWrite) {
  const bytes = proto.hexToBytes(hex);
  const chunk = 20;
  const total = Math.ceil(bytes.length / chunk);
  const writer = wxWrite || (o => wx.writeBLECharacteristicValue(o));
  return new Promise((resolve, reject) => {
    let i = 0;
    const t0 = Date.now();
    const next = () => {
      // G12: 总超时兜底 (正常 ≤180ms; 设备静默时避免挂死)
      if (Date.now() - t0 > 3000) { reject(withCode(new Error('写入超时'), 6001)); return; }
      if (i >= bytes.length) return resolve();
      const part = bytes.slice(i, i + chunk);
      i += chunk;
      TRACE.bleTxChunk(i, total, proto.bytesToHex(part), 'chunk=20B'); // 逐片原始 hex
      // 2026-09-03 勘误: Uint8Array.slice 是共享底层 ArrayBuffer 的视图 — 曾直接传 part.buffer
      // (= 整帧!), 分片写实际整帧重复 N 次 / 超 MTU 直接失败。必须拷贝出恰好 20B 的独立 ArrayBuffer。
      const buf = new ArrayBuffer(part.byteLength);
      new Uint8Array(buf).set(part);
      writer({
        deviceId: conn.deviceId, serviceId: conn.serviceId, characteristicId: conn.writeChar,
        value: buf,
        success: () => setTimeout(next, 30),
        fail: err => { TRACE.evt('warn', 'BLE 写分片 ' + i + '/' + total + ' 失败: ' + (err && (err.errMsg || err.message))); reject(withCode(err, 6005)); }
      });
    };
    next();
  });
}
// 粘包+多帧组装 (三态帧型兼容: 版本字节 0x01=7B头/0x10=8B头/0x00=10B头)
function makeAssembler() {
  let buf = '';
  return {
    push(chunkHex) {
      buf += chunkHex;
      const frames = [];
      for (;;) {
        const idx = buf.indexOf('87');
        if (idx < 0) { buf = ''; break; }
        if (idx > 0) buf = buf.slice(idx);
        if (buf.length < 14) break;
        const len = proto.readU16LE(buf, 2);
        const vb = parseInt(buf.substr(2, 2), 16);
        // V80 (F4): 8B 帧设首选 (Java 恒按 8B 头消费), 7B/10B 仅长度守卫下的失败后备;
        //   vb=0x01 帧若实为 8B 不再被 7B 试切提前截断 (旧实现会吃帧失步)。
        const prefs = vb === 0x01
          ? [(8 + len) * 2, (7 + len) * 2, (10 + len) * 2]
          : [(8 + len) * 2, (10 + len) * 2, (7 + len) * 2];
        let cut = 0;
        for (const t2 of prefs) {
          if (buf.length < t2) continue;
          const parsed = proto.parseResponse(buf.slice(0, t2));
          if (parsed.ok) { cut = t2; frames.push(parsed); break; }
        }
        if (!cut) break;
        buf = buf.slice(cut);
      }
      return frames;
    },
    pending() { return buf.length / 2; }, // 未消费缓冲字节数 (诊断粘包/断帧)
    reset() { buf = ''; }
  };
}
// 全局 notify 分发: 模块级一次性注册 (G7 — 否则每次 connect 重复注册监听器累积)
let gConn = null;
let notifyAttached = false;
function attachNotify() {
  if (notifyAttached) return;
  notifyAttached = true;
  wx.onBLECharacteristicValueChange(res => {
    const c = gConn;
    if (!c || res.deviceId !== c.deviceId) return;
    const hex = proto.bytesToHex(new Uint8Array(res.value));
    TRACE.bleRxChunk(hex); // notify 原始载荷 (重组前逐片)
    let frames;
    try {
      frames = c.asm.push(hex);
    } catch (e) {
      frames = [];
      TRACE.evt('warn', 'BLE 粘包重组异常: ' + (e && e.message));
    }
    if (frames && frames.length) {
      TRACE.evt('info', 'BLE 重组出 ' + frames.length + ' 帧 (此 notify 边界, cmd=' +
        frames.map(f => ('0' + f.cmd.toString(16)).slice(-2)).join('/') + ', 缓冲余 ' + c.asm.pending() + 'B)');
    }
    for (const f of frames) {
      for (const h of c.handlers.slice()) h(f);
    }
  });
}
function finishConnection(deviceId, serviceId, writeChar, notifyChar, log) {
  const conn = {
    deviceId, serviceId, writeChar, notifyChar,
    handlers: [],
    asm: makeAssembler(),
    write: (hex, l) => writeFrame(conn, hex, l || log),
    onFrame(cb) { conn.handlers.push(cb); },
    close() {
      if (gConn === conn) gConn = null;
      wx.closeBLEConnection({ deviceId, fail: () => {} });
    }
  };
  if (gConn) { try { wx.closeBLEConnection({ deviceId: gConn.deviceId, fail: () => {} }); } catch (e) {} }
  gConn = conn;
  attachNotify();
  log && log('info', '连接就绪: ' + deviceId);
  return conn;
}

module.exports = {
  SVC_MAIN, WRITE_CHAR, NOTIFY_CHAR, SVC_GW,
  open, close, onState, onDeviceFound, startScan, stopScan,
  connect, resolveDeviceId, writeFrame, makeAssembler, parseAdv,
  ensureOpen, btErrMsg,
  withCode, classifyError, bleErrorMessage // 错误码映射 (gap#23)
};
