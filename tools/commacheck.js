#!/usr/bin/env node
// commacheck —— 数组/参数列表元素之间的**逗号缺失**闸门。
//
// 为什么需要它：第 66 轮往 `rollbackFamilies` 里插了一行数组元素，行尾漏了逗号：
//     "kf_rflt_", ..., "kf_rdispo"        ← 少了 ,
//     "kf_cseq_", ...                     ← 下一行是新元素
// 本地 48 道闸门全部放行（swiftcheck 只查括号平衡，逗号不在它的判据里），
// 只有 CI 编译报 `Expected ',' separator`，白等 4 分钟。
//
// 判据（保守，只报高置信度）：
//   本行以元素结束符结尾（" / ' / 数字）且**没有逗号**、**不是闭合符**，
//   下一行以字符串字面量开头（明显是新元素）。
// 排除：控制流关键字结尾、闭包开头、链式调用（下一行以 . 开头）。
//
// 已知局限：只覆盖「元素以字符串字面量开头」的情形。数字/标识符元素漏逗号
// 在 Swift 里通常会立刻被类型检查抓到，或与「两个表达式」不可区分，故不报。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

const hits = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const L = fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length - 1; i++) {
      const raw = L[i];
      const cur = raw.replace(/\/\/.*$/, '').trimEnd();
      if (!cur || cur.trim().startsWith('//') || cur.trim().startsWith('///')) continue;

      // 本行必须含字符串字面量，且以元素结束符收尾、无逗号、非闭合符
      const quoteCount = (cur.match(/"[^"]*"/g) || []).length;
      if (quoteCount < 1) continue;
      if (!/["']$/.test(cur)) continue;
      if (/[)\]]$/.test(cur)) continue;

      // 下一行必须是字符串字面量开头（新元素）
      const nxt = L[i + 1].replace(/\/\/.*$/, '').trim();
      if (!nxt || !/^"/.test(nxt)) continue;

      // 排除控制流 / 声明关键字结尾
      if (/\b(case|return|if|guard|else|where|in|try|throw|await|let|var)\b/.test(cur)) continue;

      hits.push({ loc: `${d}/${f}:${i + 1}`, cur: cur.trim(), nxt: nxt });
    }
  }
}

if (hits.length === 0) {
  console.log('✓ 数组/参数列表元素之间没有漏逗号');
  process.exit(0);
}
console.log(`✗ 发现 ${hits.length} 处疑似漏逗号（上一行以元素结尾无逗号、下一行是新元素）:`);
for (const h of hits) {
  console.log(`  ${h.loc}`);
  console.log(`       ${h.cur}`);
  console.log(`       ${h.nxt}`);
}
console.log('\n修法：上一行末尾补一个逗号。');
process.exit(1);
