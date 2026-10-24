#!/usr/bin/env node
// tools/optunwrap.js —— 可选属性裸用检查（第 50 轮新增，顾问级+可判定的子集）
//
// 由来：第 49 轮 CI 失败 —— XStatChip.tint 从 Color 改成 Color? 后，
// 三处消费点只改了两处，漏了 .foregroundStyle(tint)。
// swiftcheck（括号平衡）/apicheck（符号存在）都抓不到可选类型错。
//
// 本工具抓**确定性子集**：同一 struct 内声明 var X: T? 且同 struct 内
// 出现 .modifier(X) / .stroke(X, / .fill(X) 这类"直接消费"形态（无 ?? 兜底、
// 无 if let 解包、非参数标签传值）。同 struct 内变量来源确定，无跨文件歧义。
//
// 不判失败的场景：传给接受可选的 API（如 tint(Color?)）—— 所以只报"可疑"，
// 由人读。但本仓实践中这类形态几乎全是漏兜底。

'use strict';
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');

function swiftFiles(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) swiftFiles(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const files = swiftFiles(path.join(ROOT, 'App'));
const problems = [];

for (const f of files) {
  const rel = path.relative(ROOT, f);
  const src = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n');
  // 切 struct 块
  for (const m of src.matchAll(/struct\s+(\w+)[^\{]*\{/g)) {
    const start = m.index;
    let depth = 0, end = start;
    for (let j = src.indexOf('{', start); j < src.length; j++) {
      if (src[j] === '{') depth++;
      else if (src[j] === '}') { depth--; if (depth === 0) { end = j; break; } }
    }
    const body = src.slice(start, end);
    // 找可选属性
    for (const pm of body.matchAll(/var\s+(\w+)\s*:\s*([\w.<>?\[\]]+)\?\s*[\n={]/g)) {
      const name = pm[1];
      // 消费形态：.xxx(name) 或 .xxx(name, 或 (name: —— 但排除 name ?? / if let / : name
      const consumes = [...body.matchAll(new RegExp('\\.(?:foregroundStyle|stroke|fill|background|tint|overlay)\\(\\s*' + name + '\\s*[,)]', 'g'))];
      for (const c of consumes) {
        const ctx = body.slice(Math.max(0, c.index - 120), c.index + 60);
        if (ctx.includes(name + ' ??') || ctx.includes('if let ' + name) || ctx.includes('if let')) continue;
        const line = src.slice(0, start + c.index).split('\n').length;
        problems.push(rel + ':' + line + '  可选属性 ' + name + ' 裸传给 ' + c[0].trim().slice(0, 40));
      }
    }
  }
}

if (problems.length === 0) {
  console.log('可选属性裸用 ✓ 无（扫 ' + files.length + ' 文件）');
  process.exit(0);
}
console.log('可选属性裸用可疑 ' + problems.length + ' 处（请人读）：');
problems.forEach(p => console.log('  · ' + p));
process.exit(0);  // 顾问级：API 可能本来就收可选
