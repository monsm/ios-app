#!/usr/bin/env node
// tools/pagecraft.js —— 页面品质记分卡
//
// 把"每个界面都要大师水准"变成可量化清单，而不是凭感觉逐页翻。
// 按 5 个维度给每个纵深页面打分：
//   ① 字号    是否走 .xFont 语义字号（决定 Dynamic Type 能不能用）
//   ② 空态    0 数据时用户看到什么
//   ③ 无障碍  accessibilityLabel / Hidden / Hint
//   ④ 令牌    有没有裸写颜色（绕过设计系统）
//   ⑤ 状态    加载 / 错误 / 重试 的表达
//
// ⚠ 关键实现点：这些 struct 常与别的 struct 共处一个文件（如 SecurityCenterView.swift
//   里挤了 PrivacyDashboard / SecurityAuditView / SecurityDestroyView）。
//   所以必须按 **struct 名**定位，再按花括号截出该 struct 自身的 body 再统计，
//   否则同文件其他结构的 content 会污染指标 —— 第一版就是栽在这里。
//
// 诊断工具，不参与 CI 判定。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const ROUTES = JSON.parse(fs.readFileSync(path.join(ROOT, '.routes.json'), 'utf8'));

function allSwift() {
  const out = [];
  const walk = d => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith('.swift')) out.push(p);
    }
  };
  walk(path.join(ROOT, 'App'));
  return out;
}

const FILES = allSwift();
const CACHE = new Map();
function srcOf(f) { if (!CACHE.has(f)) CACHE.set(f, fs.readFileSync(f, 'utf8')); return CACHE.get(f); }

// 截出 struct 自身范围（花括号配平，跳过字符串与注释）
function structBody(name) {
  for (const f of FILES) {
    const src = srcOf(f);
    const re = new RegExp('^(?:struct|final class) ' + name + '\\b[^\\n]*\\{', 'm');
    const m = re.exec(src);
    if (!m) continue;
    const start = m.index;
    const open = src.indexOf('{', m.index);
    let depth = 0, i = open, inStr = false, inLine = false;
    for (; i < src.length; i++) {
      const c = src[i], n = src[i + 1];
      if (inLine) { if (c === '\n') inLine = false; continue; }
      if (inStr) { if (c === '\\') { i++; continue; } if (c === '"') inStr = false; continue; }
      if (c === '/' && n === '/') { inLine = true; i++; continue; }
      if (c === '"') { inStr = true; continue; }
      if (c === '{') depth++;
      else if (c === '}') { depth--; if (depth === 0) break; }
    }
    return { file: f, text: src.slice(start, i + 1) };
  }
  return null;
}

const rows = [];
for (const [route, view] of ROUTES) {
  const s = structBody(view);
  if (!s) { rows.push({ route, view, missing: true }); continue; }
  const src = s.text;
  const code = src.split('\n').filter(l => !/^\s*\/\//.test(l)).join('\n');

  const semantic = (code.match(/\.xFont\(\.(body|caption|caption2|footnote|subheadline|callout|headline|title|title2|title3|largeTitle)/g) || []).length;
  const anyFont = (code.match(/\.xFont\(/g) || []).length;
  const fontOK = anyFont === 0 || semantic > 0;

  // 空态：XEmptyState、isEmpty 分支，或**对零值的显式分支**。
  // 配置类页面没有"列表为空"，它的空态是"一项都没开"——
  // 只要代码里对 0 做了单独的文案/语气处理，就算考虑了。
  const emptyOK = /XEmptyState|\.isEmpty\s*\{|\.isEmpty \?|\.isEmpty\)|== 0\s*\{/.test(code);

  const a11y = (code.match(/accessibility(Label|Hint|Hidden|Element|Value|Action)/g) || []).length;
  const a11yOK = a11y >= 2;                       // 单一处不算"考虑过无障碍"

  const rawColor = (code.match(/Color\(red:|Color\(white:|Color\(hex:\s*0x[0-9A-Fa-f]{6}/g) || []).length;
  const tokenOK = rawColor === 0;

  // 状态：异步三态（加载/失败/重试）**或**显式的语气色分支。
  // 本地配置页没有网络态，强求"重试"是拿错尺子量它；
  // 它该有的是"当前处于好/警告/中立"中的哪一种，并且说出来。
  const stateOK = /加载|失败|重试|retry|Retry|error|Error|isLoading|XBusyButton|XEmptyState|XStatusPill|XPalette\.(warn|danger|ok)\b/.test(code);

  const score = [fontOK, emptyOK, a11yOK, tokenOK, stateOK].filter(Boolean).length;
  rows.push({ route, view, score, fontOK, emptyOK, a11yOK, tokenOK, stateOK, a11y, lines: src.split('\n').length, file: path.relative(path.join(ROOT, 'App'), s.file) });
}

rows.sort((a, b) => (a.score ?? -1) - (b.score ?? -1));
console.log('route              视图                   分  字号 空态 无障碍 令牌 状态   行  文件');
console.log('─'.repeat(100));
for (const r of rows) {
  if (r.missing) { console.log(r.route.padEnd(19) + r.view.padEnd(23) + ' struct 未找到'); continue; }
  const m = v => v ? ' ✓ ' : ' ✗ ';
  console.log(
    r.route.padEnd(19) + r.view.padEnd(23) + String(r.score).padStart(2) +
    m(r.fontOK) + m(r.emptyOK) + m(r.a11yOK) + '  ' + m(r.tokenOK) + m(r.stateOK) +
    String(r.lines).padStart(5) + '  ' + r.file
  );
}
const scored = rows.filter(r => !r.missing);
const avg = scored.reduce((s, r) => s + r.score, 0) / scored.length;
const low = scored.filter(r => r.score <= 3);
console.log('─'.repeat(100));
console.log('平均分 ' + avg.toFixed(2) + ' / 5   ≤3 分的页面: ' + low.length + ' 个');
if (low.length) console.log('待改: ' + low.map(r => r.view).join(', '));
