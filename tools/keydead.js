#!/usr/bin/env node
// 假开关扫描 (顾问级, 不判失败) — node tools/keydead.js
// 起因：本仓反复出现"引擎/开关写了但没人读"这一整类缺陷 —— 第八批的 389–398 安全族全是零消费者死开关，
// 第九十二批的 HotCache.recent 是"写而无读"，第九十三批的 DS.Radius.pill 是"零读取常量还配了句解释注释"。
// 225–300 这批编号里 UI 开关密度最高，逐条人读会漏，所以把判据做成常驻工具。
// 判据 (取"键名"而不是"变量名"，因为 Swift 这边一律经 DB.store 存取字符串键)：
//   读/写**动词表从 App/Core/Store.swift 现场解析** (不手抄)，扫每个 kf_* 字面量出现位置，
//   **按字面量在行内的位置归属到离它最近的那个动词调用**，分成 读 与 写；
//   只有写没有读 ⇒ 疑似假开关；只有读没有写 ⇒ 该键恒为默认值 (也报，形状不同但同样是线索)。
// 第九十四批把"藏在水面下的存取"补上了 (不补则 53 条里 47 条是噪音，噪音尺子没人看，也就没法常驻)：
//   · **别名**: `static let lockTiming = "kf_slock_timing"` 这类键名常量，按"宿主类型名 + 所在作用域"消歧。
//     撞名是真事 (HolidayFeed.autoKey 与 SeasonIcon.autoKey 是两个不同键)，所以裸名只认当前所在类型那一条；
//     写成 `Owner.prop` 只认 Owner 对上的那条；嵌套类型 (BLEService 里的 enum ScanProfile) 必须连缩进也认得出宿主，
//     否则 `BLEService.ScanProfile.storeKey` 这种三段链匹配不到，**真写口会被判成不存在**。
//   · **搬运函数**: `func binding(_ k: String) -> Binding<Bool>`、`app.setUnlockOption(_ key: String, _ v: Any)`、
//     `setCodeRow → setCodeAlert` 这类"写侧藏在别的函数里"的形状，按**函数体**认定 (形参交给了 Store 的读/写动词，
//     或交给了另一个已认定的搬运函数)，并迭代到传递闭包。判据必须按体、且形参名得是键名形状，
//     否则 `swatchColor(_ key: String)` 这种与存储无关的函数也会被卷进来变成假证据。
//   · **单行 setter**: `static func setElderMode(_ on: Bool) { DB.store.set("kf_x", on) }` —— 定义行整行早退
//     等于把唯一的写口抹掉，现在只剥函数头，同行后面那截存取照算。
//   · **前缀族**: `"kf_x_" + mac` 这类键的整表读写走 matchingKeys(prefixes:)，认不出来就单列一档
//     "前缀族 (需人读)"，不混进假开关名单。
// 已知局限 (所以定顾问级，不判失败)：
//   ① 键名经变量中转且不在同一行时仍会漏 (`let k = SecKey.x` 之后的间接使用)；
//   ② 整表操作只登记 `prefixes:` 后面那串字面量，动态拼出来的前缀认不出；
//   ③ 搬运函数只认形参名是键名形状 (k / *key) 的那几个 —— 全仓确实是这套命名，换了叫法的搬运口会漏；
//   ④ 认得出"有写口"不等于"写口在界面上点得动"，命中零读写仍要按 VERIFY-CHECKLIST 真机验一遍。
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = process.argv[2] || 'App';
const files = [];
(function w(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) w(p);
    else if (p.endsWith('.swift')) files.push(p);
  }
})(ROOT);

