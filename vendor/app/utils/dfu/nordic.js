// Nordic DFU BLE 协议层 (Secure + Legacy 双模式) — APK 内嵌 Nordic 12.x Java 库 (SecureDfuImpl/
//   LegacyDfuImpl) 的逐操作移植, 操作码/字节序以 jadx 源码为准:
//   Secure  (服务 0000FE59-...): 控制点 8EC90001-..., 数据点 8EC90002-...
//     0x01 Create(type,size u32) / 0x02 PRN(u16) / 0x03 Checksum / 0x04 Execute / 0x06 Select(type)
//     响应 [0x60][req][status]; 校验和响应附 offset u32 + crc u32; Select 响应附 maxSize u32 + offset + crc
//   Legacy  (服务 00001530-1212-EFDE-1523-785FEABCD123): 控制点 1531, 数据点 1532
//     [0x01][mode] + packet(3×u32 尺寸) / [0x02][0] +dat +[0x02][1] / [0x08][prn u16] / [0x03] 流式
//     / [0x04] 校验 / [0x05] 激活复位; 响应 [0x10][req][status=1]
//   PRN 一律设 0 (逐写回调限速已足够慢, 免流控; 与库的默认路径等价但更简单可靠)
//   进度状态 0-7 与 App H5 映射一致: 0 连接 / 1 启动 / 2 切换DFU / 3 传输 / 4 校验 / 5 断开 / 6 完成 / 7 中止
const { crc32 } = require('./zip.js');

const UUID_SECURE = {
  service: '0000FE59-0000-1000-8000-00805F9B34FB',
  control: '8EC90001-F315-4F60-9FB8-838830DAEA50',
  packet: '8EC90002-F315-4F60-9FB8-838830DAEA50'
};
const UUID_LEGACY = {
  service: '00001530-1212-EFDE-1523-785FEABCD123',
  control: '00001531-1212-EFDE-1523-785FEABCD123',
  packet: '00001532-1212-EFDE-1523-785FEABCD123',
  version: '00001534-1212-EFDE-1523-785FEABCD123'
};

// ---- 字节工具 ----
function h2(v) { return ('00' + v.toString(16)).slice(-2); }
function u32leHex(v) {
  v = v >>> 0;
  return h2(v & 0xff) + h2((v >>> 8) & 0xff) + h2((v >>> 16) & 0xff) + h2((v >>> 24) & 0xff);
}
function u16leHex(v) { return h2(v & 0xff) + h2((v >>> 8) & 0xff); }
function bytesToHex(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += h2(bytes[i]);
  return s;
}

// ---- 原始 DFU 连接 (不经过 services/ble.js — DFU 设备无 NUS/FE90 服务) ----
function wxP(fn, rejectFirst) {
  return new Promise((resolve, reject) => {
    fn({ success: resolve, fail: rejectFirst ? r => reject(r) : reject });
  });
}
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function connectDfu(deviceId, log) {
  const lg = log || (() => {});
  try { await wxP(r => wx.createBLEConnection(Object.assign({ deviceId, timeout: 15000 }, r))); } catch (e) {
    throw new Error('连接 DFU 设备失败: ' + ((e && e.errMsg) || e.message || e));
  }
  try { if (wx.setBLEMTU) wx.setBLEMTU({ deviceId, mtu: 185, fail: () => {} }); } catch (e) {}
  const svRes = await wxP(r => wx.getBLEDeviceServices(Object.assign({ deviceId }, r)));
  const svcs = (svRes.services || []).map(s => s.uuid.toUpperCase());
  let mode = null, svcUuid = null;
  if (svcs.indexOf(UUID_SECURE.service) >= 0) { mode = 'secure'; svcUuid = UUID_SECURE.service; }
  else if (svcs.indexOf(UUID_LEGACY.service) >= 0) { mode = 'legacy'; svcUuid = UUID_LEGACY.service; }
  else {
    try { wx.closeBLEConnection({ deviceId, fail: () => {} }); } catch (e) {}
    throw new Error('未发现 DFU 服务 (FE59/1530), 已知: ' + svcs.join(','));
  }
  const chRes = await wxP(r => wx.getBLEDeviceCharacteristics(Object.assign({ deviceId, serviceId: svcUuid }, r)));
  let control = null, packet = null;
  for (const c of (chRes.characteristics || [])) {
    const u = c.uuid.toUpperCase();
    if (u === (mode === 'secure' ? UUID_SECURE.control : UUID_LEGACY.control)) control = c;
    if (u === (mode === 'secure' ? UUID_SECURE.packet : UUID_LEGACY.packet)) packet = c;
  }
  if (!control || !packet) {
    try { wx.closeBLEConnection({ deviceId, fail: () => {} }); } catch (e) {}
    throw new Error('DFU 服务特征缺失 (' + mode + ')');
  }
  await wxP(r => wx.notifyBLECharacteristicValueChange(Object.assign({
    deviceId, serviceId: svcUuid, characteristicId: control.uuid, state: true
  }, r)));
  lg('info', 'DFU 服务就绪 (' + mode + ') control=' + control.uuid);
  return {
    deviceId, mode,
    serviceId: svcUuid,
    controlUuid: control.uuid.toUpperCase(),
    packetUuid: packet.uuid.toUpperCase(),
    packetNoRsp: !!(packet.properties && (packet.properties.writeNoResponse || packet.properties.write))
  };
}

