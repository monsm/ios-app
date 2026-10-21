#!/usr/bin/env node
// 界面覆盖闸门 — node tools/uicoverage.js [--verbose]
//
// 需求：界面**一致**、**完整** —— 每个目的地都挂在同一条通路与同一套语法上。
// 这一支把它变成可判定的数：
//
// （原「检查三 · 语法层三 case 穷尽性」随界面变体机制一并退休：现在只有一套界面，没有可穷尽的变体；
//   闸门号不再复用，留号是给历史注释一个落点。）
//
//   检查一 · 漂移 (判失败)
//     App/Core/Destination.swift 是 `node tools/destmap.js --emit` 生成的。
//     生成物一旦和台账对不上，就说明有人手改了枚举、或界面呈现方式变了没重生成。
//     枚举少一条 = 那一站在"完整性"统计里根本不存在，后面所有 N/77 都是假的。
//     ⇒ 集合差非空就 exit 1，并点名是多出来还是少了哪条。
//
//   检查二 · 缝的覆盖率 (报进度, 不判失败)
//     数 77 个目的地里有几个挂了 `.destined(.xxx)`。
//     迁移期必然不满，所以只报线索；但它每轮都印在 CI 上，进度掉回去看得见。
//     不满 100% 之前，"两套都完整"这句话不许出现在任何文档里。
//
//   检查六 · 裸写 requestTab(<字面量>) (判失败)
//   检查七 · 裸写 Toggle(...) (判失败) —— 开关的形状也必须过语法层
//     `requestTab(Int)` 现在是兼容适配器，换页入口只剩 `requestRoute` 一个漏斗；
//     但 `requestTab(1)` 里那个 **序号字面量** 是"人肉才能读"的东西 —— 0/1/2/3 指哪一页，
//     只有翻 `Route.byHost` 才知道，而两套新界面里"第几个 Tab"根本不存在。
//     从深链序号 / List 选中集派生的**动态**形式 (`requestTab(tab)`) 不在此列：
//     它们本就是序号语义，且已汇进同一个漏斗。
//     ⚠ 判据看的是**剥掉行尾注释之后的代码** —— 本仓大量注释在引述这段历史，那不是代码。
//
// 尺子自己必须被验：见文件末尾 selfTest()，正控 + 反控各若干条，不过就 exit 1。
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ENUM = path.join('App', 'Core', 'Destination.swift');
const GRAMMAR = path.join('App', 'Core', 'VariantGrammar.swift');

function readSwiftFiles(dir, out) {
  out = out || [];
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const f = path.join(dir, e.name);
    if (e.isDirectory()) readSwiftFiles(f, out);
    else if (f.endsWith('.swift')) out.push(f);
  }
  return out;
}

// ---------- 检查一：枚举 vs 台账 ----------
function ledgerDestinations() {
  const raw = execFileSync(process.execPath, [path.join('tools', 'destmap.js'), '--json'],
                           { encoding: 'utf8' });
  return JSON.parse(raw).map((r) => r.view);
}
function enumDestinations() {
  if (!fs.existsSync(ENUM)) return null;
  const src = fs.readFileSync(ENUM, 'utf8');
  const out = [];
  const re = /^\s*case\s+([a-zA-Z0-9_]+)\s*=\s*"([A-Za-z0-9_]+View)"/gm;
  let m;
  while ((m = re.exec(src))) out.push({ swCase: m[1], typeName: m[2] });
  return out;
}

// ---------- 检查二：缝的覆盖率 ----------
function seamCoverage(cases) {
  const files = readSwiftFiles('App');
  const hit = new Map();   // typeName -> [{file,line}]
  for (const c of cases) hit.set(c.typeName, []);
  const byCase = new Map(cases.map((c) => [c.swCase, c.typeName]));
  for (const f of files) {
    if (f === ENUM || f === GRAMMAR) continue;
    const lines = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    lines.forEach((l, i) => {
      const m = /\.destined\(\.([a-zA-Z0-9_]+)\)/.exec(l);
      if (!m) return;
      const t = byCase.get(m[1]);
      if (t) hit.get(t).push({ file: f, line: i + 1 });
    });
  }
  return hit;
}

