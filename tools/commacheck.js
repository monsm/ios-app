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

    // ── 规则 2（2026-10-30 第 162 轮补）：**函数调用实参**的 label: value 之间漏逗号 ──
    // 第 150 轮我把 `window: "...",` 改成 `window: … ?? "…"` 时漏了末尾逗号，
    // 下一行 `note: note,` 被吞进同一表达式 ⇒ 连续 8 次构建全红（本闸门当时抓不到）。
    // 与规则 1 的区别：下一行是 `标签:` 而不是字符串字面量。
    // 精度关键：**排除函数/初始化器声明**（形参表和调用实参表长得一模一样）——
    // 靠跟踪每个 `(` 是由哪一行打开的：含 `func `/`init(` 的记为声明上下文。
    let depth = 0;
    const declDepth = new Set();
    for (let i = 0; i < L.length; i++) {
      const code = L[i].replace(/\/\/.*$/, "");
      const before = depth;
      const opensDecl = /\bfunc\s+\w+|\binit\s*\(/.test(code);
      for (const ch of code) {
        if (ch === "(") { depth++; if (opensDecl) declDepth.add(depth); }
        else if (ch === ")") { if (declDepth.has(depth)) declDepth.delete(depth); depth--; }
      }
      if (before < 1) continue;
      if (declDepth.has(before)) continue;              // 在声明形参表里 → 跳过
      const cur2 = L[i].replace(/\/\/.*$/, "").trimEnd();
      if (!/^[A-Za-z_]\w*\s*:\s/.test(cur2.trim())) continue;
      if (!/["\x27)\]}]$/.test(cur2.trim())) continue;  // 行尾是完整值
      if (/,$/.test(cur2.trim())) continue;
      let j2 = i + 1;
      while (j2 < L.length && (L[j2].trim() === "" || L[j2].trim().startsWith("//"))) j2++;
      if (j2 >= L.length) continue;
      const nxt2 = L[j2].replace(/\/\/.*$/, "").trim();
      if (/^[A-Za-z_]\w*\s*:\s/.test(nxt2)) {
        hits.push({ loc: `${d}/${f}:${i + 1}`, cur: cur2.trim(), nxt: nxt2 });
      }
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
