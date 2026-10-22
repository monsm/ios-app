#!/usr/bin/env node
// tools/swiftsyn.js — Swift 语法形状机检 (第一百八十二批新增, **判失败**)
//
// 为什么这道闸门存在：第一百八十二批拿 tree-sitter 对全仓 79 个 Swift 文件做了一次**语法级**扫描
// (扫描器在仓外, 方法见 docs/AUDIT-CODE.md §10.52), 报出 46 ERROR + 3 MISSING —— 逐条分类后
// **9 处是真语法错误 (编译阻断)**, 而其时本仓 25 道闸门全绿。为什么全绿：`swiftcheck` 只数括号、
// `swiftshape` 比的是调用点标签与个数, 对这四类**无解析器就看不见**的写法都没有判据。
// 这一道把其中**纯文本就能定死**的四类做成常驻机检 (S1–S4), 残余类 (插值里大括号不配对等) 留给
// 语法扫描本身, 边界写在下面, 不假装覆盖。
//
// S1  for-in 头部的逗号。Swift 编译器源码 ParseStmt.cpp: parseStmtForEach 里
//     `Where = parseExprBasic(...)` —— parseExprBasic 明确排除顶层逗号 (序列表达式),
//     于是 `for p in xs where a, b {` 在 where 之后遇到 `,` 直接报错, 无恢复。
//     本仓实修 3 处: AuditChain:448 (`where p.alias != ignoreAlias, p.pwd == newPwd`)、
//     CredentialOrg:806 (`where ..., let o = p.owner, !o.isEmpty` —— 两份语义合并进 where)、
//     DiagKit:238。注意只有 for-in 头部这样 (if-let / guard 的逗号合法), 所以只锚 `for`。
//
// S2  带标签的尾随闭包**后面又跟了一个非闭包的标签表达式**。Swift 编译器源码 ParseExpr.cpp:
//     parseTrailingClosures 用 isStartOfLabelledTrailingClosure 判 `label:` 之后是不是 `{` ——
//     `} items: [...]` 里 `items:` 后面是 `[`, 不是 `{`, 报 "expected '{'" 之类。
//     本仓实修 3 处: RecordsView:841/845/849 (chipRowSection 的 items 应当进括号参数表)。
//     合法近亲 `} label: {` (Button 标准写法) 必须放过, 见 ok 反控。
//
// S3  裸 `$`。`$` 只允许跟标识符 (`$name` property wrapper) 或数字 (`$0` 闭包简写);
//     `text.contains($)` 里 `$` 后面是 `)`, 直接报 "expected expression"。
//     本仓实修 1 处: AuditChain:377。
//
// S4  参数名后直接跟属性、缺冒号。`completionHandler @escaping () -> Void` 少了 `name:` 的冒号,
//     解析器在参数表里看到裸标识符后期待 `:` 或 `,`, 撞上 `@` 报错。
//     本仓实修 1 处: BackupStudioKit:1462 (UNDelegate.userNotificationCenter)。
//
// 掩码这笔账要单独说：本工具**不**沿用 swiftcheck"整段剥字符串"的做法 —— 那会把
// `\( ... )` 插值里的代码一并剥掉 (AlarmCenterView:211 那处错误正藏在插值里, 全体闸门看不见它)。
// 这里逐字符走一遍: 普通字符串/多行字符串的内容掩成空格 **但保留插值 \( ) 内的代码**,
// 行注释截断、块注释 (可嵌套) 掩掉 —— 位置对齐, 所以报出的行列号就是源文件里的行列号。
//
// 判不了就不报的边界 (如实写, 不假装)：
//  · 这是**逐行文本判据**, 不是解析器。大括号/字符串跨行不配对这种 (tree-sitter 抓到的另一类)
//    它看不见, 也不该假装能看见。
//  · S1 只看 for 行起 6 行窗口内、首个 `\bin\b` 之后的**深度 0** 逗号; 头部跨 6 行以上不覆盖。
//  · S2 只认"行首 `}` + 标签 + 冒号"的**同行**形态, 外加"冒号在行尾、下一非空行以 `{` 开头则合法"
//    这一条豁免 (法律上的跨行合法写法); 跨行的 `}\nitems:` 故意不判 —— switch 里 `}` 单独一行
//    后跟 `default:` 完全合法, 追下去就把闸门变成噪音机。
//  · S3/S4 在插值内也生效 (掩码保留了插值代码), 但字符串字面量内容里的 `$` 与 `@` 不算。
//  · `#"raw"` 原始字符串语法、Swift 裸正则字面量 (/.../) 未处理 —— 本仓现在没有 (grep 过)。
//
// 判据自己先过正控: `--selftest` 拿 fixtures/swiftsyn/ 下"该响的"与"不该响的"两组各跑一遍,
// S1/S2 各 3+2 条、S3/S4 各 2 条必须全响, ok/ 一条不许响; 打不响或误响退出 2。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'Widget', 'Tests'];

