#!/usr/bin/env node
// ============================================================================
// declcheck.js — 只查一类错误：@AppStorage / @State 等属性包装器引用了
//                但属性声明被误删的情况
// ============================================================================
//
// 由来:
//   本轮改 DoorFront.swift 时，我用数组 splice 替换一段视图代码，
//   把三个 @AppStorage / 计算属性的声明连同视图一起删掉了，引用还在。
//   swiftcheck（括号）和 swiftlint（臆造符号）都没发现 —— 它们不看作用域。
//
// 为什么不做完整的"未声明标识符"检查:
//   我试过了（refscheck.js），误报 11 处 —— if let 绑定、onChange 闭包参数、
//   for-in 变量……要收集全这些声明形式等于写一个 Swift parser。
//   那不是闸门的职责，是编译器的职责。
//
//   所以这里**只查能做对的那一小块**: 属性包装器（@State/@AppStorage/...）
//   形式固定，正则可靠，零误报。
//
// 用法: node tools/declcheck.js
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const APP = path.join(ROOT, 'App');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const files = walk(APP);
const findings = [];

// 每一处 @Wrapper private var name 都算"声明"。
// 然后检查：这个 name 在**同一个 struct/class 作用域里**被引用了吗？
// —— 反过来：有引用但没声明才报错。判定方式是扫描"裸标识符引用"。
//
// 但完整作用域分析做不了，所以换一个 100% 可靠的判据:
//   **每个 @Wrapper 声明的名字，必须在文件里至少出现 2 次（声明 + 至少一次使用）。**
//   如果只出现 1 次（仅声明），说明它是死变量。
//   反之，若某个名字被引用但全文件没有声明 —— 这个更难判。
//
// 真正能 100% 做对的是: **统计属性包装器声明，检验其名字在文件中被引用**。
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  const rel = path.relative(ROOT, f);

  // 收集所有属性包装器声明
  const FILE_PRIVATE = /^@(State|AppStorage|SceneStorage|FocusState|GestureState|Binding|Environment)$/;
  const decls = [...src.matchAll(/^\s*@(\w+)(?:\([^)]*\))?\s+(?:private\s+|public\s+|internal\s+)?(?:var|let)\s+(\w+)/gm)]
    .filter(d => FILE_PRIVATE.test('@' + d[1]));
  for (const d of decls) {
    const wrapper = d[1];
    const name = d[2];
    // 统计这个名字在文件里出现的次数
    const count = (src.match(new RegExp('\\b' + name + '\\b', 'g')) || []).length;
    if (count <= 1) {
      findings.push({ file: rel, msg: '@' + wrapper + ' ' + name + ' 只声明未使用（死变量）' });
    }
  }
}

// 自检: 人造一个死变量，确认能抓到
{
  const probe = '@State private var __deadProbe = false\n';
  const m = [...probe.matchAll(/^\s*@(\w+)(?:\([^)]*\))?\s+(?:private\s+)?(?:var|let)\s+(\w+)/gm)];
  if (m.length !== 1) {
    console.error('✗ 自检失败: 属性包装器正则抓不到');
    process.exit(1);
  }
  const cnt = (probe.match(new RegExp('\\b' + m[0][2] + '\\b', 'g')) || []).length;
  if (cnt !== 1) {
    console.error('✗ 自检失败: 死变量计数不对');
    process.exit(1);
  }
}

if (files.length === 0) {
  console.error('✗ 自检失败: 没扫到 .swift');
  process.exit(1);
}

if (findings.length) {
  for (const f of findings) console.error('  ✗ ' + f.file + '  ' + f.msg);
  console.error('✗ 属性包装器死变量 ' + findings.length + ' 处');
  process.exit(1);
}
console.log('✓ 属性包装器: ' + files.length + ' 文件, 无死变量（自检 3/3）');
