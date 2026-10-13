#!/usr/bin/env node
// tools/parseshadow.js — 锁回字节的**解析侧**跨语言差分 (第一百七十四批新增，判失败)
//
// cmdsshadow 验的是"发出去的字节"；这一支验另一半：**锁回来的帧怎么变成 App 里的状态**。
// 解析侧错一格的表现不是报错，是**安静地显示一个错值** (电量、锁钟、固件号、日志时间、剩余次数)，
// 而这些值又直接被统计/导出/凭证有效期读走 —— 本仓 §10.32/§10.34 那几族"恒 0 / 幽灵日"缺陷全在这一层。
//
// 做法：锁端状态那几组，输入与期望**都取自 fixtures/golden.json** (由 vendor JS 基线生成)，
//       算法逐行复刻自 Swift 的 ZKProtocol.parseResponse / parseKLV / parseAdv + StatusParser。
//       这样"输入重建"这一步没有出错空间，比对只在算法上。
//       第一百七十六批另加钥匙串 (cmd 43) 与网关 (cmd 38) 两条状态解析：golden.json 里没有这两种帧，
//       于是**直接 require vendor 的解析函数当权威侧** (比从夹具取期望还少一层转抄)，
//       输入由本工具构造、两边吃同一个对象 —— 构造错只会让某条分支没被走到，不会凑出假一致。
//
// ⚠ 边界：这证明 Swift 的解析算法与基线在这些帧上一致；不证明锁端真会发这些帧，
//   也不覆盖 Swift 独有的一条路 (手机侧失败行 kf_fevents_、缓存合并、分页游标)。
//   复刻侧与 Swift 源码是否逐行一致，仍靠人读 (见 docs/AUDIT-CODE.md §10.46/§10.48 的逐行读记录)。
process.env.TZ = process.env.PARSE_SHADOW_TZ || 'Asia/Shanghai';   // 与 tools/golden.js 同一颗钉子
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert');

const ROOT = path.resolve(__dirname, '..');
const G = JSON.parse(fs.readFileSync(path.join(ROOT, 'fixtures/golden.json'), 'utf8'));
const SKEY = '00112233445566778899aabbccddeeff';
const EP_MS = 1262304000000;
const protoFromMs = (ms) => Math.floor((ms - EP_MS) / 1000);

// ---------------- HexKit / AESKit ----------------
const hexBytes = (h) => { const o = []; for (let i = 0; i + 1 < h.length; i += 2) { const n = Number.parseInt(h.substr(i, 2), 16); o.push(Number.isNaN(n) ? 0 : n & 0xff); } return o; };
const bytesHex = (b) => b.map((x) => (x & 0xff).toString(16).padStart(2, '0')).join('');
const hexPair = (v) => (v & 0xff).toString(16).padStart(2, '0');
function reversePairs(hex) { if (hex.length % 2 !== 0) return ''; return bytesHex(hexBytes(hex).reverse()); }
const intHex = (v) => (v === '' ? 0 : (Number.parseInt(v, 16) || 0));
function leHexToU32(v) { const b = hexBytes(v); let n = 0; for (let i = b.length - 1; i >= 0; i--) n = n * 256 + b[i]; return n; }
const readU16LE = (hex, off) => { const b = hexBytes(hex); return b.length >= off + 2 ? (b[off] | (b[off + 1] << 8)) : 0; };
function encryptHex(plainHex, keyHex) {
  let p = Buffer.from(hexBytes(plainHex)); const rem = p.length % 16;
  if (rem) p = Buffer.concat([p, Buffer.alloc(16 - rem, 0)]);
  const k = Buffer.from(hexBytes(keyHex)); if (k.length !== 16) return '';
  const c = crypto.createCipheriv('aes-128-ecb', k, null); c.setAutoPadding(false);
  return bytesHex([...Buffer.concat([c.update(p), c.final()])]);
}
function decryptHex(cipherHex, keyHex) {
  const c0 = Buffer.from(hexBytes(cipherHex)), k = Buffer.from(hexBytes(keyHex));
  if (!c0.length || c0.length % 16 || k.length !== 16) return '';
  const d = crypto.createDecipheriv('aes-128-ecb', k, null); d.setAutoPadding(false);
  return bytesHex([...Buffer.concat([d.update(c0), d.final()])]);
}

