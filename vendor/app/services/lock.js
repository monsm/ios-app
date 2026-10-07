// LockService — 离线管理端核心: 连接 / 令牌生命周期 / 命令执行 / rc 守卫 / 配网编排
// 依据: 记忆库 01/02/05/06; 生产链语义 (main.pretty.js + Java 插件 + 固件 0x253FE/0x25508)
const BLE = require('./ble.js');
const P = require('../utils/kernel/protocol.js');
const C = require('../utils/kernel/cmds.js');
const SES = require('../utils/session.js');
const K = require('../utils/keys.js');
const ST = require('../utils/store.js');
const STT = require('../utils/status.js');
const TRACE = require('../utils/trace.js');
const SNAP = require('./snapshot.js'); // 离线快照: 每次真机 03 成功即留档 (随时可读)

const KC_KEY = 'kf_keychain_v1';
const KC_LIST = 'kf_keychains';
const LAST_DEV = 'kf_last_device';

// rc 所在 KLV key (01-命令字典 §1/§5; V75 勘误: 03 状态 rc@KLV#03, 旧值 1 为误表残影)
// V76 勘误: 08 SYNCPINS 响应 Jt rc@KLV#03 (行 10290) — 曾漏配 → PIN 批失败被静默当成功
const RC_KLV = {
  0x03: 3, 0x04: 3, 0x05: 1, 0x08: 3, 0x0a: 3, 0x0b: 3, 0x0e: 3, 0x12: 3,
  0x13: 3, 0x14: 3, 0x15: 3, 0x16: 3, 0x18: 3, 0x19: 3, 0x20: 3,
  0x21: 3, 0x22: 3, 0x24: 3, 0x25: 3
};
// 锁端返回码 — V80 勘误: 旧 RC_MSG 为记忆库自造 (1=通用错误/5=参数错误/22=双验…) 与固件及
//   App 实际语义不符; 以下为权威表 main.js `resultCodeToMessage` 原文 (= 报告 §5.6 表 1, 逐字取证)。
//   注意: 表无 0/4 键 (0=成功由调用层判定), rc=3=命令过期 (令牌/有效期类), rc=22=不能重复验证 (双验流程语义)。
const RC_MSG = {
  0: '成功', 1: '解密失败', 2: '无效的PIN码', 3: '命令过期', 5: '次数使用完毕',
  6: '开锁指令已绑定其他设备', 7: '执行的操作不在指定的状态', 8: '溢出', 9: '时间误差过大',
  10: '未知错误', 11: '解密失败', 12: 'mac地址不正确', 13: '通讯过期', 14: '不支持的秘钥交换方式',
  15: '未知协议', 16: '参数不在范围内', 17: '丢包', 18: '不能设置重复的值',
  19: '找不到指定的值', 20: '指纹传感器错误', 21: '门锁处于反锁状态', 22: '不能重复验证',
  23: '无法获取有效的指纹图片', 24: '录入指纹超时', 25: '锁正忙，请稍后重试', 26: '门锁被撬',
  27: '您的门锁处于布防状态'
};
// 命令显示名 (trace 用; 与 01-命令字典一致)
const CMD_NAME = {
  0x01: '01 会话令牌', 0x02: '02 BLE MAC', 0x03: '03 状态', 0x04: '04 开锁',
  0x05: '05 换钥', 0x08: '08 PIN 池', 0x0a: '0A 密码', 0x0b: '0B 有效期',
  0x0e: '0E 时间同步', 0x12: '12 回声', 0x13: '13 录指纹', 0x14: '14 指纹确认',
  0x15: '15 删指纹', 0x16: '16 日志', 0x18: '18 音量', 0x19: '19 ZOTP',
  0x20: '20 验证模式', 0x21: '21 bkey', 0x22: '22 DFU', 0x23: '23 交换方式', 0x24: '24 自动锁', 0x25: '25 布防'
};
const CMD_HEX = cmd => '0x' + ('0' + cmd.toString(16)).slice(-2);

