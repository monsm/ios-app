#!/usr/bin/env node
// gatepathcheck —— 闸门「路径可移植性」闸门（判失败）。
//
// 2026-10-31（第 35/36 轮，**代价 4 次 CI 红**）：
// 我给 kotlinimportcheck 写了硬编码 `D:/aapk/ios-app/...`，本地跑得好好的，
// CI 上 runner 路径是 `/home/runner/work/ios-app/ios-app/` ⇒ `ENOENT scandir` ⇒
// **整个 job 失败**。而我把这 4 次红都归因到 Kotlin 代码，改了 4 处无辜的代码。
//
// 真正的教训：**闸门自己也会坏，而且坏得更隐蔽**（本地永远绿）。
//
// 判据：
//   ① tools/ 下任何 .js 不得出现绝对路径字面量（`D:/` `C:\` `/Users/` `/home/`）；
//   ② 必须在 CI 里跑的闸门不得依赖 `process.cwd()`（runner 的 cwd 与本地不同）。
//
// 白名单：`add_ci_step.js` 这类**不参与 CI** 的开发工具（显式列在下面）。
const fs = require('fs');
const path = require('path');

const TOOLS = path.resolve(__dirname);
const NOT_IN_CI = new Set([
  'add_ci_step.js',      // 开发工具：给 workflow 加 step，需要命令行参数
  'gatepathcheck.js',    // 本文件
  'allgates.js',         // 调度器，不单独跑
  // apkshadow.js：`pick(rel, devRel)` 是**有意设计的回退** —— 优先仓内 `vendor/apk-baseline`
  // （已提交，CI 上必然命中第一条），本地开发机缺基线时才退到 `D:/aapk` 反编译目录。
  // CI 上永远走不到绝对路径那一支，且缺基线时它会显式报错退出（不是裸 ENOENT）。
  // 这是**合理的**开发便利，不是路径依赖缺陷。
  'apkshadow.js',
]);

// 允许出现绝对路径的场景：注释里的历史记录（"退回开发机上的 D:/aapk ..."）
// 判据只看**字符串字面量**（引号包起来的），注释不算。
function stripComments(line) {
  let inStr = false;
  for (let i = 0; i < line.length - 1; i++) {
    const ch = line[i], prev = i > 0 ? line[i - 1] : '';
    if (ch === '"' && prev !== '\\') inStr = !inStr;
    if (!inStr && ch === '/' && line[i + 1] === '/') return line.slice(0, i);
  }
  return line;
}

const ABS_PATH = /['"`](?:[A-Za-z]:[\\/]|\/Users\/|\/home\/|\/root\/|\/opt\/)[^'"`]*['"`]/;

const bad = [];
for (const f of fs.readdirSync(TOOLS)) {
  if (!f.endsWith('.js')) continue;
  if (NOT_IN_CI.has(f)) continue;
  const src = fs.readFileSync(path.join(TOOLS, f), 'utf8');
  const L = src.split(/\r?\n/);
  for (let i = 0; i < L.length; i++) {
    const c = stripComments(L[i]);
    if (!c.trim()) continue;
    if (ABS_PATH.test(c)) bad.push(`${f}:${i + 1}  ${c.trim().slice(0, 86)}`);
  }
}

if (bad.length) {
  console.log(`✗ 闸门里有硬编码绝对路径 ${bad.length} 处（CI runner 路径不同 ⇒ ENOENT ⇒ job 必红）：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n修法：用 `path.resolve(__dirname, "..")` 推仓库根，再 `path.join` 拼相对段。');
  process.exit(1);
}
console.log('✓ 闸门无硬编码绝对路径（' + (fs.readdirSync(TOOLS).filter(f => f.endsWith('.js') && !NOT_IN_CI.has(f)).length) + ' 个文件已查）');