// ---------------- ZKProtocol.parseKLV / parseResponse ----------------
function parseKLV(hex) {
  const b = hexBytes(hex); const out = []; let off = 0;
  while (off < b.length) {
    if (off + 2 > b.length) return null;
    const key = b[off], len = b[off + 1];
    if (off + 2 + len > b.length) return null;
    out.push({ key, vlen: len, val: bytesHex(b.slice(off + 2, off + 2 + len)) });
    off += 2 + len;
  }
  return out;
}
function parseResponse(hex) {
  if (hex.length < 14) return { ok: false, cmd: 0, header: 0, klvs: [] };
  const b = hexBytes(hex), vb = b[1], len = readU16LE(hex, 2);
  const orders = vb === 0x01 ? [8, 7, 10] : [8, 10, 7];
  for (const bodyOff of orders) {
    if (b.length < bodyOff + len) continue;
    const klvHex = hex.substr(bodyOff * 2, len * 2);
    const klvs = parseKLV(klvHex);
    if (klvs) return { ok: true, cmd: b[4], header: bodyOff, klvs };
  }
  return { ok: false, cmd: 0, header: 0, klvs: [] };
}

// ---------------- PidMap (逐条抄自 App/Core/PidMap.swift 的 names 表) ----------------
const PID_NAMES = { 8097: 'K1', 8098: 'KX', 7857: 'V1', 7858: 'V1_Pro', 7873: 'JZ', 7891: 'Z3', 7892: 'Z3NFC', 7893: 'Z3AL', 16289: 'ZKBBV1', 12193: 'GW', 12209: 'GW_commercial', 12194: 'GW2_commercial' };
const modelName = (pid) => pid === 0 ? '自动识别' : (PID_NAMES[pid] ?? `未知型号(pid=${pid})`);

// ---------------- StatusParser.parseStatus / parseLogEntry / truncatedLogCount ----------------
const LOG_TYPES = { 1: '数字钥匙开门', 2: '密码开门', 3: '指纹开门', 4: '临时密码开门', 5: 'NFC开门', 6: '电量低', 7: '撬锁', 8: '重新上电', 9: 'DFU 后版本', 10: '多次密码失败锁定', 12: '授时', 13: '指纹告警', 14: '同步PIN', 15: '同步密码', 20: '添加指纹', 21: '删除指纹', 22: '设置安全级别', 23: '状态广播开关', 24: '设置单双验', 25: '开通临时密码', 26: '设置音量', 27: '设置beacom密钥', 224: '键盘被锁定' };
function parseStatus(klvs, raw = '') {
  const s = { rc: -1, sKeyStatus: -1, powerLevel: -1, lockTime: null, pid: 0, pidName: '未知', firmware: '', keyboardFreeze: 0, keyboardErrCount: 0, securityLevel: 0, verifyMode: 0, broadcastMode: 0, tempPwdMode: 0, zotpPeriod: 0, soundVolumn: 0, pinInfoCapacity: 0, pinInfoStock: 0, pinInfoBinding: 0, pwdInfoCapacity: 0, pwdInfoStock: 0, pwdInfoMaxLen: 0, fpInfoCapacity: 0, fpInfoStock: 0, fpInfoBatchNumber: 0, verDFU: 0, verKeyboard: 0, eCtrlVer: '' };
  for (const k of klvs) {
    const vlen = k.vlen, val = k.val;
    switch (k.key) {
      case 0x04: { const lt = leHexToU32(val); s.lockTime = lt === 0 ? null : lt; break; }
      case 0x03: s.rc = intHex(val); break;
      case 0x01: s.sKeyStatus = intHex(val); break;
      case 0x05: s.zotpPeriod = vlen >= 2 ? leHexToU32(val) : intHex(val); break;
      case 0x06: s.keyboardFreeze = intHex(val); break;
      case 0x07: s.keyboardErrCount = intHex(val); break;
      case 0x08: s.securityLevel = intHex(val); s.verifyMode = s.securityLevel & 1; s.broadcastMode = (s.securityLevel >> 1) & 1; s.tempPwdMode = (s.securityLevel >> 2) & 1; break;
      case 0x11: s.powerLevel = intHex(val); break;
      case 0x14: s.soundVolumn = intHex(val); break;
      case 0x21: s.pinInfoCapacity = intHex(val); break;
      case 0x22: s.pinInfoStock = intHex(val); break;
      case 0x23: s.pinInfoBinding = intHex(val); break;
      case 0x24: s.pwdInfoCapacity = intHex(val); break;
      case 0x25: s.pwdInfoStock = intHex(val); break;
      case 0x26: s.pwdInfoMaxLen = intHex(val); break;
      case 0x27: s.fpInfoCapacity = intHex(val); break;
      case 0x28: s.fpInfoStock = intHex(val); break;
      case 0x29: s.fpInfoBatchNumber = intHex(val); break;
      case 0x31: {
        const o = reversePairs(val);
        if (vlen === 3 && o.length === 6) {
          const p0 = parseInt(o.slice(0, 2), 16), p1 = parseInt(o.slice(2, 4), 16), p2 = parseInt(o.slice(4, 6), 16);
          s.firmware = `${p2}.${p1}.${p0}`;
        }
        break;
      }
      case 0x32: s.verDFU = intHex(val); break;
      case 0x33: s.verKeyboard = vlen >= 2 ? leHexToU32(val) : intHex(val); break;
      case 0x34: s.pid = leHexToU32(val); s.pidName = modelName(s.pid); break;
      case 0x35: if (vlen > 0) s.eCtrlVer = Buffer.from(val, 'hex').toString('latin1'); break;
      default: break;
    }
  }
  s.raw = raw;                      // 基线在返回对象里带上原始帧 (Swift 侧同名字段在 ParsedFrame.raw)
  return s;
}
function protoLocal(sec) {
  const d = new Date((sec + EP_MS / 1000) * 1000);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}
