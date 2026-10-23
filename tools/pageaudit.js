'use strict';
// tools/pageaudit.js —— 逐页审美 / 视觉 / 布局对照（用户新目标：每页亲自过一遍）
//
// 口径：审美以 tools/proto 的 HTML 为准；功能以真实 App 为准。
// 三层核对：
//   ① 布局：卡片顺序（HTML DOM 序 vs Swift body 序）
//   ② 结构：每卡解剖是否齐（卡头 → 标题 → 标签/值 → 分隔线 → 页脚整句）
//   ③ 词汇：环 / 大数字 / 胶囊 / 彩点行
//
// 关键：**按 struct 作用域统计**，否则一文件多页（85/86 共用 CareViews、87/88 共用 MemberCenterView）
// 会把卡片数算成十几张，误判成"App 卡太多"。
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const PROTO = path.join(ROOT, 'tools/proto');
const UI = path.join(ROOT, 'App/UI');
const reg = JSON.parse(fs.readFileSync(path.join(PROTO, 'registry.json'), 'utf8'));

const MAP = {
  '01-home': ['HomeConsole.swift'], '02-keys': ['KeysPage.swift'], '03-devices': ['DevicePage.swift'],
  '04-members': ['MembersPage.swift'], '05-system': ['MePage.swift'],
  '10-keys-manage': ['KeysPage.swift'], '11-fingerprint': ['AddFingerPage.swift'],
  '12-tempcode': ['CredentialStudio.swift'], '13-key-detail': ['AddKeyPage.swift'],
  '14-otp': ['CredentialStudio.swift'], '15-add-key': ['AddKeyPage.swift'],
  '20-locks': ['LocksPage.swift'], '21-lock-profile': ['LockProfilePage.swift'],
  '22-firmware': ['FirmwarePage.swift'], '23-gateway': ['GatewayPage.swift'],
  '24-dongles': ['DonglesPage.swift'], '25-synctime': ['DeviceHomeView.swift'],
  '30-members-list': ['MembersPage.swift'], '31-member-wizard': ['MemberCenterView.swift'],
  '32-member-detail': ['MemberCenterView.swift'], '33-archived': ['MemberCenterView.swift'],
  '34-merge': ['MemberCenterView.swift'], '40-security': ['SecurityPage.swift'],
  '41-applock': ['AppLockSetupView.swift'], '42-peek': ['SecurityCenterView.swift'],
  '43-privacy-dash': ['SecurityCenterView.swift'], '44-audit': ['SecurityCenterView.swift'],
  '45-destroy': ['SecurityCenterView.swift'], '46-safemode': ['SettingsView.swift'],
  '47-backup': ['BackupPage.swift'], '48-export': ['ExportCenter.swift'],
  '49-appearance': ['StudioPage.swift'], '4a-me': ['MePage.swift'],
  '50-events': ['EventsPage.swift'], '51-feed': ['FeedPage.swift'], '52-stats': ['StatsPage.swift'],
  '60-care': ['CarePage.swift'], '61-reminders': ['CareRemindersView.swift'],
  '70-icon-picker': ['IconPicker.swift'], '75-shell': [],
  '80-states': [], '81-backup-studio': ['BackupStudio.swift'], '82-bin': ['CredentialBinView.swift'],
  '83-studio': ['StudioPage.swift'], '84-diagnostics': ['DiagnosticsPage.swift'],
  '85-battery': ['CareViews.swift'], '86-checklist': ['CareViews.swift'],
  '87-claim': ['MemberCenterView.swift'], '88-exit': ['MemberCenterView.swift'],
  '89-share-android': ['ShareToAndroidView.swift'],
};

