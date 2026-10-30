#!/usr/bin/env node
// kotlinchaincheck —— Compose `Modifier` 链的逗号位置闸门（判失败）。
//
// 正控：把 `.clickable { onClick() }` 行末的 `,` 保留、`.semantics { … },` 挂在下一行 ⇒
//       报出「参数列表已由前一行逗号闭合，后面又挂 .xxx」。
// 负控：全仓零误报。
//
// 2026-10-31（第 74 轮，**CI 连红的真根因**）：第 72 轮我给两处 Canvas 补无障碍语义，
// 把 `.semantics { … },` 插在 `.clickable { … },` 的**下一行** —— 而那个逗号已经闭合了
// `Box(modifier = …)` 的参数列表，于是下一行的 `.semantics` 变成「参数列表里的非法表达式」。
// CI 报：
//     MainActivity.kt:751:13  Syntax error: Expecting an expression.
//     MainActivity.kt:751:13  Syntax error: Expecting ')'.
//
// 判据（只查**确定的**形态，零误报优先）：
//   若某行以 `.xxx(...) { ... },` 结尾（即 modifier 链以逗号收尾），
//   而**下一非注释行**以 `.` 开头（继续挂 modifier）⇒ 矛盾 ⇒ 判失败。
//
// 正确写法：把逗号放到链的**最后一环**后面，或者把新的一环插在逗号之前。
//
// 正控：把圆盘的 .clickable { onClick() } 行末补回 ,（让下一行的 .semantics { 落在参数列表里）⇒
//       报出「MainActivity.kt:747 上一行以逗号闭合了参数列表，但第 751 行又挂 .semantics」—— 与 CI 报的同一个错误。
// 负控：全仓 37 处 modifier 链尾零误报。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const KT_DIR = path.join(ROOT, 'android-app', 'app', 'src', 'main', 'java', 'com', 'aapk', 'kfkey');

if (!fs.existsSync(KT_DIR)) {
  console.log('✓ 无 android-app 工程，跳过');
  process.exit(0);
}

const bad = [];
const okCount = { chains: 0 };

for (const f of fs.readdirSync(KT_DIR).filter(x => x.endsWith('.kt'))) {
  const src = fs.readFileSync(path.join(KT_DIR, f), 'utf8');
  const L = src.split(/\r?\n/);

  for (let i = 0; i < L.length - 1; i++) {
    const c = L[i].replace(/\/\/.*$/, '').trimEnd();
    if (!c.trim()) continue;

    // 该行是不是「modifier 链的一环 + 逗号收尾」
    // 形态：以 `,` 结尾，且行内有 `.xxx(` 或 `.xxx {`
    if (!/,$/.test(c)) continue;
    if (!/\.\w+\s*(\(|\{)/.test(c)) continue;
    // 排除函数参数（如 `onClick = { ... },`）—— 那种行首是标识符而非 `.`
    if (!/^\s*(?:Modifier|modifier)\s*$/.test(L[i]) && !/^\.\w/.test(c) && !/\.\w+\s*(\(|\{).*,$/.test(c)) continue;

    okCount.chains++;

    // 下一非注释行是否以 `.` 开头
    let j = i + 1;
    while (j < L.length && (/^\s*\/\//.test(L[j]) || !L[j].trim())) j++;
    if (j >= L.length) continue;
    const next = L[j].trimStart();
    if (/^\.\w/.test(next)) {
      bad.push(`${f}:${i + 1} 上一行以逗号闭合了参数列表，但第 ${j + 1} 行又挂 ${next.slice(0, 24)}`
        + `\n      上一行: ${c.trim().slice(0, 66)}`);
    }
  }
}

if (bad.length) {
  console.log(`✗ Compose modifier 链逗号位置错 ${bad.length} 处（Kotlin 必报 Syntax error）：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：`Box(modifier = Modifier…, contentAlignment = …)` 的参数是逗号分隔的。');
  console.log('`.clickable { … },` 的逗号**已经闭合了 modifier 这个参数**，后面再挂 `.semantics` 就是非法表达式。');
  console.log('修法：把逗号移到链的最后一环之后（`.clickable { … }.semantics { … },`）。');
  process.exit(1);
}
console.log(`✓ Compose modifier 链逗号位置正常（检查 ${okCount.chains} 处链尾）`);
