#!/usr/bin/env node
// 旧设计系统零残留闸门 (判失败) — node tools/legacyguard.js
//
// 背景 (2026-10-21): 全新 UIUX 重写完成后, 旧设计系统两文件被删:
//   · App/Core/DesignSystem.swift  (798 行: DS 命名空间 / 旧组件 / Color 扩展)
//   · App/Core/VariantGrammar.swift (457 行: vkFont / VariantToggle / VK 语法层)
//
// 但删掉不等于不会再冒出来 —— 复制粘贴一段旧代码、从备份里捞回一个文件、
// 或者哪天有人"顺手"补个 DS.Palette.text, 旧系统就悄悄长回来了。
// 这个闸门就是防那条路: 全仓 App/ 下不许再出现任何旧系统符号。
//
// 判据 (逐条都是**符号级**, 不是"有没有那个文件"):
//   L1  DS.*  令牌 (DS.Palette / DS.Space / DS.Icon / DS.HeroStats …)
//   L2  vkFont  /  VariantToggle  /  VK()  /  VK.current
//   L3  variantList() / variantPlate() / variantCallout() / dsScreenBackground()
//   L4  旧组件名 (StatusPill / MetricTile / BusyButton / EmptyState /
//       GuidedEmptyView / HeroCard / HeroStat / HeroPill) —— 不带 X 前缀
//   L5  旧样式名 (PrimaryActionStyle / SecondaryActionStyle / DestructiveActionStyle)
//   L6  旧类型 ToneColor / FlowLayout —— 不带 X 前缀
//
// 豁免: 整行注释 (// …) 与块注释里的历史引述不算 —— 本仓注释里大量引述旧写法。
//
// 用法: node tools/legacyguard.js   (CI 闸门, 有残留 exit 1)
'use strict';
const fs = require('fs');
const path = require('path');

const APP = path.join(__dirname, '..', 'App');
const RULES = [
  ['L1  DS 令牌',              /\bDS\.[A-Z]\w*/],
  ['L2  vkFont',               /\.vkFont\(/],
  ['L2  VariantToggle',        /\bVariantToggle\(/],
  ['L2  VK 命名空间',           /\bVK\(\)|\bVK\.current\b/],
  ['L3  variantList',          /\.variantList\(\)/],
  ['L3  variantPlate',         /\.variantPlate\(/],
  ['L3  variantCallout',       /\.variantCallout\(/],
  ['L3  dsScreenBackground',   /\.dsScreenBackground\(\)/],
  ['L4  旧组件 StatusPill',     /(?<!X)\bStatusPill\s*\(/],
  ['L4  旧组件 MetricTile',     /(?<!X)\bMetricTile\s*\(/],
  ['L4  旧组件 BusyButton',     /(?<!X)\bBusyButton\s*\(/],
  ['L4  旧组件 EmptyState',     /(?<!X)\bEmptyState\s*\(/],
  ['L4  旧组件 GuidedEmptyView',/(?<!X)\bGuidedEmptyView\s*\(/],
  ['L4  旧组件 HeroCard',       /(?<!X)\bHeroCard\b/],
  ['L4  旧组件 HeroStat',       /(?<!X)\bHeroStat\s*\(/],
  ['L4  旧组件 HeroPill',       /(?<!X)\bHeroPill\s*\(/],
  ['L5  旧样式 Primary',        /(?<!X)\bPrimaryActionStyle\b/],
  ['L5  旧样式 Secondary',      /(?<!X)\bSecondaryActionStyle\b/],
  ['L5  旧样式 Destructive',    /(?<!X)\bDestructiveActionStyle\b/],
  ['L6  旧类型 ToneColor',      /(?<!X)\bToneColor\b/],
  ['L6  旧类型 FlowLayout',     /(?<!X)\bFlowLayout\s*\(/],
];

function walk(dir, out) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const f = path.join(dir, e.name);
    if (e.isDirectory()) walk(f, out);
    else if (f.endsWith('.swift')) out.push(f);
  }
  return out;
}

const files = walk(APP, []);
const hits = [];

for (const f of files) {
  const rel = f.replace(/\\/g, '/').split('/App/').pop();
  const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
  let inBlock = false;
  lines.forEach((l, i) => {
    const t = l.trim();
    // 块注释跟踪
    if (inBlock) { if (t.includes('*/')) inBlock = false; return; }
    if (t.startsWith('/*')) { if (!t.includes('*/')) inBlock = true; return; }
    if (t.startsWith('//')) return;
    const code = l.replace(/\/\/.*$/, '');   // 剥行尾注释
    for (const [name, re] of RULES) {
      if (re.test(code)) hits.push({ rel: 'App/' + rel, line: i + 1, name, text: code.trim().slice(0, 80) });
    }
  });
}

// ---------- 自检 ----------
const dir = path.join(__dirname, '..', 'fixtures', 'legacyguard');
fs.mkdirSync(dir, { recursive: true });
const posFile = path.join(dir, 'Pos.swift');
const negFile = path.join(dir, 'Neg.swift');
fs.writeFileSync(posFile, [
  'import SwiftUI',
  'struct PosView: View {',
  '    var body: some View {',
  '        Text("a").vkFont(.caption)',
  '    }',
  '}',
  ''
].join('\n'));
fs.writeFileSync(negFile, [
  'import SwiftUI',
  'struct NegView: View {',
  '    var body: some View {',
  '        // 历史写法: Text("a").vkFont(.caption)',
  '        Text("b").xFont(.caption)',
  '    }',
  '}',
  ''
].join('\n'));
{
  const posSrc = fs.readFileSync(posFile, 'utf8').replace(/\r\n/g, '\n');
  const posHit = posSrc.split('\n').some((l) => {
    const t = l.trim();
    if (t.startsWith('//')) return false;
    return /\.vkFont\(/.test(l.replace(/\/\/.*$/, ''));
  });
  const negSrc = fs.readFileSync(negFile, 'utf8').replace(/\r\n/g, '\n');
  const negHit = negSrc.split('\n').some((l) => {
    const t = l.trim();
    if (t.startsWith('//')) return false;
    return /\.vkFont\(/.test(l.replace(/\/\/.*$/, ''));
  });
  fs.unlinkSync(posFile);
  fs.unlinkSync(negFile);
  if (!posHit) { console.error('✗ 自检失败: 正控 (代码里的 .vkFont) 没被认出来'); process.exit(1); }
  if (negHit) { console.error('✗ 自检失败: 反控 (注释里的 .vkFont) 被当成了代码'); process.exit(1); }
  console.log('尺子自检: 正控 1 (代码里的 .vkFont 命中) / 反控 1 (注释里的 .vkFont 不命中) → 通过');
}

// ---------- 结论 ----------
console.log('旧设计系统残留检查 — 扫 ' + files.length + ' 个 .swift');
if (hits.length === 0) {
  console.log('✓ 零残留: DS 命名空间 / VK 语法层 / 旧组件 / 旧样式 / 旧类型 全部已清除');
  process.exit(0);
}
const byRule = {};
for (const h of hits) { (byRule[h.name] ||= []).push(h); }
for (const [name, list] of Object.entries(byRule)) {
  console.log('\n' + name + ' — ' + list.length + ' 处');
  list.slice(0, 8).forEach((h) => console.log('  ' + h.rel + ':' + h.line + '  ' + h.text));
  if (list.length > 8) console.log('  … 其余 ' + (list.length - 8) + ' 处');
}
console.error('\n✗ 旧设计系统又长回来了 — 新界面只许用 X* 令牌与组件 (见 App/Core/Theme.swift / Components.swift)');
process.exit(1);