// 读/写动词名**从 Store.swift 现场解析** (第九十四批两次修判据)：
// ① 一开始手抄漏了 getDict/getDate，于是 kf_gateways/kf_keychains 这些"用 getDict 整表读"的键被误报成
//    "只写不读" —— 手抄动词这坑本仓踩过三次；
// ② 改成现场解析后仍漏了**最关键的 `get` 与 `setCodable`**：原正则写成 `func\s+(get[A-Za-z]*|object)\s*\(`，
//    要求名字后面紧跟 `(`，而 Store 的真声明是泛型 `func get<T: Decodable>(...)` —— `<T>` 卡住了匹配。
//    后果是 `kf_passcode` 被报"只写不读"，而 Store.swift:621/647 就在读它。现在允许名字后跟泛型参数表。
// ③ `has(_:)` 也是读 (存在性判定)，早先的动词表里没有；`object(forKey:)` 是 Foundation 的、Store 没有同名 func，
//    原来把它写进注释当"已覆盖"是错的 —— 现在按实际形状单独认。
const storeSrc = fs.existsSync(path.join(ROOT, 'Core', 'Store.swift'))
  ? fs.readFileSync(path.join(ROOT, 'Core', 'Store.swift'), 'utf8') : '';
const fnNames = (prefix) => {
  // 捕获组必须框住**整个方法名** (`prefix\w*`)。写成 `(prefix)\w*` 时 `\w*` 落在组外，
  // `func getString(` / `func setCodable(` 会被解析成动词名 `get` / `set` ——
  // 于是正则 `\bget\s*\(` 永远匹配不到 `getString(`，全仓的字符串/Bool/Int 读法集体隐身 (第九十四批实测踩中)。
  const re = new RegExp('func\\s+(' + prefix + '\\w*)\\s*(?:<[^>]*>)?\\s*\\(', 'g');
  return [...new Set([...storeSrc.matchAll(re)].map((m) => m[1]))];
};
const readNames = [...new Set([...fnNames('get'), ...fnNames('has'), 'object'])];
const writeNames = [...new Set([...fnNames('set'), ...fnNames('remove'), ...fnNames('clear')])];
const DEFINED = /^\s*(?:@\w+\s+)*(?:public |private |internal |fileprivate |static |final |class |override )*func\s/;
const info = new Map();   // key -> {write:[], read:[], alias:bool}
const touch = (k, where, kind) => {
  if (!info.has(k)) info.set(k, { write: [], read: [] });
  // 同一行的键可能被字面量与别名各命中一次，计数要数"处在几行"而不是"命中几次"，
  // 否则报出来的"写 N 处"会翻倍，人读时把噪音当成证据。
  if (!info.get(k)[kind].includes(where)) info.get(k)[kind].push(where);
};
// 先收别名: `static let x = "kf_y"`，**带上宿主类型名**。
// 第九十四批一开始只按属性名建表，结果 `enum AccentCustom { static let key = "kf_accent_custom" }`
// 被存成属性名 `key` —— 而 `key` 在全仓到处出现，既可能误配也可能干脆漏配 (读的地方写的是 `AccentCustom.key`)。
const aliases = [];   // {prop, owner, key}
for (const f of files) {
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  let owner = '';
  lines.forEach((raw, i) => {
    // 宿主类型名要按**缩进也认**：Swift 的嵌套类型 (`enum ScanProfile` 写在 BLEService 里) 前面有 4 空格，
    // 原来这条正则从 `^` 直接接关键字，嵌套类型一律认不出宿主 ⇒ 别名表把 `storeKey` 记到了外层
    // BLEService 名下，而调用点写的是 `BLEService.ScanProfile.storeKey` ⇒ 真写口被判成不存在。
    const tt = raw.match(/^\s*(?:public |private |internal |fileprivate |final )*(?:enum|struct|actor|class|extension)\s+([A-Z]\w*)/);
    if (tt && !raw.trimStart().startsWith('//')) owner = tt[1];
    const m = /static\s+let\s+([A-Za-z_]\w*)\s*(?::\s*\w+\s*)?=\s*"(kf[A-Za-z0-9_.]*)"/.exec(raw);
    if (m) aliases.push({ prop: m[1], owner, key: m[2] });
  });
}
// 键名**拼装函数**也算别名 (第九十四批补的): 本仓大量键是 `"kf_x_" + mac` 这种在函数里拼出来的，
// 写侧直接出现字面量、读侧只写 `histKey(mac, kind, key)` —— 不认这种形状就会把一堆正常的键报成"只写不读"
// (第一版就报了 39 条，几乎全是这个形状)。判据: `func NAME(...) -> String` 且函数体里出现该字面量 ⇒ NAME 是它的别名。
const builderKeys = new Map();   // funcName -> Set(kf_ 字面量)
for (const f of files) {
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const m = /^\s*(?:private |public |static |final )*func\s+([a-z]\w*)\s*\([^)]*\)\s*(?:async )?->\s*String\s*\{?\s*$/.exec(lines[i]);
    if (!m) continue;
    let depth = 0, seen = false, body = '', j = i;
    for (; j < lines.length; j++) {
      for (const ch of lines[j]) { if (ch === '{') { depth++; seen = true; } else if (ch === '}') depth--; }
      body += lines[j] + '\n';
      if (seen && depth <= 0) break;
    }
    const lits = [...body.matchAll(/"(kf[A-Za-z0-9_.]*)/g)].map((x) => x[1]);
    if (lits.length) builderKeys.set(m[1], new Set([...(builderKeys.get(m[1]) || []), ...lits]));
  }
}
const READSET = new Set(readNames);
// 一行里可能有**多个**动词、多个键 (如 `set("kf_a", get([T].self, "kf_b"))`)。第九十四批原写法是
// 整行判"是读还是写"，而行级 `isWrite ? 'write' : 'read'` 让**同一行只要沾一个写动词，整行的键就都算写**
// —— 放宽动词表 (裸 `get(`/`set(` 也认) 之后这条老 bug 被放大：只写不读从 39 涨到 101，`kf_accent`
// 明明在 `DS.applyAccent` 里被读却报成死开关。改成**按键名出现的位置归属到离它最近的那个动词**。
const VERB = new RegExp('\\b(' + [...readNames, ...writeNames].join('|') + ')\\s*\\(', 'g');
const LIT = /"((?:kf|lockkeeper)[A-Za-z0-9_.]*)"/g;
// **键搬运函数**也算读写口 (第九十四批第三次修判据)。上一版只认动词表里的 Store 方法名，于是
// `Toggle("", isOn: binding(SecKey.lockCoolOn))` 这类**写侧藏在别的函数里**的形状整片隐身：
// 53 个键集体被报成"只读不写"，其中应用锁安全族 389–398 全中 —— 那是本仓最不能错的开关族，
// 报告一旦全是噪音，这个工具就没有常驻价值。判据按**体**而不是按名字猜：
// `func NAME(... _ k: String ...)` 且函数体把**那个形参**交给 Store 的读/写动词 ⇒ NAME 是该键的一次读/写；
// Binding 工厂两边都有 ⇒ 算"读且写"。名字里带 set 但没有 Store 动词的 (如 swatchColor) 自动不收。
const bodyOf = (lines, i) => {
  let depth = 0, seen = false, body = '', j = i;
  for (; j < lines.length; j++) {
    for (const ch of lines[j]) { if (ch === '{') { depth++; seen = true; } else if (ch === '}') depth--; }
    body += lines[j] + '\n';
    if (seen && depth <= 0) break;
  }
  return body;
};
// 从 `verb(` 的开括号起取到配对闭括号里的实参文本 (嵌套感知，不看逗号切分，够用)
const argsOf = (src, openIdx) => {
  let depth = 0;
  for (let p = openIdx; p < src.length; p++) {
    if (src[p] === '(') depth++;
    else if (src[p] === ')') { depth--; if (depth === 0) return src.slice(openIdx + 1, p); }
  }
  return '';
};
// 参数表读法: Swift 长签名会**换行**，按单行 `\(([^)]*)\)` 取参数会把整条搬运函数漏掉
// (`private func setCodeRow(title: String, key: String, hint: String,` 后面换行接 conflictCheck ⇒ 不匹配)。
// 改成从 `func NAME(` 的左括号起做配对扫描，跨行取到配对的右括号为止。
const HEAD = /^\s*(?:@\w+\s+)*(?:private |public |internal |fileprivate |static |final |override |mutating |convenience )*func\s+([a-z]\w*)\s*\(/;
const paramsOf = (lines, startLine) => {
  const open = lines[startLine].lastIndexOf('(');
  if (open < 0) return null;
  let depth = 0, out = '';
  for (let L = startLine, p = open; L < lines.length; L++, p = 0) {
    for (; p < lines[L].length; p++) {
      const ch = lines[L][p];
      if (ch === '(') { depth++; if (depth === 1) continue; }
      else if (ch === ')') { depth--; if (depth === 0) return out; }
      if (depth >= 1) out += ch;
    }
  }
  return null;
};
// 只取**键形参**: Swift 的外标签+内名形如 `_ key: String`，整段里冒号左边最后一个标识符才是内部名
// (早先用 `_\s+|([A-Za-z_]\w*)\s*:\s*String` 一条正则去套，`_ k: String` 两种分支都不匹配，
//  结果 binding/setUnlockOption 一个没收着，反倒把 `mac: String`/`v: String` 这类**非键**形参收了进来
//  —— 那等于把调用点同行的任意键都算成读写，是比漏报更糟的错)。
const keyParamsOf = (pt) => pt.split(',')
  .map((seg) => /(^|[^\w])([A-Za-z_]\w*)\s*:\s*(?:some |any )?String\b/.exec(seg)?.[2])
  .filter((n) => n && (n === 'k' || /key$/i.test(n)));
const candidates = [];   // {name, params, body}
for (const f of files) {
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const hm = HEAD.exec(lines[i]);
    if (!hm) continue;
    const pt = paramsOf(lines, i);
    if (pt === null) continue;
    const params = keyParamsOf(pt);
    if (!params.length) continue;
    candidates.push({ name: hm[1], params, body: bodyOf(lines, i) });
  }
}
const wrappers = new Map();   // fnName -> {read:bool, write:bool}
const classify = (c) => {
  let r = false, w = false;
  for (const p of c.params) {
    for (const vm of c.body.matchAll(VERB)) {
      const args = argsOf(c.body, vm.index + vm[1].length);
      if (!new RegExp('\\b' + p + '\\b').test(args)) continue;
      if (READSET.has(vm[1])) r = true; else w = true;
    }
    // **传递**: 形参交给了另一个搬运函数 ⇒ 继承它的读写。
    // 本仓的 UI 行构造器 (setCodeRow 之类) 自己只把 key 往下递给 setCodeAlert，
    // 不认传递就会把"设置伪装口令 / 设置胁迫码"这类唯一的写口报成不存在。
    for (const [n2, v2] of wrappers) {
      if (n2 === c.name) continue;
      for (const cm of c.body.matchAll(new RegExp('(?<!\\w)(' + n2 + ')\\s*\\(', 'g'))) {
        const args = argsOf(c.body, cm.index + cm[1].length);
        if (!new RegExp('\\b' + p + '\\b').test(args)) continue;
        if (v2.read) r = true;
        if (v2.write) w = true;
      }
    }
  }
  return r || w ? { read: r, write: w } : null;
};
// 传递闭包要迭代到不动点 (A→B→Store 这种链，单趟只认到 A→B 的前一半)
let cur = new Map();
for (let pass = 0; pass < 4; pass++) {
  wrappers.clear();
  for (const [k, v] of cur) wrappers.set(k, v);
  let changed = false;
  for (const c of candidates) {
    const got = classify(c);
    if (!got) continue;
    const prev = wrappers.get(c.name);
    if (!prev || prev.read !== got.read || prev.write !== got.write) { wrappers.set(c.name, got); changed = true; }
  }
  cur = new Map(wrappers);
  if (!changed) break;
}
// 整表操作登记 (限制②里能自动化的部分): `matchingKeys(prefixes:)` 这类"按前缀族扫"的读写动词表认不出。
const famPrefixes = new Set();
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  for (const m of src.matchAll(/prefixes:\s*\[([^\]]*)\]/g))
    for (const s of m[1].matchAll(/"([^"]+)"/g)) famPrefixes.add(s[1]);
}
const propCount = new Map();
for (const a of aliases) propCount.set(a.prop, (propCount.get(a.prop) || 0) + 1);
const aliasToKey = new Map(aliases.map((a) => [a.prop, a.key]));   // 兼容下面的统计
for (const f of files) {
  const rel = f.replace(/\\/g, '/');
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  // 每行所处的类型作用域 (与别名采集同一套启发式，两边口径必须一致): 用来给撞名的裸别名消歧
  let scopeOwner = '';
  const ownerAt = lines.map((raw) => {
    const tt = /^\s*(?:public |private |internal |fileprivate |final )*(?:enum|struct|actor|class|extension)\s+([A-Z]\w*)/.exec(raw);
    if (tt && !raw.trimStart().startsWith('//')) scopeOwner = tt[1];
    return scopeOwner;
  });
  // 注释行只当"备案线索"不当读写证据 (第九十一批 deadscan 的同族教训: 注释会替死码充数)
  lines.forEach((raw, i) => {
    const ownerHere = ownerAt[i];
    let code = raw.replace(/^\s*\/\/.*$/, '').replace(/\/\/.*$/, '');
    if (!code.trim()) return;
    if (DEFINED.test(code)) {
      // 定义行的**函数头**不算一次读/写，但**同行写在后面的真存取不能一起丢** ——
      // `static func setElderMode(_ on: Bool) { DB.store.set("kf_elder_mode", on) }` 是 Swift 常见的
      // 单行 setter，整行早退等于把唯一的写口抹掉，本仓一批"只读不写"误报就是这么来的。
      const br = code.indexOf('{');
      if (br < 0) return;
      code = code.slice(br + 1);
    }
    const verbs = [];
    for (const m of code.matchAll(VERB)) verbs.push({ idx: m.index, kind: READSET.has(m[1]) ? 'read' : 'write' });
    // 注意不再因 `verbs` 为空而早退: 搬运函数的调用点 (`Toggle(isOn: binding(SecKey.lockCoolOn))`)
    // 整行一个 Store 动词都没有，早退就等于把这一类证据全丢掉。kindFor 在空动词时自然返回 null。
    // 键离哪个动词最近 (优先取它**左边**紧邻的动词，即"它是这个调用的参数") 就归哪个动作
    const kindFor = (at) => {
      let best = null;
      for (const v of verbs) if (v.idx < at && (!best || v.idx > best.idx)) best = v;
      if (best) return best.kind;
      return verbs.find((v) => v.idx > at)?.kind ?? null;
    };
    const where = `${rel}:${i + 1}`;
    for (const m of code.matchAll(LIT)) {
      const kind = kindFor(m.index);
      if (kind) touch(m[1], where, kind);
    }
    // 别名命中 (含作用域消歧)，读写归属与搬运函数两条路共用同一份结果，避免两边口径漂移
    const aliasHits = (() => {
      const out = [];
      for (const a of aliases) {
        // 左侧只挡**词字符**，不挡点号：`DB.store.set(BLEService.ScanProfile.storeKey, …)` 是三段链，
        // 若把点也挡掉就匹配不到 (早先的 `(?<![\\w.])` 就是这么把这个真实写口判没的)；
        // 捕获组取**紧邻的前一段**当限定名，与宿主类型比对，链式限定照样能对上。
        const re = new RegExp('(?<![\\w])(?:([A-Za-z_]\\w*)\\.)?' + a.prop + '(?![\\w])', 'g');
        for (const m of code.matchAll(re)) {
          const q = m[1];
          if (q) { if (!a.owner || q !== a.owner) continue; }
          else if (propCount.get(a.prop) > 1) { if (!a.owner || a.owner !== ownerHere) continue; }
          out.push({ key: a.key, idx: m.index });
        }
      }
      return out;
    })();
    // 别名形式: `store.getBool(SecKey.lockTiming, …)` 或 `DS.AccentCustom.key`。
    // **按作用域消歧** (第九十四批第四次改): 属性名会撞车 —— `HolidayFeed.autoKey` 与
    // `SeasonIcon.autoKey` 是两个不同键，而两边都用**裸名**在自己的类型里读写
    // (`static var autoOn: Bool { DB.store.getBool(autoKey) }`)。
    // 旧规则"属性名不唯一就必须行内出现宿主类型名"把这两处合法读写全判没了 ⇒ 真在用的键被报成假开关。
    // 现在按出现位置分三种: ① 写成 `Owner.prop` ⇒ 只认 Owner 对上那条；② 裸名 ⇒ 只认当前所在类型；
    // ③ 属性名全仓唯一 ⇒ 直接认。既不放过撞车，也不误伤正当使用。
    for (const h of aliasHits) {
      const kind = kindFor(h.idx);
      if (kind) touch(h.key, where, kind);
    }
    // 拼装函数形状: 读侧只写 `DB.store.get([T].self, histKey(…))` ⇒ 算 histKey 所拼那几个键的一次读。
    for (const [fn, keys] of builderKeys) {
      const bm = new RegExp('(?<![\\w.])' + fn + '\\s*\\(').exec(code);
      if (!bm) continue;
      const kind = kindFor(bm.index);
      if (!kind) continue;
      for (const k of keys) touch(k, where, kind);
    }
    // 搬运函数调用点: `binding(SecKey.lockCoolOn)` / `app.setUnlockOption("kf_fence", $0)`。
    // 只认出现在调用**右侧**的键 (左侧的是隔壁调用的参数，归它自己的动词)。
    for (const [fn, kinds] of wrappers) {
      // 只挡"紧邻词字符"的前缀 (`getXy(` 这类同名词)，**不挡点号**：
      // `app.setUnlockOption("kf_fence", $0)` 的写侧就挂在 `app.` 后面，
      // 早先写成 (?<![\w.]) 把点也算进去，结果 20 个搬运函数里最关键的几个调用点全部隐身。
      const cm = new RegExp('(?<!\\w)' + fn + '\\s*\\(', 'g').exec(code);
      if (!cm) continue;
      const hit = [];
      for (const m of code.matchAll(LIT)) if (m.index >= cm.index) hit.push(m[1]);
      for (const h of aliasHits) if (h.idx >= cm.index) hit.push(h.key);
      for (const k of hit) {
        if (kinds.read) touch(k, where, 'read');
        if (kinds.write) touch(k, where, 'write');
      }
    }
  });
}
let wo = 0, ro = 0, fam = 0;
const onlyWrite = [], onlyRead = [], family = [], retired = [];
// 前缀族键 (`"kf_x_" + mac` 这种拼装出来的) 的整表读写走 matchingKeys/keys()，动词表认不出；
// 裸报成假开关是噪音，单列一档交人读。
const famCover = (k) => k.endsWith('_') || [...famPrefixes].some((p) => p !== k && (k.startsWith(p) || p.startsWith(k)));
// 「键口径：」销号标记 (第一百六十六批，与 swiftlint 的单位口径：/方向口径：/历法例外： 同一族做法)：
// 人读过并写下理由的写点不再反复占名单 —— 天天喊没人信的尺子最后没人信。
// 语义刻意窄：该键的**所有**写点里只要有一处带标记就算销号；标记行本身要写清为什么 (删档兜底/别侧写入…)。
const SRC = new Map();
function lineAt(site) {
  const i = site.lastIndexOf(':');
  const f = site.slice(0, i), n = Number(site.slice(i + 1));
  if (!Number.isInteger(n) || n < 1) return '';
  if (!SRC.has(f)) { try { SRC.set(f, fs.readFileSync(f, 'utf8').split(/\r?\n/)); } catch { SRC.set(f, []); } }
  const L = SRC.get(f);
  return L.slice(Math.max(0, n - 3), n).join('\n');
}
for (const [k, v] of [...info.entries()].sort()) {
  if (v.write.length && !v.read.length) {
    if (v.write.some((w) => lineAt(w).includes('键口径：'))) { retired.push([k, v.write]); continue; }
    if (famCover(k)) { fam++; family.push([k, v.write]); }
    else { wo++; onlyWrite.push([k, v.write]); }
  } else if (v.read.length && !v.write.length) { ro++; onlyRead.push([k, v.read]); }
}
console.log('【只写不读 ⇒ 疑似假开关/无人消费的备案】' + wo + ' 个:');
for (const [k, w] of onlyWrite) console.log(`  ${k}  写 ${w.length} 处 @ ${w.slice(0, 2).join(' , ')}`);
console.log('【已销号 (写点带「键口径：」，人读过并写了理由)】' + retired.length + ' 个'
  + (retired.length ? ': ' + retired.map(([k]) => k).join(' , ') : ''));
