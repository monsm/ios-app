// tools/layout-audit/ast.js —— SwiftUI 布局 IR (真语法树)
// 形状 (tree-sitter-swift 实测):
//   call_expression = [simple_identifier | navigation_expression] + call_suffix
//   navigation_expression = 被修饰表达式 + navigation_suffix('.名字')  ⇒ 修饰符链靠它递归
//   call_suffix = value_arguments + lambda_literal; lambda_literal → statements → 子元素
//   字符串是 line_string_literal；命名参数带 value_argument_label
// 本文件只回答"取到了什么"，不下判断；判据在 rules.js。
// 依赖在仓外: D:/aapk/_swiftparse/node_modules (web-tree-sitter + tree-sitter-swift)，装法见 docs/AUDIT-CODE.md §10.52。
// 所以 layout-audit 只在本机跑 —— CI 上没有这两个包，也不该加：它是取证尺，不是常驻闸门。
'use strict';
const fs = require('fs');
const path = require('path');
const TP = 'D:/aapk/_swiftparse/node_modules';
if (!fs.existsSync(TP)) {
  console.error('找不到 tree-sitter 依赖目录 ' + TP + ' —— 本工具是仓外取证尺，先按 docs/AUDIT-CODE.md §10.52 装 web-tree-sitter + tree-sitter-swift。');
  process.exit(1);
}
const Parser = require(path.join(TP, 'tree-sitter'));
const Swift = require(path.join(TP, 'tree-sitter-swift'));
const PARSER = new Parser();
PARSER.setLanguage(Swift);

const CONTAINERS = new Set(['VStack', 'HStack', 'ZStack', 'LazyVGrid', 'LazyHGrid', 'Grid', 'List', 'Form', 'ScrollView', 'Section', 'GroupBox', 'DisclosureGroup']);
const INTERACTIVE = new Set(['Button', 'Toggle', 'NavigationLink', 'Menu', 'Link', 'Slider', 'Stepper', 'TextField', 'SecureField', 'Picker']);
const TEXTISH = new Set(['Text', 'Label', 'LabeledContent', 'EmptyState', 'SectionTitle', 'HeroStat', 'MetricTile', 'LabeledRow']);
const FONT_PT = { largeTitle: 26, title: 22, title2: 17, title3: 20, headline: 17, body: 17, callout: 16, subheadline: 15, footnote: 13, caption: 12, caption2: 11 };
const SCALES = [0.8, 1.0, 1.25, 1.5, 1.75];              // App 字号五档 (AccessibilityKit: kf_font_scale)
const DEVICES = [{ n: 'SE', w: 375 }, { n: '标准', w: 390 }, { n: 'Max', w: 430 }];
const TAU = { xxs: 2, xs: 4, s: 8, m: 12, l: 16, xl: 24, xxl: 32, gutter: 16 };

