#!/usr/bin/env node
// tokens.js —— 设计令牌闸门。
//
// 判什么：页面/组件里不许出现颜色、间距、圆角、字号的字面量。一切走 V./T./Ink./Signal./State.
// 为什么：上一版的教训是"页面各自写死颜色与尺寸"，令牌系统形同虚设。
//
// V7 接入（2026-10-31）：
//   · V7 的字体只能走 V.F.xxx 命名档；V.F.sans(<数字>) 是绕过通道，必须判失败。
//   · 直接写死的 font size: 数值 同样判失败（字体必须经 VFont / 语义字阶）。
//   · V.C.rgb 只许出现在 V7Tokens.swift（令牌层的家）。
//
// 例外（白名单必须写理由）：
//   · Design/Tokens.swift / Design/V7/V7Tokens.swift 本身就是字面量的家
//   · Design/Components/Dial.swift 里的 Canvas 数值（几何计算，不是样式令牌）
//   · 0 值（padding(0) / spacing(0) 是布局复位，不是样式决定）
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

// 白名单：相对路径 → 理由
const EXEMPT = {
  'Design/Tokens.swift': '旧令牌定义本身就是字面量的家',
  'Design/V7/V7Tokens.swift': 'V7 令牌层：rgb()/V.F.sans(数字) 只能在这里定义',
  'Design/Components/Dial.swift': 'Canvas 几何计算（刻度长度/角度），不是样式令牌',
};

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const files = walk(APP);
const findings = [];

// 逐条规则：[正则, 说明, 允许的上下文]
const RULES = [
  [/\.padding\(\s*\(?\s*[0-9]/, '硬编码 padding', null],
  [/\bspacing:\s*[0-9]/, '硬编码 HStack/VStack spacing', null],
  [/\.frame\([^)]*height:\s*[0-9]{2,}/, '硬编码固定高度（≥10）', null],
  [/\.cornerRadius\(\s*[0-9]/, '硬编码 cornerRadius（应走 clipShape(.rect(cornerRadius: T.R.…))）', null],
  [/\.system\(size:\s*[0-9]/, '硬编码字号（应走 V.F.* / T.F.*）', null],
  [/\bV\.F\.sans\(\s*[0-9]/, 'V7 字号字面量 V.F.sans(<数字>)（应走 V.F.xxx 命名档）', null],
  [/\.font\([^)\n]*\bsize:\s*[0-9]/, '硬编码字体 size: 数值（应走 V.F.xxx 命名档）', null],
  [/\bFont\.system\([^)\n]*\bsize:\s*[0-9]/, '硬编码字体 Font.system(size: 数字)', null],
  [/\bV\.C\.rgb\(/, 'V7 原始 RGB 只许出现在 V7Tokens.swift', 'Design/V7/V7Tokens.swift'],
  [/Color\.(red|blue|green|orange|yellow|purple|pink|gray|black|white)\b/, '系统颜色字面量（应走 Ink./Signal./State./V.C）', null],
  [/Color\(hex:\s*0x/, 'Color(hex:) 只许出现在 Design/Tokens.swift', 'Design/Tokens.swift'],
  [/\.foregroundStyle\(\s*\.(white|black|red|blue|green|gray)\s*\)/, '系统颜色字面量', null],
];

for (const f of files) {
  const rel = path.relative(APP, f).split(path.sep).join('/');
  if (EXEMPT[rel]) continue;
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    // 跳过纯注释行
    const trimmed = line.trim();
    if (trimmed.startsWith('//') || trimmed.startsWith('///')) return;
    for (const [re, why, allow] of RULES) {
      if (allow && rel === allow) continue;
      const m = re.exec(line);
      if (!m) continue;
      // 0 值豁免：padding(0) / spacing: 0
      if (/\b0\b/.test(m[0])) continue;
      findings.push({ file: rel, line: i + 1, why, text: trimmed.slice(0, 120) });
    }
  });
}

// 输出
if (findings.length === 0) {
  console.log(`tokens: OK — ${files.length} 个 Swift 文件，0 处硬编码样式字面量（含 V7 字号/色板）`);
  process.exit(0);
}
console.log(`tokens: FAIL — ${findings.length} 处硬编码\n`);
for (const f of findings) {
  console.log(`  ${f.file}:${f.line}  ${f.why}`);
  console.log(`      ${f.text}`);
}
process.exit(1);
