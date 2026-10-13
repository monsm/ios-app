#!/usr/bin/env node
// 台账指针存活检查 (顾问级, 不判失败) — node tools/docpointers.js
// 为什么单独有这一支: citecheck 核的是 `文件:行 + 摘录` 这种可机检形状, 而 §10.3 那张表的
// "定位"列写的是 `CredHistoryView.diffFrom`、CAPABILITY 里写的是 `PM.swift:6-54` 这类**散文型指针** ——
// 第八十五批我就照着 CredHistoryView 这个已经不存在的文件名去找代码, 白跳一跳。
//
// 三条机械规则:
//   ① 文档里出现的 `X.swift` 必须在树里存在 (落空=无此文件, 或只是缩写如 PM.swift 代指 PidMap.swift)。
//   ② `Ident.member` 型指针: 若 `Ident.swift` 这个**文件**在, 但 `Ident` 不是树里声明的**类型**,
//      判"把文件名当类型名用" —— 这类指针能跳到文件, 却会误导下一个读的人 (实测: 文档写
//      `ExportCenter.buildCSV`, 真实宿主是同一文件里的 `enum ExportKit`)。
//   ③ `Ident.member`: 文件与类型都不存在 → 判死指针候选 (系统类型按前缀白名单挡掉)。
// 白名单只是"宁可放过", 不证明命中的都是系统类型; 报线索不判失败, 由人决定改文档还是改代码。
'use strict';
const fs = require('fs');
const path = require('path');

// `fixtures` 也在树里：闸门自己的正控样例 (`fixtures/swiftshape/fire/CodableRisky.swift` 等)
// 是**提交进仓库的文件**，台账里会按名字指它们。只认 App/Widget/Tests 的话，
// 这些指针会被判成"无此文件"—— 一把在自己的说明书上开火的尺子。
const ROOTS = ['App', 'Widget', 'Tests', 'fixtures'];
const swiftFiles = [];
(function walkAll(dirs) {
  for (const r of dirs) {
    if (!fs.existsSync(r)) continue;
    (function walk(x) {
      for (const e of fs.readdirSync(x, { withFileTypes: true })) {
        const f = path.join(x, e.name);
        if (e.isDirectory()) walk(f);
        else if (f.endsWith('.swift')) swiftFiles.push(f);
      }
    })(r);
  }
})(ROOTS);

const baseNames = new Set(swiftFiles.map((f) => path.basename(f)));
// 每个文件里顶层声明的类型名 (enum/struct/class/actor/protocol/extension)
const declares = {};
const allTypes = new Set();
const reDecl = /^(?:final\s+|public\s+|internal\s+)?(?:enum|struct|class|actor|protocol|extension)\s+([A-Za-z_]\w*)/;
for (const f of swiftFiles) {
  const set = new Set();
  for (const line of fs.readFileSync(f, 'utf8').split(/\r?\n/)) {
    const m = line.match(reDecl);
    if (m) { set.add(m[1]); allTypes.add(m[1]); }
  }
  declares[baseName(f)] = set;
}
function baseName(f) { return path.basename(f); }
// 文件里有同名类型? 用 "标识符在任一源文件出现过" 作兜底 (引用也算活)
const joined = swiftFiles.map((f) => fs.readFileSync(f, 'utf8')).join('\n');
const alive = (nm) => allTypes.has(nm) || new RegExp('\\b' + nm + '\\b').test(joined);

// 系统类型前缀白名单 (粗粒度, 与 swiftlint 检查② 同一口径: 宁可放过不误报)
const SYS_PREFIX = ['UI', 'NS', 'CG', 'CA', 'AV', 'MK', 'SK', 'CN', 'SF', 'AX', 'WK', 'PH', 'CL', 'CV', 'SC', 'EK', 'HM', 'CK', 'PK', 'RC', 'VN', 'OS'];
const SYS_NAMES = new Set(['Apple', 'iOS', 'iPadOS', 'SwiftUI', 'WidgetKit', 'XCTest', 'JSON', 'PDF', 'URL', 'UUID', 'Demo', 'Kitty']);
const NON_MEMBER_EXT = /^(swift|md|json|js|yml|yaml|png|svg|xcassets|lock|txt|csv|pdf|ipa|mobileprovision|entitlements)$/;

const docs = fs.readdirSync('docs').filter((f) => f.endsWith('.md')).map((f) => path.join('docs', f));
if (fs.existsSync('README.md')) docs.unshift('README.md');
// 行内忽略标记: 台账里合法地需要**说出**那些死指针原文 (修指针的叙述本身就带着旧名字),
// 否则闸门会在自己的说明书上开火 —— 一把天天误响的尺子最后没人看。标记写法: 行尾 `指针检查:忽略`。
const IGNORE = /指针检查:忽略/;

const rows = [];
// 注入探针文件名自成一体：`Zprobe162.swift` / `_probe_tp.swift` 这种名字只为"当批证明判据会开火"而生，
// 用完即删 —— 文档里留的是**验证过程的历史**，不是一个还该存在于树上的文件。
// 不把它们单列一档，①就常驻十来条已知噪音；而天天误响的尺子最后没人看 (§ 顶部那条纪律)。
// 只认这个形状 (probe/probes/zzprobe + 可选数字后缀)，别的缺失文件照旧上报。
const PROBE_NAME = /^(?:z{0,2}_?probe|probe\d*)[\w]*\.swift$/i;
let cProbe = 0;
for (const d of docs) {
  const txt = fs.readFileSync(d, 'utf8');
  txt.split(/\r?\n/).forEach((line, i) => {
    if (IGNORE.test(line)) return;
    for (const m of line.matchAll(/([A-Za-z0-9_]+)\.swift/g)) {
      const nm = m[1] + '.swift';
      if (PROBE_NAME.test(nm)) { cProbe++; continue; }
      if (!baseNames.has(nm)) rows.push(`①无此文件  ${d}:${i + 1}  ${nm}  | ${line.trim().slice(0, 56)}`);
    }
    for (const m of line.matchAll(/`([A-Z][A-Za-z0-9]{2,})\.([a-zA-Z_]\w*)/g)) {
      const ident = m[1], member = m[2];
      if (NON_MEMBER_EXT.test(member)) continue;                     // X.json / X.swift 不是成员指针
      if (/^(?:Z?_?Probe|Probe)\w*$/.test(ident)) continue;           // 探针类型名 (Probe162 之类) 同上一条道理
      if (SYS_PREFIX.some((p) => ident.startsWith(p))) continue;
      if (SYS_NAMES.has(ident)) continue;
      if (alive(ident)) continue;
      const fileSet = declares[ident + '.swift'];
      if (fileSet && fileSet.size) rows.push(`②文件名当类型名用  ${d}:${i + 1}  ${ident}.${member}  ->  该文件里的类型是 ${[...fileSet].slice(0, 4).join('/')}`);
      else rows.push(`③死指针候选  ${d}:${i + 1}  ${ident}.${member}  | ${line.trim().slice(0, 56)}`);
    }
  });
}
const c1 = rows.filter((r) => r.startsWith('①')).length;
const c2 = rows.filter((r) => r.startsWith('②')).length;
const c3 = rows.filter((r) => r.startsWith('③')).length;
console.log(`台账指针存活检查 (顾问级): ①无此文件 ${c1} · ②文件名当类型名 ${c2} · ③死指针候选 ${c3}`
            + `  (另有 ${cProbe} 处引用的是用完即删的注入探针文件，按名字形状豁免，不算死指针)`);
for (const r of rows) console.log('  ' + r);
if (rows.length === 0) console.log('  ✓ 抽到的指针全部落在当前树上');
