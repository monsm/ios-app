#!/usr/bin/env node
// tools/swiftshape.js — Swift 形状机检 (第一百三十七批新增, **判失败**)
//
// 为什么这道闸门存在：Actions 上 run 43 (2026-10-07) 之后连红四场 (44–47)，失败都落在
// 「编译校验测试目标」，而本地那 14 道 node 闸门没有一道能替代编译器 —— 括号平了、名字眼熟就一路绿。
// 这一道抓的是**不需要类型推导就能定形**的四类编译错误 (R1/R2/R4/R5)，外加一条只许减不许增的棘轮 (R3)：
//
// R1  声明为 `: some View` / `-> some View` 的成员，体内有**顶层 if 而没有 else、也没有 return**，
//     却缺 `@ViewBuilder` ⇒ "function declared as returning 'some View' … non-disclosure body"。
//     本仓真实命中 3 处：RecordsTimeline/credJumpSection、RecordsView/firstDayFooter、
//     SettingsView/autoOpenSection —— 最后那处正是 run 47 那次提交带进来的形状。
// R2  `@ViewBuilder` 归属的**那一条声明**带着显式类型，而类型落在一张"值类型"短名单里
//     (String / Int / Bool / Date / 数组 / 闭包…) ⇒ 结果构建器把 body 包成 buildBlock(...)，
//     与声明类型对不上。本仓真实命中 1 处：属性被插到一段 /// 文档注释**之前**，
//     于是挂到了返回 String? 的 timeWords 身上。
//
// R3  **棘轮** (只许减不许增): 持久化 struct 靠合成 Codable 解码, 却带着"非 Optional + 有默认值"
//     的字段 ⇒ 下一次给它加字段就会让旧 JSON keyNotFound。数量超过基线才判失败, 详见 r3() 上方。
//
// R1b (第一百八十九批新增, run 56 打样): 声明 some View 的成员, body **顶层以 let/var 绑定起头**、
//     末尾一个表达式、又没有 return —— 一个 if 都没有, 纯 R1 的 if 判据永远看不见它。
//     编译器报 "function declares an opaque return type, but has no return statements"。
//     本仓真实命中 2 处: LockCompareView/rhythmSection、StatsView/memberLines (均已修)。
//
// R6  (第一百八十九批新增, run 57 打样): 函数**没有** `-> 返回类型` (= Void), 却被当 View 用
//     (两个信号: 带 @ViewBuilder, 或 body 里写了 Section/HStack 等视图构造) ⇒
//     "type '()' cannot conform to 'View'"。⚠ 关键反直觉: @ViewBuilder **不改变返回类型** ——
//     `@ViewBuilder func foo()` 只是把语句拼成 Void, 只有写了 `-> some View` 才真产出视图
//     (Apple 文档 "Marking methods with the result builder" 的示例一律带 `-> some View`)。
//     本仓真实命中: AlarmCenterView 两处 (contextSection 无 builder / detailSection 有 builder 无箭头)
//     + StatsView 15 处 (`@ViewBuilder private func xxxSection(_ m:)` 全族) —— 全都在 CI 报出前
//     从未被编到 (编译总在前面就停), 一次 run 57 全冒出来。
//
// R7  (第一百九十批新增, run 58 打样): 同一条声明挂了两个 @ViewBuilder ⇒
//     "only one result builder attribute can be attached to a declaration"。
//     起因: 修 R6 那批时按注释回看找 @ViewBuilder, 注释挡住了更上面那一个, 于是又加了一个。
//     参数属性 (@ViewBuilder dest: () -> some View) 不算重复, 判据只比"连续两行整行只有 @ViewBuilder"。
//
// R8/R9/R10/R11 (第一百九十二批新增, run 59 打样): 四类"名字眼熟 + 括号平衡 ⇒ 前 24 道闸门全绿、
//     只有编译器看得穿"的写法。它们的共同教训是**系统性写法** —— 编译每次只暴露一处 (前面先停),
//     一次 run 只能改一处, 于是永远追不完; 机器一次扫全才有意义。
//  R8  `Section("<字符串字面量>") { } footer: { }` —— 不是合法重载。多尾随闭包匹配时, 未加标签的
//      那个先去找第一个能收闭包的参数; 撞上"首参就是闭包"的重载时, 字符串字面量被当成 `() -> Content`
//      ⇒ "missing argument label 'content:'"。合法写法只有三段式 `Section { } header: { } footer: { }`。
//      run 59 全仓 6 处 (AutoOpen / DiagnosticsView×4 / SettingsView), 一次改净。
//  R9  `Section(isExpanded:content:header:)` 这一重载**没有 footer 参数**, 加 footer 报
//      "extra trailing closure passed in call" (run 59 的 DeviceManageView:62)。
//  R10 `.frame(minHeight:maxWidth:)` 次序反了 ⇒ "argument 'maxWidth' must precede argument 'minHeight'"
//      (run 59 的 HelpCenter, 同形状 4 处)。签名次序 maxWidth 在 minHeight 之前。
//  R11 `as: UTF8` 缺 `.self` ⇒ "expected member name or initializer call after type name"
//      (run 59 的 ExportCenter×3)。只认编码类型短名单, 避免误伤 `as: SomeProtocol`。
//
// R12 (第二百零八批新增, **真机首启白屏**打样): `extension View` 里的方法返回 `some View`, 却
//     **从不引用 self** ⇒ `X.f()` 的结果是函数体里那个视图, X 整个不见了。编译器不拦 (合法 Swift,
//     不报错也不警告), 症状只在跑起来之后才现: 编译全绿、装到手机打开 App 一片空白。
//     真身: `dsScreenBackground()` 只返回一层渐变, 全仓 99 处调用点 ⇒ 每页只剩底色。
//     反控: 对 self 调修饰符 (`background{}` / `modifier(…)` / `offset(…)` 这些**不带接收者**的调用
//     就是 `self.` 的省略) 与显式写 `self` 的都放过。
//
// R4  调用点的**参数标签**与声明对不上 (第一百四十八批新增)：Swift 的标签是逐字匹配的，
//     少写、多写、写错一个都不过编译，而名字眼熟 + 括号平衡让它一路通过前面所有闸门。
//     落地当批即在现网抓到 **13 处**：只判首参那版抓到 10 处 —— RecordSearch.oid(mac:rowKey:) 被 6 处按位置调用、
//     StatsView.legendRow(_ labels:) 被 1 处写成 labels:、LinkSense.successRateText(mac:) 1 处、
//     RecordSearch.unhandledAlarmCount(macs:) 2 处；改成**逐位判**之后又抓到 3 处
//     (CredentialStudio 把 CredentialOrg.firstUse/usageCount/openCountInWindow 的第二参标签 `p:` 全省了)。
//     判据、两条豁免，以及"实例调用试过又撤掉"那条写在 r4() 上方。
//
// R5  实参**个数**与声明对不上 (第一百五十一批新增，与 R4 共用同一条流水)：`missing argument` /
//     `extra argument in call`。只判"参数表里既没有默认值、也没有闭包类型参数"的声明 ——
//     那种函数写不出尾随闭包、也省不掉任何一参，括号里的个数是定死的。
//     本批现网 0 命中 (那 13 处都是标签问题，没有个数问题)，但两条正控常驻 `fire/Arity.swift`
//     (少参、多参各一条)，反控 `ok/Arity.swift` 专放"尾随闭包"与"带默认值"两种看起来少一个的合法写法。
//     加它的过程反手打出自家判据的两个 bug (`->` 里那个 `>` 被当括号，把参数表在 `(Int` 处截断；
//     零参声明不登记，于是同名重载把**定义处**读成"少传一参"的调用点) —— 都记在 §10.23。
//     "没见过自己开火的尺子不算尺子"，本仓第二次被同一句话救回来。
//
// 三条刻意的豁免边界，写清楚而不是假装没有：
//  · `var body: some View` 与 ViewModifier 的 `func body(content:)` 不检 —— 协议自己带
//    @ViewBuilder，实现处不写也合法；算进来就是 8 条噪音。
//  · 判不了就不报：目标声明没写显式类型 (`@ViewBuilder private func trendSection(_ m:) {`) 时，
//    它靠 Swift 的隐式 opaque 返回类型推导，本机没编译器无从定论。StatsView 里这种形状有十几处，
//    既不动也不报，留给下一次真编译 (§10.11 记着这条)。
//  · R2 只认"值类型短名单"：想证明"这不是 View"要的是全知 —— `@ViewBuilder var content: Content`
//    (Content: View 的泛型内容槽) 完全合法，把它当误报会让闸门变成噪音机。
//
// 判据自己先过正控：`--selftest` 拿 fixtures/swiftshape/ 里"该响的"与"不该响的"两组样例各跑一遍，
// 三条判据都各有正控 (R3 的第一版看不见单行写完的小 struct —— 是注入探针 `App/_probe_r3.swift` 一测就不响才发现的)；
// 打不响或误响就退出 2 (本仓在 changelogcheck / keydead 上都验证过这条纪律)。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'Widget', 'Tests'];
const VIEW_DECL = /^(\s*)(?:private |public |fileprivate |internal )?(?:static )?(?:@\w+ )?(?:var|func)\s+[\w<>]+(?:\([^)]*\))?\s*(?::|->)\s*some\s+View\s*\{\s*$/;
const DECL_HEAD = /^(?:@\w+\s+)*(?:private |public |fileprivate |internal |static |final )*(var|func)\b/;
const VALUE_TYPE = /^(?:\s*\?)?(String|Int\d*|UInt\d*|Double|Float|CGFloat|Bool|Date|Data|URL|Error|[([{])/;

function swiftFiles(root) {
  const out = [];
  if (!fs.existsSync(root)) return out;
  (function w(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const f = path.join(d, e.name);
      if (e.isDirectory()) w(f);
      else if (e.name.endsWith('.swift')) out.push(f);
    }
  })(root);
  return out;
}

const isCommentOrBlank = (l) => /^\s*(\/\/|\/\*|\*)/.test(l) || /^\s*$/.test(l);
const stripLine = (l) => l.replace(/\/\/.*$/, '');

// 属性与声明之间的注释/其它属性不改变归属 ⇒ 往回跳着找
function hasBuilderBefore(L, i) {
  for (let j = i - 1; j >= 0; j--) {
    if (/@ViewBuilder/.test(L[j])) return true;
    if (isCommentOrBlank(L[j]) || /^\s*@[A-Za-z]/.test(L[j])) continue;
    return false;
  }
  return false;
}

function r1(root) {
  const bad = [];
  for (const f of swiftFiles(root)) {
    const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      const m = VIEW_DECL.exec(L[i]);
      if (!m) continue;
      if (/\bvar\s+body\b|func\s+body\s*\(/.test(L[i])) continue;
      if (hasBuilderBefore(L, i)) continue;
      let depth = 0, hasReturn = false, topIf = false, hasElse = false;
      // R1b 的现场 (打样): body 里**顶层**先出现若干 `let`/`var`/`if` 之类的非表达式语句, 之后才是
      // 一个尾随表达式, 却没有 return —— 这就是"多语句 body 要靠结果构建器兜"的形状。
      // 判据只看**顶层第一条**语句是不是 `let`/`var` 绑定: 那一定不是表达式, 于是整段必须是 builder。
      let firstTop = null;            // 顶层第一条非空语句
      for (let j = i; j < L.length; j++) {
        const ln = stripLine(L[j]);
        const before = depth;                                 // 进这行**之前**的嵌套层
        for (const ch of ln) { if (ch === '{') depth++; else if (ch === '}') depth--; }
        if (j > i && before === 1) {
          const s = ln.trim();
          if (s && firstTop === null) firstTop = s;
          if (/^\s*return\b/.test(ln)) hasReturn = true;
          if (/^\s*if\b/.test(ln)) topIf = true;
        }
        if (j > i && /^\s*\}\s*else\b|^\s*else\b/.test(ln)) hasElse = true;   // `} else` 那行 before 是 2
        if (j > i && depth <= 0) break;
      }
      if (hasReturn) continue;                                 // 有显式 return 的 body 不受结果构建器约束
      if (topIf && !hasElse) {
        bad.push(f + ':' + (i + 1) + '  R1 缺 @ViewBuilder —— ' + L[i].trim().slice(0, 60));
      } else if (firstTop && /^(let|var)\s/.test(firstTop)) {
        // R1b: 顶层首句是 let/var 绑定 ⇒ 多语句 body 无 return ⇒ 必须 @ViewBuilder, 否则编译器报
        // "function declares an opaque return type, but has no return statements"。
        // 本仓 run 56 的 LockCompareView/rhythmSection 就是这个形状: let la …; let lb …; Section { }。
        bad.push(f + ':' + (i + 1) + '  R1b 缺 @ViewBuilder (body 以 let/var 起头且无 return) —— ' + L[i].trim().slice(0, 60));
      }

    }
  }
  return bad;
}

function r2(root) {
  const bad = [];
  for (const f of swiftFiles(root)) {
    const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      if (!/^\s*@ViewBuilder\b/.test(L[i])) continue;
      // 同一行就写完的 (`@ViewBuilder var content: Content`) 目标在本行；否则找下一个声明行
      let target = L[i].replace(/^\s*@ViewBuilder\s*/, '').trim();
      if (!DECL_HEAD.test(target)) {
        let j = i + 1;
        while (j < L.length && (isCommentOrBlank(L[j]) || /^\s*@[A-Za-z]/.test(L[j]))) j++;
        target = (L[j] || '').trim();
      }
      if (!DECL_HEAD.test(target)) continue;          // 表达式位置 / init 参数表里的属性
      if (/->\s*some\s+View\b/.test(target)) continue;
      const isVar = /\bvar\b/.test(target);
      const m = /->\s*([^{]+?)\s*\{/.exec(target) || (isVar ? /:\s*([^{]+?)\s*\{/.exec(target) : null);
      if (!m) continue;                               // 没写显式类型 ⇒ 判不了 (豁免边界)
      const t = m[1].trim();
      if (!VALUE_TYPE.test(t)) continue;
      bad.push(f + ':' + (i + 1) + '  R2 @ViewBuilder 落到「' + target.slice(0, 56) + '」—— 显式类型 ' + t + ' 不是 some View');
    }
  }
  return bad;
}

function run(root) { return [...r1(root), ...r2(root), ...r4(root), ...r6(root), ...r7(root), ...r8(root), ...r9(root), ...r10(root), ...r11(root), ...r12(root)]; }

// 括号增量 (去掉行尾注释后数花括号) —— R8/R9 靠它找 Section 体的收口行。
function braceDelta(line) {
  const s = stripLine(line);
  return (s.match(/\{/g) || []).length - (s.match(/\}/g) || []).length;
}

// 从 i 行 openIdx 处的 '(' 起, 取到配平的 ')' 为止的实参文本 (可跨行)。
function balancedParens(L, i, openIdx) {
  let depth = 0, out = '';
  for (let j = i; j < L.length; j++) {
    const s = stripLine(L[j]);
    for (let k = (j === i ? openIdx : 0); k < s.length; k++) {
      const ch = s[k];
      if (ch === '(') { depth++; if (depth === 1) continue; }
      if (ch === ')') { depth--; if (depth === 0) return out; }
      if (depth >= 1) out += ch;
    }
    out += ' ';
  }
  return out;
}

// ---------- R8/R9: 带 footer 的 Section 写法 (第192批新增, run 59 打样) ----------
// 起因: run 59 报 `Section("操作流水 (156)") { } footer: { }` 过不了编译 ——
//   报 "missing argument label 'content:'" + "cannot convert value of type 'String' to expected argument type '() -> Content'"。
// 原理: 多尾随闭包匹配时, 未加标签的那个先去找第一个能收闭包的参数。`Section("标题")` 若撞上
//   `init(content:footer:)` 这种"首参就是闭包"的重载, 字符串字面量被当成 `() -> Content` ⇒ 报错。
//   合法写法只有三段式 `Section { } header: { } footer: { }` (本仓自己的注释 DiagnosticsView:708 早写过这条)。
// 为什么单列一道门: 这是**系统性**写法 —— 全仓 6 处 (AutoOpen/DiagnosticsView×4/SettingsView),
//   而编译每次只暴露一处 (前面先停), 一次 run 只能改一处, 于是永远追不完。机器一次扫全。
// R9 是它的孪生: `Section(isExpanded:content:header:)` 这一重载**没有 footer 参数**,
//   加 footer 报 "extra trailing closure passed in call" (run 59 的 DeviceManageView:62)。
function sectionHasFooter(L, i) {
  let depth = 0;
  for (let j = i; j < L.length; j++) {
    if (j > i && depth === 1 && /^\s*\}\s*footer:\s*\{\s*$/.test(L[j])) return j;
    depth += braceDelta(L[j]);
    if (j > i && depth <= 0) return -1;
  }
  return -1;
}
function r8(root) {
  const bad = [];
  for (const f of swiftFiles(root)) {
    const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      if (!/^\s*Section\("[^"]*"\)\s*\{\s*$/.test(L[i])) continue;
      const close = sectionHasFooter(L, i);
      if (close >= 0) {
        bad.push(f + ':' + (i + 1) + '  R8 Section("标题") 不能带 footer —— 只有三段式 '
          + '`Section { } header: { } footer: { }` 是合法重载 (此处收口在第 ' + (close + 1) + ' 行)');
      }
    }
  }
  return bad;
}
function r9(root) {
  const bad = [];
  for (const f of swiftFiles(root)) {
    const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      if (!/^\s*Section\s*\(\s*isExpanded:/.test(L[i])) continue;
      const close = sectionHasFooter(L, i);
      if (close >= 0) {
        bad.push(f + ':' + (i + 1) + '  R9 Section(isExpanded:) 重载没有 footer 参数 —— '
          + '会报 "extra trailing closure passed in call" (此处收口在第 ' + (close + 1) + ' 行)');
      }
    }
  }
  return bad;
}

// ---------- R10: frame 实参次序 (第192批新增, run 59 打样) ----------
// 起因: HelpCenter 写 `.frame(minHeight: DS.Hit.min, maxWidth: .infinity, alignment: .leading)`,
//   报 "argument 'maxWidth' must precede argument 'minHeight'"。
// 原理: frame 的签名次序是 minWidth/idealWidth/maxWidth 在前, minHeight/idealHeight/maxHeight 在后 ——
//   两个都写时 maxWidth 必须先出现。名字眼熟 + 括号平衡让前 24 道闸门全绿, 只有编译器看得穿。
function r10(root) {
  const bad = [];
  for (const f of swiftFiles(root)) {
    const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      const m = /\.frame\s*\(/.exec(stripLine(L[i]));
      if (!m) continue;
      const args = balancedParens(L, i, m.index + m[0].length - 1);
      const mi = args.indexOf('minHeight:'), ma = args.indexOf('maxWidth:');
      if (mi >= 0 && ma >= 0 && mi < ma) {
        bad.push(f + ':' + (i + 1) + '  R10 frame 实参次序反了 —— maxWidth 必须写在 minHeight 之前 '
          + '("argument ' + "'maxWidth'" + ' must precede argument ' + "'minHeight'" + '")');
      }
    }
  }
  return bad;
}

// ---------- R12: View 扩展方法丢掉了 self (第208批新增, 真机首启白屏打样) ----------
// 症状: 编译全绿、装上手机打开 App **一片空白**。
// 形状: `extension View { func f() -> some View { Group { … } } }` —— 函数体只构造一个**别的**视图,
//   从不引用 self。于是 `X.f()` 的结果是那个视图, **X 整个不见了**。
// 为什么编译器不拦: 这是合法的 Swift —— 方法不引用 self 不报错、不警告, 而且"看起来还返回了东西"。
//   真身: `dsScreenBackground()` 就这么写, 全仓 99 处调用点 ⇒ 每页都只剩底色。
// 反控: 对 self 调修饰符的写法一律放过 —— `background { … }` / `modifier(…)` / `offset(…)` /
//   `presentationBackground(…)` 这些**不带接收者**的调用就是 `self.` 的省略;
//   还有显式写 `self` 的 (axOnehand 的 `if on { offset(y: dy) } else { self }`)。
function r12(root) {
  const bad = [];
  for (const f of swiftFiles(root)) {
    const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      if (!/^\s*extension\s+View\s*\{\s*$/.test(L[i])) continue;
      let depth = 0, extEnd = -1;
      for (let j = i; j < L.length; j++) {
        depth += braceDelta(L[j]);
        if (j > i && depth <= 0) { extEnd = j; break; }
      }
      if (extEnd < 0) continue;
      for (let k = i + 1; k < extEnd; k++) {
        const m = /^\s*(?:@\w+\s+)*(?:private |public |fileprivate |internal |static )*func\s+(\w+)\s*\([^)]*\)\s*->\s*some\s+View\s*\{\s*$/.exec(L[k]);
        if (!m) continue;
        let d2 = 0, fEnd = -1;
        for (let j = k; j < extEnd + 1; j++) {
          d2 += braceDelta(L[j]);
          if (j > k && d2 <= 0) { fEnd = j; break; }
        }
        if (fEnd < 0) continue;
        const body = L.slice(k + 1, fEnd).map(stripLine);
        if (body.some((l) => /\bself\b/.test(l))) continue;                       // 显式 self ⇒ 对
        if (body.some((l) => /^\s*[a-z_]\w*\s*[({[]/.test(l))) continue;          // 隐式 self 修饰符调用 ⇒ 对
        if (body.every((l) => l.trim() === '')) continue;                          // 空体交给别的判据
        bad.push(f + ':' + (k + 1) + '  R12 View 扩展方法从不引用 self —— 调用处 `X.' + m[1]
          + '()` 会把 X 整个丢掉 (只剩这里返回的那一层): ' + L[k].trim().slice(0, 56));
      }
    }
  }
  return bad;
}

// 起因: `String(decoding: d, as: UTF8)` 报 "expected member name or initializer call after type name"。
// 原理: `as:` 这里要的是**元类型**, 必须写 `UTF8.self`。只认编码类型短名单, 避免把 `as: SomeProtocol` 误伤。
// ---------- R11: `as:` 后跟元类型缺 .self (第192批新增, run 59 打样) ----------
// 起因: `String(decoding: d, as: UTF8)` 报 "expected member name or initializer call after type name"。
// 原理: `as:` 这里要的是**元类型**, 必须写 `UTF8.self`。只认编码类型短名单, 避免把 `as: SomeProtocol` 误伤。
const META_AS = /as:\s*(UTF8|UTF16|UTF32|ASCII|Unicode)\s*([),])/g;
function r11(root) {
  const bad = [];
  for (const f of swiftFiles(root)) {
    const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      const t = stripLine(L[i]);
      META_AS.lastIndex = 0;
      let m;
      while ((m = META_AS.exec(t)) !== null) {
        bad.push(f + ':' + (i + 1) + '  R11 `as: ' + m[1] + '` 缺 .self —— 这里要元类型, 应写 `as: ' + m[1] + '.self`');
      }
    }
  }
  return bad;
}


// ---------- R7: 同一条声明上挂了两个结果构建器属性 (第190批新增, run 58 打样) ----------
// 形状: 连续两行都是纯 `@ViewBuilder` (中间只隔注释/空行), 后面跟着**同一条**声明 ⇒
// 编译器报 "only one result builder attribute can be attached to a declaration"。
// 为什么会有这道门: 补 R6 那批"缺 -> some View"时, 我按注释回看找 @ViewBuilder —— 注释挡住了更上面那一个,
// 于是又加了一个, 当场被 CI (run 58) 抓出。**加属性前先数一遍**, 这道理用机器盯比用眼睛盯可靠。
// 反控: 同一条声明上"@ViewBuilder + 带 @ViewBuilder 的参数"是合法的 (@ViewBuilder func f(@ViewBuilder body:) -> some View),
// 那是**参数属性**不是重复, 判据只比"连续两行整行只有 @ViewBuilder"这一种, 参数属性 (同一行/缩进更深) 不触发。
function r7(root) {
  const bad = [];
  for (const f of swiftFiles(root)) {
    const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      if (!/^\s*@ViewBuilder\s*$/.test(L[i])) continue;
      let prev = -1;
      for (let j = i - 1; j >= 0; j--) {
        if (isCommentOrBlank(L[j])) continue;
        if (/^\s*@ViewBuilder\s*$/.test(L[j])) prev = j;
        break;                                   // 只看紧邻的上一条非注释行
      }
      if (prev >= 0) {
        bad.push(f + ':' + (prev + 1) + ' 与 ' + (i + 1) + '  R7 同一条声明挂了两个 @ViewBuilder —— '
          + 'only one result builder attribute can be attached to a declaration');
      }
    }
  }
  return bad;
}

// ---------- R6: 声明缺返回类型的"视图函数" (第189批新增, run 57 打样) ----------
// 形状: `func` 声明**没有** `->` 返回类型 (= Void), 却被当 View 用 ⇒
// 编译器报 "type '()' cannot conform to 'View'" (run 57 的 AlarmCenterView:325 就是这个)。
// 判据: body 里出现 SwiftUI 视图类型构造 (Section/Card/HStack/VStack/…; 这些名字只可能产出 View),
// 且该函数在**本文件**里被当独立语句调用 (`name(...)` 占一整行、非赋值/非参数)。
//
// 关于 @ViewBuilder 的取舍 (run 57/58 两轮反推, 记录在案):
//   原始源码里 contextSection 与 detailSection **都**带 @ViewBuilder、都缺 ->。CI 只报了 contextSection
//   那条 (line 325), detailSection (line 326) 没报 —— 但 job 的 9 条 error 没有一条是"只报一半"的截断
//   (workflow 的 head -40 没到顶), 更可能是 Swift 类型检查在一次 pass 里只报同形状的第一个。
//   本机没有编译器无从终局判定, 于是取**两害相权**: 这种"带 @ViewBuilder 却缺 ->"的形状一律补上
//   `-> some View` (Apple 文档 "Marking methods with the result builder" 的示例**全部**带返回类型,
//   全仓 StatsView 15 处 + AlarmCenterView 2 处已统一), 再让 R6 把**两种**形状都盯住, 只许减不许增。
//   与之配套的反控 OkBuilderNoArrow 因此从 ok/ 移除 —— 它的"合法"前提没有被编译器证实, 不能当反控。
//
// ⚠ 名字在本文件里**撞名**时不报 (ok/Ok.swift 两个 struct 各有一个 `row` 曾互相误伤) —— 宁漏勿误。
const VIEW_CTORS = /\b(Section|Card|HStack|VStack|ZStack|List|Form|Group|ScrollView|Grid|LazyVGrid|LazyHGrid|Canvas|Chart|HeroCard|HeroPill)\s*[({]/;
function r6(root) {
  const bad = [];
  for (const f of swiftFiles(root)) {
    const src = fs.readFileSync(f, 'utf8');
    const L = src.split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      // 只认"没有 -> "的函数声明
      const m = /^\s*(?:private |public |fileprivate |internal |static |final )*func\s+(\w+)\s*(?:<[^>]*>)?\s*\(([^)]*)\)\s*\{\s*$/.exec(L[i]);
      if (!m) continue;
      const name = m[1];
      // 只看**代码行**里的 @ViewBuilder (注释里提到不算 —— R6 夹具第一版就被这个坑过)
      let hasBuilder = false;
      for (let j = i - 1; j >= 0; j--) {
        if (isCommentOrBlank(L[j])) continue;
        if (/@ViewBuilder/.test(L[j])) { hasBuilder = true; break; }
        if (/^\s*@[A-Za-z]/.test(L[j])) continue;
        break;
      }
      // body 文本
      let depth = 0, bodyLines = [];
      for (let j = i; j < L.length; j++) {
        const ln = stripLine(L[j]);
        for (const ch of ln) { if (ch === '{') depth++; else if (ch === '}') depth--; }
        if (j > i) bodyLines.push(L[j]);
        if (j > i && depth <= 0) break;
      }
      if (!VIEW_CTORS.test(bodyLines.join('\n'))) continue;   // 体内没有视图构造 ⇒ 不像视图函数, 不判
      // 名字在本文件里被**声明**了多次时才跳过 —— 两个 struct 各有一个同名私有函数
      // (ok/Ok.swift 的两个 `row` 就互相误伤过), 按裸名分不清是哪一个在调用 ⇒ 宁漏勿误。
      // ⚠ 注意数的是"声明次数"而不是"出现次数": 正常函数声明 1 次 + 调用 1 次 = 出现 2 次,
      //   若按出现次数 > 1 就跳过, 会把**所有**正常命中都漏掉 (R6 夹具第二版就被这个坑过)。
      const occ = (src.match(new RegExp('(?:^|\\n)\\s*(?:private |public |fileprivate |internal |static |final )*func\\s+' + name + '\\s*[(<]', 'g')) || []).length;
      if (occ > 1) continue;
      const callRe = new RegExp('^\\s*' + name + '\\s*\\(');
      let stmtHit = false;
      for (let k = 0; k < L.length; k++) {
        if (k === i) continue;
        const t = stripLine(L[k]);
        if (!/^\s*[A-Za-z_]/.test(t)) continue;
        if (callRe.test(t)) { stmtHit = true; break; }
      }
      if (!stmtHit) continue;
      bad.push(f + ':' + (i + 1) + '  R6 视图函数缺返回类型 (无 ->, 却被当 View 用' + (hasBuilder ? '; 带 @ViewBuilder' : '') + ') —— ' + L[i].trim().slice(0, 56));
    }
  }
  return bad;
}

// ---------- R4: 调用点的参数标签与声明对不上 (第一百四十八批新增) ----------
// Swift 要求调用点的外部标签与声明**逐字一致**：少写、多写、写错一个都不过编译
// ("missing argument label 'mac:' in call" / "the argument list for 'legendRow' must end with ')'")。
// 这一类是 run 43 之后最贵的缺陷形态 —— 名字眼熟、括号平衡、类型也对，只有编译器看得穿。
// 现网抓到 13 处 (清单与两轮的差别写在文件头 R4 那一段)，全部已修。
//
// 判据故意只做两种没有歧义的调用形状 (其余一律不判，理由写在下面两条豁免里)：
//  (a) `类型.方法(` —— 类型必须是**本次扫描目录里声明过**的类型，方法名以小写字母开头；
//  (b) `方法(` 且前面没有 `.` —— 该方法在同一个文件里声明，或是本目录里的顶层函数。
// 两种都是**逐位比对** (第一百四十八批第二版)：从第 0 位起比到"第一个判不了的位"为止，
//  并且只比调用实际写了的那些参数 —— 尾随闭包不在括号里、多行调用只能看到本行那一段，两种都只是漏判。
// 豁免 1 同名的 Apple 成员：`.tag(date:)`/`Calendar.startOfDay(for:)`/`arr.remove(at:)` 这些
//   都撞得上本仓某个函数名，上一版无差别扫描 210 条里 200 条是这种噪音 ⇒ 判不了就不报。
// 豁免 2 判不了的位：带默认值 (调用可以整个不传，后面的位置会前移)、闭包/函数类型参数
//   (常写成尾随闭包，位置会空出来)、同名重载 (两份标签表无从选) —— 都从那一位置起停。
// 只认三种括号。**不把 < > 当括号**：Swift 的 `-> ` 里那个 `>` 会被当成闭括号，
// 于是 `func run(_ n: Int, body: (Int) -> Void)` 的参数表在 `(Int` 处就被"配平"截断，
// 那个函数的闭包参数就消失了 ⇒ R5 会拿"少一个实参"去判尾随闭包的正确写法。
// 代价：泛型里带逗号的声明 (`Dictionary<String, Int>`) 会被切坏 → 那位判不了 → 跳过 (漏判不误判)。
// 这条是 ok/Arity.swift 那枚反控打出来的：它本来"应该 0 条"，第一版却报了一条。
const OPEN_CH = '([{';
const CLOSE_CH = ')]}';
const TYPE_LINE = /^\s*(?:@\w+\s+)*(?:public |private |internal |fileprivate )?(?:final )?(?:struct|class|enum|actor|extension)\s+([A-Za-z_]\w*)/;
const FUNC_LINE = /(?:^|[^\w.])func\s+([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*\(/;
const STOP_WORDS = new Set(['if', 'for', 'while', 'switch', 'case', 'guard', 'return', 'where', 'as', 'is', 'catch', 'throw', 'init', 'deinit', 'subscript', 'get', 'set', 'willSet', 'didSet', 'func', 'let', 'var', 'in', 'else', 'do', 'repeat', 'defer', 'associatedtype', 'typealias', 'some', 'any', 'each', 'await', 'try', 'sizeof', 'print', 'dump', 'assert', 'precondition', 'fatalError']);

// 注释与字符串去掉后剩下的才是代码：字符串里的 `foo(` 不是调用点
function codeLines(raw) {
  const out = [];
  let block = false;
  for (const l of raw) {
    let s = stripLine(l);
    if (/"""/.test(s)) { block = !block; out.push(''); continue; }
    if (block) { out.push(''); continue; }
    out.push(s.replace(/"(?:[^"\\\n]|\\.)*"/g, '""'));
  }
  return out;
}
// 每一行落在哪个类型体内 (最内层)；顶层为 ''
function enclosingTypes(code) {
  const stack = [];
  const enc = [];
  let depth = 0;
  for (const ln of code) {
    const t = TYPE_LINE.exec(ln);
    enc.push(stack.length ? stack[stack.length - 1].name : '');
    const opens = (ln.match(/\{/g) || []).length;
    const closes = (ln.match(/\}/g) || []).length;
    if (t && opens > 0) stack.push({ name: t[1], depth });
    depth += opens - closes;
    while (stack.length && depth <= stack[stack.length - 1].depth) stack.pop();
  }
  return enc;
}
function balancedClose(text, openIdx) {   // text[openIdx] === '(' ⇒ 返回配平 ')' 的下标
  let d = 0;
  for (let k = openIdx; k < text.length; k++) {
    const c = text[k];
    if (OPEN_CH.includes(c)) d++;
    else if (CLOSE_CH.includes(c)) { d--; if (d === 0) return k; }
  }
  return -1;
}
function splitParams(s) {
  const out = [];
  let d = 0, cur = '';
  for (const c of s) {
    if (OPEN_CH.includes(c)) d++;
    if (CLOSE_CH.includes(c)) d--;
    if (c === ',' && d === 0) { out.push(cur); cur = ''; continue; }
    cur += c;
  }
  if (cur.trim()) out.push(cur);
  return out;
}
// 每个参数 => {label, stop, fixed}。stop = 从这一位起往后都判不了 (见下面两条注释)；
// fixed = 这一位**允许**参与"实参个数"判定 (带默认值或闭包类型的位都不允许)。
function paramInfo(p) {
  const t = p.trim();
  const m = /^(_\s+[A-Za-z_]\w*\s*:|_\s*:|[A-Za-z_]\w*\s*:)/.exec(t);
  if (!t || !m) return { label: '?', stop: true, fixed: false };   // 元组解构、运算符、属性下标之类: 整条作废
  const label = m[1].startsWith('_') ? '_' : m[1].split(':')[0].trim();
  const stop = /=/.test(t) || /->/.test(t);        // 默认值可整个不传 / 闭包常写成尾随闭包 ⇒ 位置会空出来
  return { label, stop, fixed: !stop };
}
// 调用括号里的实参列表 (按顶层逗号切; 多行调用只能看到本行那一段 —— 那是漏判, 不是误判)
function callArgs(ln, openIdx) {
  const out = [];
  let d = 0, cur = '';
  for (let k = openIdx + 1; k < ln.length; k++) {
    const c = ln[k];
    if (OPEN_CH.includes(c)) d++;
    else if (CLOSE_CH.includes(c)) { if (d === 0) break; d--; }
    if (c === ',' && d === 0) { out.push(cur); cur = ''; continue; }
    cur += c;
  }
  if (cur.trim()) out.push(cur);
  return out;
}
function put(table, key, params, file, line) {
  const sig = params.map(p => p.label + (p.stop ? '=' : '')).join();
  const arityFixed = params.every(p => p.fixed);          // 全表没有默认值/闭包参数 ⇒ 实参个数是定死的
  const prev = table.get(key);
  if (prev) { if (prev.sig !== sig) prev.conflict = true; return; }
  table.set(key, { params, sig, arityFixed, file, line });
}

function r4(root) {
  const bad = [];
  const files = swiftFiles(root);
  const statics = new Map();   // "TypeName.method" -> {params, sig, conflict}
  const members = new Map();   // "文件::method"     -> 同上 (同文件内的隐式 self 调用)
  const globals = new Map();   // "method"          -> 同上 (顶层函数, 全模块可直接调用)
  const parsed = [];
  for (const f of files) {
    const raw = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    const code = codeLines(raw);
    const enc = enclosingTypes(code);
    const text = code.join('\n');
    const lineStart = [0];
    for (let k = 0; k < text.length; k++) if (text[k] === '\n') lineStart.push(k + 1);
    const declRanges = [];
    for (let i = 0; i < code.length; i++) {
      const m = FUNC_LINE.exec(code[i]);
      if (!m) continue;
      const name = m[1];
      const openIdx = text.indexOf('(', lineStart[i] + m.index + m[0].length - 1);
      if (openIdx < 0) continue;
      const close = balancedClose(text, openIdx);
      if (close < 0) continue;
      const params = splitParams(text.slice(openIdx + 1, close)).map(paramInfo);
      declRanges.push([lineStart[i] + m.index, close]);      // 声明自己的那张表: 判不判得动都要记下, 扫描时好跳过
      // 零参声明也登记 (params 为空)。之前这里是 `if (!params.length) continue`，于是同名的
      // `func run(mac:)` 会把下面那行 `static func run() -> …` 的**定义处**当成"少传一个实参"的调用点 ——
      // 第一百五十一批 ok/Arity.swift 那枚反控专门盯这一对形状，一测就露了。
      const owner = enc[i];
      if (owner) put(statics, owner + '.' + name, params, f, i + 1);
      else put(globals, name, params, f, i + 1);
      put(members, f + '::' + name, params, f, i + 1);
    }
    parsed.push({ f, raw, code, text, declRanges, lineStart });
  }
  // 逐位比对：从第 0 位起，遇到"判不了的那一位"就整段停住 (默认值/闭包会让后面的位置前移或空出来)。
  // 只比调用**实际写了**的那些参数 —— 多行调用只能看到本行那一段、尾随闭包根本不在括号里，两种都只是漏判。
  const judge = (d, name, args, f, lineNo, how) => {
    if (!d || d.conflict) return;
    // R5: 实参个数。只在"参数表里没有默认值、也没有闭包参数"的声明上判 ——
    //     那种函数写不出尾随闭包 (少写一个实参就是不合法)，所以个数对不上就是编译器必拒。
    //     空表 `f()` 也算 ( arityFixed 的函数没有零参版本)。
    if (d.arityFixed && args.length !== d.params.length) {
      bad.push(`${f}:${lineNo}  R5 ${how} 声明要 ${d.params.length} 个实参, 这里括号里给了 ${args.length} 个 —— ${name}(${args.join(', ').slice(0, 40)}`);
    }
    let limit = d.params.length;
    for (let i = 0; i < d.params.length; i++) {
      if (d.params[i].label === '?' || d.params[i].stop) { limit = i; break; }
    }
    const n = Math.min(args.length, limit);
    for (let i = 0; i < n; i++) {
      const want = d.params[i].label;
      const a = args[i].trim();
      if (!a) continue;
      const labeled = /^[A-Za-z_]\w*\s*:/.test(a);
      const got = labeled ? a.split(':')[0].trim() : null;
      const pos = `第 ${i + 1} 个参数`;
      if (want === '_') {
        if (labeled) bad.push(`${f}:${lineNo}  R4 ${how} ${pos}声明**没有**外部标签, 这里却写了 "${got}:" —— ${name}(${a.slice(0, 34)}`);
      } else if (!labeled) {
        bad.push(`${f}:${lineNo}  R4 ${how} ${pos}标签应是 "${want}:", 这里按位置传 —— ${name}(${a.slice(0, 34)}`);
      } else if (got !== want) {
        bad.push(`${f}:${lineNo}  R4 ${how} ${pos}标签应是 "${want}:", 这里写的是 "${got}:" —— ${name}(${a.slice(0, 34)}`);
      }
    }
  };
  // 形状 (c) 试过、当场撤掉 (第一百四十八批)：`小写接收者.小写方法(` 只判"方法名在全目录里只有一份声明"的那些。
  // 实测 58 条命中，**逐条开代码看全是假的**：`list.remove(at:)`(Array)、`path.move(to:)`(Path)、
  // `s.range(of:options:)`(String)、`cal.startOfDay(for:)`(Calendar)、`buf.range(of:)`(Data)…
  // 这些都撞得上本仓某份唯一声明 (`LockArchive.remove(_)`、`RangeTable.range(fromDay:toDay:)`、`StatsKit.startOfDay(_)`、
  // `DesignSystem.move(_)`)。加豁免名单能压一时，但下一个同名 Apple 成员就会再冒一条 ——
  // 那正是 §10.11 里 apisig.js 被删掉的原因 (132 条假线索)，也是本批第一版探针 200/210 假的原因。
  // ⇒ 实例调用整个不判。要判它需要类型推导，那就是编译器的活，别用一把天天误报的尺子换。
  //
  // 第一百五十一批：调用点扫描改成**按整份文本走** (参数表跨行也取全)。按行截时
  // `legendRow(labels: mp.complete` 那种换行写法只能看见第一段 —— 现在两段都看得见，
  // 顺带把 R5 (实参个数) 接在同一条流水上。R5 只判"参数表里没有默认值、也没有闭包参数"的声明，
  // 因为那种函数**不可能**用尾随闭包少写一个实参，个数对不上就是编译器必拒。
  const scan = (re, nameOf, look, howOf) => {
    for (const { f, text, declRanges, lineStart } of parsed) {
      const lineOf = (off) => {
        let lo = 0, hi = lineStart.length - 1;
        while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (lineStart[mid] <= off) lo = mid; else hi = mid - 1; }
        return lo + 1;
      };
      const inDecl = (off) => declRanges.some(([a, b]) => off >= a && off <= b);
      re.lastIndex = 0;
      let m;
      while ((m = re.exec(text))) {
        const name = nameOf(m);
        if (STOP_WORDS.has(name)) continue;
        const d = look(f, m, name);
        if (!d || d.conflict) continue;
        const openIdx = m.index + m[0].length - 1;
        const closeIdx = balancedClose(text, openIdx);
        if (closeIdx < 0) continue;
        if (inDecl(openIdx)) continue;                       // 声明自己的那张参数表
        const inner = text.slice(openIdx + 1, closeIdx).trim();
        const args = inner ? splitParams(inner) : [];
        judge(d, name, args, f, lineOf(m.index), howOf(m, name));
      }
    }
  };
  scan(/(?:^|[^\w.])([A-Z][A-Za-z0-9_]*)\.([a-z]\w*)\s*\(/g,
    (m) => m[2], (f, m, name) => statics.get(m[1] + '.' + name), (m, name) => m[1] + '.' + name);
  scan(/(?:^|[^\w.])([a-z]\w*)\s*\(/g,
    (m) => m[1], (f, m, name) => members.get(f + '::' + name) || globals.get(name), (m, name) => name);
  return bad;
}

// ---------- R3: 合成 Codable + 非 Optional 带默认值 = 加字段就会炸的雷区 (棘轮, 只许减不许增) ----------
// 本仓自己在 Store.swift:119 记着这条事实：**合成 Codable 对有默认值的属性同样要求键存在**。
// 于是"给一个持久化 struct 新加一个字段"这个最普通的动作，会让**加字段之前**写下的所有旧 JSON
// keyNotFound ⇒ DB.get 返回 nil ⇒ 界面上一切回落默认值，没有任何报错 (第一百三十七批给 LockMeta
// 加 grp 时就是这样炸的，那一炸是"老用户整本锁档案凭空变空"的量级)。
// LockMeta 已补显式 init(from:)。剩下这 14 个 struct 现在都还没被加过字段，所以不是现行缺陷 ——
// 但下一次有人往里塞字段就会是。棘轮写法 (基线只许减) 而不是判"有就是错"：
// 因为"当前没错"是真的，而"以后会错"也是真的，两个都得留下记录。
const R3_BASELINE = 13;   // 第一百八十七批由 14 下调 (CredAlert 补了显式解码器, 见 r3Gate 上方注释)

function r3Hits(root) {
  const hits = [];
  for (const f of swiftFiles(root)) {
    const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    for (let i = 0; i < L.length; i++) {
      const m = /^\s*(?:public |final )?struct\s+(\w+)\s*:[^{]*Codable/.exec(L[i]);
      if (!m) continue;
      let depth = 0;
      const body = [];
      // 整行写完的小 struct (`struct P: Codable { var a: String = "" }`) 也要看到体内字段 ——
      // 第一版只逐行往下收，注入探针 (`App/_probe_r3.swift`) 一测就不响，
      // 那个"绿"是假的：判据看不见单行写法，等于对这类形状完全失明。
      const sameLine = /\{\s*(.+?)\s*\}\s*$/.exec(L[i]);
      if (sameLine) body.push(sameLine[1]);
      for (let j = i; j < L.length; j++) {
        const ln = stripLine(L[j]);
        depth += (ln.match(/\{/g) || []).length - (ln.match(/\}/g) || []).length;
        if (j > i && sameLine === null) body.push(L[j]);
        if (depth <= 0 && j > i) break;
      }
      const text = body.join('\n');
      if (/init\s*\(\s*from\s/.test(text)) continue;                 // 有显式解码器的不在名单里
      const risky = body.filter(l => /^\s*var\s+\w+\s*:\s*[^?{=\n]+=/.test(l) && !/\?\s*=/.test(l));
      if (risky.length) hits.push(`${f}:${i + 1}  R3 雷区 struct ${m[1]} —— ${risky.length} 个非 Optional 带默认值字段, 无显式 init(from:)`);
    }
  }
  return hits;
}

function selftest() {
  const dir = path.join(ROOT, 'fixtures', 'swiftshape');
  const shouldFire = run(path.join(dir, 'fire'));
  const shouldNot = run(path.join(dir, 'ok'));
  const n4 = shouldFire.filter(h => h.includes(' R4 ')).length;
  const n5 = shouldFire.filter(h => h.includes(' R5 ')).length;
  const n1 = shouldFire.filter(h => h.includes(' R1 ')).length;
  const n1b = shouldFire.filter(h => h.includes(' R1b ')).length;
  const n2 = shouldFire.filter(h => h.includes(' R2 ')).length;
  const n6 = shouldFire.filter(h => h.includes(' R6 ')).length;
  const n7 = shouldFire.filter(h => h.includes(' R7 ')).length;
  const n8 = shouldFire.filter(h => h.includes(' R8 ')).length;
  const n9 = shouldFire.filter(h => h.includes(' R9 ')).length;
  const n10 = shouldFire.filter(h => h.includes(' R10 ')).length;
  const n11 = shouldFire.filter(h => h.includes(' R11 ')).length;
  const n12 = shouldFire.filter(h => h.includes(' R12 ')).length;
  // fire/ 里 R4 有**四处**有问题的调用，报出 5 条：按位置传那一处第 1、第 2 个参数都少标签，逐位判就该各报一次。
  // R5 有两条：少一个实参、多一个实参。R1 一条 (顶层 if 无 else)、R1b 一条 (body 以 let 起头无 return)、
  // R6 两条 (无返回类型却被当 View 用: 无 @ViewBuilder 一条 + 有 @ViewBuilder 一条)、R7 一条 (重复挂 @ViewBuilder)、
  // R8/R9/R10/R11 各一条 (带 footer 的 Section 写法两种 + frame 次序 + as: 缺 .self)。
  if (n1 !== 1 || n1b !== 1 || n2 !== 1 || n4 !== 5 || n5 !== 2 || n6 !== 2 || n7 !== 1
      || n8 !== 1 || n9 !== 1 || n10 !== 1 || n11 !== 1 || n12 !== 1) {
    console.log(`✗ 正控失败: fire/ 里 R1/R2 各应 1 条、R1b 应 1 条、R6 应 2 条、R7/R8/R9/R10/R11/R12 各应 1 条、R4 应 5 条、R5 应 2 条，`
      + `实得 R1=${n1} R1b=${n1b} R2=${n2} R6=${n6} R7=${n7} R8=${n8} R9=${n9} R10=${n10} R11=${n11} R12=${n12} R4=${n4} R5=${n5}`);
    console.log(shouldFire.join('\n'));
    return 2;
  }
  if (shouldNot.length !== 0) {
    console.log('✗ 正控失败: ok/ 里应 0 条，实得 ' + shouldNot.length);
    console.log(shouldNot.join('\n'));
    return 2;
  }
  const riskyFire = r3Hits(path.join(dir, 'fire'));
  const riskyOk = r3Hits(path.join(dir, 'ok'));
  const wantBoth = ['R3Risky', 'R3RiskyOneLine'];
  const missed = wantBoth.filter(n => !riskyFire.some(h => h.includes('struct ' + n + ' ')));
  if (riskyFire.length !== 2 || riskyOk.length !== 0 || missed.length) {
    console.log(`✗ 正控失败: R3 应数出 fire/ 的两个雷区 struct (多行 + 整行写完那种)，`
      + `实得 fire=${riskyFire.length} ok=${riskyOk.length} 漏=${missed.join(',') || '无'}`);
    console.log([...riskyFire, ...riskyOk].join('\n'));
    return 2;
  }
  console.log('正控 ✓ (R1/R1b/R6/R7/R2 各开火；R8/R9 两种带 footer 的 Section 写法各开火；'
    + 'R10 frame 次序、R11 as: 缺 .self、R12 View 扩展丢 self 各开火；R3 两种写法都数得出，且放过有显式解码器的那个；'
    + 'R4 四处有问题的调用报满 5 条 (含第二个标签写错那种只有逐位判才看得见的)；'
    + 'R5 少参与多参各一条；ok/ 里尾随闭包与带默认值这两种"括号里个数少"的合法写法、'
    + '三段式 Section、maxWidth 在前、as: 带 .self 一条不响)');
  return 0;
}

/// R3 棘轮: 只有**新增**才判失败。基线 13 个 —— 第一百八十七批从 14 下调:
/// `CredAlert` 早在 cc7a569 (926/930 那批) 就补上了显式 `init(from:)`，棘轮却拖了 20 个 commit 没落。
/// 为什么一直没人看见: 摘要行印的是**基线**而不是实数 ("停在基线 14 个")，与提示行算出的 13 自相矛盾，
/// 读的人自然信了那句"停在基线 14"。现在摘要改印实数 (r3Count)，这类"闸门用自己的常量替实况说话"的口子堵掉。
function r3Count() {
  let n = 0;
  for (const d of DIRS) n += r3Hits(path.join(ROOT, d)).length;
  return n;
}
function r3Gate() {
  const hits = [];
  for (const d of DIRS) hits.push(...r3Hits(path.join(ROOT, d)));
  if (hits.length === R3_BASELINE) return [];
  if (hits.length < R3_BASELINE) {
    console.log(`提示: R3 雷区比基线少 ${R3_BASELINE - hits.length} 个 —— 把 R3_BASELINE 改成 ${hits.length} (棘轮只许往下调)`);
    return [];
  }
  return [`${hits.length} 个合成 Codable 雷区 (基线 ${R3_BASELINE}) —— 新增的那几个必须先补显式 init(from:)，`
    + `否则加字段之前写下的旧 JSON 会 keyNotFound，DB.get 返回 nil，界面上只是静静地回落默认值:`]
    .concat(hits.slice(0, 20));
}

if (process.argv.includes('--selftest')) process.exit(selftest());
else {
  const st = selftest();
  if (st !== 0) process.exit(st);
  const bad = [];
  for (const d of DIRS) bad.push(...run(path.join(ROOT, d)));
  bad.push(...r3Gate());
  if (bad.length) {
    console.log('Swift 形状机检判失败 (' + bad.length + ' 条):');
    console.log(bad.join('\n'));
    process.exit(1);
  }
// ── R13: 缩进 4 的成员声明不可能出现在深度 0 ──
//
// 实证（2026-10-23 CI）：我把 `func xFontScaled(...)` 插到了 `extension View { }` 的
// **闭括号之后**，编译器报「cannot find 'modifier' in scope」——
// `modifier` 是 View 协议的方法，裸函数里当然找不到。
//
// 判据比「extension 内外」更简单也更准：**全局花括号深度为 0 的行，只允许列 0 的声明**。
// 一个 4 空格缩进的 func/var/let 出现在深度 0，说明它上面的块已经关了 —— 它越界了。
// 这类错在源码里看着极正常（缩进对、括号平衡、名字对），只有编译器知道它越界。
{
  const r13 = r13Check();
  if (r13 > 0) { console.log('✗ R13 有 ' + r13 + ' 处缩进成员出现在深度 0（应被某个 extension / struct 包住）'); process.exit(1); }
}
}

  console.log('Swift 形状机检 ✓ (R1/R1b 缺 @ViewBuilder / R2 属性挂到值类型 / R4 调用点参数标签对不上 / '
    + 'R5 实参个数对不上 / R6 视图函数缺返回类型 / R7 重复挂 @ViewBuilder / '
    + 'R8 Section("标题") 带 footer / R9 Section(isExpanded:) 带 footer / '
    + 'R10 frame 次序 / R11 as: 缺 .self / R12 View 扩展丢 self — 零命中; R3 合成 Codable 雷区 ' + r3Count() + ' 个, 基线 ' + R3_BASELINE + ' 个)');


function r13Check() {
  let n = 0;
  for (const f of swiftFiles(path.join(__dirname, '..', 'App'))) {
    const L = fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n');
    let depth = 0;
    L.forEach((ln, i) => {
      const code = ln.replace(/\/\/.*$/, '');
      const before = depth;
      let inStr = false, prev = '';
      for (const ch of code) {
        if (ch === '"' && prev !== '\\') inStr = !inStr;
        if (!inStr) { if (ch === '{') depth++; else if (ch === '}') depth--; }
        prev = ch;
      }
      if (before === 0 && /^    (func|var|let) /.test(code)) {
        n++;
        if (n <= 6) console.log('R13 越界成员 (' + path.relative(path.join(__dirname, '..'), f) + ':' + (i + 1) + '): ' + ln.trim().slice(0, 60));
      }
    });
  }
  return n;
}