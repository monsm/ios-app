#!/usr/bin/env node
// 把裸写的 `tabSelection = <序号>` 迁到唯一漏斗 `requestRoute(_:)`
// — node tools/migrateroute.js [--dry-run] [--verbose]
//
// 为什么这一批必须做 (2026-10-16)：
//   App 里并存两套完整界面之后，`tabSelection` 这个状态**只在 legacy 存在**。
//   全仓还有 43 处 `app.tabSelection = <0..3>` 的直写 —— 它们在 core / gauge 下不会报错、
//   不会崩，只是**什么都不发生**。这就是"切到另一套就少一个功能"最典型的成因，
//   而且是静默的：走查看不出来，因为按钮在 legacy 下是好的。
//
//   顺带关掉一个老洞：仓库里已经修过好几次同类问题，注释就是证据 ——
//     CredentialOrg.swift:1156 「原写直写 app.tabSelection = 1, 绕过 377 访客门禁」
//     DeviceHomeView.swift:65  「原为直写 app.tabSelection = 3 —— 设备页在访客通道…」
//   一处一处补是补不完的，收进同一个漏斗才是收口。
//
// 口径（宁可少改也不要改错）：
//   · 只改**代码行**里的 `tabSelection = <单个数字>`；整行注释与行尾注释一律不动
//     —— 注释里大量引述这个写法（上面那两条就是），改了就是把历史证据擦掉。
//   · 不动声明行 (`@Published var tabSelection = 0`)。
//   · 不动 LockKeeperApp.swift 里访客门禁自己那处复位 (`if guestBlockedTabs.contains(tabSelection) { tabSelection = 0 }`)：
//     它是"受限就退回设备页"的执法点，走漏斗会被再判一次受限，语义绕圈。
//   · 序号→Route 的映射只有一个来源 (Route.byHost)，不在这里再抄一张表。
//
// 自检：正控 1 (代码行必须改) + 反控 2 (注释行、声明行必须不改)。不过就 exit 1。
'use strict';
const fs = require('fs');
const path = require('path');

const DRY = process.argv.includes('--dry-run');
const VERBOSE = process.argv.includes('--verbose');
const ROOTS = ['App', 'Widget', 'Shared'];
const KEEP = new Set([path.join('App', 'LockKeeperApp.swift').replace(/\\/g, '/')]);

/** 序号 → Route case。从 Route.swift 的 byHost 那一行读，不另抄一张表。 */
function routeOrder() {
  const src = fs.readFileSync(path.join('App', 'Core', 'Route.swift'), 'utf8');
  const m = /static let byHost:\s*\[Route\]\s*=\s*\[([^\]]+)\]/.exec(src);
  if (!m) { console.log('!! 读不到 Route.byHost —— 映射没有唯一来源，本工具拒绝工作'); process.exit(1); }
  return [...m[1].matchAll(/\.([a-zA-Z0-9_]+)/g)].map((x) => x[1]);
}
const ORDER = routeOrder();
const BY_IDX = Object.fromEntries(ORDER.map((c, i) => [i, c]));

