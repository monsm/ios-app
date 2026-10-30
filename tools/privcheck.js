#!/usr/bin/env node
// privcheck —— 跨文件 `private` 可见性闸门（判失败）。
//
// 2026-10-30 新增（第 128 轮）：本仓大量使用「struct 在 A 文件，extension 在 B 文件」的拆分方式。
// 这种结构下，A 文件里的 `private` 成员在 B 文件里**不可见** —— 编译直接报
// `'xxx' is inaccessible due to 'private' protection level`。
//
// 本轮就是这么红的：把 `PwdStudio.editing` 从普通属性改成 `@State private var`，
// 而 `PwdStudioSteps.swift` 的 extension 里三处用到它（L354/368/431）⇒ **连续 11 次构建失败**。
// 本机没有 Swift 编译器，这类错误只能等 CI 报 —— 所以用静态检查兜住。
//
// 判据（不看类型作用域，只看文件，避免嵌套大括号解析出错）：
//   ① 文件 F 里声明了类型 T，且 F 里有一行 `[属性] private (var|let|func) NAME`
//   ② 另一个文件 G 里有 `extension T`
//   ③ G 的正文里出现了 NAME 这个标识符
//   ⇒ 判失败
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

const files = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    files.push({ rel: `${d}/${f}`, src: fs.readFileSync(path.join(dir, f), 'utf8') });
  }
}

// ① 每个文件声明的类型 + private 成员
const info = new Map();  // rel -> {types:Set, priv:Set}
for (const { rel, src } of files) {
  const types = new Set();
  const priv = new Set();
  for (const line of src.split(/\r?\n/)) {
    const code = line.replace(/\/\/.*$/, '');
    // 顶层类型：允许 public/internal/final/open 前缀，行首无缩进
    const t = /^(?:public |internal |fileprivate |final |open )*(?:struct|class|enum|actor)\s+(\w+)/.exec(code);
    if (t) types.add(t[1]);
    // private 成员：允许 @State / @Binding / @Environment 等属性前缀
    const p = /^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:private)\s+(?:static\s+)?(?:lazy\s+)?(?:var|let|func)\s+(\w+)/.exec(code);
    if (p) priv.add(p[1]);
  }
  info.set(rel, { types, priv });
}

// ② 每个文件里的 extension
const exts = new Map();  // rel -> Set(type)
for (const { rel, src } of files) {
  const s = new Set();
  for (const m of src.matchAll(/^\s*(?:private\s+)?extension\s+(\w+)/gm)) s.add(m[1]);
  exts.set(rel, s);
}

// ③ 检查
// 通用名黑名单：这些名字在别的文件里几乎必然以「不相干的局部变量/参数」出现，
// 直接按标识符匹配会大量误报（本轮实测：app/key/r/k 各被误报一次以上）。
// 取舍：宁可放过个别真问题，也不让闸门天天误报（误报会让人开始忽略闸门）。
const GENERIC = new Set([
  'app', 'key', 'r', 'k', 'x', 'y', 'id', 'name', 'value', 'text', 'data', 'index', 'count',
  'body', 'title', 'items', 'rows', 'list', 'tag', 'type', 'state', 'tick', 'busy', 'error',
]);

const bad = [];
for (const [relF, fi] of info) {
  if (fi.priv.size === 0) continue;
  for (const [relG, ge] of exts) {
    if (relG === relF) continue;
    for (const t of ge) {
      if (!fi.types.has(t)) continue;
      const gsrc = files.find(f => f.rel === relG).src;
      for (const mem of fi.priv) {
        if (GENERIC.has(mem)) continue;
        if (mem.length < 4) continue;
        if (new RegExp(`\\b${mem}\\b`).test(gsrc)) {
          bad.push(`${t}.${mem}  ← ${relG} 的 extension 引用了 ${relF} 里声明为 private 的成员`);
        }
      }
    }
  }
}

if (bad.length) {
  console.log(`✗ 跨文件引用 private 成员 ${bad.length} 处（编译必红：private 只在声明文件内可见）：`);
  [...new Set(bad)].forEach(x => console.log('  ' + x));
  console.log('\n修法：把声明处的 `private` 去掉（改 internal），或把该成员移到同文件的 extension 里。');
  process.exit(1);
}
console.log('✓ 无跨文件 private 引用（struct 与 extension 分文件的拆分方式安全）');
