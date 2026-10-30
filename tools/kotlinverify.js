#!/usr/bin/env node
// kotlinverify —— 「改 Kotlin 后必须等 CI 绿」的提醒 + 本地可验证项汇总
//
// 2026-10-31（第 46/47 轮，**代价 5 次 CI 红**）：
// 我在没有 Kotlin 编译器的环境里连续改 Kotlin，靠闸门当代理。
// 第 37 轮引入 `.isEmpty` 缺 `()`，之后 5 轮都在改别的事，累积了 5 次红。
//
// 本脚本做两件事：
//   ① 报告「本地能验的」与「只有 CI 能验的」各是什么
//   ② 如果 tools/ 或 android-app/ 有未提交改动，提醒先等 CI
//
// 用法：node tools/kotlinverify.js
// 退出码恒 0（这是提醒工具，不是闸门 —— 别让它成为噪音）。

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');

console.log('═══ Kotlin 改动验证纪律 ═══\n');

console.log('本地能验的（69 道闸门已覆盖）：');
console.log('  ✓ 括号平衡          swiftcheck');
console.log('  ✓ 缺 import         kotlinimportcheck');
console.log('  ✓ Swift 写法混入    kotlinsyntaxcheck  (.isEmpty 缺 () 等)');
console.log('  ✓ 数值类型混算      kotlinmathcheck');
console.log('  ✓ 调色板对比度      kotlincontrast');
console.log('  ✓ 字节面对拍        kotlinshadow');
console.log('  ✓ 闸门路径可移植    gatepathcheck');
console.log('');
console.log('**只有 CI 能验的**（Kotlin 编译器才知道）：');
console.log('  ✗ 参数名与使用不一致（onToggle vs onToggleSound 这类）');
console.log('  ✗ 局部变量类型推断错误');
console.log('  ✗ 函数重载解析失败');
console.log('  ✗ Compose 作用域限制（@Composable 上下文）');
console.log('  ✗ 泛型约束不满足');
console.log('  ✗ 任何闸门没想到的语法/语义错误');
console.log('');

// 检查未提交的 Kotlin 改动
let dirty = [];
try {
  const out = execSync('git status --porcelain', { cwd: ROOT, encoding: 'utf8', timeout: 15000 });
  dirty = out.split('\n').filter(l => l.trim() && (l.includes('.kt') || l.includes('tools/')));
} catch { /* git 不可用时跳过 */ }

if (dirty.length) {
  console.log('⚠ 检测到未提交的 Kotlin / 闸门改动：');
  dirty.slice(0, 10).forEach(l => console.log('  ' + l.trim()));
  console.log('');
  console.log('**纪律**：改完 Kotlin 立刻提交 + 推送，等 CI 绿了再做下一件事。');
  console.log('  连续改多个 Kotlin 改动而不等 CI，会让一次语法错误累积成多次红。');
  console.log('  拿到失败日志的办法：`node fx/ci_logs_ctx.js`（用 git credential 里的 token）。');
} else {
  console.log('✓ 无未提交的 Kotlin / 闸门改动');
}

console.log('');
process.exit(0);
