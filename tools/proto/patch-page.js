'use strict';
// tools/proto/patch-page.js —— 安全替换生成器里的一个页面段
// 用法：node patch-page.js <gen-file> <page-name> <body-file> [--dry]
// 原理：定位 fs.writeFileSync(D+'<page>.html', L.page(<title>, ` ... `, N, {opts}));
//       用括号/反引号平衡找到 body 边界，只替换 body，保留前后包装。
const fs = require('fs'), path = require('path');
const [genFile, pageName, bodyFile, flag] = process.argv.slice(2);
if (!genFile || !pageName || !bodyFile) { console.error('用法: node patch-page.js <gen> <page> <body>'); process.exit(1); }
const genPath = path.join(__dirname, genFile);
let src = fs.readFileSync(genPath, 'utf8').replace(/\r\n/g, '\n');
const body = fs.readFileSync(path.join(__dirname, bodyFile), 'utf8').replace(/\r\n/g, '\n');

// 找 writeFileSync(D+'<page>.html'
const marker = "writeFileSync(D+'" + pageName + ".html'";
const startIdx = src.indexOf(marker);
if (startIdx < 0) { console.error('✗ 找不到 ' + pageName + ' 的 writeFileSync'); process.exit(1); }

// 从 startIdx 找 L.page( ... , ` 的第一个反引号（body 开始）
const lpIdx = src.indexOf('L.page(', startIdx);
let bodyStart = -1;
for (let i = lpIdx; i < src.length; i++) {
  if (src[i] === '`' && src[i-1] !== '\\') { bodyStart = i + 1; break; }
}
if (bodyStart < 0) { console.error('✗ 找不到 body 起始反引号'); process.exit(1); }

// 找 body 结束：跟踪 \${ } 与嵌套反引号
let i = bodyStart, depth = 0, bodyEnd = -1;
while (i < src.length) {
  const c = src[i];
  if (c === '\\') { i += 2; continue; }
  if (c === '$' && src[i+1] === '{') { depth++; i += 2; continue; }
  if (c === '}' && depth > 0) { depth--; i++; continue; }
  if (c === '`' && depth === 0) { bodyEnd = i; break; }
  i++;
}
if (bodyEnd < 0) { console.error('✗ 找不到 body 结束反引号'); process.exit(1); }

const oldBody = src.slice(bodyStart, bodyEnd);
if (flag === '--dry') {
  console.log('段定位 OK');
  console.log('  gen:', genFile, 'page:', pageName);
  console.log('  body 区间:', bodyStart, '→', bodyEnd, '(' + oldBody.length + ' 字符)');
  console.log('  body 开头:', JSON.stringify(oldBody.slice(0, 60)));
  process.exit(0);
}
src = src.slice(0, bodyStart) + body + src.slice(bodyEnd);
fs.writeFileSync(genPath, src, 'utf8');
console.log('✓ ' + pageName + ' 已替换（' + oldBody.length + ' → ' + body.length + ' 字符）');
