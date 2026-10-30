#!/usr/bin/env node
// 引用核查（**顾问级，不判失败**）— node tools/citecheck.js [docs文件…]
//
// 2026-10-30 修正（第 110 轮）：原头注写「引用核查**闸门**」，而全文只有 `process.exit(0)`
// —— 它**永远不会失败**，叫"闸门"名不副实。CI 里的步骤名本来就写着「不判失败」，
// 两边说法不一致（第 110 轮 `gateaudit` 扫出来的）。现在统一为「顾问级」。
//
// 为什么不能真判失败：台账里的 `文件:行号` 摘录会随代码漂移，而本仓有 60 份历史文档
// 保留了**有意为之**的历史行号（记的是"某批删了什么"）—— 判失败会红一片，
// 只能把"搜不到"报给人读。
// 为什么要有它: 本轮审计已经两次栽在"台账说做了"上 (278/203 只凭注释判 DONE), 而且我实测发现
// 前一个 agent 的文档里存在指向**别的类型**的行号。对抗式审计不该靠人一行行回看, 这条能机器筛掉
// "摘录在全仓根本找不到"的臆造引用, 并把"摘录对但行号漂了"单独列出来 (改过文件后必然漂)。
//
// 判定:
//   OK      摘录出现在引用的行号上
//   DRIFT   摘录在全仓找得到, 但不在引用行号 (内容真, 指针旧)
//   MISSING 摘录在 App/ Tests/ 里搜不到 —— 臆造、被删掉、或抄错
//   NOFILE  引用的文件名在仓里不存在
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');

function walk(dir, ext, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, ext, out);
    else if (p.endsWith(ext)) out.push(p);
  }
  return out;
}
// 源码库: App/ + Tests/ + Widget/ (与 deadscan 同一口径 —— 只数 App/ 会漏掉测试侧引用, 第四十一批踩过;
// 927 之后第二个 target 是 Widget/, 台账里指进它的指针同样必须能被核到)
const sources = walk(path.join(ROOT, 'App'), '.swift')
  .concat(walk(path.join(ROOT, 'Tests'), '.swift'), walk(path.join(ROOT, 'Widget'), '.swift'));
const auxDocs = walk(path.join(ROOT, 'docs'), '.md');
const srcLines = sources.concat(auxDocs).map((f) => ({
  base: path.basename(f),
  rel: path.relative(ROOT, f).replace(/\\/g, '/'),
  lines: fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n'),
}));

// 类型名 → 声明所在文件 (台账常用 `类型名:行` 而不是 `文件名:行` 定位)
const typeFile = new Map();
for (const s2 of srcLines) {
  for (const l of s2.lines) {
    const m = l.match(/^\s*(?:@\w+\s+)*(?:public |private |internal |fileprivate |final |open )*(?:struct|class|enum|actor|protocol)\s+([A-Z][A-Za-z0-9_]*)/);
    if (m && !typeFile.has(m[1])) typeFile.set(m[1], s2.base);
  }
}

const docs = process.argv.slice(2).filter((a) => !a.startsWith('-'));
const docList = docs.length ? docs : ['docs/AUDIT-A.md', 'docs/AUDIT-B.md', 'docs/AUDIT-C.md', 'docs/AUDIT-D.md', 'docs/AUDIT-E.md', 'docs/AUDIT-CODE.md', 'docs/FEATURE-TRIAGE.md', 'docs/AUDIT-GAP-CAUSES.md'];

