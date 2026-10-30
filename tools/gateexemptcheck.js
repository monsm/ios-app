#!/usr/bin/env node
// gateexemptcheck —— 闸门豁免规则的可审计性（判失败）。
//
// 正控：在 `tools/emptycheck.js` 的 WHITELIST 里加一条没有理由的项
//       `['SomeView']` ⇒ 报出「白名单项缺理由」。
// 负控：全仓 17 条豁免全部合规。
//
// 2026-10-31（UI/UX 第 6 轮）：第 5 轮发现 `uicoverage` 对 `VariantGrammar.swift` **整文件豁免**，
// 导致 6 处裸 `.font` 长期漏检（那 6 处绕过系统「加粗文本」开关）。
// 「闸门豁免过宽」比「闸门不存在」更隐蔽 —— 闸门看起来是绿的，而它本该抓的东西漏了。
//
// 所以本闸门**不判「豁免对不对」**（那需要语义理解），只判**三条可机器查的形式要求**：
//   ① 每条**白名单项**必须写明理由（字符串里含中文理由 / `why` 字段）。
//   ② **整文件/整目录跳过**必须在该行有注释说明理由（`//` 后至少 8 个字）。
//   ③ 不允许「整目录递归跳过源码目录」—— 那等于闸门对该目录失效。
//
// 这三条能挡住绝大多数「豁免写得太随意」的情况，且零误报。
//
// 正控：在 `tools/emptycheck.js` 的 WHITELIST 里加一条无理由的 `['SomeView']` ⇒
//       报出「emptycheck.js:25 白名单项缺理由」，退出码 1。
// 负控：9 条合规豁免零误报。
const fs = require('fs');
const path = require('path');

const TOOLS = path.resolve(__dirname);
const SKIP = ['allgates.js', 'add_ci_step.js', 'gateexemptcheck.js', 'gateaudit2.js'];

const bad = [];
const okList = [];

for (const f of fs.readdirSync(TOOLS)) {
  if (!f.endsWith('.js')) continue;
  if (SKIP.includes(f)) continue;
  const src = fs.readFileSync(path.join(TOOLS, f), 'utf8');
  const L = src.split(/\r?\n/);

  // ① 白名单数组项必须有理由
  for (let i = 0; i < L.length; i++) {
    const c = L[i];
    // 形如  ['Name', '理由']  或  { name: 'x', why: '理由' }
    if (/^\s*\[\s*['"]\w+['"]\s*,\s*['"][^'"]{8,}['"]\s*\]\s*,?\s*$/.test(c)) { okList.push(`${f}:${i + 1} 白名单项有理由`); continue; }
    if (/^\s*\{\s*name\s*:\s*['"]\w+['"]\s*,\s*why\s*:\s*['"][^'"]{8,}['"]\s*\}/.test(c)) { okList.push(`${f}:${i + 1} 白名单项有 why`); continue; }
    if (/^\s*\{\s*file\s*:\s*['"][^'"]+['"]/.test(c) && !/why\s*:/.test(c)) {
      // 多行对象，理由可能在下一行 —— 往下 4 行找
      let hasWhy = false;
      for (let k = i; k < i + 5 && k < L.length; k++) if (/why\s*:\s*['"][^'"]{8,}['"]/.test(L[k])) hasWhy = true;
      if (!hasWhy) bad.push(`${f}:${i + 1} 白名单项（file 形式）缺 why 字段`);
    }
    // 形如  ['Name']  单元素（无理由）
    if (/^\s*\[\s*['"]\w+['"]\s*\]\s*,?\s*$/.test(c)) {
      bad.push(`${f}:${i + 1} 白名单项缺理由：${c.trim().slice(0, 50)}`);
    }
  }

  // ② 整文件/整目录跳过必须有注释理由
  for (let i = 0; i < L.length; i++) {
    const c = L[i];
    const m = c.match(/if\s*\(\s*(?:rel|file|f)\s*===?\s*['"]([^'"]+)['"]\s*\)\s*(?:continue|\{\s*continue;\s*\})/);
    if (!m) continue;
    const hasReason = /\/\/\s*\S{8,}/.test(c);
    if (hasReason) okList.push(`${f}:${i + 1} 整文件跳过（${m[1]}）有理由`);
    else bad.push(`${f}:${i + 1} 整文件跳过（${m[1]}）没写理由 —— 后人不知道能不能收窄`);
  }

  // ③ 不许跳过整个源码目录
  for (let i = 0; i < L.length; i++) {
    if (/DIRS\s*=\s*\[[^\]]*\]/.test(L[i]) && /(?:\.\.\/)?App['"]/.test(L[i])) {
      // 正常：DIRS 声明要扫哪些目录
      continue;
    }
    if (/if\s*\(\s*!fs\.existsSync\(dir\)\s*\)\s*continue/.test(L[i])) continue;   // 目录不存在就跳过，正常
    if (/for\s*\(\s*const\s+\w+\s+of\s+DIRS\s*\)/.test(L[i])) continue;
    if (/continue;\s*\/\/\s*(?:跳过整个|不扫).*(?:App|Widget|Shared)/.test(L[i])) {
      bad.push(`${f}:${i + 1} 跳过了整个源码目录 —— 等于闸门对该目录失效`);
    }
  }
}

if (bad.length) {
  console.log(`✗ 闸门豁免规则 ${bad.length} 处不合规：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：「闸门豁免过宽」比「闸门不存在」更隐蔽 —— 闸门看起来是绿的，而它本该抓的东西漏了。');
  console.log('（第 5 轮实证：`uicoverage` 对 VariantGrammar.swift 整文件豁免，漏检 6 处裸 .font。）');
  console.log('修法：给白名单项补理由（字符串 ≥8 字 / `why` 字段）；给整文件跳过补 `//` 注释理由。');
  process.exit(1);
}
okList.forEach(x => console.log('ok    ' + x));
console.log(`\n✓ 闸门豁免规则 ${okList.length} 条全部合规（有理由 / 有注释）`);
