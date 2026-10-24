'use strict';
// tools/reviewsync.js —— REVIEW.html 与两端 registry 的一致性闸门
//   R1 REVIEW 里的 iframe 数 = iOS registry 页数 + android-proto 页数
//   R2 每个 iframe 目标文件必须存在
//   R3 每页必须有判定 radio（name = 页 id）
// 起因：第 31 轮给 REVIEW.html 加 Android 区时 String.replace 未命中**静默失败**，
// 31-39 轮的"已扩为双端"是假象，第 40 轮核对 iframe 时才被发现。本闸门防再犯。
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const h = fs.readFileSync(path.join(ROOT, 'tools/proto/REVIEW.html'), 'utf8');
const ios = JSON.parse(fs.readFileSync(path.join(ROOT, 'tools/proto/registry.json'), 'utf8'));
const and = JSON.parse(fs.readFileSync(path.join(ROOT, 'tools/android-proto/registry.json'), 'utf8'));
const frames = [...h.matchAll(/iframe src="([^"]+)"/g)].map(m => m[1]);
const problems = [];
if (frames.length !== ios.length + and.length)
  problems.push('R1 iframe 数 ' + frames.length + ' != iOS ' + ios.length + ' + Android ' + and.length);
for (const src of frames) {
  if (!fs.existsSync(path.resolve(ROOT, 'tools/proto', src))) problems.push('R2 缺文件: ' + src);
}
const names = new Set([...h.matchAll(/name="([^"]+)"/g)].map(m => m[1]));
for (const p of [...ios, ...and]) {
  const key = (p.f.startsWith('android-') ? '' : '') && names.has(p.f) ? p.f : (names.has(p.f) ? p.f : (names.has('android-' + p.f) ? 'android-' + p.f : null));
  if (!key) problems.push('R3 无判定项: ' + p.f);
}
if (problems.length) { problems.slice(0, 10).forEach(p => console.error('  ' + p)); console.error('✗ REVIEW.html 漂移 ' + problems.length + ' 处'); process.exit(1); }
console.log('REVIEW.html ✓ ' + frames.length + ' 页双端对照完整（R1-R3）');