function stripComment(line) {
  const i = line.indexOf('//');
  if (i < 0) return line;
  const before = line.slice(0, i);
  if ((before.match(/"/g) || []).length % 2 === 1) return line;
  return before;
}
const isFullComment = (l) => /^\s*\/\//.test(l);

function walk(d, out) {
  out = out || [];
  if (!fs.existsSync(d)) return out;
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const f = path.join(d, e.name);
    if (e.isDirectory()) walk(f, out);
    else if (f.endsWith('.swift')) out.push(f);
  }
  return out;
}

const RE = /(\bapp\.|\bself\.)?\btabSelection\s*=\s*([0-9])\b/;

/** 单行变换：命中且应当改则返回新行，否则返回 null。
 *  ⚠ 迁移与自检**共用这一个函数** —— 两边各写一条正则的话，自检过了也证明不了迁移是对的
 *  （本仓"同一个量算两次必已不一致"那条，工具自己也适用）。 */
function transformLine(raw) {
  if (isFullComment(raw)) return null;
  const code = stripComment(raw);
  const m = RE.exec(code);
  if (!m) return null;
  if (/\bvar\s+tabSelection\b/.test(code)) return null;         // 声明行
  const idx = Number(m[2]);
  const c = BY_IDX[idx];
  if (!c) return null;                                          // 越界序号：不改，交给调用方报
  const recv = m[1] ? m[1].replace(/\s+$/, '') : '';             // 'app.' / 'self.' / ''
  const prefix = recv === 'self.' ? 'self.' : recv === 'app.' ? 'app.' : '';
  const repl = `${prefix}requestRoute(.${c})`;
  // 只替换代码部分，行尾注释原样接回去
  const at = code.indexOf(m[0]);
  return raw.slice(0, at) + repl + raw.slice(at + m[0].length);
}

function migrate() {
  let changed = 0, files = 0, skippedKeep = 0;
  const report = [];
  for (const root of ROOTS) {
    for (const f of walk(root)) {
      const rel = f.replace(/\\/g, '/');
      const lines = fs.readFileSync(f, 'utf8').split('\n');
      let touched = 0;
      const next = lines.map((l) => {
        // 执法点保留直写：它是"受限就退回设备页"，走漏斗会被再判一次受限，语义绕圈。
        if (KEEP.has(rel) && /guestBlockedTabs\.contains/.test(l)) {
          if (RE.test(stripComment(l))) skippedKeep++;
          return l;
        }
        const n = transformLine(l);
        if (n === null) return l;
        touched++;
        return n;
      });
      if (touched) {
        files++; changed += touched;
        if (!DRY) fs.writeFileSync(f, next.join('\n'));
        report.push(`   ${DRY ? '[dry] ' : ''}${rel.padEnd(40)} ${touched} 处`);
      }
    }
  }
  return { changed, files, report, skippedKeep };
}

// ---------- 自检 ----------
function selfTest() {
  const dir = path.join('fixtures', 'migrateroute');
  fs.mkdirSync(dir, { recursive: true });
  const cases = [
    ['      Button("a") { app.tabSelection = 1 }        // 尾注',  'app.requestRoute(.credentials)', '正控: 代码行必须迁移，且行尾注释要留着'],
    ['        // app.tabSelection = 2  绕过门禁的历史说明',          null,                              '反控: 整行注释不许动 (那是历史证据)'],
    ['      @Published var tabSelection = 0 {',                     null,                              '反控: 声明行不许动'],
    ['      if x { tabSelection = 3 }',                             'requestRoute(.settings)',         '正控: 裸写(无接收者)也要迁移，且不凭空加 app. 前缀'],
    ['      app.tabSelection = 9',                                  null,                              '反控: 越界序号不猜，交给人看'],
  ];
  const problems = [];
  for (const [src, want, why] of cases) {
    const got = transformLine(src);
    if (want === null) {
      if (got !== null) problems.push(`${why} —— 不该改却改成了 ${JSON.stringify(got)}`);
    } else if (got === null || !got.includes(want)) {
      problems.push(`${why} —— 期望含 ${JSON.stringify(want)}，实得 ${JSON.stringify(got)}`);
    }
  }
  fs.writeFileSync(path.join(dir, 'A.swift'), cases.map((c) => c[0]).join('\n') + '\n');
  return problems;
}

function main() {
  console.log(`序号→Route 映射读自 Route.byHost: ${ORDER.map((c, i) => `${i}:${c}`).join(' ')}`);
  const r = migrate();
  r.report.forEach((x) => console.log(x));
  console.log('');
  console.log(`${DRY ? '预演' : '已迁移'} ${r.changed} 处，涉及 ${r.files} 个文件；执法点保留 ${r.skippedKeep} 处不改`);
  const sp = selfTest();
  if (sp.length) { sp.forEach((x) => console.log('!! ' + x)); process.exit(1); }
  console.log('尺子自检: 正控 1 (代码行迁移) / 反控 2 (注释行 + 声明行不动) → 通过');
  if (r.changed) console.log('⚠ 迁移后必须跑 tools/sheetcover.js —— 它原先把 tabSelection= 当"换 Tab 动作"，现在这些点改走漏斗了。');
}
main();
