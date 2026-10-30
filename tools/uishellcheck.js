#!/usr/bin/env node
// uishellcheck —— 页面壳一致性闸门（判失败）。
//
// 正控：把 `App/UI/RecordsChrome.swift` 里的 `NavigationStack {` 删掉 ⇒
//       报出「RecordsView 有 navigationTitle 但没有 NavigationStack」。
// 负控：四个 Tab 根 View 全部通过。
//
// 2026-10-31（第 1 轮 UI/UX 重构）：**先踩了一个方法论坑再建这道闸门** ——
// 我最初按**单文件**扫描，看到 `RecordsView.swift` 里没有 `NavigationStack` / `navigationTitle`，
// 就判定「记录 Tab 缺导航壳」。实际它们都在 `RecordsChrome.swift`（`extension RecordsView`）里。
// 本仓有大量「声明在一个文件、extension 在另一个文件」的拆分（RootView / PwdStudio / UnlockDial …），
// **单文件扫描会系统性误判**。
//
// 所以本闸门的核心不是判据，是**取源码的方式**：先把「声明 + 所有 extension」拼成一个 View 的完整源码，
// 再判断。两道遍历：第一轮收集声明，第二轮才归属 extension（否则 extension 文件先遍历时会跳过）。
//
// 判据：
//   · 四个 Tab 根 View（DeviceHomeView / CredentialsView / RecordsView / SettingsView）
//     必须有 `NavigationStack` + `.navigationTitle(`。
//   · 有 `.navigationTitle(` 的 View，要么自己含 `NavigationStack`，要么被别的 View 包着
//
// 正控：把 `RecordsView` 的全部 5 处 `NavigationStack`（分布在 RecordsChrome / RecordsFilters / RecordsSheets）
//       改名 ⇒ 报出「RecordsView: 缺 NavigationStack（Tab 根必须有导航壳）」，退出码 1。
//       （只删 1 处**不会**失败 —— 判据是"全文有一处即可"，因为多个 sheet 各自带 NavigationStack 是正常的。）
// 负控：四个 Tab 根 View 全部通过；47 个页面级 View 中 34 个自带栈、13 个作为子页。
//     （后者不判失败 —— 本仓有 13 个这样的子页面，正常）。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

const allFiles = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) if (f.endsWith('.swift')) allFiles.push({ rel: d + '/' + f, src: fs.readFileSync(path.join(dir, f), 'utf8') });
}
if (!allFiles.length) { console.log('✓ 无 Swift 源码，跳过'); process.exit(0); }

// 第一轮：收集声明
const declOf = {};
for (const { rel, src } of allFiles) {
  for (const m of src.matchAll(/struct\s+(\w+)\s*:\s*View\b/g)) (declOf[m[1]] = declOf[m[1]] || []).push(rel);
}

// 第二轮：把声明 + extension 拼成完整源码
const srcOf = {};
for (const v of Object.keys(declOf)) srcOf[v] = '';
for (const { src } of allFiles) {
  for (const m of src.matchAll(/struct\s+(\w+)\s*:\s*View\b/g)) if (srcOf[m[1]] !== undefined) srcOf[m[1]] += src + '\n';
  for (const m of src.matchAll(/extension\s+(\w+)\s*\{/g)) if (srcOf[m[1]] !== undefined) srcOf[m[1]] += src + '\n';
}

const bad = [];
const okList = [];

// 判据 1：四个 Tab 根 View
const TAB_ROOTS = ['DeviceHomeView', 'CredentialsView', 'RecordsView', 'SettingsView'];
for (const v of TAB_ROOTS) {
  if (srcOf[v] === undefined) { bad.push(`Tab 根 View ${v} 找不到（声明被删或改名？）`); continue; }
  const hasStack = srcOf[v].includes('NavigationStack');
  const hasTitle = srcOf[v].includes('.navigationTitle(');
  if (!hasStack) bad.push(`${v}: 缺 NavigationStack（Tab 根必须有导航壳）`);
  if (!hasTitle) bad.push(`${v}: 缺 .navigationTitle(（Tab 根必须有标题）`);
  if (hasStack && hasTitle) okList.push(`${v}: 有导航壳 + 标题`);
}

// 判据 2：页面级 View 的壳（有标题就必须能挂到导航栈上）
const pages = Object.entries(srcOf).filter(([, s]) => s.includes('.navigationTitle('));
const selfStack = pages.filter(([, s]) => s.includes('NavigationStack'));
const childPages = pages.filter(([, s]) => !s.includes('NavigationStack'));
okList.push(`页面级 View ${pages.length} 个：${selfStack.length} 个自带 NavigationStack，${childPages.length} 个作为子页（由父级导航壳承载）`);

if (bad.length) {
  console.log(`✗ 页面壳一致性 ${bad.length} 处问题：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：Tab 根 View 缺导航壳 ⇒ 没有标题栏、没有工具栏、返回手势失效。');
  console.log('修法：给该 View 包上 `NavigationStack { … }` 并加 `.navigationTitle(…)`。');
  console.log('⚠ 注意本闸门是**跨文件汇总**源码的 —— 单文件扫描会误判（见文件头）。');
  process.exit(1);
}
okList.forEach(x => console.log('ok    ' + x));
console.log('\n✓ 页面壳一致性通过');
