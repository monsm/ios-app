'use strict';
// tools/swiftmember.js —— Swift 成员精确边界工具（第 48-50 轮三次 CI 失败的沉淀）
//
// 用法：node tools/swiftmember.js <file.swift> <memberName>
// 输出：该成员的 { start, end }（字符偏移，含闭合大括号），深度归 0 法，不依赖
//       "下一个 private var/func" 的脆弱假设（那个假设在 func 成员处会漏判，
//       直接造成两次 CI 失败：c6c802a / 6270b60）。
//
// 供脚本 include：require("./swiftmember.js").findMember(source, "memberName")
const fs = require('fs'), path = require('path');

function findMember(src, name) {
  // 成员声明行：func/var name
  const re = new RegExp('(?:private |public |fileprivate |internal |@ViewBuilder\\s+|@Composable\\s+)*(?:func|var|let)\\s+' + name + '\\b');
  const m = re.exec(src);
  if (!m) return null;
  const start = m.index;
  // 从声明后的第一个 { 开始计深
  let depth = 0, started = false, end = -1;
  for (let j = src.indexOf('{', start); j < src.length; j++) {
    const ch = src[j];
    if (ch === '{') { depth++; started = true; }
    else if (ch === '}') { depth--; if (started && depth === 0) { end = j; break; } }
  }
  if (end < 0) return null;
  return { start, end, text: src.slice(start, end + 1) };
}

if (require.main === module) {
  const [, , file, name] = process.argv;
  if (!file || !name) { console.error('用法: node tools/swiftmember.js <file> <memberName>'); process.exit(2); }
  const src = fs.readFileSync(path.resolve(file), 'utf8').replace(/\r\n/g, '\n');
  const r = findMember(src, name);
  if (!r) { console.error('未找到成员: ' + name); process.exit(1); }
  const line = src.slice(0, r.start).split('\n').length;
  console.log(JSON.stringify({ start: r.start, end: r.end, lines: r.text.split('\n').length, startLine: line, head: r.text.split('\n')[0].trim().slice(0, 80) }, null, 1));
}
module.exports = { findMember };