function swiftFiles(root) {
  const out = [];
  if (!fs.existsSync(root)) return out;
  (function w(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const f = path.join(d, e.name);
      if (e.isDirectory()) w(f);
      else if (e.name.endsWith('.swift')) out.push(f);
    }
  })(root);
  return out;
}

// ---------- 掩码: 内容掩空格、插值留代码、注释掩掉、位置对齐 ----------
function maskFile(lines) {
  const st = { mode: 'code', stack: [], depth: 0, blockDepth: 0 };
  return lines.map((raw) => {
    let out = '';
    const n = raw.length;
    let i = 0;
    const spaces = (k) => { out += ' '.repeat(Math.max(0, k)); };
    while (i < n) {
      const ch = raw[i];
      if (st.mode === 'code') {
        if (st.blockDepth > 0) {
          if (ch === '/' && raw[i + 1] === '*') { st.blockDepth++; spaces(2); i += 2; continue; }
          if (ch === '*' && raw[i + 1] === '/') { st.blockDepth--; spaces(2); i += 2; continue; }
          spaces(1); i++; continue;
        }
        if (ch === '/' && raw[i + 1] === '/') break;                              // 行注释截断
        if (ch === '/' && raw[i + 1] === '*') { st.blockDepth = 1; spaces(2); i += 2; continue; }
        if (ch === '"' && raw[i + 1] === '"' && raw[i + 2] === '"') { spaces(3); i += 3; st.mode = 'ml'; continue; }
        if (ch === '"') { out += '"'; i++; st.mode = 'str'; continue; }
        out += ch; i++; continue;
      }
      if (st.mode === 'str' || st.mode === 'ml') {
        if (st.mode === 'ml' && ch === '"' && raw[i + 1] === '"' && raw[i + 2] === '"') { spaces(3); i += 3; st.mode = 'code'; continue; }
        if (ch === '\\') {
          if (raw[i + 1] === '(') { out += '\\('; i += 2; st.stack.push(st.mode); st.mode = 'interp'; st.depth = 1; continue; }
          spaces(2); i += 2; continue;
        }
        if (st.mode === 'str' && ch === '"') { out += '"'; i++; st.mode = 'code'; continue; }
        spaces(1); i++; continue;                                                // 串内容
      }
      // interp: \( ... ) 内的代码原样保留 (这就是 swiftcheck 看不见的那块)
      if (ch === '"') {                                                          // 插值里的嵌套字符串
        let j = i + 1;
        while (j < n) { if (raw[j] === '\\') { j += 2; continue; } if (raw[j] === '"') break; j++; }
        spaces(Math.min(j + 1, n) - i);
        i = Math.min(j + 1, n);
        continue;
      }
      if (ch === '(') { st.depth++; out += ch; i++; continue; }
      if (ch === ')') {
        st.depth--; out += ch; i++;
        if (st.depth === 0) st.mode = st.stack.pop() || 'code';
        continue;
      }
      out += ch; i++;
    }
    return out;
  });
}

