// 蓝牙钥匙串服务 (ZKBBV1 pid=16289 硬件狗) — App addkeychain 页的离线 1:1 移植
//   * 扫描: 广播厂商段 pid==16289 命中即停 (App scanKC 15s 超时文案一致)
//   * 命令面 (87 帧明文 KLV, needToken=false, 与 App Eu/Ru/Gu 类一致):
//       41 WRITEEKEY   写钥匙: KLV#01=锁MAC(6B反转) #02=type=1 #03=pid(2B LE) #04=ekey 密文
//       44 GETEKEYINFO 查钥匙: KLV#01=锁MAC(6B反转) 或空(全部) → 响应 KLV#04 = MAC 列表 (每台 6B)
//       43 GETSTATUS   查状态: KLV#01=各锁 MAC 6B 反转拼接 → 响应解析见 parseKCStatus
//   * rc 一律在响应 KLV#03 (App Ku.getResultCode); rc=3 → 命令不在有效期 (锁钟未同步)
//   * ekey 生成 = App generateEKey: AES(skey)($t 包络 cmd=04+pin), TrackId 随机, 永久窗口 (cmds.buildEkeyShare)
//   * 连接复用 services/ble.js (NUS 优先, FE90 回退 — App 同一 BleLockConnector 通道);
//     钥匙串与门锁共享单连接 (连接钥匙串会顶掉门锁连接, 后续门锁操作自动重连)
const BLE = require('./ble.js');
const P = require('../utils/kernel/protocol.js');
const C = require('../utils/kernel/cmds.js');
const ST = require('../utils/store.js');
const TRACE = require('../utils/trace.js');

const PID_ZKBBV1 = 16289; // App Nn.ZKBBV1
const KC_DONGLES = 'kf_keychain_dongles'; // {mac: dongle} — 钥匙串台账 (schema.js 静态键)

// ---------- 台账 ----------
function listDongles() {
  const m = ST.get(KC_DONGLES, {}) || {};
  return Object.keys(m).map(k => m[k]).sort((a, b) => (a.boundAt || '').localeCompare(b.boundAt || ''));
}
function getDongle(mac) {
  const m = ST.get(KC_DONGLES, {}) || {};
  return m[String(mac || '').replace(/:/g, '').toLowerCase()] || null;
}
function saveDongle(d) {
  if (!d || !d.mac) throw new Error('钥匙串缺少 MAC');
  const k = String(d.mac).replace(/:/g, '').toLowerCase();
  const m = ST.get(KC_DONGLES, {}) || {};
  m[k] = Object.assign({}, m[k] || {}, d, { mac: k });
  ST.set(KC_DONGLES, m);
  return m[k];
}
function removeDongle(mac) {
  const m = ST.get(KC_DONGLES, {}) || {};
  delete m[String(mac || '').replace(/:/g, '').toLowerCase()];
  ST.set(KC_DONGLES, m);
}