function parseLogEntry(hex) {
  if (hex.length < 20) return null;
  const b = hexBytes(hex);
  const type = b[0], len = b[1];
  const idx = leHexToU32(hex.substr(4, 8));
  const lockTime = leHexToU32(hex.substr(12, 8));
  return {
    type, typeName: LOG_TYPES[type] || `未知(${type})`, len, idx, idxRaw: idx, lockTime,
    lockTimeStr: lockTime ? protoLocal(lockTime) : '', body: hex.substr(20),
    invalid: len !== hex.length / 2 - 2,
  };
}
const parseLogs = (klvs) => klvs.filter((k) => k.key === 0x05).map((k) => parseLogEntry(k.val)).filter(Boolean);
// Swift 同口径 (StatusParser.truncatedLogCount, 第一百七十四批新加)
const truncatedLogCount = (klvs) => klvs.filter((k) => k.key === 0x05)
  .filter((e) => (e.val.length / 2 < 2 ? true : intHex(e.val.substr(2, 2)) !== e.val.length / 2 - 2)).length;

// ---------------- ZKProtocol.parseAdv ----------------
function parseAdv(advHex) {
  const at = advHex.toLowerCase().indexOf('98ed');
  if (at < 0) return null;
  if (advHex.length - at < 24) return null;
  const seg = advHex.substr(at + 4);
  if (seg.length < 20) return null;
  const frameCtrl = hexBytes(seg.substr(0, 2))[0];
  if ((frameCtrl & 0x0c) !== 0x0c) return null;
  const pid = hexBytes(seg.substr(4, 2))[0] | (hexBytes(seg.substr(6, 2))[0] << 8);
  const macRaw = seg.substr(8, 12);
  const macDisplay = (reversePairs(macRaw).match(/.{2}/g) || []).join(':').toUpperCase();
  return {
    frameCtrl, pid, macRaw: macRaw.toLowerCase(), mac: macRaw.toLowerCase(), macDisplay,
    resetStatus: (frameCtrl & 1) ? 1 : 0, containNotify: (frameCtrl & 2) ? 1 : 0,
    containPid: (frameCtrl & 4) ? 1 : 0, containMac: (frameCtrl & 8) ? 1 : 0,
    dfuState: (frameCtrl & 0x20) ? 1 : 0,
  };
}