// ---- DFU 会话 ----
// op 状态码语义 (Nordic): 1 成功; 2 invalid; 3 NotSupported; 4 data size 超限; 5 CRC 错;
//   7 操作失败; 8 资源耗尽; 10 object 不匹配; 11 extended error (value[3] 为子码)
const STATUS_MSG = { 2: '无效操作', 3: '不支持的操作', 4: '数据大小超限', 5: 'CRC 校验失败', 7: '操作失败', 8: '资源不足', 10: '对象不匹配', 11: '扩展错误' };

class DfuSession {
  constructor(conn, log) {
    this.conn = conn;
    this.logFn = log || (() => {});
    this._handlers = [];
    this._buf = [];
    this._waiter = null;
    this._aborted = false;
    this._onNotify = res => {
      if (res.deviceId !== this.conn.deviceId) return;
      if (String(res.characteristicId).toUpperCase() !== this.conn.controlUuid) return;
      const hex = bytesToHex(new Uint8Array(res.value));
      if (this._waiter && this._waiter.cmd === null) {
        const w = this._waiter; this._waiter = null;
        clearTimeout(w.timer);
        w.resolve(hex);
        return;
      }
      this._buf.push(hex); // 串话帧缓存 (PRN 等)
    };
    try { wx.onBLECharacteristicValueChange(this._onNotify); } catch (e) {}
  }
  log(level, msg) {
    try { this.logFn(level, msg); } catch (e) {}
  }
  abort() { this._aborted = true; }
  close() {
    this._aborted = true;
    try { wx.offBLECharacteristicValueChange(this._onNotify); } catch (e) {}
    if (this._waiter) {
      const w = this._waiter;
      this._waiter = null;
      clearTimeout(w.timer);
      try { w.reject(new Error('连接已关闭')); } catch (e) {} // 挂起等待方不被悬挂
    }
    try { wx.closeBLEConnection({ deviceId: this.conn.deviceId, fail: () => {} }); } catch (e) {}
  }
  // 等待一个控制点通知 (hex)
  _waitResponse(timeoutMs, what) {
    return new Promise((resolve, reject) => {
      if (this._buf.length) { resolve(this._buf.shift()); return; }
      const timer = setTimeout(() => {
        if (this._waiter && this._waiter.cmd === null) {
          this._waiter = null;
          reject(new Error('超时: 未收到 ' + (what || 'DFU') + ' 响应'));
        }
      }, timeoutMs || 10000);
      this._waiter = { cmd: null, resolve, reject, timer };
    });
  }
  async _write(charUuid, hex, noRsp) {
    if (this._aborted) throw new Error('已中止');
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
    const buf = new ArrayBuffer(bytes.length);
    new Uint8Array(buf).set(bytes);
    await wxP(r => wx.writeBLECharacteristicValue(Object.assign({
      deviceId: this.conn.deviceId, serviceId: this.conn.serviceId,
      characteristicId: charUuid, value: buf
    }, r)));
  }
  // 读响应并按 req 匹配 (陈旧/串话响应跳过, 截止时间内循环等待)
  async _readMatching(req, what, timeoutMs) {
    const deadline = Date.now() + (timeoutMs || 10000);
    for (;;) {
      const remaining = deadline - Date.now();
      if (remaining <= 0) throw new Error('超时: 未收到 ' + (what || 'DFU') + ' 响应');
      const rHex = await this._waitResponse(remaining, what);
      const b = rHex.match(/.{2}/g) || [];
      const respOp = parseInt(b[0], 16), reqGot = parseInt(b[1], 16), status = parseInt(b[2], 16);
      const isResp = (this.conn.mode === 'secure' && respOp === 0x60) || (this.conn.mode === 'legacy' && respOp === 0x10);
      if (!isResp) { this.log('warn', '忽略非响应帧: ' + rHex); continue; }
      if (reqGot !== req) { this.log('warn', '忽略陈旧响应 (req=' + reqGot + ' ≠ ' + req + '): ' + rHex); continue; }
      if (status !== 1) {
        const extra = status === 11 && b[3] !== undefined ? (' (子码 ' + parseInt(b[3], 16) + ')') : '';
        throw new Error('DFU 操作失败 (' + (what || 'op') + '): ' + (STATUS_MSG[status] || ('status=' + status)) + extra);
      }
      return { status, payload: b.slice(3).join(''), hex: rHex };
    }
  }
  // 发控制点操作并等待响应
  async op(hex, what, timeoutMs) {
    await this._write(this.conn.controlUuid, hex, false);
    return this._readMatching(parseInt(hex.substr(0, 2), 16), what, timeoutMs);
  }
  // 数据点分块流式写 (20B; 每写等待 success 回调 + 短歇, 兼容 Android 队列约束)
  async stream(hex, onWritten) {
    const chunk = 20;
    const total = hex.length / 2;
    for (let i = 0; i < hex.length; i += chunk * 2) {
      if (this._aborted) throw new Error('已中止');
      const part = hex.substr(i, chunk * 2);
      await this._write(this.conn.packetUuid, part, true);
      if (onWritten && (i / 2 + part.length / 2) % 400 === 0) onWritten(Math.min(total, i / 2 + part.length / 2), total);
    }
    if (onWritten) onWritten(total, total);
  }
  // ---------- Secure DFU ----------
  async uploadSecure(binHex, datHex, onProgress) {
    // 1. PRN=0
    await this.op('02' + u16leHex(0), 'PRN');
    // 2. Select Command object → init packet 通道
    const selCmd = await this.op('06' + h2(1), 'Select command');
    const cmdMax = rdU32(selCmd.payload, 0, 'Select command');
    if (datHex.length / 2 > cmdMax) throw new Error('init packet 大小超限 (' + datHex.length / 2 + '>' + cmdMax + ')');
    // 3. Create Command + 写 dat + 校验和 + Execute
    this.log('info', '创建命令对象 (init packet ' + datHex.length / 2 + 'B)');
    await this.op('01' + h2(1) + u32leHex(datHex.length / 2), 'Create command');
    await this.stream(datHex, null);
    const chk1 = await this.op('03', 'Checksum');
    const off1 = rdU32(chk1.payload, 0, 'Checksum');
    const crc1 = rdU32(chk1.payload, 4, 'Checksum'); // payload = [offset u32][crc u32] — CRC 在字节 4
    if (off1 !== datHex.length / 2 || crc1 !== (crc32(hexToBytes(datHex)) >>> 0)) {
      throw new Error('init packet CRC 不匹配 (dev ' + crc1.toString(16) + ' vs local ' + crc32(hexToBytes(datHex)).toString(16) + ')');
    }
    this.log('info', 'init packet 校验通过, 执行');
    await this.op('04', 'Execute command');
    if (onProgress) onProgress({ state: 3, percent: 0 });
    // 4. Select Data object → 固件通道
    const selData = await this.op('06' + h2(2), 'Select data');
    const maxObj = rdU32(selData.payload, 0, 'Select data');
    const total = binHex.length / 2;
    let sent = 0;
    while (sent < total) {
      if (this._aborted) throw new Error('已中止');
      const objSize = Math.min(maxObj, total - sent);
      await this.op('01' + h2(2) + u32leHex(objSize), 'Create data');
      const objHex = binHex.substr(sent * 2, objSize * 2);
      await this.stream(objHex, (n, t) => {
        if (onProgress) onProgress({ state: 3, percent: Math.floor(((sent + n) / t) * 100) });
      });
      const chk = await this.op('03', 'Checksum');
      const off = rdU32(chk.payload, 0, 'Checksum');
      const crc = rdU32(chk.payload, 4, 'Checksum');
      if (off !== objSize || crc !== (crc32(hexToBytes(objHex)) >>> 0)) {
        throw new Error('数据对象 CRC 不匹配 (offset ' + off + '/' + objSize + ')');
      }
      await this.op('04', 'Execute data');
      sent += objSize;
      this.log('info', '数据对象执行完成 (' + sent + '/' + total + 'B)');
    }
  }
  // ---------- Legacy DFU ----------
  async uploadLegacy(binHex, datHex, onProgress) {
    // 1. Start DFU (mode 4=application) + 3×u32 尺寸 (sd, bl, app) → packet 点
    await this._write(this.conn.controlUuid, '01' + h2(4), false);
    await this._write(this.conn.packetUuid, u32leHex(0) + u32leHex(0) + u32leHex(binHex.length / 2), true);
    await this._resp(1, 'Start DFU');
    // 2. Init packet: [0x02][0x00] + dat + [0x02][0x01]
    await this.op('02' + h2(0), 'Init start');
    await this.stream(datHex, null);
    await this.op('02' + h2(1), 'Init complete');
    // 3. PRN=0 (库不发等待 — 同样处理)
    await this._write(this.conn.controlUuid, '08' + u16leHex(0), false);
    // 4. Receive firmware + 流式 (PRN=0 → 全部传完后才来响应)
    await this._write(this.conn.controlUuid, '03', false);
    if (onProgress) onProgress({ state: 3, percent: 0 });
    let lastPct = -1;
    const total = binHex.length / 2;
    const chunk = 20;
    for (let i = 0; i < binHex.length; i += chunk * 2) {
      if (this._aborted) throw new Error('已中止');
      await this._write(this.conn.packetUuid, binHex.substr(i, chunk * 2), true);
      const done = Math.min(total, i / 2 + chunk);
      const pct = Math.floor((done / total) * 100);
      if (pct !== lastPct && (pct % 5 === 0 || done === total)) {
        lastPct = pct;
        if (onProgress) onProgress({ state: 3, percent: pct });
      }
    }
    await this._resp(3, 'Firmware received', 60000); // 尾包后设备可能整段落盘 — 加长等待
    // 5. Validate + Activate & Reset
    if (onProgress) onProgress({ state: 4, percent: 100 });
    await this.op('04', 'Validate');
    if (onProgress) onProgress({ state: 5, percent: 100 });
    await this._write(this.conn.controlUuid, '05', false); // 无响应 — 设备重启
  }
  // Legacy: Start DFU 响应等待 (控制点+数据点两写之后)
  async _resp(req, what, timeoutMs) {
    return this._readMatching(req, what, timeoutMs);
  }
}

function hexToBytes(hex) {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}
// 响应载荷 u32 LE 读取 (带长度守卫 — 畸形应答给可读错误而非 TypeError)
function rdU32(payloadHex, byteOff, what) {
  const need = (byteOff + 4) * 2;
  if (!payloadHex || payloadHex.length < need) {
    throw new Error('DFU 响应载荷过短 (' + (what || 'op') + '): ' + payloadHex);
  }
  return parseInt(payloadHex.substr(byteOff * 2, 8).match(/../g).reverse().join(''), 16) >>> 0;
}

module.exports = { UUID_SECURE, UUID_LEGACY, connectDfu, DfuSession, crc32, hexToBytes, bytesToHex, u32leHex, u16leHex };
