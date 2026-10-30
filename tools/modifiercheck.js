#!/usr/bin/env node
// modifiercheck —— SwiftUI「语句块后直接挂修饰符」闸门（判失败）。
//
// 2026-10-30 新增（第 6 轮）：第 163 轮我把 CredentialsView 里的
//     VStack(spacing: 0) { headerToolbar; if editMode { editList } else { mainList } }
// 整个删掉，改成裸的
//     if editMode { editList } else { mainList }
//     .safeAreaInset(edge: .bottom) { … }
// —— SwiftUI 里 `if/else` 是**语句**，语句不能接修饰符。CI 报
// `cannot infer contextual base` / `value of type '()' has no member 'safeAreaInset'`，
// **连续 6 次构建全红**，而本地 62 道闸门全绿（没有一道看这个）。
//
// 判据（保守，只报高置信度）：
//   某行是 `}`（块结束），紧跟的行以 `.` 开头（修饰符），
//   且那个 `}` 闭合的是一个 **if / else / for / switch / guard** 块（不是 `{` 表达式容器）。
//   ⇒ 判失败。
//
// 为什么不误报正常的 `VStack { … }.padding()`：那种 `}` 闭合的是 `容器名 {`，
// 容器调用本身是**表达式**，接修饰符合法。只有控制流语句块不行。
// 正控：把 `Group { … }` 收口删掉还原成 `if/else` 直挂 `.safeAreaInset` ⇒ 精确报出 `CredentialsView.swift:72`。
// 负控：全仓 146 个 Swift 文件零误报（`VStack { … }.padding()` 这类容器调用不报）。

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

function strip(line) {
  let inStr = false;
  for (let i = 0; i < line.length - 1; i++) {
    const ch = line[i], prev = i > 0 ? line[i - 1] : '';
    if (ch === '"' && prev !== '\\') inStr = !inStr;
    if (!inStr && ch === '/' && line[i + 1] === '/') return line.slice(0, i);
  }
  return line;
}

// 控制流开头（这些 `{` 打开的是语句块）
const CTRL = /^\s*(?:\}\s*)?(?:if|else|for|while|switch|guard|do|catch)\b/;

const bad = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const rel = `${d}/${f}`;
    const L = fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/);
    // 记录每个 `{` 打开时的行类型（语句块 vs 表达式容器）
    const stack = [];
    for (let i = 0; i < L.length; i++) {
      const code = strip(L[i]);
      const opens = (code.match(/\{/g) || []).length;
      const closes = (code.match(/\}/g) || []).length;
      // 先记本行打开的块
      for (let n = 0; n < opens; n++) stack.push(CTRL.test(code) ? 'stmt' : 'expr');
      const before = stack.length;
      for (let n = 0; n < closes; n++) stack.pop();

      // 本行是「纯 `}`」且闭合了语句块 → 检查下一行是否以 . 开头
      if (before > 0 && closes > 0 && code.trim().startsWith('}') && stack.length < before) {
        const closed = [];   // 从被 pop 的那些块里取最后一个
        // 简化：只看「本行只有 } 或 }）结尾」的情形
        const t = code.trim();
        if (/^\}+\s*$/.test(t)) {
          const kind = (function () {
            // 往回找这个块的开头
            let depth = 0;
            for (let k = i; k >= 0; k--) {
              const c = strip(L[k]);
              for (let m = c.length - 1; m >= 0; m--) {
                if (c[m] === '}') depth++;
                else if (c[m] === '{') { depth--; if (depth === 0) return CTRL.test(c) ? 'stmt' : 'expr'; }
              }
            }
            return 'expr';
          })();
          if (kind === 'stmt') {
            let j = i + 1;
            while (j < L.length && (L[j].trim() === '' || L[j].trim().startsWith('//'))) j++;
            if (j < L.length && strip(L[j]).trim().startsWith('.')) {
              bad.push(`${rel}:${i + 1}  语句块 } 之后直接挂 "${strip(L[j]).trim().slice(0, 34)}" —— 编译必红`);
            }
          }
        }
      }
    }
  }
}

if (bad.length) {
  console.log(`✗ 语句块后直接挂修饰符 ${bad.length} 处（SwiftUI 里 if/else 是语句，不能接 .xxx）：`);
  bad.slice(0, 20).forEach(x => console.log('  ' + x));
  console.log('\n修法：用 `Group { … }` 收口再挂修饰符（Group 不引入额外布局）。');
  process.exit(1);
}
console.log('✓ 未发现「语句块后直接挂修饰符」');
