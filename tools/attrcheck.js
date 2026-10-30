#!/usr/bin/env node
// attrcheck —— Swift **属性与声明配对**闸门。
//
// 2026-10-30 新增（第 109 轮）：本轮我把 `private func openDetail(_:)` 插到了
// `@ViewBuilder` 与它原本修饰的 `timelineRow` **之间** —— 于是 `@ViewBuilder`
// 落到了一个返回 `Void` 的函数上，CI 报
//   "unexpected non-void return value in void function"
// 而本地 `swiftcheck` 只查括号平衡、`swiftshape` 只查若干形状规则，都没抓到。
//
// 判据：
//   A1 `@ViewBuilder` 修饰的函数必须返回 `some View` / `View` / 具体 View 类型；
//      修饰的属性/computed property 同理。
//   A2 属性行与它修饰的声明之间不得夹着**别的声明**（那说明属性挂错了对象）。
//
// 只查 `@ViewBuilder`（本仓用得最多、也最容易挂错的那个）；
// 其它属性（@State / @MainActor …）挂错通常会被类型系统抓到，不在此重复。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

const problems = [];

for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const rel = `${d}/${f}`;
    const L = fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/);

    for (let i = 0; i < L.length; i++) {
      if (!/^\s*@ViewBuilder\s*$/.test(L[i])) continue;

      // 向下跳过空行与注释，找第一个声明行
      let k = i + 1;
      while (k < L.length && (L[k].trim() === '' || /^\s*\/\//.test(L[k]))) k++;
      if (k >= L.length) {
        problems.push({ loc: `${rel}:${i + 1}`, msg: '@ViewBuilder 后面没有任何声明（文件结束）' });
        continue;
      }

      const decl = L[k];
      // 情况 A：修饰 func
      if (/^\s*(?:private\s+|internal\s+|public\s+|fileprivate\s+|@\w+\s+)*func\s+/.test(decl)) {
        // 取签名（可能跨行，向下找 `{` 或行尾）
        let sig = decl;
        let m = k;
        while (!sig.includes('{') && m + 1 < L.length && m - k < 4) { m++; sig += ' ' + L[m]; }
        const returnsView = /->\s*(?:some\s+View|View|AnyView|\w+View)\b/.test(sig);
        if (!returnsView) {
          problems.push({ loc: `${rel}:${i + 1}`, msg: `@ViewBuilder 修饰的函数不返回 View: ${decl.trim().slice(0, 70)}` });
        }
        continue;
      }

      // 情况 B：修饰 computed property（var xxx: some View { … }）
      if (/^\s*(?:private\s+|internal\s+|public\s+|fileprivate\s+|@\w+\s+)*var\s+\w+\s*:/.test(decl)) {
        const returnsView = /:\s*(?:some\s+View|View|AnyView|\w+View)\b/.test(decl);
        if (!returnsView) {
          problems.push({ loc: `${rel}:${i + 1}`, msg: `@ViewBuilder 修饰的属性不是 View: ${decl.trim().slice(0, 70)}` });
        }
        continue;
      }

      // 情况 C：后面跟的是别的声明（struct/class/enum/let/…）→ 属性挂错对象
      problems.push({ loc: `${rel}:${i + 1}`, msg: `@ViewBuilder 后面不是 func/var: ${decl.trim().slice(0, 70)}` });
    }
  }
}

if (problems.length) {
  console.log(`✗ @ViewBuilder 挂错对象 ${problems.length} 处：`);
  for (const p of problems) console.log(`  ${p.loc}\n      ${p.msg}`);
  console.log('\n后果：CI 报 "unexpected non-void return value in void function"，本地形状闸门抓不到。');
  console.log('修法：把插进来的新声明移到被修饰声明的**后面**，别插在属性与声明之间。');
  process.exit(1);
}
console.log('✓ @ViewBuilder 全部挂在返回 View 的声明上');
