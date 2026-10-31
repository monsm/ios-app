#!/usr/bin/env node
// crosprivate.js —— 跨文件 private 访问闸门。
//
// 为什么需要：Swift 的 private 只在**同一文件**内可见。一个 struct 的成员若在另一个文件的
// extension 里被访问（本仓有 6 组 *Screen + *Parts 的拆分布局），编译器报
// "inaccessible due to 'private' protection level" —— 而且只在那个分支被实例化时才暴露，
// 本地静态检查看不出来，常常一路绿到 CI 才红。
//
// 判什么：对每一组 <Base>.swift + <Base>Parts.swift，Base 里声明为 private 的成员，
// 若在 Parts 文件里出现，即判失败。
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

const files = walk(APP);
const findings = [];
let pairs = 0;

for (const f of files) {
  const base = path.basename(f, '.swift');
  if (!base.endsWith('Parts')) continue;
  const ownerName = base.slice(0, -'Parts'.length);   // 例：MemberCreateParts → MemberCreate
  // 主文件可能是 <Owner>.swift 或 <Owner>Screen.swift（本仓两种命名都有）
  const ownerFile =
    files.find((x) => path.basename(x, '.swift') === ownerName) ||
    files.find((x) => path.basename(x, '.swift') === ownerName + 'Screen');
  if (!ownerFile) continue;
  pairs++;

  const ownerSrc = fs.readFileSync(ownerFile, 'utf8');
  const partsSrc = fs.readFileSync(f, 'utf8');

  // owner 里声明为 private 的成员名
  const privates = new Set();
  for (const m of ownerSrc.matchAll(/(?:private|fileprivate)\s+(?:@\w+\s+)?(?:var|let|func)\s+(\w+)/g)) {
    privates.add(m[1]);
  }
  for (const m of ownerSrc.matchAll(/(?:private|fileprivate)\s+(?:@\w+\s+)?(?:static\s+)?(?:var|let|func)\s+(\w+)/g)) {
    privates.add(m[1]);
  }

  for (const name of privates) {
    // 在 Parts 里以成员访问形式出现（名字前后是词边界）
    const re = new RegExp('\\b' + name + '\\b');
    if (re.test(partsSrc)) {
      findings.push(path.relative(APP, f).split(path.sep).join('/') + ' 访问了 ' +
        path.relative(APP, ownerFile).split(path.sep).join('/') + ' 里 private 的 ' + name);
    }
  }
}

console.log('crosprivate: 检查 ' + pairs + ' 组 Screen+Parts 拆分');
if (findings.length === 0) {
  console.log('crosprivate: OK — 没有跨文件访问 private 成员');
  process.exit(0);
}
console.log('crosprivate: FAIL — ' + findings.length + ' 处\n');
for (const x of findings) console.log('  ' + x);
process.exit(1);