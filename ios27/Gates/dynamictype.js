#!/usr/bin/env node
// dynamictype.js —— 动态字体闸门。
//
// 判什么：
//   ① 不许出现 `.font(.system(size: N))` —— 写死 point size 意味着用户调大字号时它纹丝不动。
//   ② 不许出现 `V.F.sans(<数字>)` —— V7 的绕过通道：字号字面量必须走 V.F.xxx 命名档。
//   ③ 所有 V7 字体必须经 VFont（内部 @ScaledMetric + relativeTo）渲染；页面不许直接 Font.system(size:)。
//   ④ 豁免名单：只有令牌层自己可以定义固定数值；每个豁免都写明理由（见 EXEMPT）。
//
// V7 的 30 个字体常量全部是 VFont，由 V7Tokens.swift 的 VScaledFontModifier 用
// @ScaledMetric(relativeTo:) 在渲染时缩放 —— 默认字号仍是参考图像素值，大字档会跟着长大。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');
const V7 = path.join(APP, 'Design', 'V7', 'V7Tokens.swift');

// 豁免名单：相对路径 → 理由。只有令牌层可以出现数值字号。
const EXEMPT = {
  'Design/Tokens.swift': '旧令牌层：Font.TextStyle 语义字阶，不含 V7 字号',
  'Design/V7/V7Tokens.swift': 'V7 令牌层：V.F.sans(数字) 只在这里定义，并统一接 @ScaledMetric',
};

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const findings = [];
const files = walk(APP);
let fontRefs = 0;
let vFontRefs = 0;

for (const f of files) {
  const rel = path.relative(APP, f).split(path.sep).join('/');
  if (EXEMPT[rel]) continue;
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('///')) return;
    if (/\.font\(\s*\.system\(\s*size:/.test(line)) {
      findings.push(rel + ':' + (i + 1) + ' 写死字号（用户调大字号时不会跟着长）: ' + t.slice(0, 80));
    }
    if (/\bV\.F\.sans\(\s*[0-9]/.test(line)) {
      findings.push(rel + ':' + (i + 1) + ' V.F.sans(<数字>) 绕过命名档: ' + t.slice(0, 80));
    }
    if (/\bFont\.system\([^)\n]*\bsize:\s*[0-9]/.test(line)) {
      findings.push(rel + ':' + (i + 1) + ' 直接 Font.system(size: 数字) 不参与 Dynamic Type: ' + t.slice(0, 80));
    }
    if (/T\.F\.|V\.F\./.test(line)) fontRefs++;
    if (/V\.F\./.test(line)) vFontRefs++;
  });
}

// 令牌层自检：必须真的用 @ScaledMetric + relativeTo 接线，否则"命名档"只是换个写法的固定字号。
const v7src = fs.readFileSync(V7, 'utf8');
if (!/@ScaledMetric/.test(v7src)) {
  findings.push('V7Tokens.swift: 缺少 @ScaledMetric —— V7 字体没有接 Dynamic Type');
}
if (!/relativeTo\s*:/.test(v7src) || !/ScaledMetric\(wrappedValue:.*relativeTo:/.test(v7src)) {
  findings.push('V7Tokens.swift: 缺少 relativeTo 缩放接线');
}

console.log('dynamictype: ' + files.length + ' 个文件，' + fontRefs + ' 处走令牌字号（其中 V7 ' + vFontRefs + ' 处经 VFont/@ScaledMetric）');
if (findings.length === 0) {
  console.log('dynamictype: OK — 0 处写死字号，V7 全部走 VFont（@ScaledMetric + relativeTo）');
  process.exit(0);
}
console.log('dynamictype: FAIL — ' + findings.length + ' 处\n');
for (const f of findings.slice(0, 40)) console.log('  ' + f);
process.exit(1);