// ---------------- 比对 ----------------
let bad = 0, checks = 0;
// 基线在返回对象里**同时**给了两套拼法 (pinInfoStock 与旧名 pinStock、firmware 与 verFirmware)，
// Swift 侧只留一个名字 (StatusParser.LockStatus)。这些别名按真值补进比对，缺别名不算缺陷、值不同才算。
const ALIAS = { pinStock: 'pinInfoStock', pwdStock: 'pwdInfoStock', fpStock: 'fpInfoStock', verFirmware: 'firmware' };
const cmp = (name, gotRaw, want, omit = []) => {
  checks++;
  // 别名只在基线确实多写了那一格时才补 (给 parseStatus 的输出补上 pinStock/verFirmware 那几个旧拼法)，
  // 补进的对象只用于比较，不参与"Swift 多了哪些键"的统计 —— 否则 parseAdv 那类对象会被报出假多的键。
  const got = { ...(gotRaw ?? {}) };
  for (const [alias, canon] of Object.entries(ALIAS)) {
    if (alias in want && !(alias in got) && canon in got) got[alias] = got[canon];
  }
  // 逐键比，不用 JSON.stringify 整对象比：别名是后补的，键序与基线不同 ⇒ 整串比会假红
  const diffs = Object.keys(want ?? {}).filter((k) => !omit.includes(k))
    .filter((k) => JSON.stringify(got[k]) !== JSON.stringify(want[k]));
  const extraIgnored = Object.keys(got).filter((k) => !(k in want));
  if (diffs.length) {
    bad++;
    console.log(`✗ ${name}`);
    for (const k of diffs) console.log(`    ${k}: 基线=${JSON.stringify(want[k])} Swift复刻=${JSON.stringify(got[k])}`);
  } else if (extraIgnored.length) console.log(`ok  ${name}  (Swift 多出的键未参与比较: ${extraIgnored.join(',')})`);
  else console.log(`ok  ${name}`);
};

const P0 = parseResponse(G.parse.status_frame);
// `raw` 不比：那是 JS 基线自己的调试袋 (未消化字段的原 hex，随帧内容变化)，Swift 无对应物
const OMIT_RAW = ['raw'];
cmp('parse.status', parseStatus(P0.klvs, G.parse.status_frame), P0.ok ? G.parse.status : null, OMIT_RAW);
for (const [h, key] of [['h8', 'header8'], ['h7', 'header7'], ['h10', 'header10']]) {
  const pr = parseResponse(G.parse[key]);
    cmp(`parse.status_parse_headers.${h}`, parseStatus(pr.klvs, G.parse[key]), G.parse.status_parse_headers[h], ['raw']);
}
cmp('parse.log_parsed[0]', parseLogs(parseResponse(G.parse.log_frame).klvs)[0], G.parse.log_parsed[0], ['invalid', 'len']);
cmp('parse.log_parsed[1]', parseLogs(parseResponse(G.parse.log_frame).klvs)[1], G.parse.log_parsed[1], ['invalid', 'len']);
cmp('parseAdv.out', parseAdv(G.parseAdv.input), G.parseAdv.out);
cmp('parseAdv.dfumode', parseAdv(G.parseAdv.dfumode_input), G.parseAdv.dfumode);

// 基线的 invalid 与 Swift 新加的 truncatedLogCount 必须数到同一个数
const kl5 = parseResponse(G.parse.log_frame).klvs;
const baseInvalid = G.parse.log_parsed.filter((e) => e.invalid).length;
assert.strictEqual(truncatedLogCount(kl5), baseInvalid, `截断计数与基线 invalid 不一致: Swift=${truncatedLogCount(kl5)} 基线=${baseInvalid}`);
console.log(`ok  截断计数与基线 invalid 同为 ${baseInvalid} 条 (Swift 侧 truncatedLogCount 同口径)`);

// AES: 输入取自 golden.js 的同一份定义
const aesGot = {
  encrypt_16: encryptHex('00112233445566778899aabbccddeeff'.slice(0, 32), SKEY),
  encrypt_padded: encryptHex('8800aabbccddeeff', SKEY),
  decrypt_roundtrip: decryptHex(encryptHex('8800aabbccddeeff' + '0102030405060708', SKEY), SKEY),
  nist_vector: encryptHex('00112233445566778899aabbccddeeff', '000102030405060708090a0b0c0d0e0f'),
};
for (const k of Object.keys(G.aes)) { checks++; if (aesGot[k] !== G.aes[k]) { bad++; console.log(`✗ aes.${k} 基线=${G.aes[k]} Swift复刻=${aesGot[k]}`); } }
console.log(`ok  aes ${Object.keys(G.aes).length} 条`);