class LockService {
  constructor(log) {
    this.logFn = log || function () {};
    this.conn = null;
    this.curMac = null;
    this.session = new SES.LockSession();
    this._waiter = null;
    this._pairMac = null;
    this._connMac = null; // P0: 当前连接对应的锁 MAC (ensureConnected 幂等判定)
  }
  log(level, msg) {
    try { this.logFn(level, msg); } catch (e) {}
    TRACE.evt(level, msg); // 全局镜像: 页内 logbox 日志同样进 LOCK 追踪
  }
  // ---------- 连接管理 ----------
  async connect(deviceId) {
    const conn = await BLE.connect(deviceId, this.logFn);
    this.conn = conn;
    conn.onFrame(f => this._onFrame(f));
    ST.set(LAST_DEV, deviceId);
    this.log('info', '已连接 ' + deviceId);
    return conn;
  }
  // P0-1/P0-2: 幂等按需连接 — 操作页在操作前/onShow 调用。
  //   顺序: 已连同一把锁 → 直接返回; kc.bleId (配对时落库) → 直连,
  //   失败回退 MAC 扫描解析 (resolveDeviceId) → 回写 kc.bleId (App 重启后 deviceId 会变)。
  async ensureConnected(mac) {
    const m = String(mac || this.curMac || '').toLowerCase();
    if (!m) throw new Error('未选择门锁 (缺少 MAC)');
    // 已连同一把锁 (或刚由 pair/connect 建连但未记 MAC) → 幂等返回, 不重复建连
    if (this.conn && (this._connMac === m || !this._connMac)) {
      this._connMac = m;
      this.curMac = m;
      return this.conn;
    }
    if (this.conn) this.disconnect(); // 连的是别的锁 → 先断旧连 (单连接 BLE)
    const kc = this.getKeychain(m);
    if (!kc) throw new Error('找不到 MAC=' + m + ' 的钥匙串 (请先在设备页配对或导入)');
    this.curMac = m;
    if (kc.bleId) {
      try {
        await this._doConnect(m, kc.bleId);
        return this.conn;
      } catch (e) {
        this.log('warn', '缓存 deviceId 直连失败 (' + e.message + '), 回退 MAC 扫描解析');
      }
    }
    this.log('info', '无有效 deviceId, 扫描解析 MAC=' + m + ' (8s 窗口, 靠近门锁)');
    const deviceId = await BLE.resolveDeviceId(m, this.logFn);
    kc.bleId = deviceId; // 回写缓存: 下次直连免扫描
    try { this.saveKeychain(kc); } catch (e) { this.log('warn', 'bleId 回写失败: ' + e.message); }
    await this._doConnect(m, deviceId);
    return this.conn;
  }
  async _doConnect(m, deviceId) {
    await this.connect(deviceId);
    this._connMac = m;
    this.curMac = m;
    return this.conn;
  }
  disconnect() {
    TRACE.evt('info', 'disconnect (mac=' + (this.curMac || '-') + ')');
    // G1: 拒绝挂起的响应等待 — 否则调用方要空等 8s 超时, 且超时 reject 可能无人处理
    const w = this._waiter;
    if (w) { this._waiter = null; clearTimeout(w.timer); w.reject(new Error('连接已断开')); }
    // G2: 清理多响应执行 (13 录指纹) — 否则残留 _multiCb 吞掉下个连接的同 cmd 帧 + interval 空转
    if (this._multiCb) { this._multiCb = null; clearInterval(this._multiTimer); this._multiTimer = null; }
    try { if (this.conn) this.conn.close(); } catch (e) {}
    this.conn = null;
    this._connMac = null;
    this.session.refresh();
  }
  isConnected() { return !!this.conn; }
  lastDevice() { return ST.get(LAST_DEV, null); }
  // ---------- 钥匙串 (多锁台账: kf_keychains{mac:kc}; 兼容旧单份 kf_keychain_v1) ----------
  _kcMap() {
    const m = ST.get(KC_LIST, {}) || {};
    const legacy = ST.get(KC_KEY, null);
    if (legacy && legacy.mac) { m[legacy.mac] = legacy; ST.remove(KC_KEY); }
    return m;
  }
  _kcSave(m) { ST.set(KC_LIST, m); }
  listKeychains() {
    const m = this._kcMap();
    return Object.keys(m).map(k => m[k]).sort((a, b) => (a.pairedAt || '').localeCompare(b.pairedAt || ''));
  }
  getKeychain(mac) {
    if (mac) { const m = this._kcMap(); return m[String(mac).replace(/:/g, '').toLowerCase()] || null; }
    const legacy = ST.get(KC_KEY, null);
    if (legacy) return legacy;
    const all = this.listKeychains();
    return all.length ? all[all.length - 1] : null;
  }
  saveKeychain(kc) {
    if (!kc || !kc.mac) throw new Error('钥匙串缺少 MAC');
    const m = this._kcMap();
    m[String(kc.mac).replace(/:/g, '').toLowerCase()] = kc;
    this._kcSave(m);
    return kc;
  }
  removeKeychain(mac) {
    const m = this._kcMap();
    delete m[String(mac).replace(/:/g, '').toLowerCase()];
    this._kcSave(m);
  }
  // 删除设备 (完整语义, 2026-09-03): 钥匙串 + 该锁全部本地数据 + 连接/当前/上次设备指针。
  // 曾只删钥匙串 → 重配对后旧台账/校时/布防/尾门/OTP 复活为脏数据 (误以为锁上还有旧凭证)。
  removeDevice(mac) {
    const m = String(mac || '').replace(/:/g, '').toLowerCase();
    this.removeKeychain(m);
    if (this.curMac === m) this.curMac = null;
    if (this._connMac === m) { try { this.disconnect(); } catch (e) {} }
    const last = ST.get(LAST_DEV, null);
    if (last && String(last).replace(/:/g, '').toLowerCase() === m) ST.remove(LAST_DEV);
    // 每锁数据族 (与 utils/schema.js MANIFEST.perMac 一致)
    for (const p of ['kf_ledger_', 'kf_fpnames_', 'kf_synctime_', 'kf_defend_', 'kf_tailgate_', 'otpStatus_', 'otpIdx_']) {
      ST.remove(p + m);
    }
    SNAP.clear(m); // 离线状态快照 + 日志缓存一并清
    return true;
  }
  clearKeychain() { ST.remove(KC_KEY); ST.remove(KC_LIST); }
  // ---------- 帧等待与发送 ----------
  _onFrame(f) {
    // 真机收帧唯一入口: 全量 trace (含 13 多帧/无等待者杂帧)
    try {
      const rcKey = RC_KLV[f.cmd];
      const rcK = rcKey !== undefined && f.klvs ? f.klvs.find(x => x.key === rcKey) : undefined;
      TRACE.rx(CMD_NAME[f.cmd], f.cmd, f.raw, f.klvs || [], {
        header: f.header, rc: rcK ? STT.intHex(rcK.val) : (rcKey !== undefined ? -1 : undefined)
      });
    } catch (e) { TRACE.evt('warn', 'rx trace 失败: ' + (e && e.message)); }
    if (this._multiCb) { this._multiCb(f); return; }
    const w = this._waiter;
    if (w && f.cmd === w.cmd) {
      this._waiter = null;
      clearTimeout(w.timer);
      w.resolve(f);
    }
  }
  _waitFrame(cmd, timeoutMs) {
    return new Promise((resolve, reject) => {
      if (this._waiter) { reject(new Error('已有命令在等待响应')); return; }
      const timer = setTimeout(() => {
        if (this._waiter && this._waiter.cmd === cmd) {
          this._waiter = null;
          reject(new Error('超时: 未收到 cmd ' + ('0' + cmd.toString(16)).slice(-2) + ' 响应'));
        }
      }, timeoutMs || 8000);
      this._waiter = { cmd, resolve, reject, timer };
    });
  }
  async _request(hex, cmd, opts) {
    const o = Object.assign({ timeout: 8000, retries: 3, needToken: false }, opts);
const label = (o && o.name) || CMD_NAME[cmd] || ('cmd ' + CMD_HEX(cmd));
    let hex2 = hex;
    // P0-2: 操作页/后台无连接时按当前锁屏自动建连 (见 ensureConnected 幂等判定)
    // 防串锁: 现当前驾驶的锁非目标 MAC → 先断旧连再按需重连
    if (this.conn && this._connMac && this.curMac && this._connMac !== this.curMac) this.disconnect();
    if (!this.conn) {
      const m = this.curMac || (() => { const k = this.getKeychain(); return k && k.mac; })();
      if (m && this.getKeychain(m)) await this.ensureConnected(m);
      if (!this.conn) throw new Error('未连接门锁 (请到设备页连接)');
    }
    if (o.needToken) {
      await this._ensureToken();
      hex2 = C.withToken(hex, this.session.tokenHex);
      TRACE.evt('info', label + ' 注入令牌 KLV#EE=' + (this.session.tokenHex || '-') + ' (2B)');
    }
    let lastErr = null;
    for (let i = 0; i < o.retries; i++) {
      if (!this.conn) {
        const m = this.curMac || (() => { const k = this.getKeychain(); return k && k.mac; })();
        if (m && this.getKeychain(m)) await this.ensureConnected(m); // 断链自愈重连
      }
      if (!this.conn) throw lastErr || new Error('未连接门锁 (请到设备页连接)');
      const w = this._waitFrame(cmd, o.timeout);
      try {
        TRACE.tx(label, cmd, hex2, 'attempt=' + (i + 1) + '/' + o.retries + ' needToken=' + o.needToken + ' 超时=' + o.timeout + 'ms');
        await this.conn.write(hex2);
        return await w;
      } catch (e) {
        // 2026-09-03 勘误: 写入失败时旧 waiter 仍挂着 → 重试轮被「已有命令在等待响应」挡死,
        // 且 8s 后旧定时器可能误杀后续同 cmd 的新 waiter (未决 Promise + 串话)。写入失败即清。
        // 注: w 是 Promise 而非 waiter 对象, 须按 cmd 匹配。
        const ww = this._waiter;
        if (ww && ww.cmd === cmd) {
          this._waiter = null;
          clearTimeout(ww.timer);
        }
        lastErr = e;
        // P0: BLE 连接被系统/他页顶掉 → 丢弃陈旧 conn, 下轮尝试自动重连
        if (/10006|disconnect|closed|已断开|连接已断开/i.test(String((e && (e.message || e.errMsg)) || ''))) {
          this.conn = null;
          this._connMac = null;
        }
        this.log('warn', 'cmd ' + cmd.toString(16) + ' 第 ' + (i + 1) + ' 次失败: ' + (e && e.message));
      }
    }
    throw lastErr || new Error('发送失败');
  }
  async _ensureToken() {
    // V81 (对齐报告 §5.3): Java 发送路径**从不检查 isExpire()**, 每条 needToken 命令
    // 无条件先 doRefreshSsToken() — 小程序不再用 45s 缓存跳过刷新 (token 生命周期以锁侧为准)。
    // LockSession.isFresh() 仍保留: 仅作 UI/调试辅助与 G3 自愈判定, 不参与发送决策。
    this.log('info', '刷新会话令牌 (cmd 01)');
    const r = await this._request(C.cmd01Session().hex, 0x01, { retries: 3, timeout: 8000 });
    const t = this.session.parseTokenResponse(r.klvs);
    if (!t) throw new Error('01 响应无令牌; 安全类型=' + this.session.securityType);
    TRACE.evt('info', '会话令牌就绪: type=' + this.session.securityType + ' token=' + t +
      ' ttl=' + Math.round(this.session.ttlMs / 1000) + 's (有效至 ' +
      new Date(this.session.expiresAtMs).toLocaleTimeString() + ')');
    return t;
  }
  // ---------- rc 与执行 ----------
  _extractRc(cmd, resp) {
    const key = RC_KLV[cmd];
    if (key === undefined) return 0;
    const k = (resp.klvs || []).find(x => x.key === key);
    return k ? STT.intHex(k.val) : -1;
  }
  rcMsg(rc) { return RC_MSG[rc] !== undefined ? RC_MSG[rc] : ('错误码 ' + rc); }
  async _exec(cmdObj, opts) {
    const o = Object.assign({ needToken: true }, opts);
    const cmd = cmdObj.cmd !== undefined ? cmdObj.cmd : parseInt(cmdObj.hex.substr(6, 2), 16);
    const resp = await this._request(cmdObj.hex, cmd, o);
    let rc = this._extractRc(cmd, resp);
    // G3: 令牌过期自愈 — rc=3 (命令不在有效期/令牌过期, 45s TTL) → 刷新会话令牌后重试一次
    if (rc === 3 && o.needToken) {
      this.log('warn', cmdObj.name + ' rc=3 → 刷新令牌重试一次');
      this.session.refresh();
      try {
        await this._ensureToken();
        const resp2 = await this._request(cmdObj.hex, cmd, o);
        const rc2 = this._extractRc(cmd, resp2);
        if (rc2 !== 3) { rc = rc2; return { resp: resp2, rc, klvs: resp2.klvs || [] }; }
      } catch (e) { this.log('warn', '令牌刷新重试失败: ' + e.message); }
    }
    this.log('info', cmdObj.name + ' -> rc=' + rc);
    return { resp, rc, klvs: resp.klvs || [] };
  }
  async _execOk(cmdObj, opts) {
    const r = await this._exec(cmdObj, opts);
    // G5: rc=-1 (响应无 rc KLV, 如无状态响应命令) 视为成功 — 固件失败必带 rc, 缺省=接受
    if (r.rc !== 0 && r.rc !== -1) throw new Error(this.rcMsg(r.rc));
    return r;
  }

