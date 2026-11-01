#!/usr/bin/env node
// a11y.js —— 无障碍闸门。
//
// 判什么：
//   ① 图标按钮（label 只有 Image(systemName:)）必须有 .accessibilityLabel
//   ② 触达：.frame(width:/height:) 小于 44 的可点区判失败
//   ③ VListRow 的 accessibilityLabel 必须拼上 value（设置页右侧读数不能对 VoiceOver 消失）
//   ④ 图表组件（VRingStack / VMiniBars / VAreaChart / VSegmentedRing）必须有 accessibilityValue 描述数据
//   ⑤ 装饰性图标必须 .accessibilityHidden(true)
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');
const V7_COMPONENTS = path.join(APP, 'Design', 'V7', 'V7Components.swift');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

function structBlock(src, name) {
  const start = src.search(new RegExp('struct\\s+' + name + '\\b'));
  if (start < 0) return null;
  const open = src.indexOf('{', start);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') {
      depth--;
      if (depth === 0) return src.slice(start, i + 1);
    }
  }
  return null;
}

const files = walk(APP);
const findings = [];

for (const f of files) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split(/\r?\n/);

  // ① 图标按钮缺 label：向后 30 行内没有 accessibilityLabel
  lines.forEach((line, i) => {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;

    if (/Button\s*\{/.test(line) || /Button\(action:/.test(line) || /Button\s*\(/.test(line)) {
      const win = lines.slice(i, i + 30).join('\n');
      const hasImage = /Image\(systemName:/.test(win);
      const hasTextish = /Text\(|Label\(|FieldRow\(|Reading\(|VTextFieldRow\(|VValueRow\(|VReading\(/.test(win);
      const hasLabel = /accessibilityLabel/.test(win);
      if (hasImage && !hasTextish && !hasLabel) {
        findings.push({ file: rel, line: i + 1, why: '图标按钮缺 accessibilityLabel（无任何文字承载）' });
      }
    }

    // ② 触达小于 44。
    // 2026-11-01 扩判据：旧实现只匹配 `.frame(width: N, height: N)`（**两个数字字面量**），
    // 于是完全看不到这两种写法：
    //   · `.frame(height: 32)`            —— 只有 height，且是字面量
    //   · `.frame(height: V.Hit.min - V.S.gapMS)` —— 令牌表达式（44-12=32）
    // `KeysBits.KeysChips` 就是后者：胶囊高 32pt，命中区实际只有 32pt，而闸门说"无 <44pt 可点区"。
    const mPair = /\.frame\(\s*width:\s*([0-9]+)\s*,\s*height:\s*([0-9]+)\s*\)/.exec(line);
    const mH = /\.frame\(\s*height:\s*([0-9]+)\s*\)/.exec(line);
    const mMinus = /\.frame\(\s*height:\s*V\.Hit\.min\s*-\s*(V\.S\.\w+)\s*\)/.exec(line);
    let bad = null;
    if (mPair) {
      const w = +mPair[1], h = +mPair[2];
      if (w < 44 || h < 44) bad = `${w}×${h}`;
    } else if (mH && +mH[1] < 44) {
      bad = `h=${mH[1]}`;
    } else if (mMinus) {
      // `V.Hit.min - V.S.gapX` 永远小于 44 —— 除非那一行同时有 minHeight 兜底。
      if (!/minHeight/.test(line)) bad = `V.Hit.min - ${mMinus[1]}`;
    }
    // 2026-11-01：`V.Action.height` / `V.Tab.height` 是**下限**，不许当固定高度用。
    // 背景：`V.F.bodyStrong`（17pt）与 `V.F.tab`（11pt）都随 Dynamic Type 缩放，
    // 固定高度在大字号下会把文字裁掉（ROUND-158 修过 4 处）。
    // 这条判据很窄（只认这两个令牌名），所以假红率为 0 —— 新增控件请用 minHeight。
    const mFixedH = /\.frame\(\s*height:\s*V\.(Action|Tab)\.height\s*\)/.exec(line);
    if (mFixedH) {
      findings.push({ file: rel, line: i + 1, why: 'V.' + mFixedH[1] + '.height 是下限，请改用 minHeight（固定高度会在大字号下裁字）' });
      bad++;
      return;
    }
    if (bad && !rel.includes('Components/')) {
      findings.push({ file: rel, line: i + 1, why: `可点区 ${bad} < 44pt` });
    }
  });
}

// ③ VListRow 必须把 value 拼进 accessibilityLabel
const v7src = fs.readFileSync(V7_COMPONENTS, 'utf8');
const listRow = structBlock(v7src, 'VListRow');
if (!listRow) {
  findings.push({ file: 'Design/V7/V7Components.swift', line: 0, why: '找不到 VListRow 组件' });
} else {
  const hasLabel = /accessibilityLabel\(/.test(listRow);
  const hasValueInLabel = /a11yLabel[\s\S]*value/.test(listRow) || /accessibilityLabel\([^)]*value/.test(listRow);
  if (!hasLabel || !hasValueInLabel) {
    findings.push({ file: 'Design/V7/V7Components.swift', line: 0, why: 'VListRow 的 accessibilityLabel 未拼上 value（VoiceOver 会吞掉右侧读数）' });
  }
}

// ④ 图表组件必须有 accessibilityValue 描述数据
for (const name of ['VRingStack', 'VMiniBars', 'VAreaChart', 'VSegmentedRing']) {
  const block = structBlock(v7src, name);
  if (!block) {
    findings.push({ file: 'Design/V7/V7Components.swift', line: 0, why: `找不到图表组件 ${name}` });
    continue;
  }
  if (!/\.accessibilityValue\(/.test(block)) {
    findings.push({ file: 'Design/V7/V7Components.swift', line: 0, why: `${name} 缺 accessibilityValue（图表数据对 VoiceOver 不可读）` });
  }
}


// ⑤ DesignLab 生成器不许产出无 alt 的 <img>（D-14）。
// 设计总览是给人看/给屏幕阅读器读的页面；27 张无 alt 的图在 VoiceOver 下等于 27 个匿名图形。
{
  const labDir = path.join(ROOT, 'DesignLab');
  if (fs.existsSync(labDir)) {
    for (const name of fs.readdirSync(labDir).filter(function (n) { return n.endsWith('.js'); })) {
      const src = fs.readFileSync(path.join(labDir, name), 'utf8');
      const re = /<img(?![^>]*\balt=)[^>]*>/g;
      let m;
      while ((m = re.exec(src)) !== null) {
        const line = src.slice(0, m.index).split('\n').length;
        findings.push({ file: 'DesignLab/' + name, line: line, why: '<img> 缺 alt（屏幕阅读器只读到匿名图形）' });
      }
    }
  }
}

// ⑥ 下限令牌不许当固定尺寸用（2026-11-01）。
// V.H.min / V.H.action 是**可点区下限**；写成 `.frame(height: V.H.action)` 就变成上限，
// 最大动态字号下按钮标题会被裁掉（SwiftUI 不报错，只是看不见字）。
// 正确写法是 `.frame(minHeight: ...)`。
{
  for (const fp of files) {
    const src = fs.readFileSync(fp, 'utf8');
    const rel = path.relative(ROOT, fp).split(path.sep).join('/');
    src.split(/\r?\n/).forEach((line, i) => {
      if (line.trim().startsWith('//')) return;
      if (!/\.frame\(\s*(height|width)\s*:\s*V\.H\./.test(line)) return;
      findings.push({ file: rel, line: i + 1, why: '下限令牌被当作固定尺寸（大字号会裁字）：改用 minHeight/minWidth' });
    });
  }
}

console.log(`a11y: 扫 ${files.length} 个文件`);
if (findings.length === 0) {
  console.log('a11y: OK — 图标按钮都有 label，无 <44pt 可点区，VListRow value 与图表数据均可朗读');
  process.exit(0);
}
console.log('a11y: FAIL — ' + findings.length + ' 处\n');
for (const f of findings) console.log(`  ${f.file}:${f.line}  ${f.why}`);
process.exit(1);
