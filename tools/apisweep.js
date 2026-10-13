// API 线索扫描器 (人工复核用，**不进闸门**): 列出"必须由框架提供、本仓自己没声明"的链式修饰符名。
// 用法: node tools/apisweep.js [--verbose]
//
// 为什么有它: 第七十九批抓到 `.listItemSpacing` (SwiftUI 无此 API, 真名 listRowSpacing) 之后发现,
// swiftlint 检查② 的形状是"首字母大写 + 后接 `.( [ `", 所以它只对**臆造类型名**有效,
// 对**臆造的小写成员名**整片失明 —— 而 SwiftUI 的修饰符恰好全是小写。
//
// 为什么不判失败 (exit 恒 0): 这份名单要判对错, 就得知道"哪些小写名字是合法框架 API"。
// 那份名单离线拿不全 (Apple 文档没有可枚举的修饰符总表), 拿不全就会误报;
// 而**误报的闸门比没有闸门更糟** —— 它会训练人忽略红色输出 (keycheck 被删时定下的口径)。
// 所以它只输出现场 + 首个出现位置, 由人在改 UI 链式调用时扫一眼。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'Widget', 'Tests'];
const verbose = process.argv.includes('--verbose');

function swiftFiles(d, out = []) {
  if (!fs.existsSync(d)) return out;
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) swiftFiles(p, out);
    else if (p.endsWith('.swift')) out.push(p);
  }
  return out;
}
const rel = (f) => path.relative(ROOT, f).replace(/\\/g, '/');
const files = DIRS.flatMap((d) => swiftFiles(path.join(ROOT, d)));
const srcs = files.map((f) => ({ f: rel(f), s: fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n') }));

// 1) 本仓自己声明的成员名: func / var / let / subscript / init
const declared = new Set();
for (const { s } of srcs) {
  for (const m of s.matchAll(/\b(?:func|var|let|subscript)\s+([a-z][A-Za-z0-9_]*)/g)) declared.add(m[1]);
}

// 2) 链式修饰符形态: 行首就是 `.name(`  (SwiftUI 修饰符的书写习惯), 排除注释行
const used = new Map();
for (const { f, s } of srcs) {
  s.split('\n').forEach((line, i) => {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) return;
    const m = /^\.([a-z][A-Za-z0-9_]*)\(/.exec(t);
    if (!m) return;
    const n = m[1];
    if (declared.has(n)) return;                 // 本仓声明过 → 不是框架 API 的事
    if (!used.has(n)) used.set(n, `${f}:${i + 1}`);
  });
}

const names = [...used.keys()].sort();
console.log(`apiSweep: 需由框架提供的链式修饰符名 ${names.length} 个 (本仓未声明)`);
if (verbose) {
  for (const n of names) console.log(`  .${n}(...)  首见 ${used.get(n)}`);
} else {
  console.log('  ' + names.join(' '));
  console.log('提示: --verbose 可看每个名字的首个出现位置；判对错要查 Apple 文档，本脚本不做判决。');
}
// 已知需人盯的一条 (第七十九批): PointMark 上的 .symbolSize 我查不到正面证据也证不了不存在
// → 只在输出里点一句名, 不判失败 (判失败就等于拿猜测当结论)。
console.log('需人工定性: listItemSpacing 已确认臆造并改为 listRowSpacing (§84)；'
          + 'symbolSize (StatsView) 尚无定论, 见 docs/VERIFY-CHECKLIST.md 第 0 节。');
process.exit(0);
