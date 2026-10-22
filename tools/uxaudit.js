#!/usr/bin/env node
//  tools/uxaudit.js — 交互层审核器 (顾问级, 不判失败)
//
//  为什么有它: 设计技能的判据是**可机检的硬规则** (44pt 触达 / 8pt 间距 /
//  对比度 4.5:1 / 每屏 ≤1-2 个动画 / 不要 overuse 触觉 / reduced-motion 必检),
//  但它们散在 3 个 SKILL.md 里, 1235 处交互靠人读不完。
//  这个脚本把判据翻译成正则, 一次扫全仓, 输出**线索**而不是判决。
//
//  ⚠️ 能力边界 (必须讲清, 否则会被误当成门禁): 本脚本只能做"单行/固定窗口"级模式匹配。
//     SwiftUI 的嵌套结构 (Button 内嵌 HStack 内嵌 Label、修饰符链跨十几行) 正则**看不出层级**。
//     因此 A/B/E 三类只作线索; C/D 两类 (repeatForever / 触觉调用) 是点查, 相对可靠。
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
    // ⚠️ A 判据的已知局限（2026-10-18 记录）:
    //   SwiftUI 的 Button 是**嵌套结构**, 而正则看不出层级的边界。
    //   试过"按大括号配对取完整块"——结果把外层函数整段吞进来, 反而 100% 命中, 更不准。
    //   所以这里退回"固定窗口"并**明确它只产生线索**: 命中不一定真缺触达(可能触达写在窗口外),
    //   不命中也不一定没问题(触达可能写在 Button 前)。
    //   真判据只能靠真机走查或 Swift 语法树 —— 那是本脚本做不到的, 不假装能做到。
    if (/\bButton\s*\{/.test(l)) {
      // 窗口 8 →「Button 之后到下一个声明」(上限 30): 触达常写在 label 里的第三四行,
      // 8 行会漏(实测 AlarmsPage:119 的 XHit.min 在 :129 被误报成缺触达)。
      let winEnd = Math.min(lines.length - 1, i + 30);
      for (let k = i + 1; k < lines.length; k++) {
        if (/^\s{0,8}(?:private |public |internal )?(?:func|var|let)\s/.test(lines[k])) { winEnd = k - 1; break; }
      }
      const win = lines.slice(i, winEnd + 1).join('\n');
      // 2026-10-22: 原判据找 `DS.Hit.min` —— 而 DS 命名空间已于 2026-10-21 整份删除,
      // 现役令牌是 XHit.min(全仓 133 处)。查一个不存在的符号, 报出的是 112 处假阳性。
      // 另外两条也要认: ① X*ButtonStyle 内部已带 minHeight: XHit.min(调用点不该重复写);
      //                 ② 显式 44 数值(外观页色板就是 .frame(width: 44, height: 44))。
      const styled = /\.buttonStyle\(\s*(?:X(?:Primary|Secondary|Destructive)ButtonStyle|PressableScaleStyle|PressableButtonStyle|AnyButtonStyle)/.test(win);
      const hasHit = /XHit\.min|DS\.Hit\.min|minWidth:\s*(?:X|DS)\.Hit|minHeight:\s*4[4-9]|minWidth:\s*4[4-9]|frame\(\s*(?:width|height):\s*4[4-9]|Capsule\(\)|RoundedRectangle|contentShape\(/.test(win);
      // 还有一个高频形态: label 里调了本文件的辅助函数（row(...) / chipLabel(...)），
      // 而触达写在**那个函数**里。此时窗口里看不到 XHit，但那不是缺口。
      // 判据: 把本文件里所有「带 XHit.min / contentShape 的函数名」收集一遍，
      // 只要 label 调用其中之一就算达标。
      let helperHit = false;
      if (!styled && !hasHit) {
        const called = (win.match(/\b([a-zA-Z_][\w]*)\s*\(/g) || []).map((x) => x.replace(/\s*\($/, ''));
        const body = lines.join('\n');
        for (const name of new Set(called)) {
          if (name.length < 3) continue;
          // 窗口从 600 放宽到「函数体结束」：chipLabel 这类函数前面有大段注释,
          // 600 字符装不下，于是明明写了 XHit.min 还是被报成缺口。
          const fnRe = new RegExp('func\\s+' + name + '\\s*\\([^)]*\\)[^{]*\\{[\\s\\S]{0,1600}?(?:XHit\\.min|contentShape\\()');
          if (fnRe.test(body)) { helperHit = true; break; }
        }
      }
      // 还有一类不该判: 动作在系统容器里 —— ToolbarItem / contextMenu / swipeActions / Menu。
      // 这些容器的行高与命中由系统给（菜单项 >=44、工具栏按钮 44、滑动操作整行高），
      // 应用侧没有自己撑一个 44 这回事。
      const up = lines.slice(Math.max(0, i - 40), i).join('\n');
      const inSystemChrome = /(?:ToolbarItem|contextMenu|swipeActions|Menu)\s*[(\{]/.test(up);
      if (!styled && !hasHit && !helperHit && !inSystemChrome) {
        hits.A.push(rel + ':' + ln + '  ' + l.trim().slice(0, 70));
      }
    }
    // B · 动画没用令牌 (散写 duration / easeInOut)
    // 令牌定义处自身当然会写 duration —— 那不是散写, 是**定义**。
    // 令牌定义处（现役是 Theme.swift / Components.swift；旧 DesignSystem.swift 已于 2026-10-21 删除）
    const isTokenDef = /App\/Core\/(Theme|Components)\.swift$/.test(rel);
    if (!isTokenDef && /\.(easeInOut|easeOut|easeIn|linear)\(duration:|withAnimation\(\.(easeInOut|easeOut|easeIn)\(/.test(l)) {
      hits.B.push(rel + ':' + ln + '  ' + l.trim().slice(0, 70));
    }

    // C · 无限循环动画没切断隐式继承 (会与父层抢同一批属性)
    if (/repeatForever/.test(l)) {
      // 2026-10-22: 原判据只看「这一行前后 6/10 行」。但无限循环的**切断点**
      // 常在同一个 struct 的 body 上 —— 循环由 body 的属性驱动，而 withAnimation
      // 写在 body 下面的私有方法里。那是正确写法，却因隔着几行注释被判成未切断。
      // 现在两级判据：① 近邻窗口（快）② 同一 struct 体内出现过切断点（准）。
      const win = lines.slice(Math.max(0, i - 6), i + 10).join('\n');
      const near = /transaction\s*\{\s*\$0\.animation = nil/.test(win);
      let inStruct = false;
      if (!near) {
        let a = i;
        while (a > 0 && !/^(?:private |public |internal )?struct\s+\w+/.test(lines[a])) a--;
        let b = i;
        while (b < lines.length - 1 && lines[b] !== '}') b++;
        inStruct = /transaction\s*\{\s*\$0\.animation = nil/.test(lines.slice(a, b + 1).join('\n'));
      }
      if (!near && !inStruct) {
        hits.C.push(rel + ':' + ln + '  ' + l.trim().slice(0, 70));
      }
    }

    // D · 触觉密度 (ui-ux-pro-max: Don't overuse vibration)
    if (/(impactOccurred|notificationOccurred|sensoryFeedback)/.test(l)) {
      hits.D.push(rel + ':' + ln + '  ' + l.trim().slice(0, 70));
    }

    // E · 手势回调里丢掉了位移值 (Apple Design §2: 必须 1:1 跟手)
    if (/\.onChanged\s*\{\s*_\s+in/.test(l)) {
      // 销号 (与本仓 swiftlint 的「单位口径：」「方向口径：」同一手法):
      // 按住-填充类确认闸 (如「按住 2 秒清空回收站」) 本来就不需要位移，
      // 在附近写 `手势口径：<理由>` 即不再报。
      const gNearby = lines.slice(Math.max(0, i - 6), i + 1).join('\n');
      if (!/手势口径：/.test(gNearby)) {
        hits.E.push(rel + ':' + ln + '  ' + l.trim().slice(0, 70));
      }
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
