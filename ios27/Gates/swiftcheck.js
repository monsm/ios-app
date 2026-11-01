#!/usr/bin/env node
// swiftcheck.js —— 无本地 Swift 编译器时的第一道闸：括号 / 字符串 / 花括号平衡。
//
// 判什么：① 括号配对 ② 字符串闭合（含 \\( 插值的嵌套括号）③ 每个 struct/class/func 有对应的收尾
// 为什么：本仓没有 Mac，CI 之外唯一能立刻发现"少一个右括号"的手段。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
// 2026-11-01：原来只扫 App/ —— `Tests/` 完全没被检查。
// 结果是我自己写的测试里少一个右括号，本地 17 道闸门全绿，CI 真编译器才报
// 「Expected ',' separator」。测试也是代码，必须过同一道闸。
const APP = path.join(ROOT, 'App');
const TESTS = path.join(ROOT, 'Tests');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

let bad = 0;
const files = walk(APP);
// 测试目录可能不存在（老分支），存在就一并检查。
try { if (fs.statSync(TESTS).isDirectory()) walk(TESTS, files); } catch { /* 没有 Tests/ */ }
for (const f of files) {
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  const src = fs.readFileSync(f, 'utf8');
  const lines = src.split(/\r?\n/);

  // ① 源码里的裸控制字符（CR / NUL / VT 等）—— Swift 会把它当语句分隔，报
  //    "Consecutive statements on a line must be separated by ';'" 这种看不懂的错。
  //    2026-10-31 真踩过：注释里混进一个裸 CR，本地三道闸全绿，CI 红 4 条。
  lines.forEach((line, i) => {
    if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(line)) {
      console.log(`  ${rel}:${i + 1}  源码含裸控制字符（CR/NUL/VT 等）—— Swift 会当语句分隔`);
      bad++;
    }
  });

  // 逐行扫描：剥掉行注释与字符串内容，再数括号
  let depth = 0;
  let inBlockComment = false;
  const stripped = [];      // 剥掉注释与字符串后的代码（供下面几条"看代码"的规则共用）
  const depthBefore = [];   // 每行**行首**的花括号深度
  lines.forEach((line, i) => {
    depthBefore[i] = depth;
    let out = '';
    let j = 0;
    let inStr = false;
    let interp = 0; // \\( … ) 的嵌套深度
    while (j < line.length) {
      const c = line[j];
      if (inBlockComment) {
        if (c === '*' && line[j + 1] === '/') { inBlockComment = false; j += 2; continue; }
        j++; continue;
      }
      if (inStr) {
        if (c === '\\') {
          if (line[j + 1] === '(') { interp++; }
          j += 2; continue;
        }
        if (interp > 0 && c === ')') { interp--; j++; continue; }
        if (interp > 0 && c === '(') { interp++; j++; continue; }
        if (interp === 0 && c === '"') { inStr = false; j++; continue; }
        j++; continue;
      }
      if (c === '/' && line[j + 1] === '/') break;
      if (c === '/' && line[j + 1] === '*') { inBlockComment = true; j += 2; continue; }
      if (c === '"') { inStr = true; j++; continue; }
      out += c;
      j++;
    }
    stripped[i] = out;
    for (const c of out) {
      if (c === '{' || c === '(' || c === '[') depth++;
      if (c === '}' || c === ')' || c === ']') depth--;
    }
    if (depth < 0) {
      console.log(`  ${rel}:${i + 1}  括号提前收尾（depth=${depth}）`);
      bad++;
      depth = 0;
    }
  });
  if (depth !== 0) {
    console.log(`  ${rel}  文件末尾括号不平衡（depth=${depth}）`);
    bad++;
  }
  if (inBlockComment) {
    console.log(`  ${rel}  块注释未闭合`);
    bad++;
  }
  // 2026-11-01：空 / 近空 Swift 文件。
  // `App/Engine/HintOnce.swift` 曾是一个 **0 字节**文件，从首次提交起就如此，零引用，
  // 却因为 `project.yml` 用 `sources: - path: App` 目录通配而被编进工程 ——
  // 它什么都编译不出来，也没人会发现。
  const body = src.replace(/\/\/.*$/gm, "").replace(/\s+/g, "");
  if (body.length < 20) {
    console.log(`  ${rel}  空或近空的 Swift 文件（去掉注释与空白后仅 ${body.length} 字符）—— 删掉它，或补上内容`);
    bad++;
  }
  // 2026-11-01：`DateFormatter()` 必须显式钉公历。
  // 不设 `calendar` 时它跟随 `Calendar.current` —— 用户把系统历法切成佛历/民国历/农历，
  // 输出年份就变成 2569 之类，而 `TimeFormat` 一直输出公历 ⇒ 同一时刻两处显示不同年份。
  // 这个缺陷从 ROUND-1 起就在（`DF.cached` / `localTime` / `localCached` / 备份文件名共 4 处），
  // 而"两个工厂比对"型测试**结构上发现不了**（两边都错得一样时永远相等）。
  // 只看代码行（去掉 `//` 注释），且接受任何形式的 `calendar = ...` 赋值
  // （`TimeFormat` 写的是 `f.calendar = calendar`，变量名不同但同样正确）。
  const codeLines = src.split(/\r?\n/).filter((l) => {
    const t = l.trim();
    return !t.startsWith("//") && !t.startsWith("///");
  });
  const code = codeLines.join("\n");
  // 只数 `DateFormatter()`，不数 `ISO8601DateFormatter()`（后者是固定格式，不受历法影响）。
  const dfCount = (code.match(/\bDateFormatter\(\)/g) || []).length;
  const calCount = (code.match(/\.calendar = /g) || []).length;
  if (dfCount > 0 && calCount < dfCount) {
    console.log(`  ${rel}  有 ${dfCount} 处 DateFormatter() 但只有 ${calCount} 处设置 calendar —— 未设的会跟随系统历法`);
    bad++;
  }
  // 2026-11-01：本仓**不用断言**（`assert` / `assertionFailure` / `precondition`）。
  // 依据是两处既有处置：`ZKProtocol:60`（超长时显式截断 + 遥测，不用 assertionFailure）、
  // `ZOTP:23`（原 `assert(periodMin <= 120)` 已移除）。
  // 理由：Release 版断言被编译掉 ⇒ 静默继续；Debug 版崩 ⇒ 用户看到闪退。两种都不可取，
  // 本仓一律用防御式 `guard ... else { return }`。
  // 我自己在 ROUND-140 一度写了 `assertionFailure`，被这条自查纠正。
  if (/\bassertionFailure\(|\bassert\(|\bprecondition\(/.test(code)) {
    console.log(`  ${rel}  用了断言（assert / assertionFailure / precondition）—— 本仓一律用防御式 guard`);
    bad++;
  }
  // 2026-11-01：`app.lastStatus?.status.X` 引用的 X 必须真的在 `StatusSnapshotData` 里。
  //
  // 我第二次因为"引用了模型上不存在的字段"把 CI 弄红（第一次是扩展里的存储属性）。
  // 这类错误本地闸门本该能看见 —— `StatusSnapshotData` 的字段表就在源码里，对一下即可。
  // 同一个坑踩两次，就说明它不是"不小心"，而是缺一道检查。
  try {
    const modelPath = path.join(ROOT, "App", "Engine", "StoreModels.swift");
    const sm = fs.existsSync(modelPath) ? fs.readFileSync(modelPath, "utf8") : "";
    const start = sm.indexOf("struct StatusSnapshotData");
    if (start >= 0) {
      let depth = 0, end = start;
      for (let i = start; i < sm.length; i++) {
        if (sm[i] === "{") depth++;
        else if (sm[i] === "}") { depth--; if (depth === 0) { end = i; break; } }
      }
      const body = sm.slice(start, end);
      const fields = new Set(Array.from(body.matchAll(/var\s+(\w+)\s*:/g)).map(m => m[1]));
      const re = /lastStatus\?\.status\.(\w+)/g;
      for (const m of src.matchAll(re)) {
        const name = m[1];
        if (!fields.has(name)) {
          console.log(`  ${rel}  引用了 app.lastStatus?.status.${name}，但 StatusSnapshotData 没有这个字段`);
          bad++;
        }
      }
    }
  } catch (e) {
    // 闸门自身出错不该让整条 CI 挂掉 —— 报出来但不计入 findings。
    console.log("  swiftcheck: 快照字段对账跳过（" + (e && e.message ? e.message : e) + "）");
  }
  // 2026-11-01：**不许用文案内容决定状态色**（`tone:` / `tint:` 实参里出现 `.contains(`）。
  // 本仓已三次踩坑：CredentialStudio 的「已」前缀（把"已…失败 N 条"涂绿）、
  // KeyCreate 的前缀猜测、LockStatus 的 `outcome.contains("失败")`（"锁忙，请稍后再试"一个
  // 关键字都没有 ⇒ 绿点）。规则：颜色必须来自**显式的成败标志**，不来自消息文本。
  // 注释里提到没关系 —— 只查代码行（`code` 已剥注释）。
  if (/\b(tone|tint)\s*:[^,)]*\.contains\(/.test(code)) {
    console.log(`  ${rel}  tone/tint 实参里用了 .contains(...) —— 文案猜颜色（失败文案不一定含关键字）`);
    bad++;
  }
  // 2026-11-01：不许用"固定 365 天"近似年。
  // 100 年里有 24–25 个闰日 ⇒ `N * 365 * 86400` 会差近一个月。
  // `WeekCal.shifted` 的注释已经写过这条纪律（"别用 `addingTimeInterval` 数日历日"），
  // 而 `AppModel` 里给指纹写 100 年有效期时又犯了一次。正确写法是 `calendar.date(byAdding: .year, ...)`。
  if (/\b365\s*\*\s*86400|86400\s*\*\s*365/.test(code)) {
    console.log(`  ${rel}  用 365*86400 近似年 —— 闰年会差近一个月，请用 calendar.date(byAdding: .year, ...)`);
    bad++;
  }
  // 2026-11-01：**`extension` 里不许有存储属性**（Swift 硬约束）。
  // 我自己刚踩过：把 `var connecting: (mac:task:)` 写进了 `extension LockService { … }`，
  // 本地 22 道闸门全绿，CI 真编译器报 `extensions must not contain stored properties`，
  // 整条流水线红了一轮。本仓没有 Mac，这条检查就是那个错误的本地等价物。
  {
    // 只判**实例**存储属性：`static let/var` 在扩展里是合法的（它是全局存储，不是实例布局）。
    const PROP = /^\s*(?:private|fileprivate|internal|public|private\(set\))?\s*(?:var|let)\s+\w+\s*(?::\s*[^={]+(?:=\s*[^{]+)?|=\s*[^{]+)$/;
    // 用**行首深度**判"是否在 extension 体内"：`extension X {` 那一行记下它的父深度，
    // 之后所有行首深度 > 该值的行都在体内；出现行首深度 <= 该值的行即已离开。
    // （用花括号计数会被字符串/注释里的括号带偏 —— 我第一版就是这样误报 256 处。）
    const extAt = [];
    for (let i = 0; i < lines.length; i++) {
      const s = stripped[i] || "";
      while (extAt.length && depthBefore[i] <= extAt[extAt.length - 1]) extAt.pop();
      if (/^\s*extension\s+[A-Za-z_][\w.]*\s*\{/.test(s)) extAt.push(depthBefore[i]);
      // 只判**直接体内**（父深度 + 1）：函数体里的 `let x = …` 是局部变量，不是存储属性。
      const atBodyLevel = extAt.length > 0 && depthBefore[i] === extAt[extAt.length - 1] + 1;
      if (atBodyLevel && PROP.test(s)) {
        console.log(`  ${rel}:${i + 1}  extension 里声明了存储属性 —— Swift 不允许（extensions must not contain stored properties）`);
        bad++;
      }
    }
  }
}

if (bad === 0) {
  console.log(`swiftcheck: OK — ${files.length} 个文件括号/字符串/注释全部平衡，无裸控制字符`);
  process.exit(0);
}
console.log(`swiftcheck: FAIL — ${bad} 处不平衡`);
process.exit(1);
