// tools/layout-audit/rules.js —— 布局算术判据
// 与 dynamictype.js 的分工：那道查"单行写法"(.system(size:)/lineLimit/minHeight)，这里做**跨行算术**:
//   R1 横向预算超支   同一 HStack 里所有"固定宽"子项 + 间距 > 可用宽 ⇒ 必有一项被挤/被切
//   R2 文字宽度估算   Text 按 CJK≈1em、拉丁≈0.55em、数字≈0.5em 估宽，超过可用宽且单行 ⇒ 静默截断
//   R3 间距脱离令牌   spacing/padding 的数字不在 Space×密度 的档上 ⇒ 节奏乱 (看着"随便")
//   R4 纵向堆叠密度   一屏 VStack 模块数与累计高度 vs 视口高 ⇒ "要滚几屏"
//   R5 触达推断       无显式 frame 时由 padding + 行高反推命中框 (< 44 才报)
//   R6 材质一致性     同屏实底/玻璃/material 混用数 ⇒ 层感不统一的量化指标
// 每条都带"算式"，人可复核；解析不出的值一律 **不判**（宁可漏报也不制造假警报）。
'use strict';
const fs = require('fs');
const A = require('./ast.js');

// R6 定性豁免: 实底面板**判定要留痕**, 所以不靠"我记得这处是故意的"。
// 源码里在它上方 6 行内写 `@layout-allow 面板实底` ⇒ 这条从"混用缺陷"改记为"已定性保留"，
// 仍出现在报告里 (计数看得见)，只是不再算进层感不统一。标记离了位就重新开火。
const lineCache = new Map();
function srcLines(file) {
  if (!lineCache.has(file)) {
    let L = [];
    try { L = fs.readFileSync(file, 'utf8').split(/\r?\n/); } catch (e) { L = []; }
    lineCache.set(file, L);
  }
  return lineCache.get(file);
}
function allowedNear(lines, ln, tag) {
  const re = new RegExp('@layout-allow\\s+' + (tag || '面板实底'));
  for (let i = Math.max(0, ln - 8); i < Math.min(lines.length, ln); i++) if (re.test(lines[i])) return true;
  return false;
}