// ---------- 扫描 (App scanKC: 命中 pid==16289 即停; 15s 超时) ----------
// opts.macFilter: 指定 MAC 时只命中该设备 (重连场景); 缺省命中第一把钥匙串
function scanDongle(opts) {
  const o = Object.assign({ timeoutMs: 15000 }, opts);
  const wantMac = o.macFilter ? String(o.macFilter).replace(/:/g, '').toLowerCase() : '';
  return new Promise((resolve, reject) => {
    let done = false;
    let hit = null;
    const finish = (err, d) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      try { wx.offBluetoothDeviceFound(handler); } catch (e) {}
      try { wx.stopBluetoothDevicesDiscovery({ fail: () => {} }); } catch (e) {}
      err ? reject(err) : resolve(d);
    };
    const timer = setTimeout(() => {
      if (hit) finish(null, hit); // 超时前已命中 (容错兜底)
      else finish(new Error('搜索设备超时'));
    }, o.timeoutMs);
    const handler = res => {
      if (done) return;
      for (const d of (res.devices || [])) {
        if (!d.advertisData || !d.advertisData.byteLength) continue;
        let adv = null;
        try { adv = BLE.parseAdv(P.bytesToHex(new Uint8Array(d.advertisData))); } catch (e) { continue; }
        if (!adv || adv.pid !== PID_ZKBBV1 || !adv.macRaw) continue;
        if (wantMac && adv.macRaw.toLowerCase() !== wantMac) continue;
        hit = { deviceId: d.deviceId, mac: adv.macRaw.toLowerCase(), name: d.localName || '(钥匙串)', rssi: d.RSSI, pid: adv.pid };
        TRACE.evt('info', '发现钥匙串: mac=' + hit.mac + ' name=' + hit.name);
        clearTimeout(timer); // 命中即停 (App stopScan + 清超时)
        done = true;
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

// ---------- 连接 + 命令执行 (单请求串行; 响应按 cmd 匹配) ----------
class KeychainLink {
  constructor(log) {
    this.logFn = log || function () {};
    this.conn = null;
    this.dongleMac = null;
    this._waiter = null;
  }
  log(level, msg) {
    try { this.logFn(level, msg); } catch (e) {}
    TRACE.evt(level, msg);
  }
  async ensureConnected(dongleMac) {
    const m = String(dongleMac || '').replace(/:/g, '').toLowerCase();
    if (!m) throw new Error('未指定钥匙串');
    if (this.conn && this.dongleMac === m) return this.conn;
    if (this.conn) this.disconnect();
    const d = getDongle(m);
    let deviceId = d && d.bleId;
    if (deviceId) {
      try {
        await this._connect(deviceId, m);
        return this.conn;
      } catch (e) {
        this.log('warn', '缓存 deviceId 直连失败 (' + e.message + '), 回退扫描');
      }
    }
    const scan = await scanDongle({ timeoutMs: 10000, macFilter: m });
    deviceId = scan.deviceId;
    if (d) saveDongle(Object.assign({}, d, { bleId: deviceId }));
    await this._connect(deviceId, scan.mac);
    return this.conn;
  }
  async _connect(deviceId, dongleMac) {
    const conn = await BLE.connect(deviceId, this.logFn);
    this.conn = conn;
    this.dongleMac = String(dongleMac).toLowerCase();
    conn.onFrame(f => {
      const w = this._waiter;
      if (w && f.cmd === w.cmd) {
        this._waiter = null;
        clearTimeout(w.timer);
        w.resolve(f);
      }
    });
    this.log('info', '钥匙串连接就绪: ' + deviceId + ' (mac=' + this.dongleMac + ')');
  }
  disconnect() {
    if (this._waiter) { const w = this._waiter; this._waiter = null; clearTimeout(w.timer); w.reject(new Error('连接已断开')); }
    try { if (this.conn) this.conn.close(); } catch (e) {}
    this.conn = null;
  }
  async request(cmdObj, timeoutMs) {
    if (!this.conn) throw new Error('未连接钥匙串');
    const cmd = cmdObj.cmd;
    const w = new Promise((resolve, reject) => {
      if (this._waiter) { reject(new Error('已有命令在等待响应')); return; }
      const timer = setTimeout(() => {
        if (this._waiter && this._waiter.cmd === cmd) {
          this._waiter = null;
          reject(new Error('超时: 未收到响应 (请靠近钥匙串重试)'));
        }
      }, timeoutMs || 8000);
      this._waiter = { cmd, resolve, reject, timer };
    });
    TRACE.tx(cmdObj.name, cmd, cmdObj.hex, '钥匙串 ' + this.dongleMac);
    // 写入失败即清 waiter (lock.js 同款 G 修复): 否则挂起 Promise 超时 reject 成为游离拒绝
    try {
      await this.conn.write(cmdObj.hex);
    } catch (e) {
      if (this._waiter && this._waiter.cmd === cmd) {
        clearTimeout(this._waiter.timer);
        this._waiter = null;
      }
      throw e;
    }
    const frame = await w;
    TRACE.rx(cmdObj.name, cmd, frame.raw, frame.klvs || [], { header: frame.header });
    return frame;
  }
  rcOf(frame) {
    const k = (frame.klvs || []).find(x => x.key === 0x03);
    if (!k) return -1; // 无 rc KLV (如 44/43 无状态位) — 调用层自行决定
    const hex = k.val || '00';
    let v = 0;
    for (let i = 0; i < hex.length; i += 2) v = v * 256 + parseInt(hex.substr(i, 2), 16);
    return v;
  }
}

// ---------- 43 状态响应解析 (App $u.parseKlv 字符级: 11/12/24/25 直读, 31/34/35 反转, 36 逐字节) ----------
function parseKCStatus(klvs) {
  const s = { power: -1, absPower: -1, ekeyCount: -1, ekeyAmount: -1, firmware: '', pid: 0, eCtrl: '', applyPids: [], rc: -1 };
  for (const k of klvs || []) {
    const val = k.val || '';
    switch (k.key) {
      case 0x03: s.rc = parseInt(val, 16) || 0; break;
      case 0x11: s.power = parseInt(val, 16) || 0; break; // 直读
      case 0x12: s.absPower = parseInt(P.reversePairs(val), 16) || 0; break; // 反转
      case 0x24: s.ekeyCount = parseInt(val, 16) || 0; break; // 直读 (App pininfo_macekey)
      case 0x25: s.ekeyAmount = parseInt(val, 16) || 0; break; // 直读 (容量)
      case 0x31: { // 固件 3B 反转 → p0.p1.p2 (与 status.js verFirmware 同式)
        const o = P.reversePairs(val);
        if (o.length === 6) s.firmware = parseInt(o.substr(4, 2), 16) + '.' + parseInt(o.substr(2, 2), 16) + '.' + parseInt(o.substr(0, 2), 16);
        break;
      }
      case 0x34: s.pid = parseInt(P.reversePairs(val), 16) || 0; break; // u32 LE
      case 0x35: { // eCtrl 3B 同固件式
        const o = P.reversePairs(val);
        if (o.length === 6) s.eCtrl = parseInt(o.substr(4, 2), 16) + '.' + parseInt(o.substr(2, 2), 16) + '.' + parseInt(o.substr(0, 2), 16);
        break;
      }
      case 0x36: { // 支持的 PID 列表: 逐字节直读 (App toNormalByteOrder(1B)=原值)
        if (val.length % 2 === 0) {
          for (let i = 0; i < val.length; i += 2) s.applyPids.push(parseInt(val.substr(i, 2), 16));
        }
        break;
      }
    }
  }
  return s;
}
// ---------- 44 响应: KLV#04 = MAC 列表 (每 6B 一台, 按接收序 hex; 展示用冒号大写) ----------
function parseEkeyMacs(klvs) {
  const out = [];
  const k = (klvs || []).find(x => x.key === 0x04);
  const v = (k && k.val) || '';
  for (let i = 0; i + 12 <= v.length; i += 12) out.push(v.substr(i, 12).toLowerCase());
  return out;
}
function macDisplay(macHex) {
  return P.reversePairs(macHex).replace(/(..)(?=.)/g, '$1:').toUpperCase();
}

module.exports = {
  PID_ZKBBV1, KC_DONGLES,
  listDongles, getDongle, saveDongle, removeDongle,
  scanDongle, KeychainLink, parseKCStatus, parseEkeyMacs, macDisplay,
  buildEkey: C.buildEkeyShare, cmds41: C.cmd41WriteEkey, cmds44: C.cmd44GetEkeyInfo, cmds43: C.cmd43KeychainStatus
};