  // ---------- 多响应执行 (13 录指纹: 锁逐次按压逐次回 orderIdx 1..N, orderIdx==0 收尾) ----------
  async _execMulti(cmdObj, opts) {
    const o = Object.assign({ needToken: true, timeout: 20000, retries: 2, done: () => true }, opts);
    if (o.needToken) await this._ensureToken();
    const hex2 = C.withToken(cmdObj.hex, this.session.tokenHex);
    if (!this.conn) throw new Error('未连接门锁');
    const frames = [];
    for (let attempt = 0; attempt < o.retries; attempt++) {
      const ret = await new Promise((resolve, reject) => {
        const pushes = [];
        this._onMulti = f => { if (f.cmd === cmdObj.cmd) pushes.push(f); };
        this._multiCb = this._onMulti;
        const done = (framesArr, timedOut) => {
          clearTimeout(timer); clearInterval(check);
          if (this._multiCb === this._onMulti) this._multiCb = null;
          this._multiTimer = null;
          resolve({ frames: framesArr.slice(), timedOut });
        };
        const timer = setTimeout(() => done(pushes, true), o.timeout);
        this.conn.write(hex2).catch(e => { done(pushes, true); reject(e); });
        // G2: interval 句柄存实例, disconnect() 可中止
        const check = setInterval(() => {
          if (o.done(pushes.slice())) done(pushes, false);
        }, 200);
        this._multiTimer = check;
      });
      if (ret.frames.length) return ret.frames;
    }
    throw new Error('13 未收到任何按压响应');
  }

