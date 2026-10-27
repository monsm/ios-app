#!/usr/bin/env node
// 设计令牌对比度闸门 — 把"对比度已核算"这种口头声明变成可复现的机器检查。
//
// 背景: DS.Palette 的颜色是 UIColor 动态色(明暗各一套), 之前对比度是手算的,
// 手算不可复现、也没人会在改色后重算。这里直接从 DesignSystem.swift 解析出
// 每一组取值, 按 WCAG 2.1 相对亮度公式算出比值, 低于阈值即失败。
//
// 包16 起色板扩展为: 基础令牌 + 六套品牌主题 (themeTable, idea 31 + 886) + AMOLED 纯黑覆盖
// (amoledOverride, idea 30) — 三张表全部机检:
//   基础:   text/textSub 对三种底, ok/warn/danger 对画布与卡片, hairline 可辨。
//   主题:   每主题×明暗: accentText 对三种底 / onAccent 对 accent / 纯白对 hero 两端。
//   AMOLED: 纯黑表面上正文与语义色 (含各主题 dark accentText) 仍 ≥4.5:1。
//   E (第八十三批): 语义填充上的前景 (onSem)、863 反转降级的**降级底自己**是否可读、
//     hero 叠层 (渐变→纹理→柔光→黑纱→底板) 合成后的真实比值、强调填充角标的洗底方向、
//     图标预览块的写死底色。这些不是"令牌对不对", 而是"屏幕上真按出来的那两个颜色对不对"。
//
// 用法: node tools/contrast.js          (CI 闸门, 不达标 exit 1)
//       node tools/contrast.js --verbose (附带完整表格)

const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'App', 'Core', 'DesignSystem.swift');
const verbose = process.argv.includes('--verbose');