// 每页在 Swift 里用来定位 struct 的 XScreen 标题候选（HTML 标题 ≠ Swift 标题）
const SCREEN_HINT = {
  '01-home': ['门厅'], '03-devices': ['设备'], '05-system': ['本机设置'], '4a-me': ['本机设置'],
  '25-synctime': ['同步时间'], '46-safemode': ['安全模式说明'], '47-backup': ['备份与恢复'],
  '85-battery': ['换电指引'], '86-checklist': ['锁体保养'], '60-care': ['维护与保养'],
  '21-lock-profile': ['锁档案'], '23-gateway': ['智能网关'], '24-dongles': ['蓝牙钥匙串'],
  '22-firmware': ['固件升级'], '20-locks': ['设备管理', '我的门锁'], '41-applock': ['应用锁'],
  '48-export': ['导出与分享'], '49-appearance': ['钥匙工坊'], '83-studio': ['钥匙工坊'],
  '89-share-android': ['分享给安卓'], '70-icon-picker': ['App 图标'],
};

// ── HTML 卡 ──
function htmlCards(file) {
  const s = fs.readFileSync(path.join(PROTO, file + '.html'), 'utf8');
  const body = s.replace(/<div class="tabbar">[\s\S]*?<\/div>\s*(?=<script|$)/g, '');
  const out = [];
  const re = /<div class="(card[^"]*|metric-card|duo-card)"[^>]*>/g;
  let m;
  while ((m = re.exec(body))) {
    const seg = body.slice(m.index, m.index + 1500);
    const head = /class="cardlink"[^>]*>([^<]{1,20})/.exec(seg);
    const ctitle = /class="ctitle"[^>]*>([^<]{1,24})/.exec(seg);
    const footer = /class="footer"[^>]*>([^<]{8,})/.exec(seg);
    const labels = [...seg.matchAll(/class="clabel"[^>]*>([^<]{1,14})/g)].map(x => x[1].trim());
    out.push({
      title: (head ? head[1] : (ctitle ? ctitle[1] : '')).trim(),
      labels, hasFooter: !!footer,
      big: /font-size:(4[4-9]|[5-9]\d|1\d\d)px/.test(seg),
      ring: /stroke-dasharray/.test(seg),
    });
  }
  return out;
}