// ---------- S1: for-in 头部的深度 0 逗号 ----------
function s1(mask, raw) {
  const hits = [];
  for (let i = 0; i < mask.length; i++) {
    const fm = /(^|[^\w$])for\b(?!\s*:)/.exec(mask[i]);
    if (!fm) continue;
    const rest = mask[i].slice(fm.index + fm[0].length);
    const im = /\bin\b/.exec(rest);
    if (!im) continue;
    let depth = 0, enteredBrace = false, hit = false;
    let li = i, used = 0;
    for (; li < mask.length && used < 6 && !hit; li++, used++) {
      const l = mask[li];
      const from = (li === i) ? (fm.index + fm[0].length + im.index + im[0].length) : 0;
      for (let c = from; c < l.length; c++) {
        const ch = l[c];
        if (ch === '(' || ch === '[') depth++;
        else if (ch === ')' || ch === ']') depth--;
        else if (ch === '{') { depth++; if (depth === 1) enteredBrace = true; }
        else if (ch === '}') { depth--; if (enteredBrace && depth <= 0) break; }
        else if (ch === ',' && depth === 0) { hit = true; break; }
      }
      if (enteredBrace && depth <= 0) break;                                     // 首个配平块结束 = 头部到头
    }
    if (hit) hits.push(`${i + 1}  S1 for-in 头部有顶层逗号 —— ` + raw[i].trim().slice(0, 70));
  }
  return hits;
}

// ---------- S2: 行首 `}` + 标签 + 冒号, 冒号后不是 `{` ----------
function s2(mask, raw) {
  const hits = [];
  for (let i = 0; i < mask.length; i++) {
    const m = /^\s*\}\s*([A-Za-z_]\w*)\s*:\s*(.*)$/.exec(mask[i]);
    if (!m) continue;
    const tail = m[2];
    if (tail.startsWith('{')) continue;                                          // 合法: `} label: {`
    if (tail === '') {                                                           // 冒号在行尾: 看下一非空行
      let nx = '';
      for (let j = i + 1; j < mask.length; j++) {
        if (mask[j].trim() !== '') { nx = mask[j]; break; }
      }
      if (/^\s*\{/.test(nx)) continue;                                           // 跨行的 `label:` + `{` 合法
    }
    hits.push(`${i + 1}  S2 \`} 标签:\` 后不是闭包大括号 —— ` + raw[i].trim().slice(0, 70));
  }
  return hits;
}

// ---------- S3: 裸 `$` ----------
function s3(mask, raw) {
  const hits = [];
  for (let i = 0; i < mask.length; i++) {
    if (/\$(?![A-Za-z0-9_])/.test(mask[i])) {
      hits.push(`${i + 1}  S3 裸美元符 (\`$\` 后须跟标识符或数字) —— ` + raw[i].trim().slice(0, 70));
    }
  }
  return hits;
}

// ---------- S4: 参数名后直接跟属性、缺冒号 ----------
function s4(mask, raw) {
  const hits = [];
  for (let i = 0; i < mask.length; i++) {
    if (/(?<![\w@:.$])[A-Za-z_]\w*\s+@[A-Za-z_]\w*/.test(mask[i])) {
      hits.push(`${i + 1}  S4 标识符后直接跟 @属性、缺冒号 —— ` + raw[i].trim().slice(0, 70));
    }
  }
  return hits;
}