// ---------- WCAG 相对亮度 ----------
function channel(c) {
  const s = c / 255;
  return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
}
function luminance(hex) {
  const r = (hex >> 16) & 0xff, g = (hex >> 8) & 0xff, b = hex & 0xff;
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}
function contrast(a, b) {
  const la = luminance(a), lb = luminance(b);
  const hi = Math.max(la, lb), lo = Math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

// ---------- 解析 DesignSystem.swift ----------
const src = fs.readFileSync(SRC, 'utf8');
const paletteBlock = src.match(/enum Palette \{([\s\S]*?)\n    \}/);
if (!paletteBlock) {
  console.error('✗ 未能在 DesignSystem.swift 中定位 enum Palette — 结构变了?');
  process.exit(1);
}
const block = paletteBlock[1];

// 1) 基础令牌: static let xxx = Color.adaptive(light, dark)
const base = {};
const reBase = /static let (\w+)\s*=\s*Color\.adaptive\(\s*0x([0-9a-fA-F]{6})\s*,\s*0x([0-9a-fA-F]{6})\s*\)/g;
let m;
while ((m = reBase.exec(block)) !== null) {
  base[m[1]] = { light: parseInt(m[2], 16), dark: parseInt(m[3], 16) };
}
if (Object.keys(base).length < 9) {
  console.error(`✗ 基础令牌只解析到 ${Object.keys(base).length} 个, 预期 >= 9 — 解析规则可能失效`);
  process.exit(1);
}

// 主题表: "主题": [ "light": [...], "dark": [...] ]
// `\s*` 后面那段 `(?://[^\n]*\n)?` 是给"主题名行尾写注释"留的余地 —— 第七十二批我就那么写了一次，
// 解析器直接少认三套主题，而它当时的报错长得像"色板不同步"，绕了一圈才找到真因。
const themes = {};
const reTheme = /"(\w+)":\s*\[\s*(?:\/\/[^\n]*\n)?\s*"light":\s*\[([^\]]*)\],\s*(?:\/\/[^\n]*\n)?\s*"dark":\s*\[([^\]]*)\]/g;
const rePair = /"(\w+)":\s*0x([0-9a-fA-F]{6})/g;
while ((m = reTheme.exec(block)) !== null) {
  const t = {};
  for (const [idx, mode] of [[2, 'light'], [3, 'dark']]) {
    const roles = {};
    let p;
    rePair.lastIndex = 0;
    while ((p = rePair.exec(m[idx])) !== null) roles[p[1]] = parseInt(p[2], 16);
    t[mode] = roles;
  }
  themes[m[1]] = t;
}
// 主题套数**不写死数字**: 以设置页色板元数据 DS.accentThemes 的键集合为准。
// 理由是防"半接线"：886 扩色板时最容易发生的是 themeTable 加了主题但色板没加 (选不到 = 死色)，
// 或色板列了但表里没有 (选中后 themed() 走 ?? indigo 回退，屏幕上悄悄换色)。
// 两个集合不等就是这两种事故之一，因此判失败而不是只数个数。
const metaKeys = [...src.matchAll(/AccentTheme\(key:\s*"(\w+)"/g)].map((x) => x[1]);
if (!metaKeys.length) {
  console.error('✗ 没解析到 DS.accentThemes 的键 — 色板元数据结构变了? 闸门不能瞎猜，直接失败');
  process.exit(1);
}
const tblKeys = Object.keys(themes);
const onlyTable = tblKeys.filter((k) => !metaKeys.includes(k));
const onlyMeta = metaKeys.filter((k) => !tblKeys.includes(k));
if (onlyTable.length || onlyMeta.length) {
  console.error(`✗ 色板与主题表不同步: 只在 themeTable ${onlyTable.join(',') || '—'} / 只在 accentThemes ${onlyMeta.join(',') || '—'}`);
  process.exit(1);
}
if (tblKeys.length < 3) {
  console.error(`✗ 品牌主题只有 ${tblKeys.length} 套, 至少 3 (indigo/forest/amber)`);
  process.exit(1);
}
for (const [name, t] of Object.entries(themes)) {
  for (const mode of ['light', 'dark']) {
    for (const role of ['accent', 'accentText', 'onAccent', 'heroA', 'heroB', 'btnA', 'btnB']) {
      if (t[mode][role] === undefined) {
        console.error(`✗ 主题 ${name}/${mode} 缺少角色 ${role}`);
        process.exit(1);
      }
    }
  }
}

// 3) AMOLED 覆盖表
const amoMatch = block.match(/static let amoledOverride:\s*\[String: UInt32\]\s*=\s*\[([^\]]*)\]/);
if (!amoMatch) {
  console.error('✗ 未找到 amoledOverride 表 — idea 30 的纯黑覆盖缺失?');
  process.exit(1);
}
const amoled = {};
rePair.lastIndex = 0;
while ((m = rePair.exec(amoMatch[1])) !== null) amoled[m[1]] = parseInt(m[2], 16);
for (const k of ['canvas', 'surface', 'surfaceAlt']) {
  if (amoled[k] === undefined) {
    console.error(`✗ amoledOverride 缺少 ${k}`);
    process.exit(1);
  }
}

// ---------- 断言表 ----------
// ratio: 该前景色必须与其背景达到的最小对比度。WCAG AA 正文需 4.5,
// 非文本/大号文字需 3.0。分隔线按下限 1.2:1 (须"看得见", 苹果自身 separator 也在 1.2 上下)。
const ASSERTIONS = [];
const push = (mode, fg, bg, min, why, fgHex, bgHex) =>
  ASSERTIONS.push({ mode, fg, bg, min, why, fgHex, bgHex });

// A. 基础令牌 (明暗双模)
for (const mode of ['light', 'dark']) {
  for (const [fg, min] of [['text', 4.5], ['textSub', 4.5]]) {
    for (const bg of ['surfaceBase', 'canvasBase', 'surfaceAltBase']) {
      push(mode, fg, bg, min, `${fg === 'text' ? '正文' : '次级文本'}在${bg.includes('Alt') ? '指标块' : bg.includes('canvas') ? '页面底' : '卡片'}上`, base[fg][mode], base[bg][mode]);
    }
  }
  for (const fg of ['ok', 'warn', 'danger']) {
    for (const bg of ['canvasBase', 'surfaceBase']) {
      push(mode, fg, bg, 4.5, '语义文案在页面底/卡片上', base[fg][mode], base[bg][mode]);
    }
  }
  for (const bg of ['surfaceBase', 'canvasBase']) {
    push(mode, 'hairline', bg, 1.2, '分隔线需可辨', base.hairline[mode], base[bg][mode]);
  }
}

