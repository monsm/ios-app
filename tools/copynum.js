#!/usr/bin/env node
// 用户可见文案里的内部规格编号检查 (顾问级, 不判失败) — node tools/copynum.js
//
// 为什么加这条: 本仓用"(N 说明)"给每处改动挂台账编号，**注释里**这么写是对的 (可追溯)，
// 但有些编号漏进了用户能看见的字符串 —— 截图里"成员别名显示 (919: 关系备注优先, 如「老妈」)"
// 就是一例：一行标签被撑成两行、右侧开关被挤到第二行，用户看到的还是一串跟自己无关的编号。
// 2026-10-14 地毯式扫出并清掉两批共 40 处 (CredentialStudio / AccessibilityView / BackupStudio /
// SettingsView / SecurityCenterView / MemberCenterView / StatsView / RecordsTimeline / Sheets …)，
// 同时抓到 SecurityCenterView 一处**硬编码假总数**
// ("另有 N 条 — 只列前 8 条 (9)"，实际 12 条时那个 9 是谎)。
// 历史口径: 乱源治理"界面文案去编号 1037 处"清过一大批，这批是后来新长出来的 —— 所以留一条静态守卫。
//
// 判定口径 (只扫**字符串字面量**内部, 且要求字面量含中文):
//   规格编号 = ( 1~4 位数字 + 紧跟 [:：,，、] 或 ) ，或 + 中文说明 (且首字不是量纲单位)
// 形如 "… (919: …)" "… (332, 约)" "… (9)" "… (306 分屏 / 307 逐位 diff)" "… (638 第三级 …)"
// 排除:
//   · 注释 (/// 与 // 开头的行) 与行尾 `// …` —— 那里正是编号该待的地方
//   · 插值 `\(...)` 内容 —— 是指令/计算, 不是给人看的编号 (先替换成占位符再判)
//   · 多行字符串 `"""` 块 —— 里面常是说明性正文, 且插值多, 易误报 (整块跳过)
//   · 量纲说明: "(30 秒演示)" "(4 批)" "(1 米内)" "(365 天)" "(0 条时…)" "(10 分钟有效)"
//     —— 数字后面跟的是**单位**, 是给人看的信息, 不是台账编号
// 定成顾问级: 与 assetscheck 同口径, 先报线索不误伤提交; 连续几批 0 命中再升判失败。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = process.argv[2] || 'App';
const files = [];
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p); else files.push(p);
  }
})(ROOT);

// 量纲单位 (数字 + 单位 = 给人看的信息, 放行)
const UNITS = ['天', '条', '批', '秒', '分', '米', '次', '小', '时', '个', '位', '号', '款', '种', '项',
               '步', '页', '行', '层', '档', '版', '周', '月', '年', '人', '枚', '张', '台', '把'];
// 有意保留的带编号对外文案 (目前为空)
const ALLOW = new Set([]);
const CJK = /[\u4e00-\u9fff]/;

function isSpecNumber(rest) {
  const m = /^(\d{1,4})(.*)$/.exec(rest);
  if (!m) return false;
  const tail = m[2];
  if (/^[:：,，、]/.test(tail)) return true;            // "(332, 约)" "(919: …)"
  if (/^[)）]/.test(tail)) return true;                 // "(9)" 裸编号
  const lead = /^\s+(.)/.exec(tail);
  if (lead && CJK.test(lead[1])) return !UNITS.includes(lead[1]);   // "(638 第三级 …)" 命中, "(365 天)" 放行
  return false;
}

// 括号配对剥离插值: 正则处理不了嵌套括号 (max(0, f()) 一类), 这里手工扫深度
function stripInterpolations(s) {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '\\' && s[i + 1] === '(') {
      let depth = 0; let j = i + 1;
      for (; j < s.length; j++) {
        if (s[j] === '(') depth++;
        else if (s[j] === ')') { depth--; if (depth === 0) { j++; break; } }
      }
      out += '§';
      i = j - 1;
    } else out += s[i];
  }
  return out;
}

let hits = 0;
for (const f of files) {
  if (!f.endsWith('.swift')) continue;
  const src = fs.readFileSync(f, 'utf8');
  // 多行字符串 """ 块整段跳过 (行号只用于报告)
  const blockLines = new Set();
  const linesAll = src.split(/\r?\n/);
  let inBlock = false;
  linesAll.forEach((l, i) => {
    const n = (l.match(/"""/g) || []).length;
    if (inBlock) { blockLines.add(i + 1); if (n % 2 === 1) inBlock = false; return; }
    if (n % 2 === 1) inBlock = true;
  });

  linesAll.forEach((raw, i) => {
    const ln = i + 1;
    const t = raw.trim();
    if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) return;
    if (blockLines.has(ln)) return;
    let code = stripInterpolations(raw);
    const cut = code.search(/\s\/\//);
    if (cut >= 0) code = code.slice(0, cut);
    // 逐个字符串字面量判
    const litRe = /"(?:[^"\\]|\\.)*"/g;
    let m;
    while ((m = litRe.exec(code)) !== null) {
      const body = m[0].slice(1, -1);
      if (!CJK.test(body)) continue;
      const inner = /[(（]\d{1,4}[^)]*/g;
      let bad = null;
      let mm;
      while ((mm = inner.exec(body)) !== null) {
        const rest = mm[0].slice(1);
        if (isSpecNumber(rest)) { bad = mm[0]; break; }
      }
      if (!bad) continue;
      if (ALLOW.has(f + ':' + ln)) return;
      console.log(`内部规格编号疑似进界面: ${f}:${ln}  ${m[0].slice(0, 96)}`);
      hits++;
      return;
    }
  });
}

console.log(hits === 0
  ? '✓ 用户可见文案无内部规格编号'
  : `⚠ 用户可见文案疑似含内部规格编号 ${hits} 处 (顾问级, 不判失败) — 保留说明、删掉编号`);
