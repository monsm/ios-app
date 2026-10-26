#!/usr/bin/env node
/* 功能蜘蛛网 · 合并器
 * 读取 inventory/*.json（侦察兵产物），合并为 features.json（供 HTML 渲染）。
 * 规则见 BRIEF.md。此脚本不做“文档取证”，只做结构校验与合并。
 */
const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const INV = path.join(ROOT, 'inventory');
const OUT = path.join(ROOT, 'features.json');

const DOMAINS = [
  { key: 'device',     name: '设备与连接', short: '设备', color: '#5aa9ff', icon: '⌂' },
  { key: 'unlock',     name: '开锁与鉴权', short: '开锁', color: '#54e0c7', icon: '◉' },
  { key: 'credential', name: '凭证',       short: '凭证', color: '#f2b24b', icon: '⚿' },
  { key: 'member',     name: '成员与家庭', short: '成员', color: '#f07fb1', icon: '◈' },
  { key: 'record',     name: '记录与统计', short: '记录', color: '#a98bff', icon: '◷' },
  { key: 'security',   name: '安全与防御', short: '安全', color: '#ff6b6b', icon: '⛨' },
  { key: 'backup',     name: '备份与迁移', short: '备份', color: '#66d98a', icon: '↧' },
  { key: 'care',       name: '关怀与维护', short: '关怀', color: '#4fd1d9', icon: '♡' },
  { key: 'diagnostic', name: '诊断与工具', short: '诊断', color: '#ff9f5a', icon: '⚗' },
  { key: 'settings',   name: '设置与偏好', short: '设置', color: '#9fb0c8', icon: '⚙' },
  { key: 'protocol',   name: '协议与命令', short: '协议', color: '#e8c56a', icon: '⌁' },
  { key: 'data',       name: '数据与存储', short: '数据', color: '#c08a6a', icon: '▤' },
  { key: 'apk',        name: '原版 APK 基线', short: 'APK', color: '#8f7bd8', icon: '◫' },
];
const DOMAIN_KEYS = new Set(DOMAINS.map(d => d.key));

function readInventory() {
  if (!fs.existsSync(INV)) return [];
  return fs.readdirSync(INV)
    .filter(f => f.endsWith('.json'))
    .sort()
    .map(f => {
      const p = path.join(INV, f);
      try {
        const j = JSON.parse(fs.readFileSync(p, 'utf8'));
        j.__file = f;
        return j;
      } catch (e) {
        console.error(`✗ ${f} JSON 解析失败: ${e.message}`);
        return null;
      }
    })
    .filter(Boolean);
}

function normEvidence(e) {
  if (!e) return null;
  if (typeof e === 'string') {
    const m = e.match(/^(.+?):(\d+)(?::(.*))?$/);
    if (!m) return { file: e, line: 0, symbol: '', note: '' };
    return { file: m[1], line: Number(m[2]), symbol: '', note: m[3] || '' };
  }
  return {
    file: String(e.file || ''),
    line: Number(e.line || 0) || 0,
    symbol: String(e.symbol || ''),
    note: String(e.note || ''),
  };
}
const evId = e => `${e.file}:${e.line}`;

function normalizeCmdKey(k) {
  return String(k).replace(/^(protocol\.cmd)([0-9A-Fa-f]{2})/, (m, p, h) => p + h.toLowerCase());
}