// B. 品牌主题 (idea 31): 每主题 × 明暗
const surfaceOf = { light: base.surfaceBase.light, dark: base.surfaceBase.dark };
const canvasOf = { light: base.canvasBase.light, dark: base.canvasBase.dark };
const altOf = { light: base.surfaceAltBase.light, dark: base.surfaceAltBase.dark };
for (const [name, t] of Object.entries(themes)) {
  for (const mode of ['light', 'dark']) {
    push(mode, `${name}.accentText`, 'surface', 4.5, '主题强调文字在卡片上', t[mode].accentText, surfaceOf[mode]);
    push(mode, `${name}.accentText`, 'canvas', 4.5, '主题强调文字在页面底上', t[mode].accentText, canvasOf[mode]);
    push(mode, `${name}.accentText`, 'surfaceAlt', 4.5, '主题强调文字在指标块上', t[mode].accentText, altOf[mode]);
    push(mode, `${name}.onAccent`, `${name}.accent`, 4.5, '主按钮文字压在主题填充上', t[mode].onAccent, t[mode].accent);
    push(mode, 'white', `${name}.heroA`, 4.5, '纯白压主题渐变亮端 (hero 卡文字)', 0xFFFFFF, t[mode].heroA);
    push(mode, 'white', `${name}.heroB`, 4.5, '纯白压主题渐变暗端 (hero 卡文字)', 0xFFFFFF, t[mode].heroB);
  }
}

// C. 节日限定色 (idea 890): 纯白正文压在节日 hero 两端 —— 同样机检。
// 第七十三批先是用一次性脚本算过就写进 Swift，那等于"这次对了"而没有守住"以后别改错"；
// 这一组把它变成闸门：节日表里任何一端亮度上浮到白字 <4.5:1 就红。
//
// 2026-10-26 功能精简：`enum Festive` 整套移除（用户确认删除节日限定色）。
// 这条检查随之失效 —— 但没有直接删掉：把它改成「若将来有人把 Festive 加回来，
// 检查必须自动复活」，这样删掉的是功能、不是守门能力。
const festBlock = src.match(/enum Festive \{[\s\S]*?pairs: \[String: \(UInt32, UInt32\)\] = \[([\s\S]*?)\n        \]/);
let festCount = 0;
const festivePairs = [];
if (festBlock) {
  const reFest = /"([^"]+)":\s*\(0x([0-9a-fA-F]{6}),\s*0x([0-9a-fA-F]{6})\)/g;
  let fm;
  while ((fm = reFest.exec(festBlock[1])) !== null) {
    festCount++;
    const pairA = parseInt(fm[2], 16), pairB = parseInt(fm[3], 16);
    festivePairs.push([fm[1], pairA, pairB]);
    push('both', `festive.${fm[1]}.heroA`, 'white-on-hero', 4.5, '纯白压节日渐变亮端', pairA, 0xFFFFFF);
    push('both', `festive.${fm[1]}.heroB`, 'white-on-hero', 4.5, '纯白压节日渐变暗端', pairB, 0xFFFFFF);
  }
  // 节日表解析不到东西 = 结构变了，宁可判失败也不要"绿灯因为看不见而亮着"
  if (festCount === 0) {
    console.error('✗ 找到 enum Festive 却没解析出任何节日配色 — 解析规则失效');
    process.exit(1);
  }
} else {
  // 2026-10-26: 功能已删 ⇒ 这里**不是**失败，而是"检查对象不存在"。
  // 若将来 Festive 被加回来，上面那个 if 分支会重新接管，无需改代码。
  console.log('节日限定色: 功能已移除 (enum Festive 不存在), 本条检查休眠');
}

