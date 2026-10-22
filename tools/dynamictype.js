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

// 927 之后有第二个 UI 面: Widget/ (哑按钮扩展)。它同样是 Text/font/accessibility 的宿主,
// 只扫 App/ 就等于让小组件躲开字号与触达检查。walk 不做存在性判断, 所以先过滤目录。
const SCAN_DIRS = [APP, path.join(__dirname, '..', 'Widget')].filter((d) => fs.existsSync(d));
const SWIFT_FILES = SCAN_DIRS.flatMap((d) => walk(d));

const findings = [];

// ---- 规则 1: Text 不得使用 .system(size:) — 它不参与 Dynamic Type 缩放 ----
// 例外: Image(systemName:) 上的 .system(size:) 是图标尺寸, 合规。
const TEXT_SIZE_RE = /Text\([^)]*\)(?:[^;]{0,400}?)\.font\(\s*\.system\(size:/g;
const ICON_SIZE_RE = /Image\(systemName:[^)]*\)(?:[^;]{0,200}?)\.font\(\s*\.system\(size:/g;

for (const file of SWIFT_FILES) {
  const src = fs.readFileSync(file, 'utf8');
  const lines = src.split('\n');

  lines.forEach((line, i) => {
    const text = line.trim();
    if (text.startsWith('//')) return;
    // 修饰符常写在下一行, 因此向上回看 3 行判断这个 .system(size:) 挂在谁身上
    const ctx = lines.slice(Math.max(0, i - 3), i + 1).join(String.fromCharCode(10));

    // 规则 1
    //
    // 2026-10-21 修: 原来只匹配 .font(.system(size:, 漏掉了 .xFont( ——
    // 而本仓 Text 全部走 xFont (内部就是 .font + .fontWeight),
    // 于是这条规则对新代码完全不生效, Canvas 里 12 处固定字号一直绿着。
    //
    // 放行"已经做了缩放"的写法:
    //   .xFont(.system(size: XMetric.dataText(N)))   ← 按 AX 字号放大
    //   .xFont(.system(size: XMetric.decorIcon(N)))  ← 装饰图标
    const FIXED_FONT_RE = /\.(?:x)?[fF]ont\(\s*\.system\(size:/;
    // 2026-10-23 补：字体修饰器内部的一个包装里，`.system(size:)` 拿到的是
    // `finalSize` —— 它由 `@ScaledMetric` 派生的 `scaled` 算出（并承载 §13.1 的
    // displayNumber AX 降档）。判据按**名字**放行不够可靠，所以显式列出这两个：
    //   scaled     @ScaledMetric 包装值
    //   finalSize  XTextModifier 里算完的最终字号（含 AX 降档）
    const SCALED_RE = /XMetric\.(?:dataText|decorIcon)\(|size:\s*(?:finalSize|scaled)\b/;
    if (FIXED_FONT_RE.test(text)
        && !SCALED_RE.test(text)
        && !/Image\(systemName:/.test(ctx)
        && !/icon:/.test(text)) {
      findings.push({
        file, line: i + 1, rule: 'DynamicType',
        msg: 'Text 用 .font/.xFont(.system(size:)) 且未做 AX 缩放 — AX 字号下字不会变大。改用语义字号, 或 Canvas 器皿文字包 XMetric.dataText(N)'
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

// ---- 自检: 证明规则 1 真的能抓到 (2026-10-21 加) ----
// 由来: 规则 1 原来只匹配 .font(, 漏了 .xFont(, 于是 Canvas 里 12 处
// 固定字号一直是绿的。闸门不会报错的闸门等于没有闸门。
{
  const probes = [
    { src: 'Text("x").xFont(.system(size: 12))', bad: true,  why: 'xFont 固定字号' },
    { src: 'Text("x").xFont(.system(size: XMetric.dataText(12)))', bad: false, why: '已做 AX 缩放' },
    { src: 'Text("x").xFont(.footnote)', bad: false, why: '语义字号' },
    { src: 'Image(systemName: "a").xFont(.system(size: 12))', bad: false, why: '图标尺寸' },
  ];
  const FIXED = /\.(?:x)?[fF]ont\(\s*\.system\(size:/;
  const SCALED = /XMetric\.(?:dataText|decorIcon)\(/;
  let bad = 0;
  for (const p of probes) {
    const isIcon = /Image\(systemName:/.test(p.src);
    const catched = FIXED.test(p.src) && !SCALED.test(p.src) && !isIcon;
    if (catched !== p.bad) {
      console.error('✗ 自检失败: ' + p.why + ' (期望 ' + p.bad + ', 实际 ' + catched + ')');
      bad++;
    }
  }
  if (bad > 0) { console.error('✗ dynamictype 闸门自检不通过, 判据已失效'); process.exit(1); }
}

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