function normNode(n, scout) {
  const platform = n.platform || scout.platform || 'ios';
  const level = Math.max(1, Math.min(4, Number(n.level) || 3));
  const key = normalizeCmdKey(String(n.key || '').trim());
  if (!key) return null;
  return {
    key,
    parentKey: n.parentKey ? String(n.parentKey) : '',
    domain: DOMAIN_KEYS.has(n.domain) ? n.domain : (DOMAIN_KEYS.has(key.split('.')[0]) ? key.split('.')[0] : (key.split('.')[0]==='platform' ? 'settings' : 'device')),
    level,
    name: String(n.name || key).trim(),
    kind: String(n.kind || 'feature'),
    summary: String(n.summary || '').trim(),
    details: Array.isArray(n.details) ? n.details.map(String) : (n.details ? [String(n.details)] : []),
    evidence: (Array.isArray(n.evidence) ? n.evidence : [n.evidence]).map(normEvidence).filter(Boolean),
    tags: Array.isArray(n.tags) ? n.tags.map(String) : [],
    status: ['implemented', 'partial', 'edge', 'deprecated'].includes(n.status) ? n.status : 'implemented',
    platform,
    source: scout.scout || scout.__file,
  };
}

function merge(all) {
  const map = new Map();
  for (const scout of all) {
    if (!Array.isArray(scout.nodes)) continue;
    for (const raw of scout.nodes) {
      const n = normNode(raw, scout);
      if (!n) continue;
      if (!map.has(n.key)) {
        map.set(n.key, {
          key: n.key,
          parentKey: n.parentKey,
          domain: n.domain,
          level: n.level,
          name: n.name,
          kind: n.kind,
          summary: n.summary,
          details: [...n.details],
          tags: new Set(n.tags),
          statuses: { [n.platform]: n.status },
          platforms: { ios: [], android: [], apk: [] },
          sources: new Set([n.source]),
        });
      }
      const t = map.get(n.key);
      // 名称/摘要取更长更具体的那份
      // 名称优先取原生端（ios/android）；apk 只在没有原生名时才当名字
      if (n.platform !== 'apk') {
        if (!t.nameSrc || t.nameSrc === 'apk' || n.name.length > t.name.length) t.name = n.name;
        t.nameSrc = n.platform;
      } else if (!t.nameSrc) {
        t.name = n.name;
      }
      if (n.summary.length > t.summary.length) t.summary = n.summary;
      if (n.level < t.level) t.level = n.level;
      if (!t.parentKey && n.parentKey) t.parentKey = n.parentKey;
      if (DOMAIN_KEYS.has(n.domain) && !DOMAIN_KEYS.has(t.domain)) t.domain = n.domain;
      n.details.forEach(d => { if (d && !t.details.includes(d)) t.details.push(d); });
      n.tags.forEach(x => t.tags.add(x));
      t.statuses[n.platform] = n.status;
      t.sources.add(n.source);
      const seen = new Set(t.platforms[n.platform].map(evId));
      for (const e of n.evidence) {
        if (!seen.has(evId(e))) { t.platforms[n.platform].push(e); seen.add(evId(e)); }
      }
    }
  }

  // 补 domain 根
  for (const d of DOMAINS) {
    if (!map.has(d.key)) {
      map.set(d.key, {
        key: d.key, parentKey: '', domain: d.key, level: 1, name: d.name, kind: 'domain',
        summary: '', details: [], tags: new Set(), statuses: {}, platforms: { ios: [], android: [], apk: [] },
        sources: new Set(), isDomain: true,
      });
    }
    const t = map.get(d.key);
    t.level = 1; t.name = d.name; t.isDomain = true;
  }

  // parent 修补：缺失/自指/环 → 挂到 domain
  for (const [k, t] of map) {
    if (t.isDomain) { t.parentKey = ''; continue; }
    if (t.parentKey === 'platform') t.parentKey = 'settings';
    if (t.parentKey === 'apk' && !map.has('apk')) t.parentKey = t.domain;
    let p = t.parentKey;
    if (!p || !map.has(p) || p === k) {
      // 试从 key 的父路径找
      const parts = k.split('.');
      let found = '';
      for (let i = parts.length - 1; i >= 1; i--) {
        const cand = parts.slice(0, i).join('.');
        if (map.has(cand)) { found = cand; break; }
      }
      t.parentKey = found && found !== k ? found : t.domain;
    }
  }
  // 环检测
  for (const [k, t] of map) {
    let cur = t, hops = 0, seen = new Set([k]);
    while (cur && cur.parentKey && hops++ < 32) {
      if (seen.has(cur.parentKey)) { t.parentKey = t.domain; break; }
      seen.add(cur.parentKey);
      cur = map.get(cur.parentKey);
    }
  }

  // 有子节点却不是 3 级 → 提升
  const childCount = new Map();
  for (const [k, t] of map) if (t.parentKey) childCount.set(t.parentKey, (childCount.get(t.parentKey) || 0) + 1);
  for (const [k, t] of map) {
    if (!t.isDomain && childCount.get(k) && t.level > 3) t.level = 3;
  }

  // domain 归属沿父链修正
  const domainOf = new Map();
  function resolveDomain(k, depth = 0) {
    if (domainOf.has(k)) return domainOf.get(k);
    const t = map.get(k);
    if (!t || depth > 32) return 'device';
    let d;
    if (t.isDomain) d = t.key;
    else d = DOMAIN_KEYS.has(t.domain) ? t.domain : resolveDomain(t.parentKey, depth + 1);
    domainOf.set(k, d);
    return d;
  }

  const nodes = [];
  for (const [k, t] of map) {
    const d = resolveDomain(k);
    t.domain = d;
    // 平台证据扁平化（详情面板用）
    const evAll = [];
    for (const plat of ['ios', 'android', 'apk']) {
      for (const e of t.platforms[plat]) evAll.push({ platform: plat, ...e, text: srcLine(e.file, e.line) });
    }
    // 去重后计数
    const platMap = {};
    for (const plat of ['ios', 'android', 'apk']) {
      if (t.platforms[plat].length) platMap[plat] = t.platforms[plat].length;
    }
    const detailText = t.details.join(' ') + ' ' + t.summary + ' ' + k;
    const commands = [...new Set((detailText.match(/cmd\s?0?([0-9A-Fa-f]{2})\b/g) || [])
      .map(x => x.replace(/cmd\s?/i, '').toUpperCase())
      .filter(x => /^[0-9A-F]{2}$/.test(x)))];
    nodes.push({
      id: k, key: k, parent: t.parentKey || null, domain: d, level: t.level,
      name: t.name, kind: t.kind, summary: t.summary, details: t.details,
      evidence: (() => {
        // 先保证「每个被引文件至少露一条」，再按平台配额补足 —— 否则同文件多条会把别处挤掉
        const seenFile = new Set();
        const out = [];
        for (const e of evAll) {
          const k = e.platform + '|' + e.file;
          if (seenFile.has(k)) continue;
          seenFile.add(k);
          out.push(e);
        }
        const used = new Set(out.map(e => e.platform + '|' + e.file + '|' + e.line));
        const quota = { ios: 5, android: 4, apk: 3 };
        const cnt = { ios: 0, android: 0, apk: 0 };
        for (const e of out) cnt[e.platform]++;
        for (const e of evAll) {
          const id = e.platform + '|' + e.file + '|' + e.line;
          if (used.has(id)) continue;
          if (cnt[e.platform] >= quota[e.platform]) continue;
          used.add(id); out.push(e); cnt[e.platform]++;
        }
        return out.slice(0, 14);
      })(), platformEvidence: t.platforms,
      platforms: Object.keys(platMap), platformCount: Object.keys(platMap).length,
      tags: [...t.tags], status: t.statuses, commands,
      sources: [...t.sources],
      childCount: childCount.get(k) || 0,
      isDomain: !!t.isDomain,
    });
  }

  // leaf count for angular allocation
  const byParent = new Map();
  for (const n of nodes) {
    if (!n.parent) continue;
    if (!byParent.has(n.parent)) byParent.set(n.parent, []);
    byParent.get(n.parent).push(n);
  }
  const leafCache = new Map();
  function leaves(k, guard = 0) {
    if (leafCache.has(k)) return leafCache.get(k);
    if (guard > 64) return 1;
    const ch = byParent.get(k) || [];
    if (!ch.length) { leafCache.set(k, 1); return 1; }
    const s = ch.reduce((a, c) => a + leaves(c.key, guard + 1), 0);
    leafCache.set(k, s);
    return s;
  }
  for (const n of nodes) n.weight = n.isDomain ? 1 : Math.max(1, leaves(n.key));

  // 路径
  const byKey = new Map(nodes.map(n => [n.key, n]));
  for (const n of nodes) {
    const p = []; let cur = n, guard = 0;
    while (cur && guard++ < 32) { p.unshift(cur.name); cur = cur.parent ? byKey.get(cur.parent) : null; }
    n.path = p.join(' › ');
  }

  // 排序：域顺序 + level + 权重降序
  const dOrder = new Map(DOMAINS.map((d, i) => [d.key, i]));
  nodes.sort((a, b) =>
    dOrder.get(a.domain) - dOrder.get(b.domain) ||
    a.level - b.level ||
    b.weight - a.weight ||
    a.name.localeCompare(b.name, 'zh'));

  // 跨域/命令连线
  const links = [];
  for (const n of nodes) if (n.parent) links.push({ source: n.parent, target: n.key, type: 'tree' });
  const cmdNodes = new Map(nodes.filter(n => /^protocol\.cmd[0-9A-F]{2}$/i.test(n.key)).map(n => [n.commands[0] || n.key.slice(-2).toUpperCase(), n.key]));
  for (const n of nodes) {
    if (n.domain === 'protocol' || n.isDomain) continue;
    for (const c of n.commands) {
      const target = cmdNodes.get(c);
      if (target) links.push({ source: n.key, target, type: 'cmd' });
    }
  }

  // 跨端对照分组
  const ORD = {ios:0, android:1, apk:2};
  const setOf = n => n.platforms.slice().sort((a,b)=>ORD[a]-ORD[b]).join('+');
  const platSets = {};
  for (const n of nodes) {
    if (n.isDomain || !n.platforms.length) continue;
    const k = setOf(n);
    (platSets[k] ||= []).push(n.key);
  }

  // 跨端能力缺口：按「功能簇」比较，避免 key 命名差异造成假缺口
  const CLUSTERS = [
    { id:'unlock.finder',  name:'FindMy 式信号箭头',     re:/finder|精确查找|信号箭头/i },
    { id:'unlock.airtag',  name:'AirTag 式全屏查找层',   re:/airtag/i },
    { id:'unlock.bind.qr', name:'扫码绑定（二维码钥匙）', re:/bind\.qr|扫码绑定|二维码.*绑定/i },
    { id:'unlock.manual',  name:'手动开锁动作',          re:/manual|手动开锁/i },
    { id:'unlock.proximity', name:'靠近自动开锁',        re:/proximity|autoopen|靠近自动/i },
    { id:'unlock.unbind',  name:'解绑设备',              re:/unbind|解绑|删除设备/i },
    { id:'device.manage',  name:'门锁设置抽屉',          re:/device\.manage|设置抽屉/i },
    { id:'unlock.dial',    name:'开锁圆盘',              re:/^unlock\.dial/ },
    { id:'credential',     name:'凭证管理（密码/指纹/临时码）', re:/^credential\.(list|pwd|fp|tempcode|queue|bin|history)/ },
    { id:'record',         name:'记录与日志',            re:/^record\./ },
    { id:'member',         name:'成员与家庭',            re:/^member\./ },
    { id:'backup',         name:'备份与恢复',            re:/^backup\./ },
    { id:'security',       name:'安全中心 / 审计 / 销毁', re:/^security\.|^data\.audit/ },
    { id:'diagnostic',     name:'诊断与体检',            re:/^diagnostic\./ },
    { id:'care',           name:'关怀与电量',            re:/^care\./ },
    { id:'settings',       name:'设置与外观',            re:/^settings\./ },
    { id:'gateway',        name:'智能网关',              re:/gateway|网关/i },
    { id:'keychainHW',     name:'蓝牙钥匙串硬件',        re:/keychain/i },
    { id:'synctime',       name:'校时',                  re:/synctime|校时|同步时间/i },
    { id:'dfu',            name:'固件升级 DFU',          re:/dfu|firmware|固件/i },
    { id:'otp',            name:'临时码 / OTP',          re:/otp|tempcode|临时码/i },
  ];
  const gaps = CLUSTERS.map(c => {
    const inCluster = nodes.filter(n => !n.isDomain && c.re.test(n.key + ' ' + n.name));
    const plats = new Set();
    for (const n of inCluster) n.platforms.forEach(p => plats.add(p));
    const peer = [...plats].filter(p => p !== 'apk');
    return { id: c.id, name: c.name, count: inCluster.length, platforms: [...plats].sort(), peers: peer.sort() };
  }).filter(g => g.count > 0);

  const stats = {
    nodes: nodes.length,
    domains: DOMAINS.length,
    modules: nodes.filter(n => n.level === 2).length,
    features: nodes.filter(n => n.level === 3).length,
    details: nodes.filter(n => n.level === 4).length,
    byPlatform: {
      ios: nodes.filter(n => n.platformEvidence.ios.length).length,
      android: nodes.filter(n => n.platformEvidence.android.length).length,
      apk: nodes.filter(n => n.platformEvidence.apk.length).length,
    },
    byDomain: Object.fromEntries(DOMAINS.map(d => [d.key, nodes.filter(n => n.domain === d.key).length])),
    evidence: nodes.reduce((a, n) => a + n.evidence.length, 0),
    commands: nodes.filter(n => /^protocol\.cmd/.test(n.key)).length,
    platSets,
    gaps,
  };

  return {
    meta: {
      title: '离线锁管家 · iOS × Android 功能蜘蛛网',
      generated: new Date().toISOString(),
      sources: all.map(a => ({ scout: a.scout, platform: a.platform, file: a.__file, nodes: (a.nodes || []).length })),
      unresolved: all.flatMap(a => (a.unresolved || []).map(u => `${a.scout}: ${u}`)),
      notes: all.flatMap(a => (a.notes || []).map(u => `${a.scout}: ${u}`)),
    },
    domains: DOMAINS,
    nodes,
    links,
    stats,
  };
}