// 文字宽度估算: 中日韩全角 = 1em; 拉丁/数字 ≈ 0.55em; 空格 ≈ 0.3em; 标点 ≈ 0.5em
function textWidth(s, pt) {
  let em = 0;
  for (const ch of s) {
    if (/[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]/.test(ch)) em += 1;
    else if (/[A-Za-z]/.test(ch)) em += 0.56;
    else if (/[0-9]/.test(ch)) em += 0.5;
    else if (ch === ' ') em += 0.28;
    else em += 0.5;
  }
  return em * pt;
}
function linePt(s) { return s * 1.21; }   // SF/PingFang 行高近似
// 字体: 语义字号 → pt (Apple Large 档), 再乘 App 字号档倍数与 Dynamic Type
function fontPt(e, scale, dyn) {
  const fm = A.mod(e, 'font');
  let pt = null, semantic = null;
  if (fm) {
    const t = (fm.args._ || []).join(' ') + ' ' + JSON.stringify(fm.args);
    const m = /size:\s*(\d+(?:\.\d+)?)/.exec(t);
    if (m) pt = +m[1];
    for (const k in A.FONT_PT) if (new RegExp('\\.' + k + '\\b').test(t)) { pt = A.FONT_PT[k]; semantic = k; break; }
  }
  if (pt == null) pt = A.FONT_PT.body;
  return { pt: pt * scale * (dyn || 1), semantic, explicitSize: !!(A.mod(e, 'font') && /\bsize:/.test(JSON.stringify(A.mod(e, 'font').args))) };
}
// 沿祖先链累计要扣掉的宽度: 页面 gutter、各级 padding 的水平分量、显式 frame 宽
function availWidth(node, deviceW, tk, dens) {
  let w = deviceW, chain = [], n = node, guard = 0;
  const index = new Map();
  while (n) { index.set(n, true); n = n.parent && n.parent.el; }
  // 往上找容器与自身修饰符
  let cur = node;
  while (cur && guard++ < 40) {
    (cur.mods || []).forEach((m) => {
      if (m.name === 'padding') {
        const first = (m.args._ || [])[0];
        const horizontal = first && /\.horizontal|\.all/.test(first) || first == null;
        const v = A.num(first && /\.horizontal|\.all|\.vertical/.test(first) ? (m.args._ || [])[1] : first, tk, dens);
        if (horizontal && v != null) w -= 2 * v;
      }
      if (m.name === 'frame') {
        const fw = A.num(m.args.width, tk, dens), mn = A.num(m.args.minWidth, tk, dens);
        if (fw != null) w = Math.min(w, fw); else if (mn != null) w = Math.min(w, Math.max(w, mn));
      }
      if (m.name === 'safeAreaInset' || m.name === 'ignoresSafeArea') chain.push(m.name);
    });
    cur = cur.parentEl;
  }
  // 页面级 gutter 只在"外层没有任何自带水平内缩的容器"时才扣。
  // List/Form/Section/Card 本身已给水平内缩，再扣一次 2×gutter 会把可用宽算成 18pt 这种不可能值
  // (上一版就是这么错的: 941 条里一大半来自这里 + 把"多行换行"当缺陷)。
  let anc = node, hop2 = 0, hasInset = false;
  while (anc && hop2++ < 24) { if (['List', 'Form', 'Section', 'Card'].includes(anc.name)) { hasInset = true; break; } anc = anc.parentEl; }
  if (!hasInset) w -= 2 * (tk.SPACE.gutter != null ? A.num('DS.Space.gutter', tk, dens) : 16);
  return Math.max(0, Math.round(w * 10) / 10);
}
function ownMods(e, names) { return e.mods.filter((m) => names.includes(m.name)); }
function childFixedWidth(c, tk, dens) {
  const fr = A.mod(c, 'frame');
  if (fr) { const w = A.num(fr.args.width, tk, dens); if (w != null) return { w, why: 'frame(width:' + fr.args.width + ')' }; }
  const im = c.name === 'Image';
  const fr2 = A.mod(c, 'frame');
  if (im && !fr) return { w: 24, why: 'Image 图标默认档 ≈24' };
  if (c.name === 'Spacer') return null;
  const mn = fr && A.num(fr.args.minWidth, tk, dens);
  if (mn != null) return { w: mn, why: 'frame(minWidth:' + fr.args.minWidth + ')' };
  return null;
}
function parseAll(files, tk, dens, cache) {
  const out = [];
  for (const f of files) { const k = f + '|@|' + dens; if (!cache[k]) { const d = { file: f, ...A.parseFile(f, tk, dens) }; cache[k] = d; } out.push(cache[k]); }
  return out;
}
function runAll(preparsed, opts) {
  const { tk, scale = 1.0, deviceW = 390, dens = 1.0 } = opts;
  const findings = [];
  const push = (f) => findings.push(f);
  for (const { file, nodes, errors } of preparsed) {
    // 建 parent 元素引用 (flatten 时只存了 name/line, 这里回连)
    const errUI = errors.filter((e) => e.ui), errLogic = errors.filter((e) => !e.ui);
    if (errUI.length) push({ rule: 'R0 覆盖缺口', file, line: errUI.map((e) => e.line).join(','), msg: `${errUI.length} 处 tree-sitter 解析失败且区域内有呈现面, 该文件这些区域未参与布局判定`, calc: errUI.map((e) => e.kind + '@' + e.line).join(' ') });
    if (errLogic.length) push({ rule: 'R0 文法盲区·无呈现面', file, line: errLogic.map((e) => e.line).join(','), sev: 'lo', msg: `${errLogic.length} 处解析失败但区域内没有视图 (do-catch/成员级 #if/try? await 条件位), 布局判定不受影响`, calc: errLogic.map((e) => e.kind + '@' + e.line).join(' ') });

    nodes.forEach((e) => {
      const avail = availWidth(e, deviceW, tk, dens);
      // ---- R1 横向预算 ----
      if (e.name === 'HStack') {
        const sp = A.num(e.args.spacing, tk, dens);
        const spacing = sp == null ? 8 : sp;
        let fixed = 0, det = [], flex = false;
        e.children.forEach((c) => {
          if (c.name === 'Spacer' || c.name === 'Text' || A.mod(c, 'frame')) { if (c.name === 'Spacer') { flex = true; return; } }
          const f = childFixedWidth(c, tk, dens);
          if (f) { fixed += f.w; det.push(`${c.name}:${f.w}`); }
        });
        const n = e.children.length;
        const gap = n > 1 ? spacing * (n - 1) : 0;
        if (flex && fixed + gap > avail) {
          push({ rule: 'R1 横向挤爆', file, line: e.line, msg: `HStack ${n} 个子项，固定部分 ${det.join('+')}=${fixed} + 间距 ${gap} = ${fixed + gap}pt > 可用 ${avail}pt`, calc: `可用宽 ${avail} (机宽 ${deviceW}−gutter−祖先padding)`, sev: 'hi' });
        } else if (!flex && n > 0 && fixed + gap > avail) {
          push({ rule: 'R1 横向挤爆', file, line: e.line, msg: `HStack 无 Spacer，子项合计 ${fixed}+${gap}=${fixed + gap}pt > 可用 ${avail}pt`, calc: det.join('+'), sev: 'hi' });
        }
      }
      // ---- R2 文字宽度 ----
      if (e.name === 'Text' || e.name === 'Label') {
        const raw = (e.args.__text || '').replace(/\\\([^)]*\)/g, '〇');
        if (raw.trim()) {
          const { pt } = fontPt(e, scale, 1);
          const lm = A.mod(e, 'lineLimit');
          const single = lm && /^(1|\d)$/.test((lm.args._ || [])[0] || '') && +((lm.args._ || [])[0]) === 1;
          const wEst = textWidth(raw, pt);
          const hasFixed = !!childFixedWidth(e, tk, dens);
          const cap = hasFixed ? childFixedWidth(e, tk, dens).w : avail;
          if (single && wEst > cap * 1.08) {
            push({ rule: 'R2 单行放不下', file, line: e.line, msg: `「${raw.slice(0, 22)}」估宽 ${Math.round(wEst)}pt > 可分配 ${Math.round(cap)}pt (字号 ${pt.toFixed(1)}pt, lineLimit(1))`, calc: `CJK=1em 拉丁=0.56em 数字=0.5em`, sev: 'hi' });
          } else if (!single) {
            // 只有"祖先把高度写死了"才算缺陷: 多行换行本身是设计, 不是问题 (上一版把每条长文案都报成噪声)
            let anc = e.parentEl, hop = 0, fixedH = null, fh = null;
            while (anc && hop++ < 12) { const fr2 = A.mod(anc, 'frame'); if (fr2) { const v = A.num(fr2.args.height, tk, dens); if (v != null) { fixedH = v; fh = fr2.args.height; break; } } anc = anc.parentEl; }
            const need = Math.ceil(wEst / Math.max(cap, 1)) * linePt(pt);
            if (fixedH != null && need > fixedH * 1.08) {
              push({ rule: 'R2 高度写死装不下', file, line: e.line, msg: `「${raw.slice(0, 20)}」需 ${Math.ceil(wEst / Math.max(cap,1))} 行 ≈ ${Math.round(need)}pt，但祖先 frame(height: ${fh}) 写死 ${fixedH}pt ⇒ 溢出/裁切`, calc: `可分配宽 ${Math.round(cap)} 行高 ${linePt(pt).toFixed(1)}`, sev: 'hi' });
            }
          }        }
      }
      // ---- R3 间距脱离令牌 ----
      // 判"字面量是否脱档"必须用**基准档**：写死的 4pt 就是 xs，跟用户当前密度无关。
      // 上一版按 density 缩放后的档去比，于是"宽松档下 DS.Space.xs=4.5 ≠ 字面量 4"把 2pt/4pt 全误报成脱档 (68 条假警报)。
      const legal = new Set(Object.values(tk.SPACE));
      legal.add(0);
      const legalNow = new Set(Object.values(tk.SPACE).map((v) => Math.round(v * dens * 2) / 2));
      legalNow.add(0);
      ownMods(e, ['padding']).forEach((m) => {
        const cand = m.args._ || [];
        const raw = cand.length > 1 && /^[.]?(horizontal|vertical|edge|edges)/.test(cand[0] || '') ? cand[1] : cand[0];
        if (raw == null) return;
        if (/^DS\.Space\./.test(raw)) return;                 // 走令牌本身就是对的，别拿密度去难为你自己
        const v = A.num(raw, tk, dens);
        if (v != null && !legal.has(v)) push({ rule: 'R3 间距脱离令牌', file, line: m.line, msg: `${e.name}.padding(${v}pt) 不在 Space 档 (${[...legal].sort((a, b) => a - b).join('/')})`, calc: raw, sev: 'md' });
      });
      if (['VStack', 'HStack', 'ZStack', 'LazyVGrid', 'LazyHGrid'].includes(e.name)) {
        const spRaw = e.args.spacing;
        if (spRaw != null && !/^DS\.Space\./.test(spRaw)) {
          const v = A.num(spRaw, tk, dens);
          if (v != null && !legal.has(v)) push({ rule: 'R3 间距脱离令牌', file, line: e.line, msg: `${e.name}(spacing: ${v}pt) 不在令牌档`, calc: spRaw, sev: 'md' });
        } else if (spRaw == null && e.name !== 'ZStack') {
          // ZStack 默认 0 且多为叠放, 不要求声明; VStack/HStack 默认吃系统 8pt ⇒ 那是"第三套间距", 必须写明
          push({ rule: 'R3 间距未声明', file, line: e.line, msg: `${e.name} 没写 spacing ⇒ 吃系统默认 (不可控的第三套间距)`, calc: '—', sev: 'lo' });
        }
      }
      // ---- R5 触达推断 (无显式 frame 时由内容反推) ----
      const inter = A.hasInteractive(e);
      const inSysRow = (function up(n, d2) { while (n && d2 < 12) { if (['List','Form','Section'].includes(n.name)) return true; n = n.parentEl; d2++; } return false; })(e, 0);
      // Menu 的**内容项**由系统排版 (UIKit 菜单单元自带行高), 给 label 撑 minHeight 不改命中区,
      // 只会把菜单撑高 —— 所以严格后代不判。但 Menu **触发器本身**照判 (AchievementsView:131 那种
      // 一整条只有 14.5pt 的触发胶囊是真缺陷), 它不是自己的后代。
      const inMenuContent = (function up(n, d2) { n = n.parentEl; while (n && d2 < 14) { if (n.name === 'Menu') return true; n = n.parentEl; d2++; } return false; })(e, 0);
      if (inter && !inMenuContent && !(inSysRow && ['Picker','Stepper','Menu','Toggle','Slider','TextField','SecureField','NavigationLink'].includes(e.name))) {
        // 按钮的命中尺寸由 **label 子节点**决定 (本仓普遍写在 label 里: .frame(minHeight: DS.Hit.min))
        // ⇒ 只看自己的 mods 会把 52 处全判成假警报 (AlarmCenterView:416 就是这么被冤枉的)。
        // 链上有多枚 frame 时取**最外那一枚** (源序最后一个): `.frame(minHeight:30)` 里再套
        // `.frame(minHeight:44)` 是"视觉小、命中大"的写法, 起作用的正是外面那枚; 取 max 会把
        // 反过来写 (外小内大) 的真缺陷藏起来。
        const self = (n) => {
          const frs = (n.mods || []).filter((m) => m.name === 'frame');
          if (!frs.length) return null;
          const fr = frs[frs.length - 1];
          const v = A.num(fr.args.height, tk, dens);
          return v != null ? v : A.num(fr.args.minHeight, tk, dens);
        };
        const descendants = (n, acc = []) => { n.children.forEach((c) => { acc.push(c); descendants(c, acc); }); return acc; };
        let h = self(e);
        const kidsH = descendants(e).map(self).filter((v) => v != null);
        if (h == null && kidsH.length) h = Math.max(...kidsH);
        const shaped = descendants(e).some((c) => A.mod(c, 'contentShape')) || !!A.mod(e, 'contentShape');
        // 与 R6 同一条豁免纪律: 标了 @layout-allow 触达 的 (系统控件本体高度不归我们管那一族) 不改判成"已修",
        // 而是单列一条"已定性"—— 计数看得见, 复测方法写在源码注释里, 标记挪走立刻重新开火。
        const allowHit = allowedNear(srcLines(file), e.line, '触达');
        if (h != null && h < tk.HIT) push({ rule: allowHit ? 'R5 触达已定性' : 'R5 触达不足', file, line: e.line, msg: `${e.name} 命中框高 ${h}pt < ${tk.HIT}pt`, calc: 'frame(height/minHeight)', sev: allowHit ? 'lo' : 'hi' });
        else if (h == null && !shaped) {
          // 原实现只看**直接子节点**里的 Text ⇒ label 写成 HStack { Image; Text } 那种 (菜单触发器/图标按钮)
          // 整个跳过, 触发器只有 14.5pt 也报不出来。改为在后代里找第一枚 Text 估行高。
          const kid = (function first(n) {
            for (const c of n.children || []) { if (c.name === 'Text') return c; const g = first(c); if (g) return g; }
            return null;
          })(e);
          const padOf = (n) => (n.mods || []).filter((m) => m.name === 'padding').map((m) => { const c = m.args._ || []; return A.num(c.length > 1 ? c[1] : c[0], tk, dens) || 0; }).reduce((a, b) => a + b, 0);
          // 原实现只看 e 自己的 padding ⇒ "padding 写在 label 里面那种"被低估成纯行高 (假警报)。
          // 沿 parentEl 从文字收到本节点, 链上每层 padding 都算进去。
          let pv = 0;
          if (kid) { let n = kid, d3 = 0; while (n && d3 < 14) { pv += padOf(n); if (n === e) break; n = n.parentEl; d3++; } }
          const { pt } = fontPt(kid || e, scale, 1);
          const est = linePt(pt) + pv;
          if (kid && est < tk.HIT - 0.5) push({ rule: allowHit ? 'R5 触达已定性' : 'R5 触达不足(推算)', file, line: e.line, msg: `${e.name} 自身与 label 都没有 frame/minHeight、也没有 contentShape ⇒ 命中高仅约 ${est.toFixed(1)}pt < ${tk.HIT}pt`, calc: '行高+padding 反推', sev: allowHit ? 'lo' : 'md' });
        }
      }
      // ---- R6 材质一致性 ----
      // 2026-10-14 修: 原实现只在 `background` 这一枚修饰符的参数文本里找 "axGlass"，于是
      // `.axGlass(DS.Radius.card)` (链式修饰符, 不是 background 的参数) **永远数不进玻璃列** ——
      // Card 改玻璃之后各文件仍报"玻璃 0 处"，这一条指标是空的。现在按修饰符名判。
      const bg = (e.mods || []).filter((m) => m.name === 'background');
      bg.forEach((m) => {
        const t = JSON.stringify(m.args);
        // 面板级实底 = 满不透明的 Palette.surface; surfaceAlt 是"玻璃面上的盘子", 本仓口径里它不是面板。
        // 原实现把两者一起算 ⇒ 一个只画了几枚小盘子的文件也被报成"层感不统一"，指标没人信。
        const panel = /Palette\.surface(?!Alt)/.test(t), plate = /Palette\.surfaceAlt/.test(t);
        const material = /Material/.test(t);
        if (panel && !/axGlass|glassEffect|Glass/.test(t)) {
          if (allowedNear(srcLines(file), m.line)) e.__allow = true; else e.__solid = true;
        }
        if (plate) e.__plate = true;
        if (material) e.__mat = true;
      });
      (e.mods || []).forEach((m) => {
        // axGlass / axGlassCircle / axGlassCapsule / glassEffect = 玻璃面;
        // card = CredentialStudio 的 .card() 卡片面 (内部就是 axGlass, 分析器看不见函数体, 按名认)
        if (/^(axGlass|axGlassCircle|axGlassCapsule|glassEffect)$/.test(m.name) || m.name === 'card') e.__glass = true;
      });
    });
    const solid = nodes.filter((n) => n.__solid).length, glass = nodes.filter((n) => n.__glass).length,
      mat = nodes.filter((n) => n.__mat).length, plate = nodes.filter((n) => n.__plate).length,
      allow = nodes.filter((n) => n.__allow).length;
    // 只有"还有面板级实底"才开火: 纯玻璃文件不是缺陷 (那正是目标), 只有小盘子的文件也不是。
    // 玻璃>0 时是同一屏两种层感 (md); 玻璃=0 时这一页一块面板玻璃都没有 (lo, 待逐页推)。
    if (solid > 0) push({
      rule: 'R6 材质混用', file, line: '文件级', sev: glass > 0 ? 'md' : 'lo',
      msg: `面板级实底 ${solid} 处 / 玻璃 ${glass} 处 / 盘中 plate ${plate} 处 ⇒ ` + (glass > 0 ? '同文件两种层感' : '这一页还没有面板玻璃'),
      calc: `glass 占比 ${(glass / (solid + glass) * 100).toFixed(0)}% (盘子不计入分母)`,
    });
    // 已定性的那些也照样报一条: 隐藏起来的豁免等于没有豁免
    if (allow > 0) push({
      rule: 'R6 材质已定性', file, line: '文件级', sev: 'lo',
      msg: `已定性保留的面板实底 ${allow} 处 (源码里带 @layout-allow 面板实底 标记) / 玻璃 ${glass} 处`,
      calc: '理由写在标记上方注释里, 不计入混用',
    });
  }
  return findings;
}
module.exports = { runAll, parseAll, textWidth, fontPt, availWidth, linePt };
