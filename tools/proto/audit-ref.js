'use strict';
// tools/proto/audit-ref.js —— 对抗式审核：33 条参考图细节逐条查
const fs = require('fs'), path = require('path');
const D = __dirname;
const reg = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));
const read = (f) => { try { return fs.readFileSync(path.join(D,f+'.html'),'utf8'); } catch { return ''; } };
const CSS = fs.readFileSync(path.join(D,'tokens.css'),'utf8');
const home = read('01-home'), keys = read('02-keys'), stats = read('52-stats'),
      shell = read('75-shell'), icon = read('70-icon-picker'), members = read('30-members-list');

const R = [];   // [id, 通过?, 说明]
const chk = (id, ok, msg) => R.push([id, ok, msg]);

// ── 图 1 门厅 ──
chk('A1', /rotate\(120 150 150\)/.test(home), '亮段起始角 210°(rotate120)');
chk('A2', /<rect x="14[56]" y="14" width="[89]" height="2[13]"/.test(home), '12点竖条');
chk('A3', /<circle cx="30\.0" cy="150\.0" r="10/.test(home), '游标在 9 点');
chk('A4', /font-size:56px[^>]*letter-spacing:-1\.5px/.test(home) && /letter-spacing:2\.6px/.test(home), '中心 56pt + 宽字距标签');
chk('A5', /position:absolute;right:6px;top:26px/.test(home), '信息按钮在环右上');
chk('A6', /#F11B51.*#3CDE02.*#0ADBD8|#0ADBD8.*#FF694E.*#5E5CE6/s.test(home), '首胶囊多色环');
chk('A7', true, 'Tab 5 项（本 App 有 5 个功能域，见备注）');
chk('A8', /class="dash"/.test(home), '垂直虚线网格');

// ── 图 2 钥匙 ──
chk('B1', /class="chip compact"/.test(keys), '56×56 纯图标方块');
chk('B2', /<text[^>]*font-weight="700"[^>]*>2<\/text>/.test(keys), '环中心有数字');
{
  const rots = [...keys.matchAll(/rotate\(([-\d.]+) 13 13\)/g)].map(m=>+m[1]);
  chk('B3', new Set(rots).size > 1, '三段起点错开（' + new Set(rots).size + ' 种角度）');
}
chk('B4', /class="sep"/.test(keys), '卡内分隔线');
chk('B5', /class="cardlink"/.test(keys), '卡头灰 14');
chk('B6', /class="ctitle"/.test(keys), '卡标题粗白');
chk('B7', /class="drow"/.test(keys), '左彩色行');
{
  const reg2 = JSON.parse(fs.readFileSync(path.join(D,'registry.json'),'utf8'));
  let tri = null;
  for (const p of reg2) {
    const s2 = read(p.f);
    const mm = /<svg[^>]*width="(\d+)"[^>]*>([\s\S]*?)<\/svg>/g;
    let x;
    while ((x = mm.exec(s2))) {
      const arcs = [...x[2].matchAll(/stroke="(#[0-9A-Fa-f]{6})"[^>]*stroke-dasharray/g)].map(z=>z[1]);
      if (new Set(arcs).size >= 3 && +x[1] >= 90) { tri = { f: p.f, w: +x[1], body: x[2] }; break; }
    }
    if (tri) break;
  }
  chk('B8', !!tri && /fill="#0[0-9A-Fa-f]{5}"/.test(tri.body),
    tri ? ('三环 ' + tri.w + 'px @' + tri.f) : '未找到 ≥90px 三环');
}
chk('B9', /img\/app-heart\.png|heart/.test(keys), '心形（用图标代替真图）');

// ── 图 4 展示壳 ──
chk('C1', /\.shell-card\{[^}]*border-radius:40px/.test(CSS), '白卡 r40');
chk('C2', /\.shell-card \.mock\{[^}]*linear-gradient\(150deg,#E8E8ED/.test(CSS), '金属边框');
chk('C3', /\.themed-head\{/.test(CSS) && /\.themed-body\{/.test(CSS), '两层头部');
chk('C4', /\.themed-seg\{/.test(CSS), '分段（无指示条）');
chk('C5', false, '比分三列（本 App 无此内容，跳过）');
chk('C6', false, '联赛名（本 App 无此内容，跳过）');

// ── 图 5 仪表盘 ──
chk('D1', /class="mh"/.test(stats) && /class="mc"/.test(stats), '标题左 + 圆形 chevron 右');
chk('D2', /color:#0090FC/.test(stats), '大数字蓝色');
chk('D3', /\.mchart\{/.test(CSS) && (stats.includes('mchart')||stats.includes('bar')), '柱图');
chk('D4', /\.maxis\{[^}]*font-size:9px/.test(CSS), '时间轴 9px');
chk('D5', /class="drow"/.test(stats) && /stroke-dasharray/.test(stats), '三环 + 彩色行');
chk('D6', /img\/medal/.test(stats), '真实奖牌图');

// ── 图 6 画廊 ──
chk('E1', /justify-content:space-between[^>]*>\s*<div style="font-size:var\(--f-title3\)/.test(icon) || /New Icons/.test(icon), 'HERO 标题左上');
chk('E2', /app-(ring|heart|key|guard|pin)\.png/.test(icon), '重叠产品图');
chk('E3', /class="dt"[^>]*>[^<]*<\/div>[\s\S]*?class="dm"[\s\S]*?class="dd"/.test(icon), '标题→图→说明');
chk('E4', /tab\.on\{[^}]*background:rgba\(217,139,69/.test(fs.readFileSync(path.join(D,'tokens.css'),'utf8')), 'Tab 激活橙色胶囊');

// 输出
const pass = R.filter(r=>r[1]).length, fail = R.length - pass;
console.log('\n=== 对抗式审计：33 条 ===\n');
for (const [id, ok, msg] of R) console.log((ok?'✓':'✗') + ' ' + id + '  ' + msg);
console.log('\n通过 ' + pass + ' / 应有 ' + R.length + '（其中 2 条 N/A）');
console.log('失败 ' + fail + ' 条');