const SRC = new Map();
function srcLine(file, line) {
  if (!file) return '';
  if (!SRC.has(file)) {
    try { SRC.set(file, fs.readFileSync(path.join('D:/aapk/ios-app', file), 'utf8').split('\n')); }
    catch (e) { SRC.set(file, null); }
  }
  const arr = SRC.get(file);
  if (!arr) return '';
  const t = (arr[line - 1] || '').trim();
  return t.length > 220 ? t.slice(0, 220) + ' …' : t;
}

const inv = readInventory();
if (!inv.length) { console.error('inventory/ 里还没有可用的 JSON'); process.exit(1); }
const out = merge(inv);
fs.writeFileSync(OUT, JSON.stringify(out, null, 2));
console.log(`✓ ${OUT}`);
console.log(`  节点 ${out.stats.nodes} = 域 ${out.stats.domains} / 模块 ${out.stats.modules} / 功能 ${out.stats.features} / 细节 ${out.stats.details}`);
console.log(`  平台：iOS ${out.stats.byPlatform.ios} · Android ${out.stats.byPlatform.android} · APK ${out.stats.byPlatform.apk}`);
console.log(`  证据 ${out.stats.evidence} 条；命令节点 ${out.stats.commands}`);
for (const d of out.domains) console.log(`  ${d.short}: ${out.stats.byDomain[d.key]}`);
