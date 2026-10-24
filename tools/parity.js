'use strict';
// tools/parity.js —— HTML 原型 ↔ SwiftUI 实现的逐页对照
//
// ⚠ 口径（用户 2026-10-24 明确）：
//   · **审美**以 HTML 原型为标准 —— 卡头、区块标签、大数字、配色、组件形态必须对齐
//   · **功能/业务**以真实 App 为准 —— 本工具**不判**导航是否一致（HTML 的链接只是原型脚手）
// 所以下面只比"审美结构"，不比 href/导航。
//
// 做法：
//   · 从 tools/proto/*.html 提取：卡头（cardlink）、区块标签（clabel/ctitle）、
//     大数字、可点入口（href + 文字）
//   · 从 App/UI/*.swift 提取：XScreen 标题、区块标签（secLabel/XCardLink/Text）、
//     大数字（XHeroNumber/XValueUnit 值）、可点入口（NavigationLink 目标 + Button）
//   · 按页面配对后逐项比对，输出「HTML 有 / App 无」与「App 有 / HTML 无」
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const PROTO = path.join(ROOT, 'tools/proto');
const UI = path.join(ROOT, 'App/UI');

const reg = JSON.parse(fs.readFileSync(path.join(PROTO, 'registry.json'), 'utf8'));

