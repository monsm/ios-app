#!/usr/bin/env node
// 闸门：注释里引用的 `文件名:行号` 是否越界。
//
// 2026-10-30 新增（第 100 轮）：本仓经历过多次文件拆分（LockKeeperApp 1138→616 行、
// LockService 1081→122 行 …），而注释里的 `Xxx.swift:123` 引用**不会自动跟着改**。
// 第 99 轮就发现 `Store.swift:124` 引用「AuditChain:242」，而那个文件只有 53 行。
//
// 纪律（本仓第二批 #13 已定）：这类注释**只写符号名，不写行号**。
// 本闸门兜住已经写了的那些：只判「行号是否超出该文件当前行数」，不判内容对不对
// （后者需要人读，静态做不到）。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

const byBase = new Map();
const allFiles = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const p = path.join(dir, f);
    const src = fs.readFileSync(p, 'utf8');
    const base = f.replace(/\.swift$/, '');
    if (!byBase.has(base)) byBase.set(base, []);
    byBase.get(base).push({ rel: `${d}/${f}`, lines: src.split(/\r?\n/).length });
    allFiles.push({ rel: `${d}/${f}`, src });
  }
}

const bad = [];
const deadFile = [];
const checked = new Set();
const checkedFile = new Set();
for (const { rel, src } of allFiles) {
  const L = src.split(/\r?\n/);
  L.forEach((l, i) => {
    const t = l.trim();
    if (!/^\/\//.test(t)) return;

    // ① 行号引用：`Xxx.swift:N`
    const ms = [...t.matchAll(/([A-Za-z_][\w.]+?)(?:\.swift)?:(\d{2,4})\b/g)];
    for (const m of ms) {
      const base = m[1].replace(/\.swift$/, '');
      const ln = Number(m[2]);
      const key = base + ':' + ln;
      if (checked.has(key)) continue;
      checked.add(key);
      const files = byBase.get(base);
      if (!files) continue;
      if (!files.some(x => ln <= x.lines)) {
        bad.push({ loc: `${rel}:${i + 1}`, ref: m[0], max: Math.max(...files.map(x => x.lines)) });
      }
    }

    // ② 死文件引用：`Xxx.swift` 但本仓无此文件
    //    只保留**两类**豁免，其余一律报错：
    //    · 例外 A：明确写「已删 / 已移除 / 原为 / 原住 / 拆分前 / 拆出 / 随…移除」的历史说明 ——
    //              那是**正确记录**，不是死引用（本仓大量注释用这种形式记录删除史）；
    //    · 例外 B：注释本身在描述"某文件名不存在"（如「原句写 SpeechKit.swift…但不存在」）——
    //              这类说明必然包含那个文件名。
    //    ⚠ 2026-10-30（第 101 轮）**删掉了原本的「`见 Xxx.swift` 豁免」** ——
    //    它的理由（"指向已拆分的同名族"）不成立：`见 RecordsTimeline.swift` 里的 RecordsTimeline 是真存在的，
    //    不需要豁免；而它会让 `见 Nonexistent.swift` 也被放过（注入测试实测漏报）。
    //    「文件是否存在」这件事没有例外 —— 不存在就是死引用。
    const HIST = /已删|已移除|原为|原住|原文件|拆分前|拆分后|拆出|整文件删除|随.{0,10}移除|不在本仓|已随/;
    const DESCRIBES_MISSING = /原句|原注|原文|此前写|曾写|写的是|不存在|无此文件/;
    const fm = [...t.matchAll(/([A-Za-z_][\w.-]*)\.swift\b(?!:\d)/g)];
    for (const m of fm) {
      // ⚠ `byBase` 的键是**不带 .swift** 的 basename（见上面 base = f.replace(/\.swift$/,'')），
      //   所以这里必须用 m[1]（不带扩展名）去查 —— 用 `m[1] + '.swift'` 查会永远 false。
      const base = m[1];
      const name = base + '.swift';
      const dk = name + '|' + (byBase.has(base) ? 'ok' : 'dead');
      if (checkedFile.has(dk)) continue;
      checkedFile.add(dk);
      if (byBase.has(base)) continue;
      // 历史说明可能跨行（例：某条注释先写「App/UI/ExportCenter（2307 行…）」，下一行才写「已随大删波 4 移除」），
      // 所以看当前行 + 下一行。
      const ctx = t + ' ' + (L[i + 1] || '').trim();
      if (HIST.test(ctx)) continue;
      if (DESCRIBES_MISSING.test(ctx)) continue;
      deadFile.push({ loc: `${rel}:${i + 1}`, name, note: t.slice(0, 80) });
    }
  });
}

if (bad.length) {
  console.log(`✗ 注释里的行号引用越界 ${bad.length} 处：`);
  for (const b of bad) console.log(`  ${b.loc}  引用 \`${b.ref}\` —— 该文件最多 ${b.max} 行`);
  console.log('\n修法：改成只写符号名（本仓纪律：这类注释不写行号）。');
  process.exit(1);
}
if (deadFile.length) {
  console.log(`✗ 注释引用了不存在的 .swift 文件 ${deadFile.length} 处：`);
  for (const b of deadFile) console.log(`  ${b.loc}  引用 \`${b.name}\`\n      ${b.note}`);
  console.log('\n修法：要么改成真实文件名，要么明确标注「已删/已移除」（历史说明是被允许的）。');
  process.exit(1);
}
console.log(`✓ 注释里的行号引用全部在范围内（检查 ${checked.size} 个）；`
  + `引用的 .swift 文件名全部存在（检查 ${checkedFile.size} 个）`);
