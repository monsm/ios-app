#!/usr/bin/env node
// tools/proto/check.js —— 原型自检：规范里能静态查的项
'use strict';
const fs = require('fs');
const path = require('path');
const DIR = __dirname;
const pages = fs.readdirSync(DIR).filter(f => /^0\d-.+\.html$/.test(f)).sort();
const css = fs.readFileSync(path.join(DIR, 'tokens.css'), 'utf8');
let fail = 0;
const need = (cond, msg) => { if (!cond) { console.error('  ✗ ' + msg); fail++; } };

console.log('== 令牌层 ==');
need(/#000000/.test(css), '画布应为 #000000');
need(/#1C1C1E/.test(css), '卡片应为 #1C1C1E');
need(/--r-card:\s*26px/.test(css), '卡片圆角应为 26（§15 A3 验收项）');
need(/--r-chip:\s*22px/.test(css), '芯片圆角应为 22（§7.2 自检）');
need(/--gutter:\s*14px/.test(css), '页边距应为 14（§5.1 s5）');
need(/--row-gap:\s*12px/.test(css), '卡片行间距应为 12（G9 / B3）');
need(/--section:\s*28px/.test(css), '区块间距应为 28（§5.1 s7）');
need(/--title-to-card:74px/.test(css), '标题→首卡应为 74（§15 L4）');
need(/--card-pad:16px/.test(css), '卡内边距应为 16（§5.1 s4）');
need(!/box-shadow:\s*0 \d+px \d+px rgba\(0,0,0,\.?[1-9]/.test(css.replace(/box-shadow:0 24px 48px rgba\(0,0,0,\.55\)/g, '')), '卡片不得有投影（§6.3）');

console.log('== 页面 ==');
for (const f of pages) {
  const src = fs.readFileSync(path.join(DIR, f), 'utf8');
  const n = pages.indexOf(f) + 1;
  need(/class="tabbar"/.test(src), f + ' 缺 Tab Bar');
  const tabs = (src.match(/class="tab( on)?"/g) || []).length;
  need(tabs === 5, f + ' Tab 数应为 5（实际 ' + tabs + '）');
  const active = (src.match(/class="tab on"/g) || []).length;
  need(active === 1, f + ' 应有且仅有 1 个选中 Tab（实际 ' + active + '）');
  need(/class="h1"/.test(src), f + ' 缺大标题');
  need(/class="card/.test(src), f + ' 缺卡片');
  // 卡头必须带 chevron（§7.11）
  const links = (src.match(/class="cardlink"/g) || []).length;
  const chevs = (src.match(/class="ch"/g) || []).length;
  need(links === chevs, f + ' 卡头数与 chevron 数不符（' + links + ' vs ' + chevs + '）');
  // 禁用内联硬编码色（除 hero 渐变）
  const hard = src.match(/#[0-9A-Fa-f]{6}/g) || [];
  const allow = ['#D98B45','#30D158','#FF9F0A','#FF3B30','#7B7BE8','#E8A05C','#22D3EE','#D98B45'];
  const bad = hard.filter(c => !allow.includes(c) && !/^#0A1220|#141418|#3C489C|#546CE4|#4A4A7A|#8A5522|#B8702E|#F0A55A/.test(c));
  need(bad.length === 0, f + ' 有未授权硬编码色: ' + [...new Set(bad)].join(', '));
}

console.log(fail === 0 ? '\n✓ 原型自检全部通过（' + pages.length + ' 页）' : '\n✗ ' + fail + ' 项不通过');
process.exit(fail === 0 ? 0 : 1);