// D. AMOLED 纯黑 (idea 30): kf_theme=="black" 时强制深色语义, 用各令牌 dark 值
for (const fg of ['text', 'textSub', 'ok', 'warn', 'danger']) {
  for (const [bgName, bgHex] of [['amoCanvas', amoled.canvas], ['amoSurface', amoled.surface], ['amoSurfaceAlt', amoled.surfaceAlt]]) {
    push('black', fg, bgName, 4.5, '纯黑表面上文字仍须达标', base[fg].dark, bgHex);
  }
}
push('black', 'hairline', 'amoSurface', 1.2, '纯黑表面上分隔线需可辨', base.hairline.dark, amoled.surface);
push('black', 'hairline', 'amoCanvas', 1.2, '纯黑页底上分隔线需可辨', base.hairline.dark, amoled.canvas);
for (const [name, t] of Object.entries(themes)) {
  push('black', `${name}.accentText`, 'amoSurface', 4.5, '主题强调文字在纯黑卡片上', t.dark.accentText, amoled.surface);
  push('black', `${name}.accentText`, 'amoCanvas', 4.5, '主题强调文字在纯黑页底上', t.dark.accentText, amoled.canvas);
  push('black', `${name}.accentText`, 'amoSurfaceAlt', 4.5, '主题强调文字在纯黑指标块上', t.dark.accentText, amoled.surfaceAlt);
  push('black', `${name}.onAccent`, `${name}.accent`, 4.5, '主按钮文字压在主题填充上 (纯黑模式)', t.dark.onAccent, t.dark.accent);
}

// D. 主按钮渐变 (包1): onAccent 压 DS.Gradient.button 两端。
//    浅色 onAccent=白, 压 hero 同值端点; 深色 onAccent=近黑(0x0A0E15),
//    压 accentText→accent 区间 — 旧案深色按钮复用 hero 暗端, 近黑字仅 ~2.4:1 (必修缺陷)。
//    6 组 = 3 主题 × 明暗, 每组两端; 纯黑模式沿用深色值, 一并锁定。
for (const [name, t] of Object.entries(themes)) {
  for (const mode of ['light', 'dark']) {
    push(mode, `${name}.onAccent`, `${name}.btnA`, 4.5, '主按钮文字压渐变亮端 (btnA)', t[mode].onAccent, t[mode].btnA);
    push(mode, `${name}.onAccent`, `${name}.btnB`, 4.5, '主按钮文字压渐变暗端 (btnB)', t[mode].onAccent, t[mode].btnB);
  }
  push('black', `${name}.onAccent`, `${name}.btnA`, 4.5, '纯黑模式主按钮文字压渐变亮端', t.dark.onAccent, t.dark.btnA);
  push('black', `${name}.onAccent`, `${name}.btnB`, 4.5, '纯黑模式主按钮文字压渐变暗端', t.dark.onAccent, t.dark.btnB);
}

// ---------- 合成与"最亮端"辅助 ----------
// 屏幕上真正的颜色是 alpha 合成后的结果, 不是令牌本身。之前所有断言都比的是"纯色压纯色",
// 而 hero 卡上的胶囊 (.white.opacity(0.9) 字 + 同色 opacity(0.18) 底) 两端都被洗淡,
// 真实比值比手算更低 —— 这一组就是把合成后的两侧拿去比。
function over(fg, bg, a) {
  const c = (k) => Math.round(((fg >> k) & 0xff) * a + ((bg >> k) & 0xff) * (1 - a));
  return (c(16) << 16) | (c(8) << 8) | c(0);
}
// 同一条渐变上离白字最远的是**较亮**那一端: 取它当最坏情况, 免得每端各写一遍断言只会淹死报表
function lightestHero(t, mode) {
  return luminance(t[mode].heroA) >= luminance(t[mode].heroB) ? t[mode].heroA : t[mode].heroB;
}

