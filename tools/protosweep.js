'use strict';
// tools/protosweep.js —— 57 页原型完整性闸门
//
// 起因：03-devices.html 漏引 pages.css —— 页内 5 卡/2 卡头/5 chips 全部无样式，
// 但 DOCTYPE/结构都正常，肉眼"看文件"发现不了，直到做了全量 sweep 才暴露。
//
// 判据（每页四项）：
//   P1 <!DOCTYPE 开头
//   P2 </html> 闭合
//   P3 引用 tokens.css
//   P4 引用 pages.css
// 另加 R1：registry 里每个页都有对应 .html 文件
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const DIRS = ['tools/proto', 'tools/android-proto'];
let total = 0, bad = 0;
for (const dir of DIRS) {
  const full = path.join(ROOT, dir);
  const reg = JSON.parse(fs.readFileSync(path.join(full, 'registry.json'), 'utf8'));
  for (const p of reg) {
    total++;
    const f = path.join(full, p.f + '.html');
    if (!fs.existsSync(f)) { console.error('  ✗ R1 缺文件: ' + dir + '/' + p.f + '.html'); bad++; continue; }
    const s = fs.readFileSync(f, 'utf8');
    const miss = [];
    if (!s.startsWith('<!DOCTYPE')) miss.push('P1 DOCTYPE');
    if (!s.trimEnd().endsWith('</html>')) miss.push('P2 </html>');
    if (!s.includes('href="tokens.css"')) miss.push('P3 tokens.css');
    if (!s.includes('href="pages.css"')) miss.push('P4 pages.css');
    if (miss.length) { console.error('  ✗ ' + dir + '/' + p.f + ': ' + miss.join(', ')); bad++; }
  }
}
if (bad) { console.error('✗ 原型完整性 ' + bad + '/' + total + ' 页不达标'); process.exit(1); }
console.log('原型完整性 ✓ ' + total + '/' + total + ' 页（P1-P4 + R1）');
