#!/usr/bin/env node
// rescuescan.js — 定义集对比: 找出「已删除但仍有代码级引用」的符号
//
// 背景: 删除页面时最常犯的错不是漏删, 而是**把别人在用的符号一起删了**。
//   `grep -w 符号名` 抓不到 `Self.foo` / `app.foo` / 枚举内同名成员 这些形态,
//   于是"零调用"的结论是错的。本工具改用定义集对比:
//     1. 取 --base 提交的全部顶层/成员定义名 (定义集 A)
//     2. 取 HEAD 的全部定义名 (定义集 B)
//     3. A - B = 本轮删掉的名字
//     4. 逐个在当前代码里查**代码级**引用 (剥掉注释与字符串)
//     5. 仍有引用 ⇒ 悬空, 报告
//
// 这是编译期错误, 但本机无 Xcode 编译不了, 只能靠 CI 抓 —— 而 CI 一轮 5 分钟。
// 本工具把 CI 的活提前到本地。
//
// 用法: node tools/rescuescan.js --base <ref>          (默认: 上一个提交)
//       node tools/rescuescan.js --base b887723^
//
// 退出码: 0 = 无悬空; 1 = 有悬空 (CI 会红)

"use strict";
const cp = require("child_process");
const fs = require("fs");
const path = require("path");

const REPO = path.resolve(__dirname, "..");
function git(args) {
  try {
    return cp.execFileSync("git", ["-C", REPO].concat(args), { encoding: "utf8", maxBuffer: 1 << 28 });
  } catch (e) { return ""; }
}

// ---------- 参数 ----------
const argv = process.argv.slice(2);
let BASE = "HEAD^";
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === "--base" && argv[i + 1]) { BASE = argv[++i]; }
  if (argv[i] === "--help" || argv[i] === "-h") {
    console.log("用法: node tools/rescuescan.js [--base <ref>]");
    console.log("  找出已删除但仍有代码级引用的符号 (定义集对比)");
    process.exit(0);
  }
}

// ---------- 定义名收集 ----------
// 覆盖: func / var / let / struct / enum / class / protocol / actor / typealias / case
const DEF_RE = new RegExp([
  "^\\s*(?:@\\w+(?:\\([^)]*\\))?\\s+)*",
  "(?:public |private |internal |fileprivate |final |open |static |class |mutating |nonisolated(?:\\(unsafe\\))? |override |lazy |weak |indirect )*?",
  "(?:func|var|let|struct|enum|class|protocol|actor|typealias)\\s+(\\w+)",
].join(""));
const CASE_RE = /^\s*case\s+(\w+)/;

// 系统/框架 API 与常见参数名 —— 这些名字在基线里出现过, 但不是本项目定义的"功能"
const SYS_NAMES = new Set([
  "colors", "weekday", "container", "files", "direction", "complete", "compare", "local",
  "docs", "index", "count", "first", "last", "next", "prev", "name", "value", "key", "tag",
  "start", "end", "step", "rows", "items", "list", "data", "text", "note", "date", "time",
  "opacity", "offset", "scale", "rotation", "anchor", "width", "height", "size", "point",
  "increment", "decrement", "success", "failure", "none", "all", "some", "any", "empty",
  "source", "target", "result", "output", "input", "state", "mode", "type", "kind", "role",
  "short", "long", "full", "half", "top", "bottom", "left", "right", "middle", "center",
  "red", "green", "blue", "white", "black", "gray", "clear", "fill", "stroke", "border",
  "radius", "spacing", "padding", "margin", "frame", "bounds", "origin", "position",
]);

function stripCode(line) {
  // 剥注释与字符串内容 —— 引用判断只看代码
  return line.replace(/"(?:[^"\\]|\\.)*"/g, '""').replace(/'(?:[^'\\]|\\.)*'/g, "''").replace(/\/\/.*$/, "");
}