function loadTokens(dsPath) {
  const s = fs.readFileSync(dsPath, 'utf8');
  const SPACE = {}, RADIUS = {}, ICON = {};
  for (const m of s.matchAll(/static var (xxs|xs|s|m|l|xl|xxl|gutter): CGFloat \{ d\((\d+(?:\.\d+)?)\)/g)) SPACE[m[1]] = +m[2];
  for (const m of s.matchAll(/static var (card|control|tile): CGFloat \{ r\((\d+(?:\.\d+)?)\)/g)) RADIUS[m[1]] = +m[2];
  for (const m of s.matchAll(/static let (xs|sm|md|lg|xl): CGFloat = (\d+)/g)) ICON[m[1]] = +m[2];
  const hit = +(/enum Hit \{ static let min: CGFloat = (\d+)/.exec(s) || [0, 44])[1];
  return { SPACE, RADIUS, ICON, HIT: hit };
}
// 值文字 → pt。只认写死的数字 / DS 令牌 / 简单四则；状态量返回 null ⇒ 调用方必须"不判"，不许猜 0
function num(txt, tk, dens) {
  if (txt == null) return null;
  const t = String(txt).trim().replace(/\s+/g, ' ');
  if (/^-?\d+(\.\d+)?$/.test(t)) return +t;
  let m = /^DS\.Space\.(\w+)$/.exec(t); if (m && TAU[m[1]] != null) return Math.round(TAU[m[1]] * dens * 2) / 2;
  m = /^DS\.Icon\.(\w+)$/.exec(t); if (m && tk.ICON[m[1]] != null) return tk.ICON[m[1]];
  m = /^DS\.Radius\.(\w+)$/.exec(t); if (m && tk.RADIUS[m[1]] != null) return tk.RADIUS[m[1]];
  if (/^DS\.Hit\.min$/.test(t)) return tk.HIT;
  m = /^(\d+(?:\.\d+)?) *([-+*/]) *(\d+(?:\.\d+)?)$/.exec(t);
  if (m) { const a = +m[1], b = +m[3]; return m[2] === '+' ? a + b : m[2] === '-' ? a - b : m[2] === '*' ? a * b : a / b; }
  return null;
}
// 这版 tree-sitter 的 Node 没有 isNamed() 方法 —— 用 namedChildren 取值器
const kids = (n) => (n ? (n.namedChildren || n.children.filter((c) => c.isNamed === undefined || c.isNamed())) : []);
function argMap(callNode) {
  const o = { _: [] };
  const cs = (callNode.children || []).find((c) => c.type === 'call_suffix');
  const va = cs ? (function f(x) { if (!x) return null; if (x.type === 'value_arguments') return x; for (const c of kids(x)) { const r = f(c); if (r) return r; } return null; })(cs) : null;
  if (!va) return o;
  for (const a of kids(va).filter((k) => k.type === 'value_argument')) {
    const lab = a.children.find((c) => c.type === 'value_argument_label');
    const val = kids(a).filter((c) => c.type !== 'value_argument_label' && c.type !== 'operator').pop();
    const txt = val ? val.text.replace(/\s+/g, ' ').trim() : '';
    if (lab) o[lab.text.replace(/`/g, '')] = txt; else o._.push(txt);
    if (val && (val.type === 'line_string_literal' || val.type === 'multi_line_string_literal') && !o.__text) o.__text = txt.slice(1, -1);
  }
  return o;
}
function build(node, file, tk, dens) {
  if (!node) return null;
  if (node.type === 'call_expression') {
    const first = node.children[0];
    const cs = (node.children || []).find((c) => c.type === 'call_suffix');
    // Button { 动作 } label: { 内容 } 有两个 lambda: 取全部, 否则 label 里的子视图会整片丢掉
    const lams = cs ? cs.children.filter((c) => c.type === 'lambda_literal') : [];
    if (first && first.type === 'navigation_expression') {
      const base = build(first.children.filter((c) => c.type !== 'navigation_suffix')[0], file, tk, dens);
      const suf = first.children.filter((c) => c.type === 'navigation_suffix').pop();
      // 修饰符自己那一行才是"它写在哪"：call_expression 的起点是**整条链的根**(如 `Text(` 那行)，
      // 用它当行号会让所有"按行改代码"的后续脚本指错地方 (31 条定位失败就是这个原因)。
      if (base) { base.mods.push({ name: (suf ? suf.text : '').replace(/^\./, ''), args: argMap(node), line: suf ? suf.startPosition.row + 1 : node.startPosition.row + 1 }); return base; }
      return null;
    }
    if (first && first.type === 'simple_identifier') {
      const el = { name: first.text, line: node.startPosition.row + 1, col: node.startPosition.column, args: argMap(node), mods: [], children: [], file, depth: 0 };
      el.children = lams.flatMap((l) => childElems(l, file, tk, dens));
      return el;
    }
    if (first) return build(first, file, tk, dens);
    return null;
  }
  if (node.type === 'navigation_expression') return build(node.children.filter((c) => c.type !== 'navigation_suffix')[0], file, tk, dens);
  return null;
}
function childElems(lam, file, tk, dens) {
  const st = lam.children.find((c) => c.type === 'statements');
  if (!st) return [];
  const out = [];
  for (const s of kids(st)) collect(s, out, file, tk, dens, 0);
  return out;
}
// if / ForEach / switch 分支里的子视图也收进来，但打 cond 标记（"有时才在屏上"）
function collect(node, out, file, tk, dens, depth) {
  if (!node || depth > 4) return;
  const t = node.type;
  if (t === 'call_expression' || t === 'navigation_expression') {
    const e = build(node, file, tk, dens);
    if (e) { out.push(e); return; }
  }
  const structural = /^(if_statement|else_clause|for_each_statement|switch_statement|switch_case|catch_clause|do_statement|optional_binding|value_binding_pattern|return_statement|statements|expression_statement)$/;
  if (structural.test(t) || /^case /.test(node.text)) {
    for (const c of kids(node)) {
      if (c.type === 'call_expression' || c.type === 'navigation_expression') { const e = build(c, file, tk, dens); if (e) { e.cond = true; out.push(e); } }
      else collect(c, out, file, tk, dens, depth + 1);
    }
    return;
  }
  for (const c of kids(node)) collect(c, out, file, tk, dens, depth + 1);
}
function flatten(e, list = [], parent = null) {
  e.parent = parent ? { name: parent.name, line: parent.line } : null;
  e.parentEl = parent || null;   // 直接挂引用: 闭包子元素与父调用不在同一行, 按行号回连必然失败
  e.depth = parent ? parent.depth + 1 : 0;
  list.push(e);
  e.children.forEach((c) => flatten(c, list, e));
  return list;
}
function parseFile(file, tk, dens) {
  const src = fs.readFileSync(file, 'utf8');
  const tree = PARSER.parse(src);
  const errors = [];
  (function w(n) { if (n.type === 'ERROR' || n.type === 'MISSING') errors.push({ line: n.startPosition.row + 1, kind: n.type }); for (const c of n.children) w(c); })(tree.rootNode);
  // 材质载体: 自己挂了实底背景/玻璃的那一颗。叶子节点 (Image/Circle/自定义卡) 也常是面板 ——
  // 2026-10-14 与一把正则尺子对表时发现: 只按"容器/可交互/文字"收节点会漏掉这类面板,
  // 于是 MemberCenterView 的角标底板这种实底永远数不到 (R6 就在那儿变成半瞎的)。
  const bearsMaterial = (e) => (e.mods || []).some((m) => {
    if (m.name === 'background' || m.name === 'overlay') { const t = JSON.stringify(m.args || {}); if (/Palette\.surface/.test(t) || /Material/.test(t)) return true; }
    return /^(axGlass|axGlassCircle|axGlassCapsule|glassEffect|card)$/.test(m.name);
  });
  const roots = [];
  (function w(n) {
    if (n.type === 'call_expression') {
      const e = build(n, path.basename(file), tk, dens);
      if (e && (CONTAINERS.has(e.name) || INTERACTIVE.has(e.name) || TEXTISH.has(e.name) || e.children.length || bearsMaterial(e))) roots.push(e);
    }
    for (const c of n.children) w(c);
  })(tree.rootNode);
  const all = [];
  roots.forEach((r) => flatten(r, all));
  const seen = new Set(), uniq = [];
  all.forEach((e) => { const k = e.name + ':' + e.line + ':' + e.col; if (!seen.has(k)) { seen.add(k); uniq.push(e); } });
  return { roots, nodes: uniq, errors };
}
const mod = (e, n) => e.mods.find((m) => m.name === n);
const hasInteractive = (e) => INTERACTIVE.has(e.name) || !!mod(e, 'onTapGesture') || !!mod(e, 'buttonStyle') || !!mod(e, 'contextMenu');
module.exports = { loadTokens, parseFile, build, flatten, num, mod, hasInteractive, CONTAINERS, INTERACTIVE, TEXTISH, FONT_PT, SCALES, DEVICES, TAU };
if (require.main === module) {
  const tk = loadTokens('D:/aapk/ios-app/App/Core/DesignSystem.swift');
  const f = process.argv[2] || 'D:/aapk/ios-app/App/UI/DeviceHomeView.swift';
  const r = parseFile(f, tk, 1.0);
  console.log('元素数:', r.nodes.length, '· AST 盲区:', r.errors.length);
  const by = {}; r.nodes.forEach((n) => by[n.name] = (by[n.name] || 0) + 1);
  console.log('分布:', Object.entries(by).sort((a, b) => b[1] - a[1]).slice(0, 12).map(([k, v]) => k + ':' + v).join(' '));
  console.log('--- 抽查 (抽不对就别往下写判据) ---');
  r.nodes.filter((n) => n.name === 'VStack' || n.name === 'HStack').slice(0, 5).forEach((n) =>
    console.log(` ${n.line} ${n.name} spacing=${n.args.spacing || '(未写)'} 子=${n.children.length}`));
  r.nodes.filter((n) => n.name === 'Text').slice(0, 5).forEach((n) =>
    console.log(` ${n.line} Text «${(n.args.__text || '').slice(0, 18)}» mods=${n.mods.map((m) => m.name).join(',')} 子=${n.children.length}`));
  r.nodes.filter((n) => n.name === 'Button').slice(0, 4).forEach((n) =>
    console.log(` ${n.line} Button mods=${n.mods.map((m) => m.name + '(' + (m.args._ || []).join('|') + ')').join(' ')} 子=${n.children.length}`));
}