// rc 词表与 pid 表：直接比 **Swift 源码里的表** (数据表不靠复刻，靠读源)
const src = fs.readFileSync(path.join(ROOT, 'App/Core/StatusParser.swift'), 'utf8');
const rcBlock = src.slice(src.indexOf('static let rcMsg'), src.indexOf('static func rcMessage'));
const rcSwift = {};
for (const m of rcBlock.matchAll(/(\d+):\s*"([^"]*)"/g)) rcSwift[+m[1]] = m[2];
const rcWant = Object.fromEntries(Object.entries(G.rcMsgTable).map(([k, v]) => [+k, v]));
const rcDiff = Object.keys(rcWant).filter((k) => rcSwift[k] !== rcWant[k]);
checks++;
if (rcDiff.length) { bad++; console.log(`✗ rcMsg 表 ${rcDiff.length} 条不同: ` + rcDiff.map((k) => `${k}:基线"${rcWant[k]}" Swift"${rcSwift[k] ?? '缺'}"`).join(' | ')); }
else console.log(`ok  rcMsg 表 ${Object.keys(rcWant).length} 条与 Swift 源码逐条相同 (Swift 另有 ${Object.keys(rcSwift).length - Object.keys(rcWant).length} 条基线没有的)`);

const pidSrc = fs.readFileSync(path.join(ROOT, 'App/Core/PidMap.swift'), 'utf8');
const pidBlock = pidSrc.slice(pidSrc.indexOf('static let names'), pidSrc.indexOf('// 中文产品名'));
// 符号→pid 也从源码解析 (`static let K1 = 8097, KX = 8098, ...` 那一行)：
// 于是这一段没有一处是我手抄的 —— 符号→pid 与 符号→名字 都取自源文件，合成 pid→名字再与基线比。
const SYM = {};
// 常量声明在源码里是**三行** (K1/KX/V1/V1_Pro/JZ、Z3/Z3NFC/Z3AL/ZKBBV1、GW/GW_commercial/GW2_commercial) ——
// 第一版只取 `static let K1` 那一行 ⇒ 只认出 5 个，被下面的 assert 当场逮住。
for (const line of pidSrc.split(/\r?\n/)) {
  if (!/^\s*static let [A-Za-z0-9_]+\s*=\s*\d+/.test(line)) continue;
  for (const m of line.matchAll(/([A-Za-z0-9_]+)\s*=\s*(\d+)/g)) SYM[m[1]] = +m[2];
}
const pidSwift = {};
for (const m of pidBlock.matchAll(/([A-Za-z0-9_]+)\s*:\s*"([^"]*)"/g)) {
  const key = /^\d+$/.test(m[1]) ? +m[1] : SYM[m[1]];
  if (key !== undefined) pidSwift[key] = m[2];
}
assert.ok(Object.keys(pidSwift).length >= 12, `PidMap 解析失败: 只认出 ${Object.keys(pidSwift).length} 条, 表一改形状这工具就得提醒`);
// 基线另有 `pidTable.default` 之类的**非数字下标** (JS 侧的默认名，不是一个 pid) ⇒ 只比数字键，其余报名字
const pidNum = Object.entries(G.pidTable).filter(([k]) => /^\d+$/.test(k));
const pidOther = Object.keys(G.pidTable).filter((k) => !/^\d+$/.test(k));
// 基线的 pidTable 是**名字→pid**，Swift 的 names 是 **pid→名字** —— 反过来比才是同一件事
const pidPairs = Object.entries(G.pidTable).filter(([k]) => k !== 'auto');
const pidMissing = pidPairs.filter(([k, v]) => pidSwift[+v] !== k);
if (G.pidTable.auto !== undefined && !(0 in pidSwift) && modelName(0) === '自动识别') console.log('   (基线 auto 下标在 Swift 侧是 modelName(0) 的分支, 不在 names 表里) ');
checks++;
if (pidMissing.length) { bad++; console.log('✗ pidTable 名字对不上: ' + pidMissing.map(([k, v]) => `${k}(${v})⇒Swift “${pidSwift[+v] ?? '缺'}”`).join(' | ')); }
else console.log(`ok  pidTable ${pidPairs.length} 个型号名字与 Swift PidMap.names 逐条相同 (基线另有 auto 下标)`);

