#!/usr/bin/env node
// uinavarchcheck —— 导航架构一致性闸门（判失败）。
//
// 正控：把 `App/UI/LockSettingsView.swift` 的 `NavigationLink { DeviceInfoView() }` 改成
//       `NavigationLink { DeviceHomeView() }` ⇒ 报出「NavigationLink 指向一级页面 DeviceHomeView」。
// 负控：19 处 NavigationLink 全部指向二级页面，零误报。
//
// 2026-10-31（UI/UX 第 4 轮）：本仓有两层导航，**职责必须分开**：
//   · Tab 级  → `Route` 枚举 + `requestRoute`（唯一漏斗，`uicoverage` 守着不许回退成 `requestTab`）
//   · 子页级  → `NavigationLink`（在 NavigationStack 里下钻）
//
// 为什么这条重要：若 `NavigationLink` 指向**一级页面**（DeviceHomeView / CredentialsView /
// RecordsView / SettingsView），就会出现「Tab 里再压一个 Tab 页面」的嵌套 ——
// 返回栈、Tab 选中态、`Route.guestBlocked` 的访客门禁全部对不上。
// `Route.swift` 头注记录过这类事故：`RecordsView` 被 sheet 端出来后内部 `requestTab(1)`
// 去切一个不存在的 Tab，而 sheet 还盖在上面。
//
// 判据：
//   · `NavigationLink { XxxView() }` 的 XxxView 不得是一级页面。
//   · 通过 `quickDestination(id)` 动态分发的，检查它的 switch 分支目标（同一判据）。
//
// 正控：把 `App/UI/LockSettingsView.swift` 的 `NavigationLink { DeviceInfoView() }` 改成
//       `NavigationLink { DeviceHomeView() }` ⇒ 报出「NavigationLink 指向一级页面 DeviceHomeView」，退出码 1。
// 负控：7 处可静态解析的 NavigationLink 全指向二级页面；quickDestination 的分支也不指向一级页面。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

const files = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) if (f.endsWith('.swift')) files.push({ rel: d + '/' + f, abs: path.join(dir, f) });
}
if (!files.length) { console.log('✓ 无 Swift 源码，跳过'); process.exit(0); }

// 一级页面（由 Route 驱动，只能通过 requestRoute 到达）
const TOP_LEVEL = ['DeviceHomeView', 'CredentialsView', 'RecordsView', 'SettingsView'];

const bad = [];
const okList = [];
let linkCount = 0;

for (const { rel, abs } of files) {
  const src = fs.readFileSync(abs, 'utf8');
  const L = src.split(/\r?\n/);
  for (let i = 0; i < L.length; i++) {
    const c = L[i].replace(/\/\/.*$/, '');
    if (!/NavigationLink/.test(c)) continue;

    // 目标：同行 `{ XxxView(` 或往下 3 行
    let target = null;
    const m1 = c.match(/NavigationLink\s*\{\s*(\w+)\s*\(/);
    if (m1) target = m1[1];
    else {
      for (let k = i + 1; k < i + 4 && k < L.length; k++) {
        const mm = L[k].replace(/\/\/.*$/, '').match(/\{\s*(\w+)\s*\(/);
        if (mm) { target = mm[1]; break; }
      }
    }
    if (!target) continue;
    linkCount++;
    if (TOP_LEVEL.includes(target)) {
      bad.push(`${rel}:${i + 1}  NavigationLink 指向一级页面 ${target}（应由 requestRoute 切换，不要压栈）`);
    } else {
      okList.push(`${target}`);
    }
  }
}

// 额外：quickDestination 的 switch 分支不得指向一级页面
const qp = path.join(ROOT, 'App/Core/QuickPool.swift');
if (fs.existsSync(qp)) {
  const qs = fs.readFileSync(qp, 'utf8');
  for (const m of qs.matchAll(/case\s+"\w+"\s*:\s*(\w+)\s*\(/g)) {
    if (TOP_LEVEL.includes(m[1])) bad.push(`QuickPool.swift quickDestination 的 case 指向一级页面 ${m[1]}`);
  }
}

if (bad.length) {
  console.log(`✗ 导航架构 ${bad.length} 处问题：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：本仓有两层导航 —— `Route`+`requestRoute` 管 Tab 级，`NavigationLink` 管子页下钻。');
  console.log('若 NavigationLink 指向一级页面，就会出现「Tab 里再压一个 Tab 页面」的嵌套：');
  console.log('返回栈、Tab 选中态、访客门禁（Route.guestBlocked）全部对不上。');
  console.log('修法：一级页面用 `app.requestRoute(.xxx)` 切换；NavigationLink 只用于二级页面。');
  process.exit(1);
}
console.log(`ok    NavigationLink ${linkCount} 处全部指向二级页面（无一级页面嵌套）`);
console.log('ok    quickDestination 的分支也不指向一级页面');
console.log('\n✓ 导航架构一致：Route 管 Tab 级 · NavigationLink 管子页');
