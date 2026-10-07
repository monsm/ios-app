// 开门事件归属推断 (2026-09-03) — 「谁开的门」只在**可证明**时给出, 绝不猜测:
//   锁内 cmd16 日志不带身份字段 (无 alias/批次指纹), 只能靠本地台账反推, 两条可证规则:
//   R1 一次性密码窗口: 事件时刻落在某条「给成员发的 10 分钟临时码」[from,to] 内且唯一命中 →
//     归属该成员。证据在本机台账, 离线/缓存态同样可信。
//   R2 锁内唯一凭证 + 实时背书: 本次会话实时 03 显示锁内该型凭证只剩 1 个, 台账把它归给唯一成员,
//     且事件发生时间距实时读数**足够近** (默认 ≤3 天, 防凭证此后被删/增导致冤枉人) → 归属该成员。
//     需要现场读数 — 离线/旧快照一律关闭本规则。
//   其余开门事件保持中性 (可在记录页「无法识别」里看到, 但绝不明文点名)。
// 本模块纯 Node 可测; 首页「最近开门」卡片与 记录 Tab 共用同一实现, 不各自漂移。
const TIME = require('../utils/time.js');

// cmd16 开门事件型 → 开门凭证种类 (用于人话「用 X 开了门」)
// 2026-09-09 勘误: 旧表 {11:key,16:temp,17:pwd,19:fp} 是预研阶段的错枚举 —
// main.js 开具枚举为 1=数字钥匙/2=密码/3=指纹/4=临时密码/5=NFC, 实锁按此落地。
const OPEN_KIND = { 1: 'key', 2: 'pwd', 3: 'fp', 4: 'temp' };
const WORD = { fp: '指纹', pwd: '密码', temp: '一次性密码', key: '数字钥匙' };
// R2 新鲜度阈值: 事件锁钟与实时读数相差不得超过该秒数 (3 天)
const UNIQUE_MAX_AGE_SEC = 3 * 86400;

function keyOf(e) { return (e && e.idxRaw !== undefined) ? e.idxRaw : (e ? e.idx : undefined); }
// 'YYYY-MM-DD HH:mm[:ss]' (UTC) → ms; 非法返回 NaN
function msOf(s) {
  const t = new Date(String(s || '').replace(' ', 'T') + 'Z').getTime();
  return Number.isFinite(t) ? t : NaN;
}
function _fresh(status, lockTime, ageMax) {
  const now = status && status.lockTime != null ? status.lockTime : null;
  if (now == null || lockTime == null) return false;
  const age = Number(now) - Number(lockTime);
  return age >= 0 && age <= ageMax;
}

// 输入: logs = cmd16 原始事件 [{idxRaw|idx, type, lockTime(协议秒), ...}]
// ctx = { pwds: 台账密码, fps: 台账指纹, status: 实时 03 | null, ageMaxSec? }
// 返回: 与 logs 一一对应的 [{key, type, lockTime, kind, who(成员id|null), provable('temp'|'unique'|null)}]
function classify(logs, ctx) {
  const c = ctx || {};
  const pwds = Array.isArray(c.pwds) ? c.pwds : [];
  const fps = Array.isArray(c.fps) ? c.fps : [];
  const status = (c.status && typeof c.status === 'object') ? c.status : null; // null = 非实时 → R2 关闭
  const ageMax = c.ageMaxSec !== undefined ? Number(c.ageMaxSec) : UNIQUE_MAX_AGE_SEC;
  const temps = pwds.filter(p => p && p.temp && p.owner);
  const permOwned = pwds.filter(p => p && !p.temp && p.owner);
  const fpOwned = fps.filter(f => f && f.owner);

  return (logs || []).map(e => {
    const kind = OPEN_KIND[e.type] || null;
    const out = { key: keyOf(e), type: e.type, lockTime: e.lockTime, kind, who: null, provable: null };
    if (!kind) return out;
    // R1 临时码窗口 (4 临时密码开门 / 2 密码开门 都可能由临时码完成)
    if (kind === 'temp' || kind === 'pwd') {
      const t = TIME.protoSecondsToMs(e.lockTime);
      const hits = temps.filter(p => {
        const f = msOf(p.from), to = msOf(p.to);
        if (!Number.isFinite(f) || !Number.isFinite(to)) return false;
        return f <= t && t <= to;
      });
      if (hits.length === 1) { out.who = hits[0].owner; out.provable = 'temp'; }
    }
    // R2 锁内唯一凭证 (需本次会话实时 03 + 事件够新)
    if (!out.who && status && _fresh(status, e.lockTime, ageMax)) {
      if (kind === 'fp' && Number(status.fpStock) === 1 && fpOwned.length === 1) {
        out.who = fpOwned[0].owner; out.provable = 'unique';
      } else if (kind === 'pwd' && Number(status.pwdStock) === 1 && permOwned.length === 1) {
        out.who = permOwned[0].owner; out.provable = 'unique';
      }
    }
    return out;
  });
}
module.exports = { classify, OPEN_KIND, WORD, UNIQUE_MAX_AGE_SEC };