// ---------- E. 语义填充上的前景 / 863 降级底 / hero 上的淡色 (第八十三批) ----------
// E1. onSem 压三枚语义填充。语义色是"浅色档深、深色档浅"的, 纯白在深色档只剩 1.74~2.77:1
//     (RecordsView 角标、SettingsView 图标角标就是这个形状)。
for (const mode of ['light', 'dark']) {
  if (base.onSem === undefined) {
    console.error('✗ Palette.onSem 解析不到 — 语义填充上的前景色失去机检');
    process.exit(1);
  }
  for (const sem of ['ok', 'warn', 'danger']) {
    push(mode, 'onSem', sem, 4.5, `语义填充上的文字/符号 (压 ${sem})`, base.onSem[mode], base[sem][mode]);
  }
  // E2. 长按清空控件: danger 以 0.85 不透明度铺在 surfaceAlt 上, 底是合成色而不是 danger 本身
  push(mode, 'onSem', 'danger@0.85/surfaceAlt', 4.5,
       '长按满格时文字压在 danger 与次级块的合成色上', base.onSem[mode], over(base.danger[mode], base.surfaceAltBase[mode], 0.85));
}


// E4. hero 面上的每一层可读文字, 按"真实的叠层顺序"核: 渐变 → 纹理(white@0.07) → 柔光(white@0.12)
//     → 卡内黑纱(heroScrim 0.20) → 底板(heroPlate 0.22) → 前景 (含 heroFg 的 alpha 档位)。
//     之前只核"纯色压纯色", 漏掉了洗白底板与柔光把局部亮度抬高这一半 —— 实测白字压白@0.14 洗底只有
//     3.74:1, 是这一组把它逼出来的。纹理与柔光都**在黑纱之下**, 所以叠层里先洗白再压暗。
const fieldOver = (surface) => over(0x000000, over(0xFFFFFF, over(0xFFFFFF, surface, 0.07), 0.12), 0.20);
const plateOver = (surface) => over(0x000000, fieldOver(surface), 0.22);
const surfaces = [];
for (const [name, t] of Object.entries(themes)) {
  for (const mode of ['light', 'dark']) surfaces.push({ name: `${name}.${mode}.hero亮端`, hex: lightestHero(t, mode), mode });
}
for (const [name, a, b] of festivePairs) {
  surfaces.push({ name: `festive.${name}.亮端`, hex: luminance(a) >= luminance(b) ? a : b, mode: 'both' });
}
const HERO_FG = [
  ['white@1.0 (裸压渐变+柔光+纱)', 1, false],
  ['white@1.0 (HeroStat 数值, 底板上)', 1, true],
  ['white@0.8 (HeroStat 标签)', 0.8, true],
  ['white@0.75 (LinkPill 未连接)', 0.75, true],
  ['mint@1.0 (LinkPill 在线)', 1, 'mint'],
  ['gold@1.0 (耗时超时)', 1, 'gold'],
];
for (const s of surfaces) {
  for (const [label, alpha, plate] of HERO_FG) {
    const fg = (plate === 'mint' || plate === 'gold') ? (plate === 'mint' ? 0xBBF7D0 : 0xFFE9A8) : 0xFFFFFF;
    const bg = plate === true ? plateOver(s.hex) : plate === false ? fieldOver(s.hex) : plateOver(s.hex);
    push(s.mode, label.split(' ')[0], s.name + (plate === false ? ' (无底板)' : ' (底板)'), 4.5,
         `hero 叠层最坏情况: ${label}`, over(fg, bg, alpha), bg);
  }
}

// E5. 强调填充上的角标底板 (CredentialsView 分段计数): 洗底方向必须与 onAccent **相反**,
//     否则浅档白字压白洗底 / 深档墨字压白洗底, 越垫越糊。
for (const [name, t] of Object.entries(themes)) {
  for (const mode of ['light', 'dark']) {
    push(mode, `${name}.onAccent`, `${name}.accent+wash`, 4.5,
         '选中 chip 的计数角标 (onFillWash 0.24 洗底后)', t[mode].onAccent, over(base.onFillWash[mode], t[mode].accent, 0.24));
    push(mode, `${name}.onAccent`, `${name}.accentText`, 4.5,
         '成员头像首字母压 accentText 填充', t[mode].onAccent, t[mode].accentText);
  }
}

