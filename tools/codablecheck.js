#!/usr/bin/env node
// tools/codablecheck.js — 持久化 Codable 模型的「容错解码」棘轮（判失败：只许降不许升）
//
// 背景：Swift 的**合成** init(from:) 只对 Optional 字段用 decodeIfPresent；
// 非 Optional 字段的默认值**不参与解码** —— 键必须存在。
// 于是一次「给模型加一个字段」或「导入一份缺字段的旧备份」就会让整份数据解码失败，
// 而失败后果往往是静默的：
//   · Ledger 家族  → markLedgerCorrupt，整个会话的凭证写入被拒
//   · LogCache     → readLogs 返回空，记录页看起来「记录全没了」
//   · MemberExt    → 整张成员扩展表变空，角色/分组/归档全部回落默认值
//
// 规则：凡 `struct X: Codable` 且**有非 Optional 存储字段**、又没有手写 `init(from decoder:` 的，
// 记一条。基线在 fixtures/codable-baseline.json，只允许减少（逐个补容错 init）。
//
// 用法：
//   node tools/codablecheck.js            # 校验
//   node tools/codablecheck.js --list     # 打印当前所有未容错的模型
//   node tools/codablecheck.js --update   # 补完容错 init 后收窄基线
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const BASE = path.join(ROOT, 'fixtures', 'codable-baseline.json');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

function scan() {
  const out = [];
  for (const d of DIRS) {
    const dir = path.join(ROOT, d);
    for (const f of fs.readdirSync(dir)) {
      if (!f.endsWith('.swift')) continue;
      const L = fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/);
      for (let i = 0; i < L.length; i++) {
        const m = /^\s*(?:private\s+|internal\s+|public\s+)?struct\s+(\w+)\s*:\s*([^{]*\bCodable\b[^{]*)\{/.exec(L[i]);
        if (!m) continue;
        const name = m[1];
        let dep = 0, end = i, s = false;
        for (let k = i; k < L.length; k++) {
          const code = L[k].replace(/\/\/.*$/, '');
          for (const ch of code) { if (ch === '{') { dep++; s = true; } else if (ch === '}') dep--; }
          if (s && dep <= 0) { end = k; break; }
        }
        let required = 0, hasInitFrom = false;
        for (let k = i + 1; k < end; k++) {
          const t = L[k].trim();
          if (/init\(from\s+\w+\s*:/.test(t)) hasInitFrom = true;
          if (!t || t.startsWith('//') || t.startsWith('///')) continue;
          if (t.includes('{')) continue;   // 计算属性
          const fm = /^(?:@\w+\s+)?var\s+(\w+)\s*:\s*([^=]+?)(?:\s*=\s*(.+))?$/.exec(t);
          if (!fm) continue;
          if (!fm[2].trim().endsWith('?')) required++;
        }
        if (required > 0 && !hasInitFrom) out.push({ id: `${d}/${f}::${name}`, name, file: `${d}/${f}`, line: i + 1, required });
      }
    }
  }
  return out;
}

const cur = scan();
const curMap = Object.fromEntries(cur.map(x => [x.id, x.required]));
const baseline = fs.existsSync(BASE) ? JSON.parse(fs.readFileSync(BASE, 'utf8')) : {};

if (process.argv.includes('--list')) {
  for (const x of cur.sort((a, b) => b.required - a.required)) {
    console.log(`  ${x.file}:${x.line}  ${x.name}  (${x.required} 个非 Optional 字段)`);
  }
}

if (process.argv.includes('--update')) {
  fs.writeFileSync(BASE, JSON.stringify(curMap, null, 2) + '\n', 'utf8');
  console.log(`已更新基线 → fixtures/codable-baseline.json（${cur.length} 个）`);
  process.exit(0);
}

const added = Object.keys(curMap).filter(k => !(k in baseline));
const increased = Object.keys(curMap).filter(k => k in baseline && curMap[k] > baseline[k]);

console.log(`Codable 容错棘轮: 未加容错的模型 ${cur.length} 个（基线 ${Object.keys(baseline).length}）`);

if (added.length) {
  console.error('✗ 新增了未做容错解码的 Codable 模型：');
  for (const k of added) console.error(`  ${k}  (${curMap[k]} 个非 Optional 字段)`);
  console.error('修法：给该模型手写 init(from:)，逐字段 decodeIfPresent ?? 默认值（参考 LedgerPwd / MemberExt）。');
  process.exit(1);
}
if (increased.length) {
  console.error('✗ 已有模型新增了非 Optional 字段但没加进容错解码：');
  for (const k of increased) console.error(`  ${k}  ${baseline[k]} → ${curMap[k]}`);
  process.exit(1);
}
console.log('✓ 没有新增未容错的 Codable 模型');