// ── Swift：定位该页 struct ──
function findScope(files, hints) {
  for (const f of files) {
    const fp = path.join(UI, f);
    if (!fs.existsSync(fp)) continue;
    const s = fs.readFileSync(fp, 'utf8').replace(/\r\n/g, '\n');
    const re = /\bstruct\s+(\w+)\s*:\s*View\s*\{/g;
    let m;
    while ((m = re.exec(s))) {
      const bodyStart = m.index + m[0].length;
      let depth = 1, j = bodyStart;
      for (; j < s.length; j++) {
        if (s[j] === '{') depth++;
        else if (s[j] === '}') { depth--; if (depth === 0) break; }
      }
      const body = s.slice(bodyStart, j);
      if (hints.some(h => body.includes('XScreen("' + h) || body.includes('navigationTitle("' + h)))
        return { file: f, name: m[1], body };
    }
  }
  return null;
}

// ── Swift 卡（在给定源片段里）──
function swiftCards(src) {
  const out = [];
  let i = 0;
  while ((i = src.indexOf('XPanel(', i)) >= 0) {
    const open = i + 'XPanel'.length;
    let depth = 0, j = open;
    for (; j < src.length; j++) {
      if (src[j] === '(') depth++;
      else if (src[j] === ')') { depth--; if (depth === 0) break; }
    }
    const seg = src.slice(j, j + 2200);
    // 卡头/标签/footer 的写法在同一行或换行都可能（我自己的新代码多是单行）
    const head = /Text\("([^"]{1,20})"\)[^\n]{0,40}\.xFont\(\.(subheadline|caption)/.exec(seg)
              || /Text\("([^"]{1,20})"\)[\s\n]{0,60}\.xFont\(\.(subheadline|caption)/.exec(seg);
    const anyText = /Text\("([^"]{2,20})"\)/.exec(seg);
    const footer = /Text\("([^"]{12,})"\)/.exec(seg) || /Text\("([^"]{12,})"/.exec(seg);
    const labels = [...seg.matchAll(/Text\("([^"]{2,10})"\)[^\n]{0,30}\.xFont\(\.(caption2|footnote)/g)].map(x => x[1]);
    out.push({
      title: (head ? head[1] : (anyText ? anyText[1] : '')).trim(),
      labels, hasFooter: !!footer,
      big: /XHeroNumber|XValueUnit/.test(seg),
      ring: /XGradientDial|XTripleThinRing|XActivityRings|XCycleRing/.test(seg),
    });
    i = j;
  }
  return out;
}

function audit(page) {
  const h = htmlCards(page.f);
  const hints = SCREEN_HINT[page.f] || [page.t];
  const scope = findScope(MAP[page.f] || [], hints);
  const a = scope ? swiftCards(scope.body) : [];
  const sum = (arr, k) => arr.filter(x => x[k]).length;
  return {
    page: page.f, title: page.t, scope: scope ? scope.name : null,
    html: { n: h.length, big: sum(h, 'big'), ring: sum(h, 'ring'), footer: sum(h, 'hasFooter'), labels: h.reduce((n, x) => n + x.labels.length, 0) },
    swift: { n: a.length, big: sum(a, 'big'), ring: sum(a, 'ring'), footer: sum(a, 'hasFooter'), labels: a.reduce((n, x) => n + x.labels.length, 0) },
    htmlTitles: h.map(x => x.title).filter(Boolean),
    swiftTitles: a.map(x => x.title).filter(Boolean),
  };
}

const only = process.argv.indexOf('--page');
if (only > 0) {
  const name = process.argv[only + 1];
  const p = reg.find(x => x.f === name);
  if (!p) { console.error('没有这一页: ' + name); process.exit(1); }
  const r = audit(p);
  console.log('页 ' + r.page + ' 「' + r.title + '」 Swift struct: ' + (r.scope || '未定位'));
  console.log('HTML  ' + r.html.n + ' 卡 / 大数字 ' + r.html.big + ' / 环 ' + r.html.ring + ' / 页脚 ' + r.html.footer + ' / 标签 ' + r.html.labels);
  console.log('Swift ' + r.swift.n + ' 卡 / 大数字 ' + r.swift.big + ' / 环 ' + r.swift.ring + ' / 页脚 ' + r.swift.footer + ' / 标签 ' + r.swift.labels);
  console.log('\nHTML 卡序: ' + r.htmlTitles.join(' → '));
  console.log('Swift 卡序: ' + r.swiftTitles.join(' → '));
  process.exit(0);
}

console.log('page'.padEnd(20) + 'struct'.padEnd(24) + 'cards   big  ring  foot  label');
const todo = [];
for (const p of reg) {
  const r = audit(p);
  const g = (h, s) => h > 0 && s === 0 ? ' ⚠' : '';
  console.log(
    r.page.padEnd(20) + (r.scope || '—').padEnd(24) +
    (r.html.n + '/' + r.swift.n).padStart(6) +
    (r.html.big + '/' + r.swift.big).padStart(6) + g(r.html.big, r.swift.big) +
    (r.html.ring + '/' + r.swift.ring).padStart(6) + g(r.html.ring, r.swift.ring) +
    (r.html.footer + '/' + r.swift.footer).padStart(6) + g(r.html.footer, r.swift.footer) +
    (r.html.labels + '/' + r.swift.labels).padStart(8) + g(r.html.labels, r.swift.labels)
  );
  const score = (r.html.big > r.swift.big ? 1 : 0) + (r.html.ring > r.swift.ring ? 1 : 0) + (r.html.footer > r.swift.footer ? 1 : 0);
  if (score) todo.push({ page: r.page, score });
}
console.log('\n=== 待逐页过一遍（按缺口类数排序）===');
todo.sort((a, b) => b.score - a.score).forEach(t => console.log('  ' + t.page + '  缺 ' + t.score + ' 类'));
console.log('合计:', todo.length, '页');
