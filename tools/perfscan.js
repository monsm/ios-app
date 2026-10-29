#!/usr/bin/env node
// tools/perfscan.js — 性能反模式棘轮闸门（判失败：只许降不许升）
//
// 为什么需要：本仓的「数据库」是 UserDefaults + JSON，很多读操作看起来像普通属性访问，
// 实际上是一次全量解码。写在 body / ForEach 里就是按帧、按行地解码 —— 编译和现有闸门都不会红，
// 只在真机上表现为掉帧、发热、滚动卡顿。2026-10-29 巡检修掉一批后，用这份棘轮把口子扎住。
//
// 三条规则：
//   R1 `DateFormatter()` / `ISO8601DateFormatter()` 新建次数 —— 应该用 App/Core/DateFormats.swift 的 DF.cached。
//       （DateFormatter 初始化 0.3–2ms，比一次格式化贵两三个数量级。）
//   R2 `ForEach { ... }` 闭包里出现 DB 的**读**调用 —— 会变成按行全量解码。
//   R3 `.onReceive(Timer.publish(...))` 内联 —— 每次 body 重算都新建一个 TimerPublisher。
//
// 基线在 fixtures/perf-baseline.json；只允许下降。新增违例 → 先修掉，不要抬基线。
//
// 用法：
//   node tools/perfscan.js            # 校验
//   node tools/perfscan.js --list     # 打印当前每条违例的明细
//   node tools/perfscan.js --update   # 仅在修掉之后收窄基线（不得用于放行新违例）
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const BASE = path.join(ROOT, 'fixtures', 'perf-baseline.json');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

