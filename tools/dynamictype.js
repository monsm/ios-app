#!/usr/bin/env node
// Dynamic Type / 触达尺寸静态闸门。
//
// 为什么需要: 本项目跑不了模拟器截图校验 (runner 镜像无 iOS 模拟器设备),
// 但"最大动态字体下会不会破版""可点区域是否 ≥44pt"这类问题里有相当一部分
// 可以从源码静态判定 —— 写死高度、给 Text 用 .system(size:)、
// 给行设固定 frame 而不给 fixedSize, 都是 AX 字号下必破版的写法。
//
// 用法: node tools/dynamictype.js  (不达标 exit 1)

const fs = require('fs');
const path = require('path');

const APP = path.join(__dirname, '..', 'App');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const findings = [];

// ---- 规则 1: Text 不得使用 .system(size:) — 它不参与 Dynamic Type 缩放 ----
// 例外: Image(systemName:) 上的 .system(size:) 是图标尺寸, 合规。
const TEXT_SIZE_RE = /Text\([^)]*\)(?:[^;]{0,400}?)\.font\(\s*\.system\(size:/g;
const ICON_SIZE_RE = /Image\(systemName:[^)]*\)(?:[^;]{0,200}?)\.font\(\s*\.system\(size:/g;

for (const file of walk(APP)) {
  const src = fs.readFileSync(file, 'utf8');
  const lines = src.split('\n');

  lines.forEach((line, i) => {
    const text = line.trim();
    if (text.startsWith('//')) return;
    // 修饰符常写在下一行, 因此向上回看 3 行判断这个 .system(size:) 挂在谁身上
    const ctx = lines.slice(Math.max(0, i - 3), i + 1).join(String.fromCharCode(10));

    // 规则 1
    if (/\.font\(\s*\.system\(size:/.test(text)
        && !/Image\(systemName:/.test(ctx)
        && !/icon:/.test(text)) {
      findings.push({
        file, line: i + 1, rule: 'DynamicType',
        msg: 'Text 使用 .system(size:) — 该写法不参与 Dynamic Type 缩放, AX 字号下文字不会变大。改用语义字号 (.footnote/.subheadline/…) 或 .imageScale()'
      });
    }

    // 规则 2: 固定高度容器包住 Text 而未给 fixedSize — 必然截断/溢出
    if (/\.frame\(\s*height:\s*\d+\s*\)/.test(text) && /Text\(/.test(text)) {
      findings.push({
        file, line: i + 1, rule: 'DynamicType',
        msg: 'Text 被固定 .frame(height:) 约束 — 最大动态字体下会被截断。去掉固定高度或改 .fixedSize(vertical:)'
      });
    }

    // 规则 3: 关键信息被 lineLimit(1) 截断且无 minimumScaleFactor 兜底
    if (/\.lineLimit\(1\)/.test(text) && /\.font\(/.test(text)) {
      findings.push({
        file, line: i + 1, rule: 'DynamicType',
        msg: '单行文本可能被截断 — 若承载关键信息请确认可接受, 或给 .fixedSize(vertical: true) / .minimumScaleFactor'
      });
    }

    // 规则 4: 可点区域小于 44pt
    const tap = text.match(/\.frame\(\s*(?:width:\s*(\d+)|height:\s*(\d+))\s*\)/);
    if (tap && (text.includes('Button') || text.includes('.onTapGesture'))) {
      const v = parseInt(tap[1] || tap[2], 10);
      if (v > 0 && v < 44) {
        findings.push({
          file, line: i + 1, rule: 'TouchTarget',
          msg: `可点区域 ${v}pt < 44pt — iOS 最小触达目标。用 .frame(minWidth:44, minHeight:44) 或 .contentShape 扩展`
        });
      }
    }

    // 规则 5: 中文界面不应使用 .bold (PingFang SC 无 Bold 字重, 会静默回退)
    if (/\.bold\(\)/.test(text) || /\.weight\(\.bold\)/.test(text)) {
      findings.push({
        file, line: i + 1, rule: 'Chinese',
        msg: 'PingFang SC 无 Bold(700) 字重, .bold 会静默回退到 Semibold — 中文层级请用 .weight(.semibold) + 字号'
      });
    }
  });
}

// ---- 汇总 ----
const byRule = {};
for (const f of findings) (byRule[f.rule] ||= []).push(f);

if (findings.length === 0) {
  console.log('✓ 动态字体 / 触达 / 中文字重 静态检查无问题');
  process.exit(0);
}

console.log(`发现 ${findings.length} 处：\n`);
for (const [rule, list] of Object.entries(byRule)) {
  console.log(`── ${rule} (${list.length}) ──`);
  for (const f of list) {
    console.log(`  ${path.relative(path.join(__dirname, '..'), f.file)}:${f.line}\n    ${f.msg}`);
  }
  console.log('');
}
console.error('✗ 静态检查未通过');
process.exit(1);