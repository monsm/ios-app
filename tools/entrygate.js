'use strict';
// tools/entrygate.js —— 入口可点性闸门
//
// 用户反馈「很多入口不能点击」。实证到的第一个真 bug：
// MePage 的四个状态瓦片注释写着「每项都是一个能直接跳过去的入口」，
// 但 summaryTile 没有 action 参数、也没包发送航 —— 点上去什么都不会发生。
//
// 判据（一条，精确）：
//   E1 带 showsChevron: true 的 XRow 调用，必须有尾随闭包或外层 Button/NavigationLink
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const UI = path.join(ROOT, 'App/UI');
const files = fs.readdirSync(UI).filter(f => f.endsWith('.swift'));

let problems = [];

for (const f of files) {
  const s = fs.readFileSync(path.join(UI, f), 'utf8').replace(/\r\n/g, '\n');
  const lines = s.split('\n');

  // ── E1 ──
  for (let i = 0; i < lines.length; i++) {
    if (!/showsChevron:\s*true/.test(lines[i])) continue;
    const ctx = lines.slice(Math.max(0, i - 12), Math.min(lines.length, i + 4)).join('\n');
    // 尾随闭包（下一行是 } { ... } 形态）或外层包裹都算
    // XRow 的动作形态：showsChevron 之后紧跟 ") {"（尾随闭包）
    const tail = lines.slice(i, Math.min(lines.length, i + 4)).join('\n');
    const hasTrailing = /\)\s*\{/.test(tail) || /action:/.test(tail);
    if (/NavigationLink|Button\s*\{|Button\(|actionRow|\.onTapGesture/.test(ctx)) continue;
    if (hasTrailing) continue;
    problems.push({ rule: 'E1', file: f, line: i + 1, msg: 'XRow 带 chevron 但没有动作' });
  }

  // ── E3 已停用（2026-10-24）──
  // 原来按「注释里出现 入口/可点/轻点」判，实测 3 处全是散文提及（描述别的屏），
  // 判据不可靠。入口可点性真正可靠的机器判据只有 E1（带 chevron ⇒ 必须有动作）。
  // 其余靠 parity.js 的逐页对照 + 人工走查。
}

if (problems.length) {
  for (const p of problems.slice(0, 20)) {
    console.error('  ' + p.file + ':' + p.line + '  [' + p.rule + '] ' + p.msg);
  }
  console.error('✗ 入口可点性 ' + problems.length + ' 处（看着能点但没有动作）');
  process.exit(1);
}
console.log('入口可点性 ✓ 所有带可点暗示的入口都有动作（' + files.length + ' 文件）');
