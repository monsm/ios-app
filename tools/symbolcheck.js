#!/usr/bin/env node
// tools/symbolcheck.js — SF Symbols 名称白名单闸门（判失败）
//
// 背景：`Image(systemName:)` / `Label(_, systemImage:)` 遇到**不存在的符号名**时
// 不抛错、不留占位框，就是什么都不画。表现出来只是"这一行没图标"。
// 2026-10-29 连踩两次：
//   · 凭证工坊的临时码行 `clock.badge.chevron.right`（clock 的 badge 变体没有 chevron）
//   · 设备页「待添加指纹」空态 `hand.raised.dotted`
// 编译、swiftcheck、iconmap（只查"同标签是否配了不同图标"）全都不会红。
//
// 本闸门不验证"符号是否真的存在"（Windows 上没有 SF Symbols 目录，无法机检），
// 而是强制**每个名称都必须经过一次人工确认并写进 fixtures/sf-symbols-used.txt**。
// 新增图标名 → 先真机/模拟器确认存在 → 追加到清单；清单里多余的 → 删掉。
//
// 覆盖的图标位置（枚举式，不做"形似符号的字面量"猜测，避免误报）：
//   · systemImage: "..."
//   · Image(systemName: "...")
//   · icon: "..."                       （SearchHit / QuickAction / capabilityLabel / batchBtn 等）
//   · fanoutRow("...", ...)             （首参是图标名，不是 systemImage 标签）
//
// 用法：
//   node tools/symbolcheck.js            # 校验
//   node tools/symbolcheck.js --list     # 打印差异明细
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const ALLOW = path.join(ROOT, 'fixtures', 'sf-symbols-used.txt');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

const PATTERNS = [
  /systemImage:\s*"([^"]+)"/g,
  /Image\(systemName:\s*"([^"]+)"/g,
  /\bicon:\s*"([^"]+)"/g,
  /fanoutRow\(\s*"([^"]+)"/g,
];

const used = new Map();   // name -> [file:line]
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const text = fs.readFileSync(path.join(dir, f), 'utf8');
    text.split(/\r?\n/).forEach((line, i) => {
      const t = line.trim();
      if (t.startsWith('//') || t.startsWith('///')) return;
      for (const re of PATTERNS) {
        re.lastIndex = 0;
        for (const m of t.matchAll(re)) {
          if (!used.has(m[1])) used.set(m[1], []);
          used.get(m[1]).push(`${d}/${f}:${i + 1}`);
        }
      }
    });
  }
}

if (!fs.existsSync(ALLOW)) {
  console.error('✗ 缺少 fixtures/sf-symbols-used.txt');
  process.exit(1);
}
const allow = new Set(
  fs.readFileSync(ALLOW, 'utf8').split(/\r?\n/).map(s => s.trim()).filter(s => s && !s.startsWith('#'))
);

const missing = [...used.keys()].filter(n => !allow.has(n)).sort();
const stale = [...allow].filter(n => !used.has(n)).sort();

if (process.argv.includes('--list')) {
  if (missing.length) {
    console.log('=== 代码里有、白名单没有 ===');
    missing.forEach(n => used.get(n).forEach(loc => console.log(`  ${n}  @${loc}`)));
  }
  if (stale.length) {
    console.log('=== 白名单有、代码里没有 ===');
    stale.forEach(n => console.log(`  ${n}`));
  }
}

console.log(`符号白名单: 代码 ${used.size} 个 · 白名单 ${allow.size} 个 · 未登记 ${missing.length} · 过期 ${stale.length}`);

if (missing.length) {
  console.error('✗ 有未登记的 SF Symbol 名称：');
  missing.forEach(n => {
    console.error(`  ${n}`);
    used.get(n).slice(0, 3).forEach(loc => console.error(`      @${loc}`));
  });
  console.error('处理：先在真机/模拟器确认该符号存在，再追加到 fixtures/sf-symbols-used.txt。');
  process.exit(1);
}
if (stale.length) {
  console.error('✗ 白名单里有代码已不再使用的名称（清单会腐化，必须删）：');
  stale.forEach(n => console.error(`  ${n}`));
  process.exit(1);
}
console.log('✓ SF Symbol 名称全部已登记');
