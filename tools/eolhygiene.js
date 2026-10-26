#!/usr/bin/env node
/**
 * tools/eolhygiene.js — 行尾卫生闸门（判失败）
 *
 * 为什么要有这一道：
 *   本会话我多次用脚本改文件，写出过 **CRCRLF**（一个换行配两个 CR）。
 *   后果很隐蔽但很致命：
 *     · PowerShell 的 Select-String 把每个 CR 当行分隔符 ⇒ 行号翻倍、对不上；
 *     · bash 把 CR 当普通字符 ⇒ `\` 续行符失效 ⇒ CI 报 "syntax error near unexpected token"；
 *     · git diff 显示"整个文件都改了"，真实改动被淹没。
 *   2026-10-26 因此连红两次（SettingsView 一次、workflows/ios.yml 一次）。
 *
 * 判据：
 *   任何文本文件里出现**连续两个及以上 CR** ⇒ 红。
 *   孤立 CR（老 Mac 行尾）也红 —— 本仓统一 LF/CRLF，不存在那种文件。
 */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const TEXT_EXT = /\.(swift|js|mjs|cjs|ts|yml|yaml|json|md|csv|kt|kts|java|xml|sh|txt|pbxproj|plist)$/;
const SKIP_DIRS = new Set(['.git', 'node_modules', 'build', 'DerivedData']);

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (TEXT_EXT.test(e.name)) out.push(p);
  }
  return out;
}

const problems = [];

for (const file of walk(ROOT)) {
  let buf;
  try { buf = fs.readFileSync(file); } catch { continue; }
  const rel = path.relative(ROOT, file).replace(/\\/g, '/');

  let i = 0, multiCR = 0, loneCR = 0, firstAt = -1, line = 1;
  while (i < buf.length) {
    if (buf[i] === 0x0D) {
      let n = 0;
      const at = i;
      while (i < buf.length && buf[i] === 0x0D) { n++; i++; }
      if (i < buf.length && buf[i] === 0x0A) {
        i++;
        if (n > 1) { multiCR++; if (firstAt < 0) firstAt = line; }
      } else {
        loneCR++;
        if (firstAt < 0) firstAt = line;
      }
      line++;
    } else {
      if (buf[i] === 0x0A) line++;
      i++;
    }
  }

  if (multiCR || loneCR) {
    problems.push({ rel, multiCR, loneCR, firstAt });
  }
}

if (problems.length === 0) {
  console.log('行尾卫生闸门 (无 CRCRLF / 无孤立 CR) ✓ 零命中');
  process.exit(0);
}

console.error('✗ 行尾损坏 —— 连续多 CR 或孤立 CR 会让行号与 shell 续行全部错乱');
console.error('  修法：按字节把连续 CR 折叠成一个 CRLF（不要用字符串 split/join，那正是成因）\n');
for (const p of problems) {
  console.error(`  ${p.rel}  多CR=${p.multiCR} 孤立CR=${p.loneCR} 首个位置≈第${p.firstAt}行`);
}
console.error(`\n共 ${problems.length} 个文件。`);
process.exit(1);
