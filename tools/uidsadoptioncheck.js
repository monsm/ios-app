#!/usr/bin/env node
// uidsadoptioncheck —— 设计系统组件的采纳率闸门（判失败）。
//
// 正控：在 `App/Core/DesignSystem.swift` 里新增一个从未被使用的
//       `struct DeadDemo: View { var body: some View { EmptyView() } }` ⇒
//       报出「DeadDemo 零使用（设计系统里的死组件）」。
// 负控：17 个组件全部有使用，零误报。
//
// 2026-10-31（UI/UX 第 12 轮）：设计系统里定义了组件却**没有任何调用点**，
// 就是「同一语义两份实现」的镜像问题 —— 有人写了组件，但各页面还在自己画。
// 本轮核查 17 个组件，**零死代码**（最少的也是 1 处，且都是场景专用：
// `BLEOffBanner` 只在蓝牙关闭时出现、`RSSIBars` 只在信号处出现）。
//
// 判据：
//   · 从 `DesignSystem.swift` / `UIKitComponents.swift` / `VariantGrammar.swift` / `LinkSenseViews.swift`
//     收集所有 `struct Xxx: View` / `struct Xxx: ViewModifier` / `struct Xxx: ...ButtonStyle`
//   · 若某组件在**其它文件**里零出现 ⇒ 判失败
//   · 排除：`private struct`（文件内私有，不跨文件使用是设计如此）
//
// 为什么只判「零」不判「少」：1~2 处使用完全可能是**场景专用组件**
//
// 正控：在 DesignSystem.swift 末尾加一个 `struct DeadDemoComponent: View`（从不调用）⇒
//       报出「DeadDemoComponent 零使用」，退出码 1。
// 负控：19 个组件全部有调用点；3 个间接调用（DestinedModifier / VKTypography / PressFeedback）有白名单理由。
// （如蓝牙关闭横幅），那不是缺陷。只有零使用才是「写了没人用」。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

const DEF_FILES = [
  'App/Core/DesignSystem.swift',
  'App/UIKitComponents.swift',
  'App/Core/VariantGrammar.swift',
  'App/Core/LinkSenseViews.swift',
];

const allFiles = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) if (f.endsWith('.swift')) { const abs = path.join(dir, f); allFiles.push({ rel: d + '/' + f, abs, src: fs.readFileSync(abs, 'utf8') }); }
}
if (!allFiles.length) { console.log('✓ 无 Swift 源码，跳过'); process.exit(0); }

// 收集设计系统组件（跳过 private）
const comps = [];
for (const rel of DEF_FILES) {
  const p = path.join(ROOT, rel);
  if (!fs.existsSync(p)) continue;
  const src = fs.readFileSync(p, 'utf8');
  const L = src.split(/\r?\n/);
  for (let i = 0; i < L.length; i++) {
    const c = L[i].replace(/\/\/.*$/, '');
    const m = c.match(/^\s*(private\s+)?struct\s+(\w+)\s*:\s*(View|ViewModifier|\w*ButtonStyle)\b/);
    if (!m) continue;
    if (m[1]) continue;   // private：文件内私有，不跨文件用是设计如此
    comps.push({ name: m[2], defFile: rel });
  }
}

if (!comps.length) {
  console.log('✓ 设计系统里没有非 private 组件，跳过');
  process.exit(0);
}

const bad = [];
const okList = [];
for (const { name, defFile } of comps) {
  let n = 0;
  const re = new RegExp('\\b' + name + '\\s*[({]|:\\s*' + name + '\\b|\\b' + name + '\\s*\\.');
  for (const { rel, src } of allFiles) {
    if (rel === defFile) continue;   // 定义文件自身不算使用
    const L = src.split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      if (/^\s*\/\//.test(L[i])) continue;
      if (re.test(L[i].replace(/\/\/.*$/, ''))) { n++; break; }
    }
  }
  // 2026-10-31（UI/UX 第 12 轮，**间接调用白名单**）：这三个组件不是"没人用"，
  // 而是**通过修饰符/包装函数间接调用**，按名字直扫找不到：
  //   · `DestinedModifier`  → 通过 `extension View { func destined(_:) }` 调用（29 处 `.destined(`）
  //   · `VKTypography`      → 是 `vkFont` 的内部实现（`vkFont` = `modifier(VKTypography(...))`，530 处）
  //   · `PressFeedback`     → 在 `PressableButtonStyle` 的私有 `Gate` 内部使用（同文件）
  const INDIRECT = {
    DestinedModifier: "通过 .destined() 修饰符调用（29 处）",
    VKTypography: "vkFont 的内部实现（530 处 .vkFont(）",
    PressFeedback: "PressableButtonStyle 的私有 Gate 内部使用（同文件）",
  };
  if (INDIRECT[name]) { okList.push(name + " 有使用（间接：" + INDIRECT[name] + "）"); continue; }
  if (n === 0) bad.push(`${name}（定义于 ${defFile}）零使用 —— 设计系统里的死组件`);
  else okList.push(`${name} 有使用`);
}

if (bad.length) {
  console.log(`✗ 设计系统死组件 ${bad.length} 个：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：定义了组件却没人调用 = 有人写了组件、各页面还在自己画。');
  console.log('这是「同一语义两份实现」的镜像问题。');
  console.log('修法：要么把调用点改成用该组件，要么删掉这个组件（别留着误导后人）。');
  process.exit(1);
}
okList.forEach(x => console.log('ok    ' + x));
console.log(`\n✓ 设计系统 ${comps.length} 个组件全部有调用点（无死组件）`);