// time
checks++;
if (G.time.epochMs !== EP_MS || G.time.protoFromMs_zero !== protoFromMs(Date.parse('2010-01-01T00:00:00Z'))) { bad++; console.log('✗ time 基准不同'); }
else console.log('ok  time 纪元 (epochMs 与 2010-01-01 ⇒ 0)');

// ---------------- 钥匙串 / 网关状态解析 (第一百七十六批新增) ----------------
// 这两条路径不在 fixtures/golden.json 里 (那份基线跑的是门锁状态帧)，所以这里**直接 require vendor 的解析函数**
// 当权威侧 —— 比"从夹具取期望"还少一层转抄。输入由本工具构造，两边吃同一个对象：
// 构造错只会让某条分支没被走到，不会把两边凑成假一致。
const KC = require(path.join(ROOT, 'vendor/app/services/keychain.js'));
const GWS = require(path.join(ROOT, 'vendor/app/services/gateway.js'));
const hexToAscii = (h) => { const b = hexBytes(h); let s = '';
  for (const x of b) { if (x >= 0x20 && x < 0x7f) s += String.fromCharCode(x); else return h; } return s; };
const dotted = (h) => (h.length !== 6 ? h : [4, 2, 0].map((o) => (Number.parseInt(h.substr(o, 2), 16) || 0)).join('.'));
const dotted3 = (h) => { const r = reversePairs(h); return r.length === 6 ? dotted(r) : ''; };
const pick = (klvs, key) => (klvs.find((x) => x.key === key) ?? null);

// Swift HardwareService.parseKCStatus 逐行复刻。基线另有 rc(KLV#03) 与 applyPids(KLV#36)：
//   · rc 在 Swift 侧不在 DongleStat 里，判它的是调用方 readDongleState 走 rcOf(f) (本批新加的失败闸)；
//   · applyPids 基线解析了但**没有任何消费点** (vendor 全仓只有这一处 push)，
//     Swift 侧不解析也不给 DongleStat 加一个没人读的持久化字段 —— 两边都按下不表，比对口径写明。
function kcStatus(klvs) {
  const direct = (key) => { const k = pick(klvs, key); return k === null ? null : intHex(k.val); };
  const f12 = pick(klvs, 0x12), f31 = pick(klvs, 0x31), f34 = pick(klvs, 0x34), f35 = pick(klvs, 0x35);
  return { power: direct(0x11) ?? -1,
           absPower: f12 === null ? -1 : leHexToU32(f12.val),
           ekeyCount: direct(0x24) ?? -1, ekeyAmount: direct(0x25) ?? -1,
           firmware: f31 === null ? '' : dotted3(f31.val),
           pid: f34 === null ? 0 : leHexToU32(f34.val),
           eCtrl: f35 === null ? '' : dotted3(f35.val) };
}
// Swift HardwareService.parseGWStatus 逐行复刻 (0x01 原 hex / 0x02 0x03 三字节点分否则 ASCII / 04 05 ASCII / 06 直读)
function gwStatus(klvs) {
  const s = { wifimac: '', romVer: '', eCtrlVer: '', ssid: '', wifiIP: '', netState: -1 };
  for (const k of klvs) {
    if (k.key === 0x01) s.wifimac = k.val;
    else if (k.key === 0x02) { const r = reversePairs(k.val); s.romVer = r.length === 6 ? dotted(r) : hexToAscii(k.val); }
    else if (k.key === 0x03) { const r = reversePairs(k.val); s.eCtrlVer = r.length === 6 ? dotted(r) : hexToAscii(k.val); }
    else if (k.key === 0x04) s.ssid = hexToAscii(k.val);
    else if (k.key === 0x05) s.wifiIP = hexToAscii(k.val);
    else if (k.key === 0x06) s.netState = intHex(k.val);
  }
  return s;
}
const KC_OMIT = ['rc', 'applyPids'], GW_OMIT = ['rc'];
const kcCases = [
  ['kc.full', [{ key: 0x03, val: '00' }, { key: 0x11, val: '64' }, { key: 0x12, val: 'f4ffffff' },
               { key: 0x24, val: '03' }, { key: 0x25, val: '20' }, { key: 0x31, val: '010203' },
               { key: 0x34, val: '613f' }, { key: 0x35, val: '0a0102' }]],
  ['kc.sparse_only_power', [{ key: 0x11, val: '32' }]],
  ['kc.firmware_2bytes', [{ key: 0x31, val: '0102' }, { key: 0x11, val: '64' }]],
  ['kc.ectrl_4bytes', [{ key: 0x35, val: '01020304' }]],
  ['kc.rc_fail_frame', [{ key: 0x03, val: '01' }, { key: 0x11, val: '64' }]],
  ['kc.abs_power_u32_wrap', [{ key: 0x12, val: '00000100' }]],
  ['kc.pid_2bytes', [{ key: 0x34, val: '613f' }]],
];
for (const [name, klvs] of kcCases) cmp(name, kcStatus(klvs), KC.parseKCStatus(klvs), KC_OMIT);
const gwCases = [
  ['gw.full', [{ key: 0x01, val: 'aabbccddeeff' }, { key: 0x02, val: '010203' }, { key: 0x03, val: '0a0102' },
               { key: 0x04, val: '46495f484f4d45' }, { key: 0x05, val: '3139322e3136382e312e35' }, { key: 0x06, val: '01' }]],
  ['gw.rom_4bytes_ascii', [{ key: 0x02, val: '41424344' }]],
  ['gw.rom_4bytes_nonprintable', [{ key: 0x02, val: '01020304' }]],
  ['gw.ectrl_2bytes', [{ key: 0x03, val: '4142' }]],
  ['gw.wifimac_looks_like_ascii_not_decoded', [{ key: 0x01, val: '303132333435' }]],
  ['gw.no_netstate', [{ key: 0x04, val: '4142' }]],
  ['gw.ssid_nonprintable_keeps_hex', [{ key: 0x04, val: '00ff' }]],
];
for (const [name, klvs] of gwCases) cmp(name, gwStatus(klvs), GWS.parseGWStatus(klvs), GW_OMIT);

