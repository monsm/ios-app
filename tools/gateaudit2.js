#!/usr/bin/env node
// gateaudit2 —— 「闸门自身的可信度」元闸门（判失败）。
//
// 2026-10-31（第 58 轮）：本仓有 75 道闸门，但我这 18 轮新加的 8 道**正控验证只在会话里做过，
// 没写进文件** —— 下次维护者（或未来的我）不知道它们被验证过，可能误以为"从没验过"而
// 重新写一遍，或者更糟：改了判据却没重做正控，闸门悄悄失效。
//
// 判据（只查**新加**的高风险闸门，不追溯历史）：
//   ① 文件头（前 30 行）必须出现「正控」或「已验证」或「self-test」字样 —— 说明作者做过反向验证；
//   ② 若闸门判失败（含 process.exit(1)），必须有对应的「修法」提示（不能只报错不指路）。
//
// 白名单：纯统计/扫描类闸门（无判失败能力）不需要正控记录。
const fs = require('fs');
const path = require('path');

const TOOLS = path.resolve(__dirname);

// 这些闸门只做统计输出，从不出非零退出码 —— 不需要正控
const STATS_ONLY = new Set([
  'apisweep.js', 'auditcover.js', 'bigfiles.js', 'deadscan.js', 'delsweep.js',
  'dupscan.js', 'perfscan.js', 'constscan.js', 'citecheck.js', 'symbolcheck.js',
  'toplevel.js', 'bindinguse.js', 'assetscheck.js', 'iconmap.js', 'keydead.js',
  'aritycheck.js', 'commacheck.js', 'sheetcover.js', 'destmap.js',
]);

// 2026-10-31（第 58 轮，**闸门不该一次报 42 处** —— 那会训练人忽略它）：
// 本闸门只查「近期新加的、尚未补齐自检记录的」闸门。历史闸门的自检状态不在本闸门的管辖范围
// （它们的正控若从没做过，那是历史债，一次性报 42 条既不能修也不该堵 CI）。
//
// 规则：新加闸门时把它加进 NEW_GATES 并补自检记录；补完之后从列表移除。
const NEW_GATES = [
  "modifiercheck.js", "scopecheck.js", "gatepathcheck.js",
  "kotlinimportcheck.js", "kotlinmathcheck.js", "kotlinsyntaxcheck.js",
  "kotlincontrast.js", "gatepersistcheck.js", "docclaimcheck.js", "hotpathcheck.js", "kotlinchaincheck.js", "docnumbercheck.js", "asyncwindowcheck.js", "kotlinasyncwindowcheck.js", "manualunlockcheck.js", "kotlinmanualcheck.js", "uishellcheck.js",
];

const bad = [];
const okList = [];

for (const f of NEW_GATES) {
  if (!fs.existsSync(path.join(TOOLS, f))) continue;
  if (!f.endsWith('.js')) continue;
  if (['allgates.js', 'add_ci_step.js', 'gateaudit2.js'].includes(f)) continue;
  if (STATS_ONLY.has(f)) continue;

  const src = fs.readFileSync(path.join(TOOLS, f), 'utf8');
  const head = src.split(/\r?\n/).slice(0, 30).join('\n');
  const canFail = /process\.exit\(1\)/.test(src);

  if (!canFail) continue;   // 不出非零码 = 不是判失败闸门

  // ① 自检记录
  const hasSelfCheck = /正控|反控|负控|已验证|self-test|自检/.test(head);
  if (!hasSelfCheck) bad.push(f + '：文件头缺「正控/已验证」记录（作者是否做过反向验证无法追溯）');

  // ② 修法提示（有 bad()/错误输出时要有"修法/修法：/请"）
  const hasFixHint = /修法|请|should|改为|改成/.test(src);
  if (!hasFixHint) bad.push(f + '：缺「修法」提示（只报错不指路）');

  if (hasSelfCheck && hasFixHint) okList.push(f);
}

if (bad.length) {
  console.log(`✗ 闸门自身可信度问题 ${bad.length} 处：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：判失败闸门若从没做过反向验证，它可能"永远绿"（判据写错却没人发现）。');
  console.log('本仓纪律（第 101 轮）：每道新闸门必须有正控 + 负控。');
  console.log('修法：在文件头加一行 `// 正控：<注入什么> ⇒ <报什么>`，让验证可追溯。');
  process.exit(1);
}
console.log(`✓ 判失败闸门 ${okList.length} 道均有自检记录 + 修法提示`);