function collectDefs(text) {
  const set = new Set();
  for (const line of text.split(/\r?\n/)) {
    if (/^\s*(\/\/|\/\*|\*)/.test(line)) continue;
    const m = DEF_RE.exec(line);
    if (m) { set.add(m[1]); continue; }
    const c = CASE_RE.exec(line);
    if (c) set.add(c[1]);
  }
  return set;
}

// ---------- 文件清单 ----------
function listSwift(ref) {
  if (ref === null) {
    return git(["ls-files", "--", "App/**/*.swift", "App/*.swift"]).split(/\r?\n/).filter(Boolean);
  }
  return git(["ls-tree", "-r", "--name-only", ref, "--", "App"]).split(/\r?\n/).filter(f => f.endsWith(".swift"));
}

function readText(ref, file) {
  if (ref === null) return fs.readFileSync(path.join(REPO, file), "utf8");
  return git(["show", ref + ":" + file]);
}

// ---------- 基线 ----------
// 基线不可用 (浅克隆 / 指定 ref 不存在) ⇒ 跳过而不是判失败。
// CI 的 actions/checkout 默认 fetch-depth:1, HEAD~1 取不到 —— 那时本步无从比起。
// 真要有覆盖, workflow 里把 fetch-depth 设成 2 (ios.yml 已改)。
const baseType = BASE ? git(["cat-file", "-t", BASE]).trim() : "";
if (baseType !== "commit") {
  console.log("⚠ 基线 " + BASE + " 不可用 (浅克隆或 ref 不存在) —— 本次跳过定义集对比。");
  console.log("  要让它生效: actions/checkout 带 fetch-depth: 2, 或本地显式 --base <ref>。");
  process.exit(0);
}

const baseFiles = listSwift(BASE);
const headFiles = listSwift(null);
const headText = headFiles.map(f => readText(null, f)).join("\n");
const headDefs = collectDefs(headText);

const baseDefs = new Set();
for (const f of baseFiles) {
  const t = readText(BASE, f);
  if (!t) continue;
  for (const n of collectDefs(t)) baseDefs.add(n);
}

const deleted = [...baseDefs].filter(n => !headDefs.has(n));

// ---------- 逐个查引用 ----------
const findings = [];
for (const name of deleted) {
  if (name.length < 3) continue;               // 太短误报太多
  if (SYS_NAMES.has(name)) continue;         // 系统 API / 框架成员, 非本项目定义
  if (/^[a-z]/.test(name) && name.length < 5) continue;
  const re = new RegExp("\\b" + name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\b");
  const hits = [];
  for (const f of headFiles) {
    const L = readText(null, f).split(/\r?\n/);
    L.forEach((line, i) => {
      if (/^\s*(\/\/|\/\*|\*)/.test(line)) return;
      const code = stripCode(line);
      if (!code) return;
      if (re.test(code)) hits.push({ file: f.replace(/^App\//, ""), line: i + 1, txt: line.trim().slice(0, 88) });
    });
  }
  if (hits.length) findings.push({ name, hits });
}

// ---------- 报告 ----------
findings.sort((a, b) => b.hits.length - a.hits.length);
console.log("定义集对比: 基线 " + baseDefs.size + " 个定义名, 当前 " + headDefs.size + " 个");
console.log("本轮删除: " + deleted.length + " 个定义名");
if (!findings.length) {
  console.log("✓ 无悬空引用 (删掉的名字都没有代码级消费者)");
  process.exit(0);
}
console.log("✗ 悬空引用 " + findings.length + " 个 —— 这些符号被删了但还有代码在调用:");
for (const f of findings) {
  console.log("  " + f.name + "  (" + f.hits.length + " 处)");
  for (const h of f.hits.slice(0, 4)) console.log("      " + h.file + ":" + h.line + "  " + h.txt);
  if (f.hits.length > 4) console.log("      …另 " + (f.hits.length - 4) + " 处");
}
console.log("\n处理方式: ① 符号还有消费者就搬回存活文件 ② 连同调用点一起删。");
process.exit(1);
