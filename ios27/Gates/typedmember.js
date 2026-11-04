#!/usr/bin/env node
// typedmember.js - gate 40: 属性声明与裸赋值的对账（**只在已知类型体内**）
//
// 2026-11-05（CI 真编译错驱动）：我删了 SettingsModel 的 rowHeight / timelineGap /
// digitFont / recentCount / recordPolicy 五个属性，39 道闸门**全绿**，
// 而 CI 的金标测试报 5 条 "cannot find 'rowHeight' in scope"。
//
// 为什么闸门没抓到：`storemember` 只查 `store.xxx` 这种**点号访问**；
// 而 resetAppearance() 里写的是裸赋值 `rowHeight = ""` —— 不是点号语法，正则匹配不到。
//
// 我第一版判据（"零外部点号访问 + 体内有裸赋值"）报了 1697 处假红：
// @State 属性、局部变量、VFont 的成员参数全都符合那个形状。**静态解析做不到**。
//
// 这一版的判据换成**可证明的形态**：只看 `SettingsStore` 与 `AppModel` 这两个
// 「以 var/let 声明、以裸赋值写入」的类 —— 它们的成员表是显式的、可枚举的。
// 对这两个类型：函数体内的 `<name> = ...` / `self.<name> = ...`，若 `<name>` 不在成员表里
// ⇒ 判红。这恰好覆盖「删了属性但忘了删赋值」这一类，且不会误报（局部变量不在这两个类体内声明）。
//
// 不判什么：其它类型（@State 与局部变量混在一起，静态判不了）；协议扩展。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const files = walk(APP).map((f) => {
  const rel = path.relative(APP, f).split(path.sep).join('/');
  return { rel, src: fs.readFileSync(f, 'utf8') };
});

// 这两个类的成员表是显式的（见文件头说明）
const TARGETS = ['SettingsStore', 'AppModel'];

function blockAt(text, openIdx) {
  let depth = 0, i = openIdx;
  for (; i < text.length; i++) {
    if (text[i] === '{') depth++;
    else if (text[i] === '}') { depth--; if (depth === 0) break; }
  }
  return text.slice(openIdx, i + 1);
}

const members = new Map();   // 类型名 → Set(成员)
const bodies = new Map();    // 类型名 → [{rel, body}]
for (const t of TARGETS) members.set(t, new Set());
for (const t of TARGETS) bodies.set(t, []);

for (const { rel, src } of files) {
  for (const t of TARGETS) {
    const re = new RegExp('(?:final class|class|struct|enum|extension)\\s+' + t + '\\b[^{]*', 'g');
    let m;
    while ((m = re.exec(src)) !== null) {
      const open = src.indexOf('{', m.index + m[0].length - 1);
      if (open < 0) continue;
      const body = blockAt(src, open);
      bodies.get(t).push({ rel, body });
      for (const d of body.matchAll(/^\s{0,16}(?:@\w+(?:\([^)]*\))?\s+)?(?:(?:public|private|fileprivate|internal|static|class|final|override|mutating|nonisolated|lazy|weak|indirect)\s+)*(?:var|let|func)\s+([A-Za-z_]\w*)/gm)) {
        members.get(t).add(d[1]);
      }
    }
  }
}

const findings = [];
for (const t of TARGETS) {
  for (const { rel, body } of bodies.get(t)) {
    const lines = body.split(/\r?\n/);
    lines.forEach((line, i) => {
      const s = line.trim();
      if (s.startsWith('//') || s.startsWith('///')) return;
      // 声明行不算（var/let/func/@ 开头）
      if (/^(?:@|var|let|func|static|private|public|internal|fileprivate|class|case|init|deinit)\b/.test(s)) return;
      // 裸赋值：name = / self.name = / name += 等
      const m = /^(?:self\.)?([a-z_][A-Za-z0-9_]*)\s*(?:\+=|\-=|\*=|=(?!=))/.exec(s);
      if (!m) return;
      const name = m[1];
      if (name === "_") return;   // _ = revision 是 Swift 的 discard，不是成员
      if (members.get(t).has(name)) return;
      findings.push(rel + '  ' + t + ' 体内赋值 ' + name + '，但成员表里没有它');
    });
  }
}

const uniq = [...new Set(findings)];
if (uniq.length === 0) {
  console.log('typedmember: OK — ' + TARGETS.join(' / ') + ' 体内裸赋值的名字都在成员表里');
  process.exit(0);
}
console.log('typedmember: FAIL — ' + uniq.length + ' 处');
for (const f of uniq.slice(0, 30)) console.log('  ' + f);
process.exit(1);
