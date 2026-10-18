#!/usr/bin/env node
//  tools/uxaudit.js — 交互层审核器 (顾问级, 不判失败)
//
//  为什么有它: 设计技能的判据是**可机检的硬规则** (44pt 触达 / 8pt 间距 /
//  对比度 4.5:1 / 每屏 ≤1-2 个动画 / 不要 overuse 触觉 / reduced-motion 必检),
//  但它们散在 3 个 SKILL.md 里, 1235 处交互靠人读不完。
//  这个脚本把判据翻译成正则, 一次扫全仓, 输出**线索**而不是判决。
//
//  判据来源:
//    · apple-design        —— 响应/直接操纵/可中断性/spring
//    · emil-design-eng     —— 动效决策框架/看不见的细节
//    · ui-ux-pro-max       —— 触达 44pt(iOS)/48dp(Android)、8pt 间距、对比度、动画预算
//
//  用法: node tools/uxaudit.js [--verbose]
'use strict';
const fs = require('fs');
const path = require('path');

function walk(d, out) {
  out = out || [];
  if (!fs.existsSync(d)) return out;
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

// 从 lines[start] 起, 按大括号配对找块的结束行 (跳过字符串里的花括号: 本仓的字符串里没有裸花括号)
function blockEnd(lines, start) {
  let depth = 0;
  for (let i = start; i < lines.length; i++) {
    const code = lines[i].replace(/\/\/.*$/, '');
    for (const ch of code) {
      if (ch === '{') depth++;
      else if (ch === '}') { depth--; if (depth === 0) return i; }
    }
  }
  return Math.min(lines.length - 1, start + 40);
}

const files = walk('App');
const hits = { A: [], B: [], C: [], D: [], E: [], F: [] };

// 剥注释与字符串字面量, 避免把注释里的示例当成真代码
function codeOf(line) {
  return line.replace(/\/\/.*$/, '');
}

for (const f of files) {
  const rel = f.replace(/\\/g, '/');
  const src = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n');
  const lines = src.split('\n');
  lines.forEach((raw, i) => {
    const l = codeOf(raw);
    const ln = i + 1;

    // A · 可点元素没有最小触达 (ui-ux-pro-max: 44pt iOS / 48dp Android)
    if (/\bButton\s*\{/.test(l)) {
      // 只看**这一个 Button 的 label 块**: 从 Button 行起, 遇到 .buttonStyle / .onTapGesture /
      // 顶层 } 就停。原来用大括号配对会把整个外层函数都算进去 —— 那样永远"有触达"。
      let end = i;
      for (let j = i + 1; j < Math.min(lines.length, i + 40); j++) {
        if (/\.buttonStyle|\.onTapGesture|\.contentShape/.test(lines[j])) { end = j; break; }
        if (/^\s{0,12}\}\s*$/.test(lines[j])) { end = j; break; }
      }
      const win = lines.slice(i, end + 1).join('\n');
      if (!/DS\.Hit\.min|minHeight:\s*4[4-9]|minHeight:\s*5\d|frame\(height:\s*4[4-9]|frame\(height:\s*5\d|padding\(\.vertical: DS\.Space\.(m|l|xl)\)|Capsule\(\)|RoundedRectangle/.test(win)) {
        hits.A.push(rel + ':' + ln + '  ' + l.trim().slice(0, 70));
      }
    }
    // B · 动画没用令牌 (散写 duration / easeInOut)
    // 令牌定义处自身当然会写 duration —— 那不是散写, 是**定义**。
    const isTokenDef = rel === 'App/Core/DesignSystem.swift';
    if (!isTokenDef && /\.(easeInOut|easeOut|easeIn|linear)\(duration:|withAnimation\(\.(easeInOut|easeOut|easeIn)\(/.test(l)) {
      hits.B.push(rel + ':' + ln + '  ' + l.trim().slice(0, 70));
    }

    // C · 无限循环动画没切断隐式继承 (会与父层抢同一批属性)
    if (/repeatForever/.test(l)) {
      const win = lines.slice(Math.max(0, i - 6), i + 10).join('\n');
      if (!/transaction\s*\{\s*\$0\.animation = nil/.test(win)) {
        hits.C.push(rel + ':' + ln + '  ' + l.trim().slice(0, 70));
      }
    }

    // D · 触觉密度 (ui-ux-pro-max: Don't overuse vibration)
    if (/(impactOccurred|notificationOccurred|sensoryFeedback)/.test(l)) {
      hits.D.push(rel + ':' + ln + '  ' + l.trim().slice(0, 70));
    }

    // E · 手势回调里丢掉了位移值 (Apple Design §2: 必须 1:1 跟手)
    if (/\.onChanged\s*\{\s*_\s+in/.test(l)) {
      hits.E.push(rel + ':' + ln + '  ' + l.trim().slice(0, 70));
    }

    // F · 固定时长的等待/动画用在可中断交互上
    if (/Task\.sleep\(nanoseconds:\s*\d{9,}/.test(l) && /withAnimation/.test(lines.slice(Math.max(0,i-6), i).join('\n'))) {
      hits.F.push(rel + ':' + ln + '  ' + l.trim().slice(0, 70));
    }
  });
}

const titles = {
  A: '可点元素缺最小触达 (ui-ux-pro-max: iOS 44pt / Android 48dp)',
  B: '动画散写时长/曲线, 未走 DS.Motion 令牌 (emil: 拒绝 one duration for everything)',
  C: '无限循环动画未切断隐式动画继承 (会与父层抢属性)',
  D: '触觉调用点 (判据: 不要 overuse —— 逐个确认是否有必要)',
  E: '手势回调丢掉了位移值 (Apple Design §2: 必须 1:1 跟手)',
  F: '可中断交互上用了固定时长等待 (Apple Design §3)',
};

let total = 0;
for (const k of ['A','B','C','D','E','F']) {
  const arr = hits[k];
  total += arr.length;
  console.log('');
  console.log('【' + k + '】' + titles[k] + '  —— ' + arr.length + ' 处');
  const show = process.argv.includes('--verbose') ? arr : arr.slice(0, 12);
  show.forEach(x => console.log('    ' + x));
  if (!process.argv.includes('--verbose') && arr.length > 12) console.log('    … 其余 ' + (arr.length - 12) + ' 处见 --verbose');
}

console.log('');
console.log('合计线索 ' + total + ' 处。');
console.log('口径: 本脚本输出的是**线索不是判决** —— 触觉与动画的"是否必要"必须人读。');
process.exit(0);   // 顾问级: 恒 0