// cmd 44 响应里的 MAC 列表 (Swift HardwareService.parseEkeyMacs ↔ vendor keychain.js 同名函数)。
// 数组不直接逐键比：Object.keys(数组) 是下标，Swift 多吐一条时那些下标会被算成"Swift 多出的键"而**不参与比较**，
// 于是"多一台假钥匙"看不见 ⇒ 先包成 {条数, 内容}，条数差也会红。
function ekeyMacs(klvs) {
  const k = pick(klvs, 0x04); if (k === null) return [];
  const h = k.val, out = [];
  for (let i = 0; i + 12 <= h.length; i += 12) out.push(h.substr(i, 12).toLowerCase());
  return out;
}
const wrapMacs = (a) => ({ n: a.length, list: a.join('|') });
const macCases = [
  ['ekey.two', [{ key: 0x04, val: 'aabbccddeeff001122334455' }]],
  ['ekey.uppercase_input_lowercased_out', [{ key: 0x04, val: 'AABBCCDDEEFF' }]],
  ['ekey.tail_5_bytes_dropped', [{ key: 0x04, val: 'aabbccddeeff0011223344' }]],
  ['ekey.empty_val', [{ key: 0x04, val: '' }]],
  ['ekey.no_klv_only_rc', [{ key: 0x03, val: '01' }]],
  ['ekey.three', [{ key: 0x04, val: '0102030405060708090a0b0c0d0e0f10111213141516' }]],
];
for (const [name, klvs] of macCases) cmp(name, wrapMacs(ekeyMacs(klvs)), wrapMacs(KC.parseEkeyMacs(klvs)));

console.log(`\n解析侧跨语言差分: ${checks - bad}/${checks} 组一致`);
console.log('口径差 (不参与比较，两边各自的形状): 基线 kcStatus 另有 rc 与 applyPids、gwStatus 另有恒 -1 的 rc；');
console.log('  rc 在 Swift 侧由调用方 rcOf 判 (第一百七十六批起 readDongleState 会因 rc>0 直接拒绝这份读数)，');
console.log('  applyPids 基线自己也没有消费点。未覆盖: 手机侧失败行 kf_fevents_、缓存合并与分页游标。');
console.log('边界: 算法与基线一致 ≠ 锁端真会发这些帧；那要真锁。');
process.exit(bad ? 1 : 0);