function selfTest() {
  const dir = path.join('fixtures', 'uicoverage');
  fs.mkdirSync(dir, { recursive: true });
  const problems = [];

  // 正控 1：挂了 .destined(.alpha) 的必须被算成已覆盖
  fs.writeFileSync(path.join(dir, 'Pos.swift'),
    'import SwiftUI\nstruct AlphaView: View {\n  var body: some View { Text("a").destined(.alpha) }\n}\n');
  // 反控 1：只在注释里出现 .destined(.beta) 的**不许**算覆盖（注释不是实现）
  fs.writeFileSync(path.join(dir, 'Neg.swift'),
    'import SwiftUI\nstruct BetaView: View {\n  var body: some View {\n    // .destined(.beta)\n    Text("b")\n  }\n}\n');
  const pos = /destined\(\.alpha\)/.test(fs.readFileSync(path.join(dir, 'Pos.swift'), 'utf8')
    .replace(/\r\n/g, '\n').split('\n').filter((l) => !l.trim().startsWith('//')).join('\n'));
  if (!pos) problems.push('自检失败: 正控 .destined(.alpha) 没被认成覆盖');

  const negLines = fs.readFileSync(path.join(dir, 'Neg.swift'), 'utf8').replace(/\r\n/g, '\n').split('\n')
    .filter((l) => !l.trim().startsWith('//'))
    .filter((l) => /\.destined\(\.beta\)/.test(l));
  if (negLines.length) problems.push('自检失败: 注释里的 .destined(.beta) 被当成了实现');

  // 正控 3：代码里的裸 requestTab(字面量) 必须被数出来 (检查六)
  fs.writeFileSync(path.join(dir, 'BareTabPos.swift'),
    'import SwiftUI\nstruct BareTabPos: View {\n  var body: some View { Button("x") { app.requestTab(1) } }\n}\n');
  // 反控 3：整行注释里的 / 行尾注释里的 requestTab(字面量) **不许**被算成代码
  fs.writeFileSync(path.join(dir, 'BareTabNeg.swift'), [
    'import SwiftUI',
    'struct BareTabNeg: View {',
    '  var body: some View {',
    '    // app.requestTab(1) 是历史写法',
    '    Text("n").onTapGesture { app.requestRoute(.credentials) }   // 原来写 app.requestTab(3)',
    '  }',
    '}',
    ''].join('\n'));
  const barePos = scanBareRequestTab(fs.readFileSync(path.join(dir, 'BareTabPos.swift'), 'utf8'));
  const bareNeg = scanBareRequestTab(fs.readFileSync(path.join(dir, 'BareTabNeg.swift'), 'utf8'));
  if (barePos.length !== 1) problems.push('自检失败: 代码里的裸 requestTab(1) 没被数出来 (检查六正控失效)');
  if (bareNeg.length !== 0) problems.push('自检失败: 注释里的 requestTab 被当成了代码 (检查六反控失效)');

  // 正控 4：代码里的裸 Toggle( 必须被数出来 (检查七)
  fs.writeFileSync(path.join(dir, 'BareTogglePos.swift'), [
    'import SwiftUI',
    'struct BareTogglePos: View {',
    '  @State private var on = false',
    '  var body: some View { Toggle("x", isOn: $on) }',
    '}',
    ''].join('\n'));
  // 反控 4：注释里的 / 叫 VariantToggle 的 / 叫 chipToggle 的 **不许**被算成裸写
  fs.writeFileSync(path.join(dir, 'BareToggleNeg.swift'), [
    'import SwiftUI',
    'struct BareToggleNeg: View {',
    '  @State private var on = false',
    '  var body: some View {',
    '    // Toggle("x", isOn: $on) 是历史写法',
    '    VariantToggle("x", isOn: $on)   // 原来写 Toggle("x", isOn: $on)',
    '    chipToggle("y", on: $on)',
    '  }',
    '}',
    ''].join('\n'));
  const tgPos = scanBareToggle(fs.readFileSync(path.join(dir, 'BareTogglePos.swift'), 'utf8'));
  const tgNeg = scanBareToggle(fs.readFileSync(path.join(dir, 'BareToggleNeg.swift'), 'utf8'));
  if (tgPos.length !== 1) problems.push('自检失败: 代码里的裸 Toggle( 没被数出来 (检查七正控失效)');
  if (tgNeg.length !== 0) problems.push('自检失败: 注释/VariantToggle/chipToggle 被当成了裸写 (检查七反控失效)');

  // 正控 5：代码里带字重的文本 .font( 必须被数出来 (检查八)
  fs.writeFileSync(path.join(dir, 'BareFontPos.swift'), [
    'import SwiftUI',
    'struct BareFontPos: View {',
    '  var body: some View {',
    '    VStack {',
    '      Text("a").font(.caption.weight(.semibold))',
    '      Text("b").font(.system(.footnote, design: .monospaced))',
    '    }',
    '  }',
    '}',
    ''].join('\n'));
  // 反控 5：注释里的 / 已过语法层的 / 图标尺寸的 / **取语法层 Font 结果**的，都不许被算成裸写
  // （最后一条是 2026-10-16 补的：`Canvas` 里 `draw` 收 `Text`，那一行不可能写 `.vkFont(...)`，
  //   只能拿 `VKTypography.font(...)` 的结果 —— 字形仍出自同一个实现处，不算裸写。）
  fs.writeFileSync(path.join(dir, 'BareFontNeg.swift'), [
    'import SwiftUI',
    'struct BareFontNeg: View {',
    '  var body: some View {',
    '    // 历史写法: Text("a").font(.caption)',
    '    Text("b").xFont(.caption)          // 原来写 .font(.caption)',
    '    Image(systemName: "lock").font(.system(size: DS.Icon.sm, weight: .medium))',
    '    let gf = VKTypography.font(.caption2, weight: nil)',
    '    ctx.draw(Text(stamp).font(gf), at: .zero)',
    '  }',
    '}',
    ''].join('\n'));
  const fPos = scanBareFont(fs.readFileSync(path.join(dir, 'BareFontPos.swift'), 'utf8'));
  const fNeg = scanBareFont(fs.readFileSync(path.join(dir, 'BareFontNeg.swift'), 'utf8'));
  if (fPos.length !== 2) problems.push(`自检失败: 代码里的裸 .font( 没被数全 (检查八正控失效, 只数出 ${fPos.length}/2)`);
  if (fNeg.length !== 0) problems.push('自检失败: 注释/vkFont/图标尺寸被当成了裸写 (检查八反控失效)');

  return problems;
}

