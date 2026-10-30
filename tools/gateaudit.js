#!/usr/bin/env node
// gateaudit —— 闸门自检：每道闸门**真的能失败**吗？
//
// 2026-10-30 新增（第 110 轮）：台账里最大剩余项是「闸门自身正确性 —— 58 道里只做了 6 道正控」。
// 逐道注入合成违规太慢，但「这个脚本有没有能力失败」可以**静态判定**：
//
//   G1 有 `process.exit(1)`（或 throw）—— 没有任何失败出口的脚本是报告器，不是闸门
//   G2 真的读源码（`readFileSync` / `readdirSync`）—— 不读源码就无从检查
//   G3 有实质判据（≥2 个正则字面量或 `.test(` / `.match(` 调用）
//   G4 不吞掉自己的失败（不得出现 `process.exit(0)` 在所有分支之前）
//
// 局限（诚实写清）：本工具只能证明「闸门有失败的能力」，**不能证明它的判据是对的** ——
// 后者必须逐道正控（见第 101/102/104/107/109 轮的做法）。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const AG = path.join(ROOT, 'tools/allgates.js');

// 从 allgates 里取出闸门清单（唯一真相）
const agSrc = fs.readFileSync(AG, 'utf8');
const gates = [...agSrc.matchAll(/\['(\w+)',\s*\[/g)].map(m => m[1]);
if (!gates.length) { console.log('X 未能从 allgates 解析出闸门清单'); process.exit(1); }

const report = [];
const advisory = [];
for (const g of gates) {
  const p = path.join(ROOT, 'tools', g + '.js');
  if (!fs.existsSync(p)) { report.push({ g, bad: ['文件不存在'] }); continue; }
  const src = fs.readFileSync(p, 'utf8');
  const code = src.replace(/\/\/[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '');

  // 顾问型：头注明确写「不判失败 / 顾问级 / 只报线索 / 恒退出 0 / 线索生成器」——它们**本来就不该失败**
  const header = src.split(/\r?\n/).slice(0, 25).join('\n');
  const isAdvisory = /不判失败|顾问级|只报线索|恒退出\s*0|线索生成器/.test(header);
  if (isAdvisory) { advisory.push(g); continue; }

  const bad = [];

  // G1 失败出口 —— 任意非零退出都算：
  //   process.exit(1) / process.exit(2) / process.exit(cond ? 1 : 0) / process.exitCode = N / throw
  const hasExit1 = /process\.exit\(\s*[12]\s*\)/.test(code)
    || /process\.exit\([^;]*\?/.test(code)          // 三元形式（嵌套括号也覆盖）
    || /process\.exitCode\s*=\s*[^0\s]/.test(code)
    || /\bthrow\s+new\b/.test(code);
  if (!hasExit1) bad.push('G1 无失败出口（没有非零 exit / 三元 exit / exitCode / throw）');

  // G2 读源码 —— 直接读文件，或 `require` 本仓模块（如 shadowdiff 加载 vendor JS 做差分）
  const reads = /readFileSync|readdirSync|execFileSync|execSync|spawnSync/.test(code)
    || /require\(\s*path\.join\(\s*__dirname/.test(code)
    || /require\(\s*['"]\.\.?\//.test(code);
  if (!reads) bad.push('G2 不读源码（无 readFileSync / readdirSync / exec / 本仓 require）');

  // G3 实质判据 —— 正则/字符串判定，或字符级扫描（swiftcheck 那类按字符数括号的）
  const reCount = (code.match(/\/[^\/\n]+\/[gimsuy]*/g) || []).length;
  const testCalls = (code.match(/\.(test|match|exec|includes|startsWith|hasPrefix)\(/g) || []).length;
  const charScan = /charCodeAt|codePointAt|for\s*\(\s*const\s+ch\s+of|\[\.\.\.\w+\]|\w+\[i\]|for\s*\(\s*let\s+i\s*=\s*0/.test(code);
  if (reCount + testCalls < 3 && !charScan) {
    bad.push(`G3 判据过少（正则 ${reCount} 个 / 判定调用 ${testCalls} 次 / 无字符级扫描）`);
  }

  // G4 无条件 exit 0
  if (/process\.exit\(\s*0\s*\)/.test(code) && !hasExit1) bad.push('G4 只有 exit(0)');

  if (bad.length) report.push({ g, bad });
}

console.log(`════ 闸门自检（${gates.length} 道：硬闸门 ${gates.length - advisory.length}，顾问型 ${advisory.length}）════\n`);
if (advisory.length) console.log(`顾问型（头注写明不判失败，不参与判定）: ${advisory.join(' / ')}\n`);
if (!report.length) {
  console.log('✓ 每道硬闸门都有：失败出口 + 读源码 + 实质判据');
  process.exit(0);
}
console.log(`⚠ ${report.length} 道闸门可疑：`);
for (const r of report) {
  console.log(`  ${r.g}`);
  for (const b of r.bad) console.log(`      ${b}`);
}
console.log('\n注意：本工具只证明「有失败的能力」，不证明「判据是对的」。');
console.log('后者必须逐道正控（第 101/102/104/107/109 轮已对 6 道做过）。');
process.exit(1);
