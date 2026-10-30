#!/usr/bin/env node
// uiglobalcolorcheck —— 全局文字色默认值闸门（判失败）。
//
// 正控：把 `App/LockKeeperApp.swift` 里的 `.foregroundStyle(DS.Palette.text)` 删掉 ⇒
//       报出「RootView 缺全局文字色默认」。
// 负控：RootView 有该行，通过。
//
// 2026-10-31（UI/UX 第 7 轮）：本仓主题是**暖调** ——
//   `DS.Palette.text` 浅色 `0x17140F`（暖黑）/ 深色 `0xF7F3EA`（暖白）
// 而 SwiftUI 的 `List` / `Form` 里没写 `color:` 的 `Text` 用**系统默认 label**（中性纯黑/纯白）。
// 于是同一屏里「显式指定了 text 的文字」和「没指定的文字」是**两种色温**。
//
// 实证：`BackupView` / `DefendView` / `LockSettingsView` 三个页面的
// 「显式 `DS.Palette.text` 次数」为 **0** —— 它们的主文本全靠默认色，全是中性黑白。
// 全仓 87 处显式 `foregroundStyle(DS.Palette.text)` 说明作者一直在补这个洞，但补不全。
//
// 判据：`WindowGroup { RootView() … }` 的修饰符链里必须有 `.foregroundStyle(DS.Palette.text)`。
// 为什么放在根：已有自己 `foregroundStyle` 的文字（273 处 textSub + 87 处 text）会**覆盖**它，
// 所以不会改变任何已显式指定的样式；只有「没指定」的那些才被兜住。
//
// 正控：删掉 `App/LockKeeperApp.swift` 的 `.foregroundStyle(DS.Palette.text)` ⇒
//       报出「RootView 缺全局文字色默认」，退出码 1。
// 负控：该行存在时通过，零误报。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App', 'LockKeeperApp.swift');

if (!fs.existsSync(APP)) { console.log('✓ LockKeeperApp.swift 不存在，跳过'); process.exit(0); }
const src = fs.readFileSync(APP, 'utf8');

// 找 WindowGroup 到 RootView() 之后的一段
const wg = src.indexOf('WindowGroup {');
if (wg < 0) {
  console.log('✗ 找不到 `WindowGroup {` —— 根视图结构变了，先更新本闸门');
  process.exit(1);
}
const seg = src.slice(wg, wg + 900);

const hasRootView = /RootView\(\)/.test(seg);
const hasGlobalColor = /\.foregroundStyle\(DS\.Palette\.text\)/.test(seg);

if (!hasRootView) {
  console.log('✗ WindowGroup 里找不到 `RootView()` —— 根视图结构变了，先更新本闸门');
  process.exit(1);
}
if (!hasGlobalColor) {
  console.log('✗ RootView 缺全局文字色默认 `.foregroundStyle(DS.Palette.text)`');
  console.log('\n为什么查这个：本仓主题是暖调（text = 0x17140F 暖黑 / 0xF7F3EA 暖白），');
  console.log('而 SwiftUI 的 List/Form 里没写 color 的 Text 用系统默认 label（中性纯黑/纯白）。');
  console.log('于是同一屏里「显式指定了 text」和「没指定」的文字是两种色温 —— 凑近看能看出偏色。');
  console.log('实证：BackupView / DefendView / LockSettingsView 三个页面的显式 text 次数为 0。');
  console.log('修法：在 WindowGroup { RootView() … } 的修饰符链上补 `.foregroundStyle(DS.Palette.text)`。');
  console.log('      已有自己 foregroundStyle 的文字会覆盖它，不会改变已显式指定的样式。');
  process.exit(1);
}
console.log('ok    RootView 有全局文字色默认 `.foregroundStyle(DS.Palette.text)`');
console.log('\n✓ 全局文字色默认值齐备（暖调主题不会被系统中性色打散）');