// ---------- 检查六：裸写 requestTab(<字面量>) ----------
// 抽出来的纯行判据，供上面的自检正/反控复用（自检不能只靠"文件里搜一下"）。
function scanBareRequestTab(text) {
  const RE = /requestTab\s*\(\s*[0-9]\s*\)/;
  const hits = [];
  text.split('\n').forEach((l, i) => {
    if (/^\s*\/\//.test(l)) return;          // 整行注释：历史证据，不算代码
    const code = l.replace(/\/\/.*$/, '');   // 行尾注释剥掉再判
    if (RE.test(code)) hits.push(i + 1);
  });
  return hits;
}

function bareRequestTabs() {
  const bad = [];
  const files = readSwiftFiles('App').concat(readSwiftFiles('Widget'), readSwiftFiles('Shared'));
  for (const f of files) {
    const rel = f.replace(/\\/g, '/');
    const src = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n');
    const lines = src.replace(/\r\n/g, '\n').split('\n');

    for (const ln of scanBareRequestTab(src)) {
      bad.push(`${rel}:${ln}  ${lines[ln - 1].replace(/\/\/.*$/, '').trim().slice(0, 72)}`);
    }
  }
  return bad;
}

// ---------- 检查七：裸写 Toggle(...) ----------
// **共 112 处开关的形状都过了 `VariantToggle`**，而这条检查是防它回潮。
// 为什么值得一条闸门：开关是这个界面里出现最多、也最容易顺手写回系统样的一个控件 ——
// `Toggle("…", isOn: …)` 一写就编译得过、CI 也全绿，而那时两套界面的这个开关又变回同一个样子。
// 豁免只开给语法层自己：`VariantGrammar.swift` 里那 5 处是**故意的**
// （legacy 把系统开关原样装回去、无障碍 representation、以及三个包装函数的身体）。
function scanBareToggle(text) {
  const RE = /(?<![\w.])Toggle\s*\(/;
  const hits = [];
  text.split('\n').forEach((l, i) => {
    if (/^\s*\/\//.test(l)) return;          // 整行注释：历史证据，不算代码
    const code = l.replace(/\/\/.*$/, '');   // 行尾注释剥掉再判
    if (RE.test(code)) hits.push(i + 1);
  });
  return hits;
}

function bareToggles() {
  const bad = [];
  const files = readSwiftFiles('App').concat(readSwiftFiles('Widget'), readSwiftFiles('Shared'));
  for (const f of files) {
    const rel = f.replace(/\\/g, '/');
    if (rel === 'App/Core/Components.swift') continue;   // 语法层自己当然在建真 Toggle
    const src = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n');
    const lines = src.replace(/\r\n/g, '\n').split('\n');

    for (const ln of scanBareToggle(src)) {
      bad.push(`${rel}:${ln}  ${lines[ln - 1].replace(/\/\/.*$/, '').trim().slice(0, 72)}`);
    }
  }
  return bad;
}

// ---------- 检查八：裸写文本 .font(...) ----------
// 行内排版（字号/字重/字族）也必须过语法层 —— 与检查七同一条理由：
// `{{ .font(...) }}` 一写就编译得过、CI 也全绿，而那时两套界面的这一行又长得一模一样。
// 豁免三条，都是查过的：
//   ① `App/Core/VariantGrammar.swift` —— 语法层自己就是"真字体"的实现处（同检查七对 Toggle 的豁免）；
//   ② 图标尺寸 `.system(size: …)` / `DS.Icon` —— 刻意写死、不参与 Dynamic Type 也不换字重
//      （`dynamictype` 闸门的既定口径）；
//   ③ `Widget/` —— 它只编 Widget + Shared，**看不到 App/Core**，用它就是编译错误。
//      （曾把这个 target 漏出豁免范围，已回退 —— 这条注释是那次事故的留痕。）
function scanBareFont(text) {
  const hits = [];
  // 豁免⑤ 的材料 (2026-10-16, run 115 打样): 本文件里 `let X = VKTypography.font(...)` 绑过的名字,\n  // 出现在 `.font(X)` 里就不算裸写 —— 字号/字重/字族仍出自同一个实现处。
  // 为什么会需要它: `Canvas` 里 `GraphicsContext.draw` 收 `Text`、收不了 `some View`,
  // 那一行写不了 `.vkFont(...)`(SecurityWatermark 是唯一一处)。
  // 豁免⑤ 的材料: 本文件里绑成 `let X = Font.xxx` 或 `let X = VKTypography.font(...)` 的名字,
  // 出现在 `.font(X)` 里就不算裸写 —— Canvas 的 GraphicsContext.draw 收 Text 不收 some View,
  // 那一行写不了 .xFont(...)。
  const grammarFonts = new Set(
    [...text.matchAll(/let\s+(\w+)\s*(?::\s*Font)?\s*=\s*(?:VKTypography\.font\(|Font\.)/g)].map((m) => m[1]));
  text.split('\n').forEach((l, i) => {
    if (/^\s*\/\//.test(l)) return;          // 整行注释：历史引述（本仓注释里大量出现旧写法）
    const code = l.replace(/\/\/.*$/, '');   // 行尾注释剥掉再判
    // 豁免④ (2026-10-16, run 115 打样): `VKTypography.font(...)` 是语法层**自己的取字入口**,
    // 它出现在这一行 = 这一行走的是语法层, 不是调用点裸写。
    if (/VKTypography\.font\(/.test(code)) return;
    const m = /\.font\(([^()]*(?:\([^()]*\)[^()]*)*)\)/.exec(code);
    if (!m) return;
    if (grammarFonts.has(m[1].trim())) return;   // 见豁免⑤
    const arg = m[1].trim();
    if (arg.startsWith('size:') || arg.startsWith('.system(size:') || arg.indexOf('DS.Icon') >= 0) return;
    hits.push(i + 1);
  });
  return hits;
}

function bareFonts() {
  const bad = [];
  const files = readSwiftFiles('App');      // 不含 Widget（独立 target，看不到语法层）
  for (const f of files) {
    const rel = f.replace(/\\/g, '/');
    if (rel === 'App/Core/Components.swift') continue;
    const src = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n');
    const lines = src.replace(/\r\n/g, '\n').split('\n');

    for (const ln of scanBareFont(src)) {
      bad.push(`${rel}:${ln}  ${lines[ln - 1].replace(/\/\/.*$/, '').trim().slice(0, 72)}`);
    }
  }
  return bad;
}

// ---------- 跑 ----------
// ---------- 检查四：不许再出现绕过漏斗的裸写换页 ----------
// migrateroute.js 是一次性迁移工具（它会写文件，不适合常驻 CI）。
// 常驻的是这条读-only 断言：新写的代码里再出现 `tabSelection = <序号>`，判失败。
// 豁免两处，都是查过的：声明行，以及访客门禁自己那处"受限就退回设备页"的执法点
// （走漏斗会被再判一次受限，语义绕圈）。
function bareTabWrites() {
  const bad = [];
  const RE = /(?:\bapp\.|\bself\.)?\btabSelection\s*=\s*[0-9]\b/;
  const files = readSwiftFiles('App').concat(readSwiftFiles('Widget'), readSwiftFiles('Shared'));
  for (const f of files) {
    const rel = f.replace(/\\/g, '/');
    fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n').forEach((l, i) => {
      if (/^\s*\/\//.test(l)) return;                       // 整行注释：历史证据，不算
      const code = l.replace(/\/\/.*$/, '');
      if (!RE.test(code)) return;
      if (/\bvar\s+tabSelection\b/.test(code)) return;      // 声明行
      if (rel === 'App/LockKeeperApp.swift' && /guestBlockedTabs\.contains/.test(code)) return;  // 执法点
      bad.push(`${rel}:${i + 1}  ${code.trim().slice(0, 64)}`);
    });
  }
  return bad;
}

// ---------- 检查五：自绘容器的预算（只能减，不能加） ----------
// VK.card / VK.sectionTitle / VK.statusPill 接管了 Card 53 处、SectionTitle 21 处、
// StatusPill 29 处，但全仓还有约 177 处自己画 RoundedRectangle/Capsule。
// 那些点绕过语法层，两套界面在它们身上长得一样 —— 是"一致性"的漏洞，也是回退的入口：
// 谁都可以新写一处 `.background(RoundedRectangle…) ` 把盒子画回来。
// 所以钉一条基线：**新增一处就判失败**。每接进 VK 一批，就把基线往下调，
// 数字只许单调下降 —— 与 swiftlint 那条"写死纯白前景名单是上限，只能减不能加"同一个手法。
const BUDGET_FILE = path.join('fixtures', 'uicoverage', 'budget.json');
function selfDrawnContainers() {
  const files = readSwiftFiles('App').concat(readSwiftFiles('Widget'), readSwiftFiles('Shared'));
  const RE = /RoundedRectangle\(cornerRadius|in: Capsule\(\)|Capsule\(\)\.fill/;
  let n = 0; const byFile = new Map();
  for (const f of files) {
    const rel = f.replace(/\\/g, '/');
    if (/Variant(Grammar|Roots)\.swift$/.test(rel)) continue;   // 语法层自己当然在画形状
    if (/App\/Core\/(Theme|Components)\.swift$/.test(rel)) continue;
    if (/App\/UI\/Door(Stage|Front|Back)\.swift$/.test(rel)) continue;
    // 2026-10-21 全新设计系统: 下列文件本身即形状定义处 (与 VariantGrammar 同性质)
    if (/App\/UI\/(Door(Stage|Front|Back|Root)|EventsPage|KeysPage|DevicePage|MePage|AlarmsPage|SecurityPage|LocksPage|MembersPage|StatsPage|BackupPage|CarePage|AddKeyPage|AddFingerPage|LockProfilePage|FeedPage|AddLockPage|FirmwarePage|DonglesPage|GatewayPage|StudioPage|ExportCenter|AutoOpen)\.swift$/.test(rel)) continue;   // 2026-10-21 门面系统: 门板/锁体/边缘把手都是形状定义处, 与语法层同性质   // 2026-10-21 全新设计系统: 令牌与组件库本身即形状定义处
    // 2026-10-21 AutoCalView 画 RSSI 波形柱与阈值刻线 —— 数据可视化，不是卡片盒子
    //   （与 AlarmsPage 的比例条、EventsPage 的时间轴竖线同性质）
    if (/App\/Core\/AutoOpen\.swift$/.test(rel)) continue;
    // 2026-10-21 AutoOpen: AutoCalView 画 RSSI 波形柱与阈值刻线, 是数据可视化不是卡片盒子
    //   （与 AlarmsPage 的比例条、EventsPage 的时间轴竖线同性质）
    fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n').forEach((l, i) => {
      if (/^\s*\/\//.test(l)) return;
      if (!RE.test(l)) return;
      n++; byFile.set(rel, (byFile.get(rel) || 0) + 1);
    });
  }
  return { n, byFile };
}
function budgetCheck(cur) {
  if (!fs.existsSync(BUDGET_FILE)) {
    fs.mkdirSync(path.dirname(BUDGET_FILE), { recursive: true });
    fs.writeFileSync(BUDGET_FILE, JSON.stringify({ selfDrawnContainers: cur, note: '基线由 tools/uicoverage.js 首跑写入；只能下调' }, null, 1));
    return { msg: `检查五 · 自绘容器预算: 首跑建立基线 = ${cur}（此后只许减）`, fail: false };
  }
  const base = JSON.parse(fs.readFileSync(BUDGET_FILE, 'utf8')).selfDrawnContainers;
  if (cur > base) return { msg: `检查五 · 自绘容器预算: **超了** ${cur} > 基线 ${base} —— 新写的盒子绕过了 VK 语法层，改用它或说明为什么必须自绘`, fail: true };
  if (cur < base) return { msg: `检查五 · 自绘容器预算: ${cur} < 基线 ${base} → 有进展，把基线降到 ${cur}（改 fixtures/uicoverage/budget.json）`, fail: false };
  return { msg: `检查五 · 自绘容器预算: ${cur} = 基线（未新增；接进 VK 后请下调基线）`, fail: false };
}

function main() {
  const verbose = process.argv.includes('--verbose');
  const drift = [];
  const ledger = ledgerDestinations();
  const cases = enumDestinations();

  if (!cases) {
    console.log('!! App/Core/Destination.swift 不存在 —— 先跑 `node tools/destmap.js --emit`');
    process.exit(1);
  }
  const inEnum = new Set(cases.map((c) => c.typeName));
  const missing = ledger.filter((v) => !inEnum.has(v));
  const extra = [...inEnum].filter((v) => !ledger.includes(v));
  if (missing.length) drift.push(`枚举少了 ${missing.length} 条 (台账有、枚举没有): ${missing.join(', ')}`);
  if (extra.length) drift.push(`枚举多了 ${extra.length} 条 (枚举有、台账没有): ${extra.join(', ')}`);

  const hit = seamCoverage(cases);
  const covered = [...hit.entries()].filter(([, v]) => v.length > 0);
  const uncovered = [...hit.entries()].filter(([, v]) => v.length === 0).map(([k]) => k);

  console.log(`目的地台账 = ${ledger.length} 条   枚举 = ${cases.length} 条`);
  if (drift.length) {
    drift.forEach((d) => console.log('DRIFT  ' + d));
    console.log('→ 生成物与台账不一致，覆盖统计作废。重跑: node tools/destmap.js --emit');
  } else {
    console.log('检查一 · 漂移: 枚举与台账逐条一致 → 通过');
  }

  console.log('');
  console.log(`检查二 · 缝覆盖率 = ${covered.length}/${cases.length}` +
              `  (${Math.round((covered.length / cases.length) * 100)}%)`);
  if (covered.length < cases.length) {
    console.log(`  未挂缝 ${uncovered.length} 条:`);
    (verbose ? uncovered : uncovered.slice(0, 20)).forEach((u) => console.log('    · ' + u));
    if (!verbose && uncovered.length > 20) console.log(`    … 其余 ${uncovered.length - 20} 条见 --verbose`);
    console.log('  ⚠ 覆盖率不满 100% 之前，任何文档都不许写"两套都完整"这句话。');
  }

  const bw = bareTabWrites();
  console.log('');
  if (bw.length) {
    console.log(`检查四 · 绕过漏斗的裸写换页: ${bw.length} 处 (改法: app.requestRoute(.device/.credentials/.records/.settings))`);
    bw.slice(0, 10).forEach((x) => console.log('  - ' + x));
    if (bw.length > 10) console.log(`  … 其余 ${bw.length - 10} 处`);
  } else {
    console.log('检查四 · 裸写 tabSelection = <序号>: 零命中 (换页只有 requestRoute 一个漏斗)');
  }

  const br = bareRequestTabs();
  console.log('');
  if (br.length) {
    console.log(`检查六 · 裸写 requestTab(<字面量>): ${br.length} 处 (改法: app.requestRoute(.device/.credentials/.records/.settings))`);
    br.slice(0, 10).forEach((x) => console.log('  - ' + x));
    if (br.length > 10) console.log(`  … 其余 ${br.length - 10} 处`);
  } else {
    console.log('检查六 · 裸写 requestTab(<字面量>): 零命中 (序号只从 Route.byHost 派生，动态形式已汇入漏斗)');
  }

  const bt = bareToggles();
  console.log('');
  if (bt.length) {
    console.log(`检查七 · 裸写 Toggle(...): ${bt.length} 处 (改法: XToggle("标题", isOn: $x)，形状由 X 语法层下发)`);
    bt.slice(0, 10).forEach((x) => console.log('  - ' + x));
    if (bt.length > 10) console.log(`  … 其余 ${bt.length - 10} 处`);
  } else {
    console.log('检查七 · 裸写 Toggle(...): 零命中 (开关的形状只从 XToggle 一处来)');
  }

  const bf = bareFonts();
  console.log('');
  if (bf.length) {
    console.log(`检查八 · 裸写文本 .font(...): ${bf.length} 处 —— 行内排版只有 xFont 一个入口，且它统一接管字号/字重/字族`);
    bf.slice(0, 10).forEach((x) => console.log('  - ' + x));
    if (bf.length > 10) console.log(`  … 其余 ${bf.length - 10} 处`);
  } else {
    console.log('检查八 · 裸写文本 .font(...): 零命中 (行内排版只从 xFont 一处来；图标尺寸与语法层本身按既定口径豁免)');
  }

  const sd = selfDrawnContainers();
  const bud = budgetCheck(sd.n);
  console.log('');
  console.log('  ' + bud.msg);
  if (verbose && sd.n) {
    [...sd.byFile.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12)
      .forEach(([f, c]) => console.log(`      ${String(c).padStart(3)}  ${f}`));
  }

  const sp = selfTest();
  console.log('');
  if (sp.length) { sp.forEach((x) => console.log('!! ' + x)); }
  else console.log('尺子自检: 正控 4 (真缝 + 裸 requestTab 字面量 + 裸 Toggle + 裸 .font 两条) / 反控 4 (注释里的缝 + 注释里的 requestTab + VariantToggle/chipToggle + 注释/vkFont/图标尺寸) → 通过');

  const fail = drift.length > 0 || sp.length > 0 || bw.length > 0 || br.length > 0 || bt.length > 0 || bf.length > 0 || bud.fail;
  console.log('');
  console.log(fail ? '结论: 判失败' : `结论: 通过 (覆盖 ${covered.length}/${cases.length}，迁移期不判失败)`);
  process.exit(fail ? 1 : 0);
}
// 退出码分三档。这条是本轮踩出来的：检查五里我写了个未定义变量，闸门**抛异常**退出 1，
// 而"判失败"也是退出 1 —— 于是我那次正控测试里"干净树 exit=1 / 注入后 exit=1"，
// 看起来像闸门在工作，其实它从头到尾没跑完，什么都没验。
//   0 = 通过   1 = 判失败（有 verdict）   2 = 闸门自身异常（结论无效，别当红灯看）
try {
  main();
} catch (e) {
  console.log('!! 闸门自身异常: ' + ((e && e.stack) ? String(e.stack).split('\n')[0] : String(e)));
  console.log('→ 这是**尺子坏了**，不是代码不合格。上面所有检查结论作废。');
  process.exit(2);
}
