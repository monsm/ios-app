#!/usr/bin/env node
// tools/viewdbcheck.js — 视图计算属性里的 DB 调用棘轮（判失败：只许降不许升）
//
// 为什么需要：这轮审计里最反复出现的一类性能问题是
//   「在 `var xxx: some View { ... }` 里直接调 DB.*」
// —— 视图每次重算 body 都会重读一次存储。典型修复：
//   · MemberCenterView 的 activityTable / visitorOpenCount（O(成员²×锁×日志)）
//   · RecordsView 的 lastYearTodayCount（每次 body 扫全部日志）
//   · DeviceHomeView 的布防摘要（同一份数据解两遍）
//
// 规则：按**文件**统计「视图计算属性块内的 DB. 调用次数」。
// 基线在 fixtures/viewdb-baseline.json，只允许下降；新增文件或某文件次数上升即失败。
//
// 用法：
//   node tools/viewdbcheck.js            # 校验
//   node tools/viewdbcheck.js --list     # 列出所有命中点
//   node tools/viewdbcheck.js --update   # 收窄基线
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const BASE = path.join(ROOT, 'fixtures', 'viewdb-baseline.json');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

function scan() {
  const perFile = {};
  const sites = [];
  for (const d of DIRS) {
    const dir = path.join(ROOT, d);
    for (const f of fs.readdirSync(dir)) {
      if (!f.endsWith('.swift')) continue;
      const L = fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/);
      for (let i = 0; i < L.length; i++) {
        const m = /^\s*(?:@ViewBuilder\s*)?var\s+(\w+)\s*:\s*some\s+View\s*\{/.exec(L[i]);
        if (!m) continue;
        let dep = 0, end = i, s = false;
        for (let k = i; k < L.length; k++) {
          const code = L[k].replace(/\/\/.*$/, '');
          for (const ch of code) { if (ch === '{') { dep++; s = true; } else if (ch === '}') dep--; }
          if (s && dep <= 0) { end = k; break; }
        }
        // 2026-10-30：区分轻重 —— `getString/getBool/getInt/getDouble` 走 defaults 直接取值（不涉 JSON），
        // 而 `ledger/listPwds/readLogs/members/store.get(...)` 这些每次都要解码整份数据。
        // 只统计后者，否则闸门被一堆廉价标量读淹没（appearanceSection 的 10 次全是 getString）。
        // 2026-10-30 续：`.task { }` / `.onAppear { }` 块里的读库是**进页一次**的一次性填充，
        // 那是正确修法（把逐帧读库挪到生命周期回调），不该算欠账 —— 排除掉。
        const asyncBlocks = [];
        for (let k = i; k <= end; k++) {
          if (/^\.(task|onAppear)\s*\{/.test(L[k].trim())) {
            let d2 = 0, e2 = k, s2 = false;
            for (let j = k; j <= end; j++) {
              const c2 = L[j].replace(/\/\/.*$/, '');
              for (const ch of c2) { if (ch === '{') { d2++; s2 = true; } else if (ch === '}') d2--; }
              if (s2 && d2 <= 0) { e2 = j; break; }
            }
            asyncBlocks.push([k, e2]);
            k = e2;
          }
        }
        const inAsync = (k) => asyncBlocks.some(([a, b]) => k >= a && k <= b);
        let n = 0;
        for (let k = i; k <= end; k++) {
          if (inAsync(k)) continue;
          const code = L[k].replace(/\/\/.*$/, '');
          const all = (code.match(/\bDB\./g) || []).length;
          const light = (code.match(/\bDB\.store\.(getString|getBool|getInt|getDouble)\s*\(/g) || []).length;
          n += Math.max(0, all - light);
        }
        if (!n) continue;
        const key = `${d}/${f}`;
        perFile[key] = (perFile[key] || 0) + n;
        sites.push({ file: key, line: i + 1, name: m[1], n });
      }
    }
  }
  return { perFile, sites };
}

const { perFile, sites } = scan();
const total = Object.values(perFile).reduce((a, b) => a + b, 0);

if (process.argv.includes('--list')) {
  sites.sort((a, b) => b.n - a.n).forEach(s => console.log(`  ${s.file}:${s.line}  ${s.name}  DB×${s.n}`));
}

if (process.argv.includes('--update')) {
  fs.writeFileSync(BASE, JSON.stringify(perFile, null, 2) + '\n', 'utf8');
  console.log(`已更新基线 → fixtures/viewdb-baseline.json（${Object.keys(perFile).length} 个文件 / ${total} 次）`);
  process.exit(0);
}

const baseline = fs.existsSync(BASE) ? JSON.parse(fs.readFileSync(BASE, 'utf8')) : {};
const baseTotal = Object.values(baseline).reduce((a, b) => a + b, 0);
console.log(`视图内 DB 调用棘轮: ${total} 次 / ${Object.keys(perFile).length} 文件（基线 ${baseTotal} / ${Object.keys(baseline).length}）`);

const bad = [];
for (const [f, n] of Object.entries(perFile)) {
  const b = baseline[f] || 0;
  if (n > b) bad.push({ f, b, n });
}

if (bad.length) {
  console.error('✗ 视图计算属性里的 DB 调用变多了：');
  for (const x of bad) console.error(`  ${x.f}  ${x.b} → ${x.n}`);
  console.error('修法：把读库提到 render()/task 里算一次，或在视图里用 @State 缓存（参考 RecordsView.lastYearToday）。');
  process.exit(1);
}
console.log('✓ 没有新增「视图内读库」');
