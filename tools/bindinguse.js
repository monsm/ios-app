#!/usr/bin/env node
/**
 * tools/bindinguse.js — Binding 误用闸门（判失败）
 *
 * 为什么要有这一道：
 *   2026-10-26 把备份口令改成共享容器 `BackupPassphrase` 后，两处 `encPw`/`cloudPw`
 *   从 `String` 变成了 `Binding<String>`（为了给 SecureField 用），
 *   但**业务逻辑里的 9 处仍然把它当 String** —— `.isEmpty`、`!=`、传参。
 *   `swiftcheck`（括号）与 `swiftshape`（形状）都抓不到，只有真编译器会报
 *   "cannot convert value of type 'Binding<String>' to expected argument type 'String'"。
 *
 * 判据：
 *   声明为 `Binding<T>` 的属性，在非 SwiftUI 绑定参数位置（text:/isOn:/selection:/tag: 等）
 *   以裸名出现 ⇒ 红。
 */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

// SwiftUI 里接受 Binding 的参数标签 —— 这些位置裸名是错的，要用 $name，所以这里反而要放行 $
// SwiftUI 参数位：`label: cloudXxxField` 直接传 Binding 变量是**合法**的（参数类型就是 Binding）。
// 所以不能按「有没有 $」判，要看它是不是被当成**值**在算。
// 真的会编译失败的用法只有这几类：
//   · 调 String/Bool 的成员：xxx.isEmpty / xxx.count / xxx.hasPrefix
//   · 参与比较/运算：xxx == y / xxx != y / xxx + y
//   · 传给声明为 String/Bool 的参数（这里靠 isEmpty/比较两种覆盖绝大多数）
const VALUE_MISUSE = /(^|[^$\w.])(NAME)\s*(\.\s*(isEmpty|count|hasPrefix|hasSuffix|lowercased|uppercased|first|last|prefix|suffix|trimmingCharacters)|[!=]=|[+\-*\/]\s|\?\?)/;

const problems = [];

for (const file of walk(path.join(ROOT, 'App'))) {
  const rel = path.relative(ROOT, file).replace(/\\/g, '/');
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);

  // 收集所有 Binding<T> 属性名
  const binds = [];
  lines.forEach((l, i) => {
    const m = l.match(/var\s+(\w+)\s*:\s*Binding<([^>]+)>/);
    if (m) binds.push({ name: m[1], type: m[2], line: i + 1 });
  });
  if (binds.length === 0) continue;

  for (const b of binds) {
    const re = new RegExp('(^|[^$\\w.])' + b.name + '\\b');
    lines.forEach((l, i) => {
      if (i + 1 === b.line) return;                      // 声明行
      if (i + 1 === b.line + 1) return;                  // Binding(get:set:) 那一行
      const t = l.trim();
      if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) return;
      if (!re.test(l)) return;
      // 只有「当值算」才算问题 —— 直接当 Binding 实参传是对的
      const misuse = VALUE_MISUSE.source.replace('NAME', b.name);
      if (!new RegExp(misuse).test(l)) return;
      problems.push({ rel, line: i + 1, name: b.name, type: b.type, text: t.slice(0, 100) });
    });
  }
}

if (problems.length === 0) {
  console.log('Binding 误用闸门 (Binding<T> 属性的裸名使用) ✓ 零命中');
  process.exit(0);
}

console.error('✗ 声明为 Binding<T> 的属性被当成普通值用了 —— 编译会报类型不匹配');
console.error('  修法：要么在逻辑里读它的值（如 SharedXxx.current），要么在 SwiftUI 参数处写 $name。\n');
for (const p of problems) {
  console.error(`  ${p.rel}:${p.line}  ${p.name} (Binding<${p.type}>)  ${p.text}`);
}
console.error(`\n共 ${problems.length} 处。括号平衡与形状机检都抓不到这一类。`);
process.exit(1);