// E6. SettingsView 图标选择器的四个预览块: 预览底是**写死的**渐变 (与真 PNG 同底色),
//     白勾压在写死的深色上 —— 这一组不在主题表里, 只能直接从 UI 文件解析, 否则改预览色没人知道。
const SV = path.join(__dirname, '..', 'App', 'UI', 'SettingsView.swift');
const svSrc = fs.readFileSync(SV, 'utf8');
const reIconBg = /bg:\s*\[Color\(hex:\s*0x([0-9a-fA-F]{6})\),\s*Color\(hex:\s*0x([0-9a-fA-F]{6})\)\]/g;
let iconHits = 0;
for (const im2 of svSrc.matchAll(reIconBg)) {
  iconHits++;
  // 名字取本条 IconOption 里最近的那个 name: (id 允许 nil = 默认图标)
  const before = svSrc.slice(0, im2.index);
  const nm = before.match(/IconOption\(id:\s*(?:nil|"[^"]*"),\s*name:\s*"([^"]*)"/g);
  const label = (nm && (nm[nm.length - 1].match(/name:\s*"([^"]*)"/) || [])[1]) || 'icon' + iconHits;
  push('both', 'white', `图标预览 ${label}.A`, 4.5, '预览块上的白符号压写死渐变亮端', 0xFFFFFF, parseInt(im2[1], 16));
  push('both', 'white', `图标预览 ${label}.B`, 4.5, '预览块上的白符号压写死渐变暗端', 0xFFFFFF, parseInt(im2[2], 16));
}
if (iconHits === 0) {
  // 2026-10-27 二轮: 备选 App 图标选择区已删（settings.appearance.icon），预览块不存在了。
  // 与节日色同一条纪律 —— 检查休眠而非移除：若将来 IconOption 预览块被加回来，
  // 上面的 matchAll 会重新命中，无需改代码。
  console.log('图标预览: 功能已移除 (SettingsView 无 IconOption 预览块), 本条检查休眠');
}

// ---------- 求值 ----------
let failed = 0;
const rows = [];


for (const a of ASSERTIONS) {
  const r = contrast(a.fgHex, a.bgHex);
  const ok = r >= a.min;
  if (!ok) failed++;
  rows.push({ mode: a.mode, pair: `${a.fg} on ${a.bg}`, ratio: r, min: a.min, ok, why: a.why });
}

if (verbose) {
  const pad = (s, n) => String(s).padEnd(n);
  console.log('\n设计令牌对比度 (WCAG 2.1)\n');
  console.log(pad('模式', 7) + pad('前景', 20) + pad('背景', 16) + pad('实测', 8) + pad('阈值', 7) + '说明');
  console.log('-'.repeat(100));
  for (const r of rows) {
    console.log(
      pad(r.mode, 7) + pad(r.pair.split(' on ')[0], 20) + pad(r.pair.split(' on ')[1], 16) +
      pad(r.ratio.toFixed(2) + ':1', 8) + pad(r.min.toFixed(1), 7) +
      (r.ok ? '✓' : '✗') + ' ' + r.why
    );
  }
  console.log('');
}

console.log(`基础令牌 ${Object.keys(base).length} 个 | 主题 ${Object.keys(themes).length} 套 | 断言 ${rows.length} 条 | 不达标 ${failed} 条`);
if (failed > 0) {
  console.error('\n✗ 对比度不达标 — 见上表 (--verbose 查看全表)。修改 DS.Palette 后必须重新核对。');
  process.exit(1);
}
console.log('✓ 全部对比度达标 (正文 4.5:1 / 非文本 3:1 / 分隔线 1.2:1, 含全部主题与 AMOLED)');