console.log('【前缀族键 (整表操作覆盖, 需人读)】' + fam + ' 个:');
for (const [k, w] of family) console.log(`  ${k}  写 ${w.length} 处 @ ${w.slice(0, 2).join(' , ')}`);
console.log('【只读不写 ⇒ 恒为默认值 (可能是别的语言侧写入, 要人读)】' + ro + ' 个:');
for (const [k, r] of onlyRead) console.log(`  ${k}  读 ${r.length} 处 @ ${r.slice(0, 2).join(' , ')}`);
// ---------- 第四档: 同一个键读出多套「字面量默认值」(第一百五十六批新增) ----------
// 为什么单列：默认值就是"这台机器还没写过这个键时该显示什么"的唯一口径。
// 同一个 kf_ 键被两处读出**不同的字面量** ⇒ 同一个值有两套真相 (设置页一档、别处另一档)，
// 而这类漂移编译器与形状闸门都看不见 —— 与 delsweep/lockpair 同一族 ("改了一侧没管另一侧") 的键面版本。
// 边界 (故意收得窄)：只看单行、字面量形态的默认值 (`"x"` / 数字 / true|false)。
//  · 默认值写成属性 (`BackupStudio.webdavRoot`) 的那类是**走同一个口径**，不算竞争 ——
//    第一百五十六批第一次跑就是把这两类报成假的 (kf_webdav_root / kf_launch_line)，逐条读代码后都排除；
//  · 别名形式 (`getBool(SecKey.xxx)`) 与跨行的读取本档看不见；报线索、不判失败，与整道闸门一样要人读。
const DEF_LIT = /^(".*"|-?\d+(?:\.\d+)?|true|false)$/;
const defMap = new Map();
for (const f of files) {
  const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  L.forEach((ln, i) => {
    if (/^\s*(\/\/|\/\*|\*)/.test(ln)) return;
    const m = /\.get(?:Bool|Int|String|Double|Float)?\s*\(\s*"(kf_[^"]+)"[^)]*\)/.exec(ln);
    if (!m) return;
    const seg = ln.slice(m.index, m.index + m[0].length);
    const parts = seg.split(',');
    if (parts.length < 2) return;                       // 没写默认值 = 用底层默认, 不参与竞争
    const def = parts[parts.length - 1].replace(/[)\s;]+$/, '').trim();
    if (!DEF_LIT.test(def)) return;                     // 间接默认 (走 canonical 属性) 不算第二套字面量
    const key = m[1];
    if (!defMap.has(key)) defMap.set(key, []);
    defMap.get(key).push({ def, at: path.relative(ROOT, f).replace(/\\/g, '/') + ':' + (i + 1) });
  });
}
const defBad = [];
for (const [k, v] of [...defMap.entries()].sort()) {
  const set = new Set(v.map(x => x.def));
  if (set.size > 1) defBad.push(`  ${k} 有 ${set.size} 套字面量默认值: ` + v.map(x => `"${x.def}" @ ${x.at}`).join('  |  '));
}
console.log(`【同一键多套字面量默认值 ⇒ 两套真相】${defBad.length} 个 (只认单行字面量; 别名与跨行看不见 —— 计数见末行):`);
if (defBad.length) console.log(defBad.join('\n'));
console.log(`键面统计: 收集到 ${info.size} 个 kf_/别名键 · 别名表 ${aliasToKey.size} 条 · 拼装函数 ${builderKeys.size} 个 · 搬运函数 ${wrappers.size} 个 (${[...wrappers.entries()].filter(([, v]) => v.write).map(([n, v]) => n + (v.read ? '±' : '')).join(',')}) · 带字面量默认值的读取点 ${[...defMap.values()].reduce((a, b) => a + b.length, 0)} 处 (顾问级, 不判失败)`);
