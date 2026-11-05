#!/usr/bin/env node
// secretext.js - gate 29: plaintext secret accessors must not be rendered
//
// 2026-11-03 incident: DiagSnapshot.build opens by stating it contains no key
// material - skey, ekey and PIN appear only as fingerprints - because the whole
// point is that a user pastes it into a chat to ask for help. Two lines
// interpolated ekeyPin() and chosenPin(), both of which return the raw value;
// and GodModeScreen rendered ekeyPin() on screen with no capture shield.
//
// Scope is deliberately narrow. I first tried a general 'is this call inside a
// string interpolation' detector and it flagged three legitimate uses
// (comparing PINs during pool repair, passing a PIN to unlock), because counting
// quotes is not parsing Swift. So the rule covers only the shapes that can
// actually leak: an out.append(...) in the diagnostics builder, and any Text(...)
// or VFieldRow(...) in the feature layer.
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..', 'App');
function walk(d, out) {
  out = out || [];
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const q = path.join(d, e.name);
    if (e.isDirectory()) walk(q, out);
    else if (e.name.endsWith('.swift')) out.push(q);
  }
  return out;
}
const PLAIN = ['ekeyPin', 'chosenPin', 'rawEmbeddedPin'];
const RENDERERS = ['out.append(', 'Text(', 'VFieldRow('];
let bad = 0;
const report = [];
for (const f of walk(ROOT)) {
  const lines = fs.readFileSync(f, 'utf8').split('\n');
  lines.forEach(function (line, i) {
    const t = line.trim();
    if (t.startsWith('//')) return;
    const renders = RENDERERS.some(function (r) { return t.indexOf(r) >= 0; });
    if (!renders) return;
    for (const name of PLAIN) {
      // 必须紧跟 '(' —— 这样 ekeyPinMasked 不会被误命中
      const needle = name + '(';
      let from = 0;
      while (true) {
        const at = t.indexOf(needle, from);
        if (at < 0) break;
        // 前一个字符若是字母/数字/下划线，说明是更长的名字（如 xxxekeyPin）
        const prev = at > 0 ? t[at - 1] : ' ';
        if (!/[A-Za-z0-9_]/.test(prev)) {
          bad++;
          report.push(path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) + '  ' + name + '(...) 出现在渲染行');
          break;
        }
        from = at + needle.length;
      }
    }
  });
}
// 2026-11-05（对抗审查 · 安全）：第二条判据 —— 明文输入一个「要写进锁的密码」的页面
// 必须挂截图遮挡。事故原型：KeyCreateHomeScreen 用 TextField(text: $code) 明文输入
// 6~8 位开锁密码，且没有 captureShield —— 而同一串值在凭证详情页是打码 + 遮挡的。
// 用户在新建流程里截图就会把一把能开门的密码拍进相册。
// 判据刻意窄：只认「TextField 且绑定变量名就是 code/pwd/password/pin」这一种形状。
const SECRET_FIELDS = ['$code', '$pwd', '$password', '$pin'];
for (const f of walk(ROOT)) {
  const src = fs.readFileSync(f, 'utf8');
  if (src.indexOf('captureShield') >= 0) continue;
  const lines = src.split('\n');
  lines.forEach(function (line, i) {
    const t = line.trim();
    if (t.startsWith('//')) return;
    // 注意：SecureField( 里含 TextField( 子串 —— 必须先排除 SecureField，否则三个
    // 已经打码的输入框会被误报（第一版就是这么错的）。
    const plainField = t.indexOf('TextField(') >= 0 && t.indexOf('SecureField(') < 0;
    if (!plainField) return;
    for (const field of SECRET_FIELDS) {
      if (t.indexOf('text: ' + field) >= 0) {
        bad++;
        report.push(path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) + '  明文输入 ' + field + ' 且本文件无 captureShield');
      }
    }
  });
}

if (bad === 0) {
  console.log('secretext: OK - no plaintext secret accessor is rendered');
  process.exit(0);
}
console.log('secretext: FAIL - ' + bad + ' plaintext leak(s):');
report.slice(0, 20).forEach(function (r) { console.log('  ' + r); });
process.exit(1);