  // ---------- MAC / 加密面入口 ----------
  _mac() {
    if (this._pairMac) return this._pairMac;
    const kc = this.getKeychain(this.curMac);
    let m = kc && kc.mac;
    if (!m) throw new Error('钥匙串缺少 MAC (请先配网或导入钥匙串)');
    m = String(m).replace(/:/g, '').toLowerCase();
    if (m.length !== 12) throw new Error('MAC 格式异常: ' + m);
    return m;
  }
  _keys() {
    const kc = this.getKeychain(this.curMac);
    if (!kc || !kc.skey || kc.skey.length !== 32) throw new Error('钥匙串缺少有效 skey (请先配网或导入钥匙串)');
    return { mac: this._mac(), skey: kc.skey.toLowerCase() };
  }
  // ---------- 状态 ----------
  async getStatus(macOrOpts, opts) {
    if (typeof macOrOpts === 'string') { this.curMac = macOrOpts; opts = opts || {}; }
    else { opts = macOrOpts || {}; }
    const kc = this.getKeychain(this.curMac);
    let r;
    if (kc && kc.skey) {
      const { mac, skey } = this._keys();
      const wrap = C.cmd03StatusWrap(mac, skey);
      r = await this._exec(wrap, opts);
    } else {
      r = await this._exec(C.cmd03StatusPlain(this._macSafe() || ''), Object.assign({ needToken: false }, opts));
    }
    const status = STT.parseStatus(r.klvs);
    // 离线快照 (2026-09-03): 真机 03 成功即留档 — 电量/音量/安全位/容量/版本随时可读, 不依赖锁在场
    if (status && status.rc === 0) {
      try {
        const m = this._macSafe();
        if (m && m.length === 12) SNAP.writeStatus(m, status);
      } catch (e) {}
    }
    return { status, rc: status.rc, resp: r.resp };
  }
  _macSafe() { try { return this._mac(); } catch (e) { return ''; } }
  async readLockTime() {
    const { status } = await this.getStatus();
    if (!status.lockTime) throw new Error('状态中无锁钟 (KLV#04)');
    return status.lockTime;
  }
  // ---------- 开锁 ----------
  // U3 已闭合 (V38): 凭证 = hex(AES-ECB(skey)($t 包络)), $t 包络 = 88 00 MAC反转 TrackId VF VT 04 pinLE 0000
  //   优先 kc.ekey (云式台账); 否则自签发: buildEkeyOpen(skey, mac, pin=pins[0] 或 opts.pinDec)
  async unlock(macOrOpts, opts) {
    if (typeof macOrOpts === 'string') { this.curMac = macOrOpts; opts = opts || {}; }
    else { opts = macOrOpts || {}; }
    const kc = this.getKeychain(this.curMac);
    if (!kc || !kc.skey) throw new Error('无钥匙串, 无法开锁');
    let cred;
    if (opts && opts.credHex) cred = opts.credHex;                    // 探测对照覆盖
    else if (kc.ekey) cred = kc.ekey;                                 // 云式台账 (配网时已生成)
    else {
      const pin = (opts && opts.pinDec !== undefined) ? opts.pinDec : (kc.pins && kc.pins[0]);
      if (pin === undefined || pin === null) throw new Error('无 PIN 可用: 需要 kc.ekey 或 kc.pins[0] 才能签发开锁凭证');
      cred = C.buildEkeyOpen(kc.skey, kc.mac, pin);
    }
    const r = await this._exec(C.cmd04Open(cred, (opts && opts.klv01Hex) || '0000'), { retries: 2 });
    return r; // rc=0 成功; rc=22 双验继续; 其余抛错由 _execOk 语义处理 — 这里保留 rc 一并返回; G4: 开锁重试降至 2 次防电机连触发
  }
  async openExpectOk(macOrOpts, opts) {
    const r = await this.unlock(macOrOpts, opts === undefined && typeof macOrOpts !== 'string' ? opts : (typeof macOrOpts === 'string' ? opts : macOrOpts));
    if (r.rc !== 0 && r.rc !== 22) throw new Error(this.rcMsg(r.rc));
    return r;
  }
  // ---------- 布防 / 时间 / 设置 ----------
  async setDefence(control, startSec, endSec) {
    const { mac, skey } = this._keys();
    return this._execOk(C.cmd25Defence(mac, skey, control, startSec, endSec));
  }
  async syncTime() {
    const { mac, skey } = this._keys();
    // 先读锁钟, 补偿手机↔锁钟偏差 (A7 纪律: 先读后校)
    let offset = 0;
    try {
      const lockSec = await this.readLockTime();
      offset = lockSec - Math.floor(Date.now() / 1000 - P.EPOCH);
    } catch (e) { this.log('warn', '读锁钟失败, 直接用手机时间: ' + e.message); }
    const target = Math.floor(Date.now() / 1000 - P.EPOCH) + offset;
    return this._execOk(C.cmd0ESyncTime(mac, skey, target));
  }
  // App setSilentMode 原文: new he(1==l?1:0) — 18 是 1B 状态位 (0=有声 1=静音), 不是绝对音量
  async setVolume(on) {
    const { mac, skey } = this._keys();
    return this._execOk(C.cmd18Volume(mac, skey, on ? 1 : 0));
  }
  async setValidationMode(mode) {
    const { mac, skey } = this._keys();
    return this._execOk(C.cmd20ValidationMode(mac, skey, mode));
  }
  async setAutoLock(interval) {
    const { mac, skey } = this._keys();
    return this._execOk(C.cmd24AutoLock(mac, skey, interval));
  }
  async setZotp(on) {
    const { mac, skey } = this._keys();
    return this._execOk(C.cmd19OpenZotp(mac, skey, on));
  }
  // cmd 22 enableDFUstate (App sendDFUCmd): param=0 → 重启进 bootloader。锁会主动断链 —
  //   rc 读取不到 (响应可能先于断链到达, 也可能直接失败) — 这里容忍 rc=-1 与超时前成功。
  async enableDfu(param) {
    const { mac, skey } = this._keys();
    try {
      const r = await this._execOk(C.cmd22EnableDfu(mac, skey, param), { needToken: true, retries: 2 });
      this.log('info', '22 DFU -> rc=' + r.rc);
      return r;
    } catch (e) {
      // 锁重启瞬间断链属预期 (10006/disconnect) — 不当失败
      if (/10006|disconnect|断开|closed/i.test(String(e && e.message))) {
        this.log('info', 'cmd 22 后锁断链 (进入升级模式的预期行为)');
        return { rc: -1 };
      }
      throw e;
    }
  }
  // ---------- 密码 ----------
  // App 两步链 (hu 页): 0A 下发 (addPwd) → 响应 KLV#04=pwdAlisa (LE 2B) → 0B 设置有效期
  async pwdAdd(pwd, validFrom, validTo) {
    const { mac, skey } = this._keys();
    const r = await this._execOk(C.cmd0ASyncPwd(mac, skey, { addPwd: pwd, validFrom, validTo }));
    let alias = 0;   // V51: 暴露给本地台账
    const klv = (r.klvs || []).find(k => k.key === 0x04);
    if (klv && klv.val && klv.val.length >= 2) {
      const raw = klv.val.length >= 4 ? klv.val.substr(0, 4) : klv.val;
      let rev = '';
      for (let i = raw.length - 2; i >= 0; i -= 2) rev += raw.substr(i, 2);
      alias = parseInt(rev, 16);
      if (alias) {
        try {
          const r2 = await this._execOk(C.cmd0BSyncPwdExpire(mac, skey, alias, validFrom, validTo));
          this.log('info', '0B 设置有效期 alias=' + alias + ' rc=' + r2.rc + ' (App setPwdPeriodToForever)');
        } catch (e2) {
          this.log('warn', '0B 设置有效期失败(不影响添加): ' + e2.message);
        }
      }
    } else {
      this.log('warn', '0A 响应无 KLV#04 alias (固件未返回), 跳过 0B');
    }
    return Object.assign({}, r, { alias });   // V51: 附带 alias 供本地台账记录
  }
  // App modifypwd (gu.modifyLockPwd) 语义: 0A 单帧原位改写 — delAlias=现别名 + addPwd=新密码,
  // 同帧携带有效期 (App 固定 2010~2118 永久; 此处沿用台账现值以兼容自定义有效期)。
  // 响应 KLV#04 = 锁侧别名 (原位改写应与入参一致; 万一锁回新别名也如实返回)。
  async pwdModify(alias, pwd, validFrom, validTo) {
    const { mac, skey } = this._keys();
    const r = await this._execOk(C.cmd0ASyncPwd(mac, skey, { delAlias: alias, addPwd: pwd, validFrom, validTo }));
    let aliasOut = Number(alias);
    const klv = (r.klvs || []).find(k => k.key === 0x04);
    if (klv && klv.val && klv.val.length >= 2) {
      const raw = klv.val.length >= 4 ? klv.val.substr(0, 4) : klv.val;
      let rev = '';
      for (let i = raw.length - 2; i >= 0; i -= 2) rev += raw.substr(i, 2);
      const a = parseInt(rev, 16);
      if (a) aliasOut = a;
    }
    return Object.assign({}, r, { alias: aliasOut });
  }
  async pwdDelete(alias) {
    const { mac, skey } = this._keys();
    return this._execOk(C.cmd0ASyncPwd(mac, skey, { delAlias: alias }));
  }
  async pwdClear() {
    const { mac, skey } = this._keys();
    return this._execOk(C.cmd0ASyncPwd(mac, skey, { delAlias: 0xffff }));
  }
  async pwdExpire(alias, validFrom, validTo) {
    const { mac, skey } = this._keys();
    return this._execOk(C.cmd0BSyncPwdExpire(mac, skey, alias, validFrom, validTo));
  }
  // ---------- 指纹 ----------
  // 13 录指纹: 一请求多响应 (App: times=8, 每按一次锁回一帧 orderIdx=1..8, orderIdx==0=结束)
  async fpStart(times, timeoutMs) {
    const { mac, skey } = this._keys();
    const frames = await this._execMulti(C.cmd13AddFp(mac, skey, times || 8, 15), {
      done: fs => fs.some(f => {
        const k = (f.klvs || []).find(x => x.key === 0x04);
        return k ? STT.leHexToU32(k.val) === 0 : false;
      })
    });
    const g = (f, key) => { const k = (f.klvs || []).find(x => x.key === key); return k ? STT.leHexToU32(k.val) : null; };
    const presses = frames.map(f => ({
      orderIdx: g(f, 0x04), featureNumber: g(f, 0x05),
      batchNumber: g(f, 0x06), nextTimeout: g(f, 0x07), rc: this._extractRc(0x13, f)
    }));
    if (!presses.length) throw new Error('无按压响应');
    return presses;
  }
  async fpConfirm(batchNumber, validFrom, validTo) {
    const { mac, skey } = this._keys();
    return this._execOk(C.cmd14FpConfirm(mac, skey, batchNumber, validFrom, validTo));
  }
  async fpDelete(batchNumber) {
    const { mac, skey } = this._keys();
    return this._execOk(C.cmd15DeleteFp(mac, skey, batchNumber));
  }
  // ---------- 日志 ----------
  async getLogs(opts) {
    const { mac, skey } = this._keys();
    const r = await this._exec(C.cmd16GetLog(mac, skey, opts));
    if (r.rc !== 0 && r.rc !== -1) throw new Error(this.rcMsg(r.rc));
    const surplusKlv = r.klvs.find(x => x.key === 0x04);
    return { rc: r.rc, surplus: surplusKlv ? STT.leHexToU32(surplusKlv.val) : null, logs: STT.parseLogs(r.klvs) };
  }
  // ---------- 配网编排 (重置后全流程, 蓝本 06-pairing-flow) ----------
  // 前置: 锁已在重置态 (resetStatus==1, 广播 bit0)。参数 prog(msg) 汇报进度。
  async pair(deviceId, prog, macHex) {
    if (macHex) this._pairMac = String(macHex).replace(/:/g, '').toLowerCase();
    const p = (m) => { this.log('info', m); if (prog) prog(m); };
    // 2026-09-03 勘误: 曾检查「任意」钥匙串 → 已有任何一把锁后第二把永远配不上 (多锁台账成摆设)。
    // 改为只拦**目标 MAC** 已存在的钥匙串 (防覆盖当前锁密钥); 其余锁不受影响。
    let kc = this._pairMac ? this.getKeychain(this._pairMac) : null;
    if (kc && kc.skey && kc.mac) throw new Error('该锁已有钥匙串 (MAC=' + kc.mac + '), 拒绝覆盖配网; 如需重配请先在设置删除该设备');
    await this.connect(deviceId);
    try {
      // 0. 23 交换方式 (免令牌明文)
      p('步骤 1/7: 探测交换方式 (cmd 23)');
      const w = await this._request(C.cmd23ExKeyWay().hex, 0x23, { needToken: false });
      const wayK = (w.klvs || []).find(x => x.key === 0x01);
      const way = wayK ? STT.intHex(wayK.val) : 0;
      if (!(way & 2)) throw new Error('交换方式不支持 (exSKeyWay=' + way + '), 固件要求 bit1=1');
      // 1. 生成密钥族 — 必须走异步 wx CSPRNG (keys.js 2026-09-03): wx.getRandomValues 是异步 API,
      //    曾同步误用 → 全零 → genPins 死循环占死主线程 (内存不足被微信杀)
      p('步骤 2/7: 生成本地密钥 (skey/bkey/64 PIN)');
      const skey = await K.genSkeyAsync(), bkey = await K.genBkeyAsync(), pins = await K.genPinsAsync(64);
      // 2. 05 明文换钥 (免令牌; 已配对锁会 rc=7 — 说明未处于重置态)
      p('步骤 3/7: cmd 05 交换密钥');
      const r5 = await this._request(C.cmd05Exchange(skey).hex, 0x05, { needToken: false });
      const rc5 = this._extractRc(0x05, r5);
      const echoK = (r5.klvs || []).find(x => x.key === 0x02);
      if (rc5 !== 0) throw new Error('换钥失败 rc=' + rc5 + ' (' + this.rcMsg(rc5) + ') — 锁可能未处于重置态');
      if (echoK && echoK.val.toLowerCase() !== skey.toLowerCase()) {
        throw new Error('换钥回显不匹配 (本地=' + skey + ' 回显=' + echoK.val + '), 已中止');
      }
      // 3. 刷新令牌 (密文面需要)
      p('步骤 4/7: 获取会话令牌');
      await this._ensureToken();
      // 4. 08 PIN 池: 64 个分 4 批 (≤20/批); 首批 delPins=[0xFFFFFFFF] 清哨兵
      p('步骤 5/7: 同步 PIN 池 (4 批)');
      const BATCH = 16;
      for (let i = 0; i < 4; i++) {
        const batch = pins.slice(i * BATCH, (i + 1) * BATCH);
        const delPins = i === 0 ? [K.DEL_PIN_SENTINEL] : [];
        const rb = await this._exec(C.cmd08SyncPinsBatch(this._macOf(deviceId), skey, batch, { delPins }));
        if (rb.rc !== 0) throw new Error('PIN 批次 ' + (i + 1) + ' 失败 rc=' + rb.rc + ' (' + this.rcMsg(rb.rc) + ')');
      }
      // 5. 21 bkey
      p('步骤 6/7: 设置 bkey (cmd 21)');
      const r21 = await this._exec(C.cmd21SetBkey(this._macOf(deviceId), skey, bkey));
      if (r21.rc !== 0) throw new Error('bkey 失败 rc=' + r21.rc);
      // 6. 03 加密回读校验配对
      p('步骤 7/7: 加密状态校验 (cmd 03)');
      const st = await this._exec(C.cmd03StatusWrap(this._macOf(deviceId), skey));
      const status = STT.parseStatus(st.klvs);
      if (st.rc !== 0) throw new Error('配对校验失败 rc=' + st.rc);
      // 落库 (ekey 自签发 = skey, U3 策略)
      const trackid = K.genTrackId();
      kc = {
        version: 1, mac: this._macOf(deviceId), pid: status.pid, pidName: status.pidName,
        skey, bkey, pins, ekey: C.buildEkeyOpen(skey, this._macOf(deviceId), pins[0]), trackid: String(trackid),
        // P0-1: 配对期的 BLE 扫描 deviceId 一并落库 — App 重启后按 kc.bleId 直连, 失效再扫描解析
        bleId: deviceId,
        fw: status.firmware, pairedAt: new Date().toISOString()
      };
      this.saveKeychain(kc);
      // G8: 配网成功后清掉配对期 MAC 覆盖, 后续 _mac() 走钥匙串台账
      this._pairMac = null;
      p('配网完成: ' + (status.pidName || ('pid=' + status.pid)) + ' @ ' + kc.mac);
      return kc;
    } catch (e) {
      this.disconnect();
      throw e;
    }
  }
  _macOf() { return this._macSafe(); }
}
module.exports = { LockService, RC_MSG, KC_KEY, KC_LIST, LAST_DEV };