// ---------- HTML 侧 ----------
function htmlProfile(file) {
  const s = fs.readFileSync(path.join(PROTO, file + '.html'), 'utf8');
  const cards = [...s.matchAll(/class="cardlink"[^>]*>([^<]{1,20})/g)].map(m => m[1].trim());
  const labels = [...s.matchAll(/class="clabel"[^>]*>([^<]{1,14})/g)].map(m => m[1].trim());
  const titles = [...s.matchAll(/class="ctitle"[^>]*>([^<]{1,24})/g)].map(m => m[1].trim());
  const bigs = [...s.matchAll(/font-size:(\d{2,3})px;font-weight:7/g)].map(m => m[1]);
  // 先把 TabBar 与 Navbar 整段删掉 —— 它们是页面框架，不是"内容入口"
  const bodyOnly = s
    .replace(/<div class="tabbar">[\s\S]*?<\/div>\s*(?=<script|$)/g, '')
    .replace(/<div class="navbar">[\s\S]*?<\/div>/g, '');
  const links = [...bodyOnly.matchAll(/href="([a-z0-9\-]+\.html)"[^>]*>\s*(?:<[^>]*>\s*)*([^<]{0,18})/g)]
    .map(m => ({ to: m[1].replace('.html',''), label: (m[2]||'').trim() }))
    .filter(l => l.label);
  const chips = [...s.matchAll(/class="chip[^"]*"[^>]*>/g)].length;
  return { cards, labels, titles, bigs, links, chips };
}

// ---------- Swift 侧 ----------
function swiftProfile(fileMap) {
  // fileMap: 该页可能涉及的多个 .swift 文件
  const out = { screens: [], labels: [], numbers: [], links: [], strings: [], buttons: 0 };
  for (const f of fileMap) {
    if (!fs.existsSync(path.join(UI, f))) continue;
    const s = fs.readFileSync(path.join(UI, f), 'utf8').replace(/\r\n/g, '\n');
    out.screens.push(...[...s.matchAll(/XScreen\(\s*"([^"]+)"/g)].map(m => m[1]));
    out.screens.push(...[...s.matchAll(/\.navigationTitle\(\s*"([^"]+)"/g)].map(m => m[1]));
    // secLabel("X") 与 XCardLink(title: "X")
    out.labels.push(...[...s.matchAll(/secLabel\(\s*"([^"]+)"/g)].map(m => m[1]));
    out.labels.push(...[...s.matchAll(/XCardLink\(\s*title:\s*"([^"]+)"/g)].map(m => m[1]));
    out.labels.push(...[...s.matchAll(/headerTitle:\s*"([^"]+)"/g)].map(m => m[1]));
    // 大数字
    out.numbers.push(...[...s.matchAll(/XHeroNumber\(\s*text:\s*([^,\n]+)/g)].map(m => m[1].trim()));
    out.numbers.push(...[...s.matchAll(/XValueUnit\(\s*value:\s*([^,\n]+)/g)].map(m => m[1].trim()));
    // 入口
    out.links.push(...[...s.matchAll(/NavigationLink\s*\{[\s\n]*([A-Z]\w+)\(/g)].map(m => m[1]));
    out.links.push(...[...s.matchAll(/requestRoute\(\.(\w+)\)/g)].map(m => m[1]));
    out.buttons += (s.match(/Button\s*[{:(]/g) || []).length;
    out.buttons += (s.match(/Button\(\s*"[^"]*"\s*\)\s*\{/g) || []).length;
    out.buttons += (s.match(/\.onTapGesture\s*\{/g) || []).length;
    // 全部字符串字面量 —— "这个概念在代码里存不存在"的最公平口径
    out.strings.push(...[...s.matchAll(/"([^"\\]{1,40})"/g)].map(m => m[1]));
  }
  return out;
}

// ---------- 页面 → Swift 文件映射（手工维护，凭证/成员域多文件） ----------
const MAP = {
  '01-home': ['HomeConsole.swift'],
  '02-keys': ['KeysPage.swift'],
  '03-devices': ['DevicePage.swift'],
  '04-members': ['MembersPage.swift'],
  '05-system': ['MePage.swift'],
  '10-keys-manage': ['KeysPage.swift'],
  '11-fingerprint': ['AddFingerPage.swift'],
  '12-tempcode': ['CredentialStudio.swift'],
  '13-key-detail': ['AddKeyPage.swift'],
  '14-otp': ['CredentialStudio.swift'],
  '15-add-key': ['AddKeyPage.swift'],
  '20-locks': ['LocksPage.swift'],
  '21-lock-profile': ['LockProfilePage.swift'],
  '22-firmware': ['FirmwarePage.swift'],
  '23-gateway': ['GatewayPage.swift'],
  '24-dongles': ['DonglesPage.swift'],
  '25-synctime': ['DeviceHomeView.swift'],
  '30-members-list': ['MembersPage.swift'],
  '31-member-wizard': ['MemberCenterView.swift'],
  '32-member-detail': ['MemberCenterView.swift'],
  '33-archived': ['MemberCenterView.swift'],
  '34-merge': ['MemberCenterView.swift'],
  '40-security': ['SecurityPage.swift'],
  '41-applock': ['AppLockSetupView.swift'],
  '42-peek': ['SecurityCenterView.swift'],
  '43-privacy-dash': ['SecurityCenterView.swift'],
  '44-audit': ['SecurityCenterView.swift'],
  '45-destroy': ['SecurityCenterView.swift'],
  '46-safemode': ['SettingsView.swift'],
  '47-backup': ['BackupPage.swift'],
  '48-export': ['ExportCenter.swift'],
  '49-appearance': ['StudioPage.swift'],
  '4a-me': ['MePage.swift'],
  '50-events': ['EventsPage.swift'],
  '51-feed': ['FeedPage.swift'],
  '52-stats': ['StatsPage.swift'],
  '53-alarms': ['AlarmsPage.swift'],
  '60-care': ['CarePage.swift'],
  '61-reminders': ['CareRemindersView.swift'],
  '70-icon-picker': ['IconPicker.swift'],
  '75-shell': [],
  '80-states': [],
  '81-backup-studio': ['BackupStudio.swift'],
  '82-bin': ['CredentialBinView.swift'],
  '83-studio': ['StudioPage.swift'],
  '84-diagnostics': ['DiagnosticsPage.swift'],
  '85-battery': ['CareViews.swift'],
  '86-checklist': ['CareViews.swift'],
  '87-claim': ['MemberCenterView.swift'],
  '88-exit': ['MemberCenterView.swift'],
  '89-share-android': ['ShareToAndroidView.swift'],
};

const rows = [];
let totalGap = 0;
for (const p of reg) {
  const h = htmlProfile(p.f);
  const swiftFiles = MAP[p.f] || [];
  const a = swiftProfile(swiftFiles);
  // 卡头/标签覆盖率：HTML 的每一条 label 在 Swift 里能不能找到近似
  const norm = (x) => x.replace(/[\s·\/（）()]/g, '');
  const hitIn = (needle, hay) => hay.some(k => norm(k).includes(norm(needle)) || norm(needle).includes(norm(k)));
  const hit = (needle) => hitIn(needle, a.labels) || hitIn(needle, a.strings);
  const missingLabels = h.labels.filter(l => !hit(l));
  const missingCards = h.cards.filter(c => !hit(c) && !hitIn(c, a.screens));
  const gaps = missingCards.length + missingLabels.length;
  totalGap += gaps;
  rows.push({
    page: p.f, title: p.t,
    htmlCards: h.cards.length, htmlLabels: h.labels.length, htmlLinks: h.links.length, htmlBig: h.bigs.length,
    swiftScreens: a.screens.length, swiftLabels: a.labels.length, swiftLinks: a.links.length, swiftNumbers: a.numbers.length,
    missingCards, missingLabels, gaps,
  });
}

// 输出
const showGaps = process.argv.includes('--gaps');
console.log('page'.padEnd(20) + 'cards  labels  big  | screens labels  num | 缺口');
for (const r of rows) {
  console.log(
    r.page.padEnd(20) +
    String(r.htmlCards).padStart(5) + String(r.htmlLabels).padStart(8) +
    String(r.htmlBig).padStart(5) + ' |' +
    String(r.swiftScreens).padStart(8) + String(r.swiftLabels).padStart(7) +
    String(r.swiftNumbers).padStart(4) + ' | ' + r.gaps
  );
}
console.log('\n合计缺口项:', totalGap);

// ══════════════════════════════════════════════════════════════════════
// 视觉词汇对照（审美口径的核心）
//
// 用户口径：审美以 HTML 为标准。所以逐页检查「HTML 用了哪些视觉组件，
// App 对应页是否也有同类组件」——这是比"卡头文字"更本质的一层。
// ══════════════════════════════════════════════════════════════════════

// HTML 侧的视觉特征
function htmlVisual(file) {
  const s = fs.readFileSync(path.join(PROTO, file + '.html'), 'utf8');
  return {
    ring: /stroke-dasharray/.test(s),                       // 环 / 仪表
    bigNumber: /font-size:(4[4-9]|[5-9]\d|1\d\d)px/.test(s), // >=44px 大数字
    chip: /class="chip/.test(s),                            // 玻璃胶囊
    coloredRow: /class="drow|background:#[0-9A-F]{6};width:/i.test(s), // 彩色数据行/条
    bars: /class="hbar|bars|maxis/.test(s),                 // 柱图
    gallery: /overflow-x:auto|gallery|104px/.test(s),        // 横向画廊
    twoTone: /themed-head|dsheet|\.dtop/.test(s),            // 两层结构
    hero: /linear-gradient\(1[0-9]0deg,#[4-9A-F]/i.test(s),  // 渐变 hero 卡
  };
}

// Swift 侧的视觉特征
function swiftVisual(fileMap) {
  const s = fileMap
    .filter(f => fs.existsSync(path.join(UI, f)))
    .map(f => fs.readFileSync(path.join(UI, f), 'utf8'))
    .join('\n');
  return {
    ring: /XGradientDial|XTripleThinRing|XActivityRings|XCycleRing|stroke\(|Circle\(\)/.test(s),
    bigNumber: /XHeroNumber|XValueUnit|DSFont\.hero|font-size: ?[2-9]\d/.test(s),
    chip: /XStatChip|Chip\(|chip/.test(s),
    coloredRow: /XDataRow|\.fill\(XPalette\.(ok|warn|danger|accent)/.test(s),
    bars: /XDayClock|XBars|frame\(height:.*\/ ?CGFloat|Rectangle\(\)/.test(s),
    gallery: /ScrollView\(\.horizontal|LazyVGrid/.test(s),
    twoTone: /dsheet|themed|XTwoTone|dbody/.test(s),
    hero: /XGradient\.hero|linear-gradient|Gradient/.test(s),
  };
}

const VIS_LABEL = {
  ring: '环/仪表', bigNumber: '大数字', chip: '玻璃胶囊', coloredRow: '彩色数据行',
  bars: '柱图', gallery: '横向画廊', twoTone: '两层结构', hero: '渐变 hero',
};

console.log('\n=== 视觉词汇缺口（HTML 有、App 无）===');
let visGap = 0;
const visRows = [];
for (const p2 of reg) {
  const hv = htmlVisual(p2.f);
  const av = swiftVisual(MAP[p2.f] || []);
  const missing = Object.keys(hv).filter(k => hv[k] && !av[k]).map(k => VIS_LABEL[k]);
  if (missing.length) { visGap += missing.length; visRows.push({ page: p2.f, title: p2.t, missing }); }
}
for (const r of visRows) console.log('  ' + r.page.padEnd(20) + '「' + r.title + '」缺: ' + r.missing.join(' / '));
console.log('视觉词汇缺口合计:', visGap);
