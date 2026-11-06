#!/usr/bin/env node
// tokensync.js —— 生成的 Tokens.swift / tokens.css 必须与 tokens.json 完全一致。
// 不同步就判红：令牌只有一个来源，改颜色只能改 JSON 再重新生成。
'use strict';
const { execFileSync } = require('child_process');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
try {
  execFileSync(process.execPath, [path.join(ROOT, 'Tools', 'gen_tokens.js'), '--check'], { stdio: 'inherit' });
  console.log('tokensync: OK — 令牌与 JSON 一致');
} catch (e) {
  console.error('tokensync: FAIL — 请运行 node Tools/gen_tokens.js');
  process.exit(1);
}