// S5 语句结束后跟了中文。
// 起因：第一百零一轮我改一行 subtitle 时，replace 只换了前半段，
// 旧行的尾巴 "长与最后操作存在诊" 被拼到了新行 "))" 后面。
// 那一行**括号仍然平衡** —— swiftcheck/swiftshape/swiftsyn 全绿，CI 才会红。
// 判据：行尾是中文 + 引号数为偶（不在字符串里）+ 中文前面紧邻 ) ] } 之一。
function s5(mask, lines) {
  const out = [];
  lines.forEach((raw, i) => {
    if (mask[i]) return;
    const t = raw.replace(/\s+$/, '');
    if (!t) return;
    // ⚠ maskFile 只掩多行字符串，**不掩 // 注释** —— 第一版因此把
    // TimeFormat.swift:5 的一句注释里「…，同一条记录会在」判成事故，直接把 CI 弄红了。
    // 注释天然以中文收尾，本检查对它毫无意义。
    if (/^\s*\/\//.test(t)) return;
    if (!/[\u4e00-\u9fa5]$/.test(t)) return;
    const q = (t.replace(/\\"/g, '').match(/"/g) || []).length;
    if (q % 2 !== 0) return;
    if (!/[\)\]\}][\u4e00-\u9fa5]/.test(t)) return;
    out.push((i + 1) + ' S5 语句结束后跟了中文 (丢字/拼接事故): ' + t.trim().slice(0, 80));
  });
  return out;
}

function run(root) {
  const out = [];
  for (const f of swiftFiles(root)) {
    const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    const mask = maskFile(lines);
    for (const h of s1(mask, lines)) out.push(f + ':' + h);
    for (const h of s2(mask, lines)) out.push(f + ':' + h);
    for (const h of s3(mask, lines)) out.push(f + ':' + h);
    for (const h of s4(mask, lines)) out.push(f + ':' + h);
    for (const h of s5(mask, lines)) out.push(f + ':' + h);
  }
  return out;
}

function count(out, tag) { return out.filter((h) => h.includes(' ' + tag + ' ')).length; }

function selftest() {
  const dir = path.join(ROOT, 'fixtures', 'swiftsyn');
  const shouldFire = run(path.join(dir, 'fire'));
  const shouldNot = run(path.join(dir, 'ok'));
  const n1 = count(shouldFire, 'S1'), n2 = count(shouldFire, 'S2');
  const n3 = count(shouldFire, 'S3'), n4 = count(shouldFire, 'S4');
  const n5 = count(shouldFire, 'S5');
  // fire/: S1 三条 (where 后逗号两种形态 + 序列里的逗号), S2 两条 (`} items: [` 与 `} b: 2)`),
  // S3 两条 (括号里与行尾), S4 两条 (@escaping 与 @Sendable)
  if (n1 !== 3 || n2 !== 2 || n3 !== 2 || n4 !== 2) {
    console.log(`✗ 正控失败: fire/ 里 S1/S2/S3/S4 应各 3/2/2/2 条, 实得 ${n1}/${n2}/${n3}/${n4}`);
    console.log(shouldFire.join('\n'));
    return 2;
  }
  if (shouldNot.length !== 0) {
    console.log('✗ 反控失败: ok/ 里应 0 条, 实得 ' + shouldNot.length);
    console.log(shouldNot.join('\n'));
    return 2;
  }
  console.log('正控 ✓ (S1 for 头逗号 3 条开火; S2 `} items: [` 与 `} b: 2)` 开火; S3 裸 $ 两处开火; '
    + 'S4 缺冒号两处开火; ok/ 里 `} label: {` / 序列尾随闭包 / 括号内逗号 / 插值里的 $0 / '
    + '多行字符串 / `} default:` 跨行这些合法近亲一条不响)');
  return 0;
}

if (process.argv.includes('--selftest')) process.exit(selftest());
else {
  const st = selftest();
  if (st !== 0) process.exit(st);
  const bad = [];
  for (const d of DIRS) bad.push(...run(path.join(ROOT, d)));
  if (bad.length) {
    console.log('Swift 语法形状机检判失败 (' + bad.length + ' 条):');
    console.log(bad.join('\n'));
    process.exit(1);
  }
  console.log('Swift 语法形状机检 ✓ (S1 for-in 头逗号 / S2 带标签尾随闭包后接非花括号 / '
    + 'S3 裸美元符 / S4 参数名后属性缺冒号 / S5 语句后跟中文 — 零命中)');
}