// 归一化: 摘录取前 24 个"实质字符"(跳过空白/反引号/破折号类), 比对两侧同规则
const norm = (s) => s.replace(/[\s`'""⚠️→·、,.;:!?()（）{}[\]<>+#*]/g, '').replace(/…|\.\./g, '').slice(0, 24);
// 引用形态: `Name.swift:123 摘录…` / `Name:123 摘录…`, 摘录 = 该行剩余部分 (先按 ‖ 拆成一行一条)
const CITE = /([A-Z][A-Za-z0-9_]{2,})(?:\.swift)?:(\d{1,5})\s+(.{6,})$/g;

let ok = 0, drift = 0, missing = 0, nofile = 0, skipped = 0, prose = 0, symOk = 0;
const missingList = [], driftList = [];

for (const d of docList) {
  const p = path.join(ROOT, d);
  if (!fs.existsSync(p)) continue;
  const text = fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n').replace(/‖/g, '\n');
  const seen = new Set();
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    for (const m of line.matchAll(CITE)) {
      const file = m[1], ln = Number(m[2]);
      // 摘录截到下一个表格分隔为止, 去掉尾部 markdown
      const excerpt = m[3].split(/\s*\|\s/)[0];
      const key = d + '|' + file + ':' + ln + '|' + norm(excerpt);
      if (seen.has(key)) continue;
      seen.add(key);
      if (/^[+、与及和]/.test(excerpt)) { prose++; continue; }
      let cand = srcLines.filter((s) => s.base === file + '.swift' || s.base === file + '.md');
      if (!cand.length) {
        // 台账里有简写 (`Studio:1624` 指 CredentialStudio.swift), 也有一行跨文件引用 (`+ SettingsView(479)`)。
        // 先按词干模糊匹配, 匹配不到才报"无此文件"; 以 + / 、 / 与 开头的摘录是跨引用标记, 不是摘录 → 跳过。
        if (typeFile.has(file)) cand = srcLines.filter((s) => s.base === typeFile.get(file));
        const lc = file.toLowerCase();
        if (!cand.length) cand = srcLines.filter((s) => s.base.toLowerCase().includes(lc));
        if (!cand.length) { nofile++; missingList.push(`${d}: ${file}:${ln} 找不到对应文件 (简写或臆造)`); continue; }
      }
      const want = norm(excerpt);
      if (want.length < 8) { skipped++; continue; }        // 摘录太短没有判别力, 不参与判定
      // 三种引用形态要分开核 (上一版混在一起导致 443 条假阳性):
      //   A 逐字代码摘录  → 按内容比对行号
      //   B 符号名(说明)   → 只要求该符号出现在这个文件里, 不要求逐字
      //   C 中文说明       → 机器无法核对, 计数后跳过
      const symCit = /^([A-Za-z_]\w*)\s*[({:，,]/.test(excerpt);
      const codeish = /^\s*(\/\/|\/\*|#|@|let |var |func |static |enum |struct |class |case |return |if |guard |for |switch |import |extension |final |private |public )/.test(excerpt)
        || (/[()=]/.test(excerpt) && !/[\u4e00-\u9fff]/.test(excerpt));
      if (!codeish && !symCit) { prose++; continue; }
      if (symCit && !codeish) {
        const sym = excerpt.match(/^([A-Za-z_]\w*)/)[1];
        const re = new RegExp('\\b' + sym + '\\b');   // 允许 Type.member 形式 (台账常写 verifyChecksum 而源码是 BackupStudio.verifyChecksum)
        const inFile = cand.some((s) => s.lines.some((l) => re.test(l)));
        if (inFile) { symOk++; } else { missing++; if (missingList.length < 60) missingList.push(`${d}: ${file}:${ln} 符号 ${sym} 在该文件里根本不存在 (臆造或已删)`); }
        continue;
      }
      const atLine = cand.some((s) => s.lines[ln - 1] && norm(s.lines[ln - 1]).startsWith(want.slice(0, 10)));
      if (atLine) { ok++; continue; }
      const anywhere = cand.some((s) => s.lines.some((l) => norm(l).startsWith(want.slice(0, 10))));
      if (anywhere) {
        drift++;
        if (driftList.length < 40) {
          const hit = cand[0].lines.findIndex((l) => norm(l).startsWith(want.slice(0, 10))) + 1;
          driftList.push(`${d}: ${file}:${ln} → 实际在 ${file}:${hit} (内容真, 指针旧)`);
        }
      } else {
        // 逐字没命中, 但摘录以标识符开头 (如 `verifyChecksum(423)`) → 降级成"符号在该文件里存在吗"
        const sym = excerpt.match(/^([A-Za-z_]\w*)/);
        if (sym) {
          const re = new RegExp('\\b' + sym[1] + '\\b');
          if (cand.some((s) => s.lines.some((l) => re.test(l)))) { symOk++; continue; }
        }
        missing++;
        if (missingList.length < 60) missingList.push(`${d}: ${file}:${ln} 摘录全仓搜不到 → "${excerpt.slice(0, 46)}"`);
      }
    }
  }
}

console.log(`引用核查 (${docList.length} 个台账): OK ${ok} · 行号漂 ${drift} · 搜不到 ${missing} · 无此文件 ${nofile} · 太短跳过 ${skipped} · 中文说明型不核对 ${prose} · 符号级成立 ${symOk}`);
if (missingList.length) { console.log('\n【需要人读: 摘录搜不到】'); missingList.forEach((l) => console.log('  ' + l)); }
if (driftList.length) { console.log('\n【行号漂 (内容真, 可批量刷新指针)】'); driftList.forEach((l) => console.log('  ' + l)); }
// 漂移与搜不到都是"台账可信度"问题, 但不该把构建卡死: 报告 + 退出 0, 由人决定何时清账
process.exit(0);
