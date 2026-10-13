#!/usr/bin/env node
// 219 资源纪律检查 (顾问级, 不判失败) — node tools/assetscheck.js
// 为什么本批才补：FEATURE-TRIAGE 219 此前挂着 "✅ CI 资源检查"，而 tools/ 下**从来没有**资源检查脚本，
// ios.yml 也没有对应步骤 —— 是"把计划记成已做"的同一族 (见 AUDIT-CODE §103)。
// 口径修正 (原句"新增资源必须是 SF Symbol 引用"前提已被破)：App 图标是 iOS 必需位图，
// Assets.xcassets 下 4 个 *.appiconset 共 12 个 png 是合法存在，所以本闸门按**可证伪的三条**判：
//   R1 位图只允许出现在 *.appiconset 目录里 (imageset 一律算违例)
//   R2 源码不得出现捆绑资源初始化 `Image("名字")` (界面图标一律走 Image(systemName:)；
//      Image(uiImage:/nsImage:/decorative: 是**运行时生成的**图像，如二维码与分享封面，允许)
//   R3 新增的非符号资源文件 (pdf/svg/jpg/gif) 直接报
// 定成顾问级的理由：新闸门头几批不知深浅，先报线索不误伤提交；连续几批 0 命中再升为判失败。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = process.argv[2] || 'App';
const IMG_EXT = ['.png', '.jpg', '.jpeg', '.gif', '.pdf', '.svg'];
const files = [];
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p);
    else files.push(p);
  }
})(ROOT);

const problems = [];
// R1 + R3: 位图位置
for (const f of files) {
  const ext = path.extname(f).toLowerCase();
  if (!IMG_EXT.includes(ext)) continue;
  const norm = f.split(path.sep).join('/');
  if (!/\.appiconset\//.test(norm)) problems.push(`R1 位图不在 appiconset 里: ${norm}`);
}
// R2: 捆绑资源 Image("name")
const swifts = files.filter((f) => f.endsWith('.swift'));
let bundled = 0;
for (const f of swifts) {
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  lines.forEach((raw, i) => {
    // 只判"紧贴左括号的字符串字面量"，别把 Image(uiImage: img) 或注释里的例子算进来
    const m = raw.match(/\bImage\(\s*"/);
    if (!m) return;
    const code = raw.replace(/\/\/.*$/, '');
    if (!/\bImage\(\s*"/.test(code)) return;
    bundled++;
    problems.push(`R2 捆绑资源 Image("…") : ${f}:${i + 1}  ${code.trim().slice(0, 88)}`);
  });
}
const symbolCount = swifts.reduce((a, f) => a + (fs.readFileSync(f, 'utf8').match(/Image\(systemName:/g) || []).length, 0);
const uiCount = swifts.reduce((a, f) => a + (fs.readFileSync(f, 'utf8').match(/Image\((uiImage|nsImage|decorative):/g) || []).length, 0);
const appiconPng = files.filter((f) => /\.appiconset\/.*\.png$/i.test(f.split(path.sep).join('/'))).length;

for (const p of problems) console.log('  ' + p);
console.log(`资源纪律 (219, 顾问级): appiconset 位图 ${appiconPng} 个(合法) · Image(systemName:) ${symbolCount} 处 · 运行时图像 ${uiCount} 处 · 违例 ${problems.length} 处`);
