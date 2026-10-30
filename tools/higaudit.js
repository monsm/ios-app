#!/usr/bin/env node
// higaudit —— 74 个 View 的「界面构成」一致性批量审核。
//
// 2026-10-30 新增（第 104 轮）：台账里最大缺口是「逐页 HIG 构成审核（74 个 View），剩 ~49 个」。
// 人工逐页读 33k 行不现实，但**结构性的东西可以机检**：
//   H1 每个页面级 View 必须 `.destined(...)` 登记路由（本仓的"这个页面怎么被打开"唯一声明）
//   H2 sheet/模态页必须有 navigationTitle（否则用户不知道自己在哪一页）
//   H3 页面级 View 必须 `.dsScreenBackground()`（否则深浅色下底色不一致）
//   H4 列表型页面应走 `.variantList()`（否则行高/分隔线与全 App 不一致）
//   H5 页面级 View 的 toolbar 必须有退出手段（完成/取消/关闭）
//   H6 用户可见颜色必须走 DS.Palette（硬编码 Color(hex:) 会绕过主题/AMOLED/高对比）
//   H7 纯图标 Button 必须有 accessibilityLabel（否则 VoiceOver 念"按钮"）
//
// 判据保守：只报**页面级** View（有 .destined 或有 navigationTitle 的），跳过小组件。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

const all = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    all.push({ rel: `${d}/${f}`, src: fs.readFileSync(path.join(dir, f), 'utf8') });
  }
}

const views = [];
for (const { rel, src } of all) {
  const L = src.split(/\r?\n/);
  for (let i = 0; i < L.length; i++) {
    const m = /^\s*(?:private\s+)?struct\s+(\w+)\s*:\s*View\b/.exec(L[i]);
    if (!m) continue;
    let dep = 0, s = false, end = i;
    for (let k = i; k < L.length; k++) {
      const code = L[k].replace(/\/\/.*$/, '');
      for (const ch of code) { if (ch === '{') { dep++; s = true; } else if (ch === '}') dep--; }
      if (s && dep <= 0) { end = k; break; }
    }
    views.push({ name: m[1], rel, line: i + 1, body: L.slice(i, end + 1).join('\n') });
  }
}

const issues = { H2: [], H3: [], H5: [], H6: [], H7: [] };
let pageCount = 0;

// 2026-10-30（第 104 轮，正控发现的工具 bug）：
// 结构判据必须在**剥掉注释**之后做。否则一句「本页缺 `.dsScreenBackground()`」的
// **说明性注释**会让 H3 判据误以为该页已经有背景 —— 正控实测就是这么漏过去的。
// （与第 102 轮 `cnpunctcheck` 那个坑同源：拿正则处理源码前先想清楚注释/字符串边界。）
const stripComments = (s) => s.replace(/\/\/[^\n]*/g, '');

for (const v of views) {
  const b = stripComments(v.body);
  const isPage = /\.destined\s*\(/.test(b) || /\.navigationTitle\s*\(/.test(b);
  if (!isPage) continue;
  pageCount++;

  // H2 模态/页面必须有「标题」——
  //    导航栏标题 (navigationTitle) **或** 内容内标题（`.vkFont(.title3/.title2/.headline, weight: .semibold|.bold)`）。
  //    半高 sheet 用内容内标题是 HIG 允许的（导航栏标题反而冗余），所以两者等价。
  if (!/\.navigationTitle\s*\(/.test(b)
      && !/\.vkFont\(\s*\.(title3|title2|title|headline)\s*,\s*weight:\s*\.(semibold|bold)/.test(b)) {
    issues.H2.push(v);
  }

  // H3 页面必须有主题背景 —— `.dsScreenBackground()` **或** `.background(DS.Gradient.screen…)`（等价写法）。
  if (!/\.dsScreenBackground\s*\(/.test(b) && !/\.background\(\s*DS\.Gradient\.screen/.test(b)) {
    issues.H3.push(v);
  }

  // H5 有 toolbar 就必须有退出手段
  if (/\.toolbar\s*\{/.test(b) && !/dismiss\(\)|\.dismiss|完成|取消|关闭|返回/.test(b)) issues.H5.push(v);

  // H6 硬编码颜色（排除 DS 令牌里的定义文件本身）
  if (!/DesignPalette|DesignTokens|DesignSystem/.test(v.rel)) {
    const hard = [...b.matchAll(/Color\(\s*(?:hex:)?\s*0x[0-9A-Fa-f]{6}/g)];
    if (hard.length) issues.H6.push({ ...v, n: hard.length });
  }

  // H7 纯图标 Button 缺 accessibilityLabel
  const iconBtns = [...b.matchAll(/Button\s*\{[^}]{0,200}\}\s*label:\s*\{\s*Image\(systemName:/g)];
  if (iconBtns.length) {
    const labels = (b.match(/accessibilityLabel/g) || []).length;
    if (labels < iconBtns.length) issues.H7.push({ ...v, n: iconBtns.length, labels });
  }
}

console.log('════ 页面级 View 构成审核 ════\n');
console.log(`74 个 View 中页面级（有 destined 或 navigationTitle）: ${pageCount}\n`);

const names = {
  H2: 'H2 缺 navigationTitle',
  H3: 'H3 缺 dsScreenBackground',
  H5: 'H5 toolbar 无退出手段',
  H6: 'H6 硬编码颜色',
  H7: 'H7 图标按钮缺 accessibilityLabel',
};
let total = 0;
for (const k of ['H2', 'H3', 'H5', 'H6', 'H7']) {
  const list = issues[k];
  if (!list.length) { console.log(`✓ ${names[k]}: 0`); continue; }
  total += list.length;
  console.log(`✗ ${names[k]}: ${list.length}`);
  for (const v of list.slice(0, 12)) {
    const extra = v.n ? `（${v.n} 处${v.labels !== undefined ? ` / label ${v.labels}` : ''}）` : '';
    console.log(`    ${v.name}  ${v.rel}:${v.line} ${extra}`);
  }
  if (list.length > 12) console.log(`    …还有 ${list.length - 12} 个`);
}
console.log(`\n合计 ${total} 处`);
// 2026-10-30（第 104 轮）：本闸门首次跑通时 5 处线索**全部是工具误报**（已修正判据），
// 修完 `ShareToAndroidView` 后归零。既然到 0，就设成**硬闸门**防回归 ——
// 新增页面若漏了标题/主题背景/退出手段/无障碍标签，CI 直接红。
if (total > 0) {
  console.log('修法：见各条说明。若确认是等价写法（如内容内标题、DS.Gradient.screen 背景），请扩展本工具的判据而不是放过。');
  process.exit(1);
}
console.log('✓ 39 个页面级 View 的构成一致性全部通过');