const FORMatter = /(?:^|[^.\w])DateFormatter\(\)|ISO8601DateFormatter\(\)/;
// R4：DateFormatter.localizedString(...) 是个**每次调用都新建 formatter** 的类方法，与 DateFormatter() 同罪。
const LOCALIZED_STRING = /DateFormatter\.localizedString\(/;
// R5：Store.keys() 走 defaults.dictionaryRepresentation()（整域拷贝），只许出现在 Store 层。
const DICT_DUMP = /store\.keys\(\)|dictionaryRepresentation\(\)/;
const DB_READ = /\bDB\.(?:list\w+|read\w+|ledger|members|member|keychains|keychain|dongles|dongle|defend|otpStatus|getPwd|getPwdList|getFpList|pendingPair|store\.get\w*)\s*\(/;

function swiftFiles() {
  const out = [];
  for (const d of DIRS) {
    const dir = path.join(ROOT, d);
    for (const f of fs.readdirSync(dir)) if (f.endsWith('.swift')) out.push({ d, f, p: path.join(dir, f) });
  }
  return out;
}

function countForEachDbRead(L) {
  let n = 0;
  for (let i = 0; i < L.length; i++) {
    if (!/ForEach\s*\(/.test(L[i])) continue;
    const openIdx = L[i].indexOf('{');
    if (openIdx < 0) continue;
    let depth = 0, end = -1, started = false;
    for (let k = i; k < L.length; k++) {
      const line = L[k].replace(/\/\/.*$/, '');
      const from = k === i ? openIdx : 0;
      for (let c = from; c < line.length; c++) {
        const ch = line[c];
        if (ch === '{') { depth++; started = true; }
        else if (ch === '}') { depth--; if (started && depth === 0) { end = k; break; } }
      }
      if (end >= 0) break;
    }
    if (end < 0) continue;
    // 只数**闭包体内**的 DB 读；ForEach 源表达式本身（如 ForEach(DB.members())）每次 body 只求值一次，不算按行。
    for (let k = i + 1; k <= end; k++) {
      if (/^\s*\/\//.test(L[k])) continue;
      if (DB_READ.test(L[k])) { n++; break; }
    }
    i = end;
  }
  return n;
}

const cur = {};
const detail = {};
for (const { d, f, p } of swiftFiles()) {
  const key = `${d}/${f}`;
  const L = fs.readFileSync(p, 'utf8').split(/\r?\n/);
  let r1 = 0, r3 = 0, r4 = 0, r5 = 0;
  const r1Lines = [], r3Lines = [], r4Lines = [], r5Lines = [];
  L.forEach((l, i) => {
    if (/^\s*\/\//.test(l)) return;
    if (FORMatter.test(l) && !key.endsWith('DateFormats.swift')) { r1++; r1Lines.push(i + 1); }
    if (/\.onReceive\(\s*Timer\.publish\(/.test(l)) { r3++; r3Lines.push(i + 1); }
    if (LOCALIZED_STRING.test(l)) { r4++; r4Lines.push(i + 1); }
    if (d === 'App/UI' && DICT_DUMP.test(l)) { r5++; r5Lines.push(i + 1); }
  });
  const r2 = countForEachDbRead(L);
  if (r1 || r2 || r3 || r4 || r5) {
    cur[key] = { r1_rawFormatter: r1, r2_forEachDbRead: r2, r3_inlineTimer: r3, r4_localizedString: r4, r5_dictDumpInUI: r5 };
    detail[key] = { r1: r1Lines, r3: r3Lines, r4: r4Lines, r5: r5Lines };
  }
}

const baseline = fs.existsSync(BASE) ? JSON.parse(fs.readFileSync(BASE, 'utf8')) : {};
const keys = new Set([...Object.keys(cur), ...Object.keys(baseline)]);
const violations = [];
for (const k of [...keys].sort()) {
  const b = baseline[k] || { r1_rawFormatter: 0, r2_forEachDbRead: 0, r3_inlineTimer: 0, r4_localizedString: 0, r5_dictDumpInUI: 0 };
  const c = cur[k] || { r1_rawFormatter: 0, r2_forEachDbRead: 0, r3_inlineTimer: 0, r4_localizedString: 0, r5_dictDumpInUI: 0 };
  for (const rule of ['r1_rawFormatter', 'r2_forEachDbRead', 'r3_inlineTimer', 'r4_localizedString', 'r5_dictDumpInUI']) {
    if (c[rule] > b[rule]) violations.push({ file: k, rule, base: b[rule], now: c[rule] });
  }
}

const sum = (o, rule) => Object.values(o).reduce((a, x) => a + (x[rule] || 0), 0);
console.log(`性能棘轮: R1 formatter ${sum(cur, 'r1_rawFormatter')} (基线 ${sum(baseline, 'r1_rawFormatter')}) · ` +
            `R2 ForEach 内 DB 读 ${sum(cur, 'r2_forEachDbRead')} (基线 ${sum(baseline, 'r2_forEachDbRead')}) · ` +
            `R3 内联 Timer ${sum(cur, 'r3_inlineTimer')} (基线 ${sum(baseline, 'r3_inlineTimer')}) · ` +
            `R4 localizedString ${sum(cur, 'r4_localizedString')} (基线 ${sum(baseline, 'r4_localizedString')}) · ` +
            `R5 UI 层字典转储 ${sum(cur, 'r5_dictDumpInUI')} (基线 ${sum(baseline, 'r5_dictDumpInUI')})`);

if (process.argv.includes('--list')) {
  for (const k of Object.keys(detail).sort()) {
    const d = detail[k];
    if (d.r1.length) console.log(`  R1 ${k}  DateFormatter @${d.r1.join(',')}`);
    if (d.r3.length) console.log(`  R3 ${k}  inline Timer @${d.r3.join(',')}`);
    if (d.r4.length) console.log(`  R4 ${k}  DateFormatter.localizedString @${d.r4.join(',')}`);
    if (d.r5.length) console.log(`  R5 ${k}  Store.keys/dictionaryRepresentation @${d.r5.join(',')}`);
  }
}

if (process.argv.includes('--update')) {
  fs.writeFileSync(BASE, JSON.stringify(Object.fromEntries(Object.entries(cur).sort()), null, 2) + '\n', 'utf8');
  console.log('已更新基线 → fixtures/perf-baseline.json');
  process.exit(0);
}

if (violations.length) {
  console.error('✗ 性能反模式比基线更差：');
  for (const v of violations) {
    console.error(`  ${v.file}  ${v.rule}: 基线 ${v.base} → 现在 ${v.now}`);
  }
  console.error('修法：R1 用 App/Core/DateFormats.swift 的 DF.cached；R2 把 DB 读提到 ForEach 外；R3 Timer.publish 放进 @State。');
  process.exit(1);
}
console.log('✓ 性能棘轮通过（无新增反模式）');
