// 智能网关服务 (pid 12193/12209/12194, FE90 服务) — App 网关六页的离线 1:1 移植
//   * 配网链 (App gwreset 页): 扫描 (resetStatus==1 && pid==网关族) → 连接 → cmd 38 读状态
//     → cmd 31 写 WiFi (SSID/密码 UTF8 hex, auth=8, enc=0) → cmd 35 重启 → 完成。
//     App 中间的 checkDeviceBinding/addGateway(cmd 32 IoT) 是云端步骤 — 厂商云已停服, 跳过。
//   * 状态 (App gwstate 页离线等价): cmd 38 → wifimac/romVer/eCtrlVer/ssid/wifiIP/netState。
//   * 重启: cmd 35; 设备名: cmd 30。
//   * 帧面: 87 帧明文 KLV, needToken=false (与 App Io/ko/Do/Bo/Lo 一致); FE90/FE92/FE91 由
//     services/ble.js discover 的 FE90 回退路径处理。
const BLE = require('./ble.js');
const P = require('../utils/kernel/protocol.js');
const C = require('../utils/kernel/cmds.js');
const ST = require('../utils/store.js');
const TRACE = require('../utils/trace.js');

const GW_PIDS = [12193, 12209, 12194]; // GW / GW_commercial / GW2_commercial (App Nn)
const GW_LIST = 'kf_gateways'; // {mac: gw} — 网关台账

// ---------- 台账 ----------
function listGateways() {
  const m = ST.get(GW_LIST, {}) || {};
  return Object.keys(m).map(k => m[k]).sort((a, b) => (a.boundAt || '').localeCompare(b.boundAt || ''));
}
function getGateway(mac) {
  const m = ST.get(GW_LIST, {}) || {};
  return m[String(mac || '').replace(/:/g, '').toLowerCase()] || null;
}
function saveGateway(g) {
  if (!g || !g.mac) throw new Error('网关缺少 MAC');
  const k = String(g.mac).replace(/:/g, '').toLowerCase();
  const m = ST.get(GW_LIST, {}) || {};
  m[k] = Object.assign({}, m[k] || {}, g, { mac: k });
  ST.set(GW_LIST, m);
  return m[k];
}
function removeGateway(mac) {
  const m = ST.get(GW_LIST, {}) || {};
  delete m[String(mac || '').replace(/:/g, '').toLowerCase()];
  ST.set(GW_LIST, m);
}

