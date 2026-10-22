// 复刻内容抽取 (模块) —— build.js 与 index.html 的唯一内容源
// 原则: 只从 Swift 源码取字符串, 取不到就标"未抽到", 绝不用想象的文字填空。
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '../..');
const rd = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8').split(/\r?\n/);

function scan(line) {
  let i = 0, inStr = false, s = -1, d = 0, cs = -1; const ranges = [];
  while (i < line.length) {
    const c = line[i];
    if (inStr) {
      if (c === '\\') { if (line[i + 1] === '(') d++; i += 2; continue; }
      if (d > 0 && c === ')') { d--; i++; continue; }
      if (d === 0 && c === '"') { ranges.push([s, i]); inStr = false; i++; continue; }
      i++; continue;
    }
    if (c === '"') { inStr = true; s = i; i++; continue; }
    if (c === '/' && line[i + 1] === '/') { cs = i; break; }
    i++;
  }
  return { ranges, commentStart: cs };
}
// 去掉字符串内容后的纯代码 (数括号用)
const dequote = (line) => {
  const { ranges, commentStart } = scan(line);
  let out = line, cut = [];
  for (const [s, e] of ranges) { if (commentStart >= 0 && s >= commentStart) continue; cut.push([s, e]); }
  for (const [s, e] of cut.reverse()) out = out.slice(0, s) + '\u0001' + out.slice(e + 1);
  return commentStart >= 0 ? out.slice(0, Math.min(commentStart, out.length)) : out;
};
function label(line) {
  const { ranges, commentStart } = scan(line);
  const m = /(?:Label|Text|Toggle|Button|Section|NavigationLink|Picker|Menu|LabeledRow|SectionTitle|EmptyState|HeroStat|HeroPill)\s*\(\s*(?:.*?label:\s*)?"([^"]{2,40})"/.exec(line);
  if (m && !(commentStart >= 0 && line.indexOf('"' + m[1]) > commentStart)) { const t = clean(m[1]); if (usable(t)) return t; }
  for (const [s, e] of ranges) {
    if (commentStart >= 0 && s >= commentStart) continue;
    const b = clean(line.slice(s + 1, e));
    if (usable(b)) return b;
  }
  return null;
}
const clean = (b) => b.replace(/\\\((?:[^()\\]|\\.|\((?:[^()\\]|\\.)*\))*\)/g, '…').replace(/\\"/g, '"').trim();
// 脏数据闸: 未闭合的插值残段 / 纯 SF Symbol 名 / 只有代码符号的串, 一律不当可见文字
function usable(t) {
  if (!t || t.length < 2 || t.length > 40) return false;
  if (/\\?\(/.test(t) || /[{}<>]/.test(t)) return false;              // \(…) 跨行没闭合
  if (/^[a-z0-9.]+$/.test(t) && /\./.test(t)) return false;          // "arrow.down.circle" 这类图标名
  if (/^[\s\d.,%:;·、–—…+/*-]+$/.test(t)) return false;               // 只有数字标点
  if (!/[\u4e00-\u9fa5]/.test(t) && /^[a-z][a-z0-9]*$/.test(t)) return false;  // 纯小写单词 = 存储键 (hold/soft/tall/build), 不是给用户看的
  if (/\$\w|^\w:$/.test(t)) return false;
  return true;
}
function bodyRange(lines, nameRe, maxLines) {
  const i = lines.findIndex((L) => nameRe.test(L));
  if (i < 0) return null;
  let d = 0, seen = false;
  for (let k = i; k < Math.min(lines.length, i + (maxLines || 400)); k++) {
    const c = dequote(lines[k]);
    for (const ch of c) { if (ch === '{') { d++; seen = true; } else if (ch === '}') d--; }
    if (seen && d <= 0) return [i, k];
  }
  return [i, Math.min(lines.length - 1, i + 60)];
}
function labelsOf(lines, range, cap) {
  if (!range) return [];
  const seen = new Set(), out = [];
  for (let k = range[0]; k <= range[1]; k++) {
    const L = lines[k];
    if (/^\s*(\/\/|\/\*|\*)/.test(L)) continue;
    if (!/(Label|Text|Toggle|Button|LabeledRow|SectionTitle|EmptyState|HeroStat|HeroPill|DisclosureGroup|NavigationLink)\s*[({]/.test(L)) continue;
    const t = label(L);
    if (!t || seen.has(t)) continue;
    seen.add(t); out.push(t);
    if (out.length >= (cap || 16)) break;
  }
  return out;
}

function extract() {
  const res = { tabs: [], settings: [], device: [], quickAll: [], quickDefault: [], credentials: [], records: [] };
  // Tab 栏
  const lk = rd('App/LockKeeperApp.swift');
  // 2026-10-22: 原内容源是四 Tab + CredentialsView/RecordsView/DeviceHomeView 的模块表 ——
  // 那三代界面全部随单控制台重构删掉了, 于是这个复刻器连着一个月跑不起来。
  // 现役结构: 门厅(HomeConsole) + 管理台(ManagerFace 5 组) + 各叶页。
  // 复刻页要回答的是"真实界面的密度/层级对不对", 所以取**有真实字符串的那些块**。
  res.tabs = [];   // 4 Tab 已删; 复刻页改为展示管理台的 5 个分组

  // 通用: 一个文件里所有 xxxSection 属性（原来的实现，我上一版误删了它）
  function sections(file, cap) {
    const lines = rd(file);
    const out = [];
    lines.forEach((L, i) => {
      const m = /(?:private )?var (\w+Section): some View/.exec(L);
      if (!m) return;
      const range = bodyRange(lines, new RegExp(`var ${m[1]}: some View`), 300);
      if (!range) return;
      let title = null;
      for (let k = range[0]; k <= range[1] && !title; k++) {
        const t = /Section\("([^"]{2,26})"/.exec(lines[k]); if (t) title = clean(t[1]);
      }
      for (let k = range[0]; k <= range[1] && !title; k++) {
        if (!/\}\s*header:\s*\{/.test(lines[k])) continue;
        for (let j = k; j <= Math.min(k + 3, range[1]); j++) { const h = /Text\("([^"]{2,26})"\)/.exec(lines[j]); if (h) { title = clean(h[1]); break; } }
      }
      out.push({ prop: m[1], src: path.basename(file) + ':' + (i + 1), title: title || m[1], rows: labelsOf(lines, [range[0] + 1, range[1]], cap || 24) });
    });
    return out;
  }

  function sectionsOf(file, cap) { return sections(file, cap); }

  // 管理台 5 组 (ManagerFace 的 rows([...]) 里的 (route, 标题, 副标题, 图标))
  {
    const mf = rd('App/UI/ManagerFace.swift').join(String.fromCharCode(10));
    const groups = [];
    const gm = /case \.(\w+):\s*\n\s*rows\(\[([\s\S]*?)\]\)/g;
    let g;
    while ((g = gm.exec(mf))) {
      const rows = [];
      for (const r of g[2].matchAll(/\(\s*\.(\w+),\s*"([^"]+)",\s*"([^"]+)",\s*"([^"]+)"\s*\)/g)) {
        rows.push({ route: r[1], title: clean(r[2]), subtitle: clean(r[3]), icon: r[4] });
      }
      if (rows.length) groups.push({ prop: g[1], title: g[1], src: 'ManagerFace.swift', rows: rows.map(r => r.title) });
    }
    res.settings = groups.slice(0, 8);
  }

  res.credentials = sectionsOf('App/UI/KeysPage.swift', 14);
  res.records = sectionsOf('App/UI/EventsPage.swift', 14);

  // 设备页: 按 body 里的出现顺序取模块, 每个模块再取自己的可见文字
  const dv = rd('App/UI/DeviceHomeView.swift');
  const MODS = [
    ['migrationWizard', '换机迁移验证向导', '一次性'], ['capsuleSwitcher', '设备切换胶囊', '必留'],
    ['groupChips', '按组切换', '可隐'], ['statusIconRow', '多锁状态图标行', '可隐'],
    ['heroPager', '状态卡 (Hero 槽)', '必留'], ['attentionCard', '异常待办卡', '必留'],
    ['linkSenseCard', '连接感知区', '可隐'], ['unlockDial', '开锁圆盘', '必留'],
    ['quickActions', '快捷操作格 (快捷槽)', '必留'], ['recentCard', '最近开门 (最近槽)', '必留'],
    ['nightCheckRow', '安心夜打卡', '可隐'], ['familyCareRows', '家庭关怀行', '可隐'],
    ['privacyFootnote', '隐私脚注', '可隐'],
  ];
  const bodyEnd = dv.findIndex((L) => /^\s*\.refreshable/.test(L));
  // heroPager/quickActions/recentCard 不在 body 里直写, 而是经 moduleSlot 的 switch 渲染 ⇒ 出处落到那个 case
  const SLOT = { heroPager: 'hero', quickActions: 'quick', recentCard: 'recent' };
  for (const [key, name, kind] of MODS) {
    // 顺序: 在 body (前 bodyEnd 行) 里找它被渲染的那一行
    let at = dv.findIndex((L, i) => i < bodyEnd && new RegExp(`(^|[^\\w.])${key}\\b`).test(L) && !/private var|func /.test(L));
    if (at < 0 && SLOT[key]) {
      const s = dv.findIndex((L) => /private func moduleSlot/.test(L));
      const c = dv.findIndex((L, i) => i > s && new RegExp(`case "${SLOT[key]}":`).test(L));
      if (c >= 0) at = c;
    }
    const range = bodyRange(dv, new RegExp(`(private )?var ${key}[:(]`), 260);
    res.device.push({ key, name, kind, bodyLine: at >= 0 ? at + 1 : null, src: range ? `DeviceHomeView.swift:${range[0] + 1}-${range[1] + 1}` : '未找到', labels: labelsOf(dv, range, 14) });
  }
  // 快捷格池
  const qp = rd('App/Core/QuickPool.swift').join('\n');
  res.quickAll = [...qp.matchAll(/QuickAction\(id: "(\w+)",\s*icon: "([^"]+)",\s*label: "([^"]+)"/g)].map((m) => ({ id: m[1], icon: m[2], label: m[3] }));
  const dm = /static let defaultIds = \[([^\]]+)\]/.exec(qp);
  res.quickDefault = dm ? [...dm[1].matchAll(/"(\w+)"/g)].map((m) => m[1]) : [];
  return res;
}
module.exports = { extract };
if (require.main === module) {
  const r = extract();
  console.log('Tab', r.tabs.map((t) => t.title).join('/'));
  console.log('设置节', r.settings.length, '· 凭证节', r.credentials.length, '· 记录节', r.records.length);
  r.settings.forEach((s) => console.log(`   ${s.prop.padEnd(20)}「${s.title}」 ${s.rows.length} 行  ← ${s.src}`));
  console.log('设备模块', r.device.length);
  r.device.forEach((m) => console.log(`   ${String(m.bodyLine).padStart(4)} ${m.kind.padEnd(4)} ${m.name.padEnd(16)} ${m.labels.length} 条: ${m.labels.slice(0, 4).join(' · ')}`));
  console.log('快捷格', r.quickAll.length, '默认', r.quickDefault.join(','));
}
if (require.main === module) {
  const r = extract();
  console.log(JSON.stringify(r, null, 1).slice(0, 1200));
  console.log('...\nTab', r.tabs.length, '| 设置节', r.settings.length, '| 设备模块', r.device.length, '| 凭证节', r.credentials.length, '| 记录节', r.records.length, '| 快捷格', r.quickAll.length);
}
