#!/usr/bin/env node
// overflow-audit.js —— 在指定宽度下渲染每一屏并检查横向溢出。
//
// 用法：node DesignLab/overflow-audit.js [width]
// 做法：给每个镜像页临时注入一段脚本，量出 scrollWidth 与视口宽度，
// 用 --dump-dom 把结论带回标题行。宽度不足即判失败。
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'DesignLab', 'out');
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const WIDTH = parseInt(process.argv[2] || '375', 10);

const PROBE = `<script>
window.addEventListener('load', function () {
  var d = document.documentElement, b = document.body;
  var w = Math.max(d.scrollWidth, b.scrollWidth);
  var over = Math.max(0, w - d.clientWidth);
  document.title = 'AUDIT over=' + over + ' scroll=' + w + ' client=' + d.clientWidth;
});
</script>`;

const files = fs.readdirSync(OUT).filter((f) => f.endsWith('.html') && f !== 'index.html');
let bad = 0;
const report = [];

for (const f of files) {
  const src = fs.readFileSync(path.join(OUT, f), 'utf8');
  const probe = path.join(OUT, '.probe-' + f);
  fs.writeFileSync(probe, src.replace('</head>', PROBE + '</head>'), 'utf8');
  let dom = '';
  try {
    dom = execFileSync(EDGE, ['--headless=new', '--disable-gpu', '--hide-scrollbars',
      '--window-size=' + WIDTH + ',932', '--virtual-time-budget=1500', '--dump-dom',
      'file:///' + probe.replace(/\\/g, '/')], { stdio: ['ignore', 'pipe', 'ignore'], timeout: 30000, encoding: 'utf8' });
  } catch (e) {
    dom = (e.stdout || '') + '';
  }
  fs.unlinkSync(probe);
  const m = /<title>([^<]*)<\/title>/.exec(dom);
  const line = m ? m[1] : 'AUDIT no-title';
  const over = /over=(-?\d+)/.exec(line);
  const n = over ? parseInt(over[1], 10) : -1;
  if (n > 0) {
    bad++;
    report.push('  ' + f + '  ' + line);
  }
}

if (bad === 0) {
  console.log('overflow-audit: OK — ' + files.length + ' 屏在 ' + WIDTH + 'pt 宽下无横向溢出');
  process.exit(0);
}
console.log('overflow-audit: FAIL — ' + bad + '/' + files.length + ' 屏在 ' + WIDTH + 'pt 宽下横向溢出');
for (const r of report) console.log(r);
process.exit(1);