// ---------- 扫描 (App gwreset.scanDevice: resetStatus==1 && pid==网关族; 15s 超时文案一致) ----------
function scanGateway(opts) {
  const o = Object.assign({ timeoutMs: 15000, requireReset: true }, opts);
  const wantMac = o.macFilter ? String(o.macFilter).replace(/:/g, '').toLowerCase() : '';
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
    const timer = setTimeout(() => finish(new Error('搜索超时，是否继续搜索？若长时间搜索不到，请尝试重启手机蓝牙')), o.timeoutMs);
    const handler = res => {
      if (done) return;
      for (const d of (res.devices || [])) {
        if (!d.advertisData || !d.advertisData.byteLength) continue;
        let adv = null;
        try { adv = BLE.parseAdv(P.bytesToHex(new Uint8Array(d.advertisData))); } catch (e) { continue; }
        if (!adv || !adv.macRaw) continue;
        if (GW_PIDS.indexOf(adv.pid) < 0) continue;
        if (o.requireReset && !adv.resetStatus) continue;
        if (wantMac && adv.macRaw.toLowerCase() !== wantMac) continue;
        done = true;
        const hit = { deviceId: d.deviceId, mac: adv.macRaw.toLowerCase(), name: d.localName || '(网关)', rssi: d.RSSI, pid: adv.pid };
        TRACE.evt('info', '发现网关: mac=' + hit.mac + ' pid=' + hit.pid);
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

// ---------- 连接 + 命令 ----------
class GatewayLink {
  constructor(log) {
    this.logFn = log || function () {};
    this.conn = null;
    this.gwMac = null;
    this._waiter = null;
  }
  log(level, msg) {
    try { this.logFn(level, msg); } catch (e) {}
    TRACE.evt(level, msg);
  }
  async ensureConnected(gwMac) {
    const m = String(gwMac || '').replace(/:/g, '').toLowerCase();
    if (this.conn && this.gwMac === m) return this.conn;
    if (this.conn) this.disconnect();
    const g = getGateway(m);
    let deviceId = g && g.bleId;
    if (deviceId) {
      try {
        await this._connect(deviceId, m);
        return this.conn;
      } catch (e) {
        this.log('warn', '缓存 deviceId 直连失败 (' + e.message + '), 回退扫描');
      }
    }
    const scan = await scanGateway({ timeoutMs: 10000, requireReset: false, macFilter: m || '' });
    deviceId = scan.deviceId;
    if (g) saveGateway(Object.assign({}, g, { bleId: deviceId }));
    await this._connect(deviceId, scan.mac);
    return this.conn;
  }
  async _connect(deviceId, gwMac) {
    const conn = await BLE.connect(deviceId, this.logFn);
    this.conn = conn;
    this.gwMac = String(gwMac || '').toLowerCase();
    conn.onFrame(f => {
      const w = this._waiter;
      if (w && f.cmd === w.cmd) {
        this._waiter = null;
        clearTimeout(w.timer);
        w.resolve(f);
      }
    });
    this.log('info', '网关连接就绪: ' + deviceId);
  }
  disconnect() {
    if (this._waiter) { const w = this._waiter; this._waiter = null; clearTimeout(w.timer); w.reject(new Error('连接已断开')); }
    try { if (this.conn) this.conn.close(); } catch (e) {}
    this.conn = null;
  }
  async request(cmdObj, timeoutMs) {
    if (!this.conn) throw new Error('未连接网关');
    const cmd = cmdObj.cmd;
    const p = new Promise((resolve, reject) => {
      if (this._waiter) { reject(new Error('已有命令在等待响应')); return; }
      const timer = setTimeout(() => {
        if (this._waiter && this._waiter.cmd === cmd) {
          this._waiter = null;
          reject(new Error('超时: 未收到网关响应 (请靠近网关重试)'));
        }
      }, timeoutMs || 8000);
      this._waiter = { cmd, resolve, reject, timer };
    });
    TRACE.tx(cmdObj.name, cmd, cmdObj.hex, '网关 ' + this.gwMac);
    // 写入失败即清 waiter (lock.js 同款 G 修复): 否则重试轮被「已有命令在等待响应」挡死,
    // 且挂起的 Promise 稍后超时 reject 会成为无人处理的游离拒绝
    try {
      await this.conn.write(cmdObj.hex);
    } catch (e) {
      if (this._waiter && this._waiter.cmd === cmd) {
        clearTimeout(this._waiter.timer);
        this._waiter = null;
      }
      throw e;
    }
    const frame = await p;
    TRACE.rx(cmdObj.name, cmd, frame.raw, frame.klvs || [], { header: frame.header });
    return frame;
  }
  // 网关应答码 (Co/So/Mo): KLV#01 = errCode; 响应缺 KLV#01 时 App 默认 0 (成功) — 同语义
  errCodeOf(frame) {
    const k = (frame.klvs || []).find(x => x.key === 0x01);
    if (!k) return 0;
    const hex = k.val || '00';
    let v = 0;
    for (let i = 0; i < hex.length; i += 2) v = v * 256 + parseInt(hex.substr(i, 2), 16);
    return v;
  }
}

// ---------- 38 状态响应解析 (App Oo.parseKlv; 01/04/05 = 双重反转即原始字节序 → ASCII 解码) ----------
function hexToAscii(hex) {
  let s = '';
  for (let i = 0; i + 1 < hex.length; i += 2) {
    const c = parseInt(hex.substr(i, 2), 16);
    if (c >= 0x20 && c < 0x7f) s += String.fromCharCode(c);
    else return hex; // 不可打印 → 原样返回 hex (不猜)
  }
  return s;
}
function parseGWStatus(klvs) {
  const s = { rc: -1, wifimac: '', romVer: '', eCtrlVer: '', ssid: '', wifiIP: '', netState: -1 };
  for (const k of klvs || []) {
    const val = k.val || '';
    switch (k.key) {
      case 0x01: // wifimac = 原始字节序 hex (App 双重反转还原原值) — 不做 ASCII 解码:
        // ASCII 段内的 MAC (如 0x30-0x39 字节) 会被 hexToAscii 误伤, 展示时再格式化
        s.wifimac = val;
        break;
      case 0x02: { // romVer: 3B 反转点分 (App: reversed → parseInt(s).parseInt(o).parseInt(u))
        const o = P.reversePairs(val);
        if (o.length === 6) s.romVer = parseInt(o.substr(4, 2), 16) + '.' + parseInt(o.substr(2, 2), 16) + '.' + parseInt(o.substr(0, 2), 16);
        else s.romVer = hexToAscii(val);
        break;
      }
      case 0x03: { // eCtrlVer: setKlvs 路径 = ASCII 解码; 3B 时与 romVer 同式
        const o = P.reversePairs(val);
        if (o.length === 6) s.eCtrlVer = parseInt(o.substr(4, 2), 16) + '.' + parseInt(o.substr(2, 2), 16) + '.' + parseInt(o.substr(0, 2), 16);
        else s.eCtrlVer = hexToAscii(val);
        break;
      }
      case 0x04: s.ssid = hexToAscii(val); break;
      case 0x05: s.wifiIP = hexToAscii(val); break;
      case 0x06: s.netState = parseInt(val, 16) || 0; break;
    }
  }
  return s;
}
function macDisplay(macHex) {
  const h = String(macHex || '').replace(/:/g, '').toLowerCase();
  return h.replace(/(..)(?=.)/g, '$1:').toUpperCase();
}

module.exports = {
  GW_PIDS, GW_LIST,
  listGateways, getGateway, saveGateway, removeGateway,
  scanGateway, GatewayLink, parseGWStatus, macDisplay, hexToAscii,
  cmds: { status: C.cmd38GWStatus, setWifi: C.cmd31GWSetWifi, setIot: C.cmd32GWSetIot, reboot: C.cmd35GWReboot, deviceName: C.cmd30GWDeviceName }
};
