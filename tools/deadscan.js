#!/usr/bin/env node
// 第六道闸门: 零引用声明扫描 (线索生成器, 不是判决)
// 用法: node tools/deadscan.js [--json]
// 口径: 扫 App/ 下顶层类型与 func 声明, 按标识符在**去掉注释后**的全源 (App/ + Tests/ + Widget/) 里计数;
//       计数 <=1 = 只找到声明自身。SwiftUI 协议成员/字符串间接入口会落在这里, 需人工判定。
//       (计数剥注释是第九十一批加的: 此前一句注释就能让 34 行零调用引擎从清单上消失。)
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

function swiftFiles(dir) {
  let out = [];
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out = out.concat(swiftFiles(p));
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

// 声明只从 App/ 收集, 但**计数要算上 Tests/ 与 Widget/**: 只扫 App/ 会把"仅被金标向量测试引用"的
// 协议构建函数误报成死码 (cmd12Echo / cmd30GWDeviceName / cmd32GWSetIot 都是假阳性, 第四十一批抓到)。
// Widget/ 也只进计数不进声明源: 927 扩展的 @main / WidgetBundle 是系统按名字调用的入口,
// 把它们当"零引用声明"报出来只会稀释清单。
const appFiles = swiftFiles(APP);
const testFiles = swiftFiles(path.join(ROOT, 'Tests'));
const widgetFiles = swiftFiles(path.join(ROOT, 'Widget'));
const norm = (f) => path.relative(ROOT, f).replace(/\\/g, '/');
const toSrc = (f) => ({ f: norm(f), lines: fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n').split('\n') });
const appSrcs = appFiles.map(toSrc);
const allSrcs = appSrcs.concat(testFiles.map(toSrc), widgetFiles.map(toSrc));
const srcs = appSrcs;                    // 声明清单来源

// 计数来源要**先剥掉注释**。第九十一批抓到这一处虚判: `Watchdog` 的 34 行引擎零调用,
// 但 LinkSenseKit 的一句注释里提到了它的名字 —— 计数因此变成 2 (声明 1 + 注释 1) 而从未报出来。
// "注释里提到"不等于"有人调用"，而本闸门的整个前提就是找零调用点。
// 字符串里的 `//` (URL 等) 不算注释起始 —— 字符串内可能藏着 selector/通知名的真实引用，那些是要留的。
function codeOnly(text) {
  return text.split('\n').map((line) => {
    let inStr = false, esc = false, out = '';
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (inStr) {
        out += c;
        if (esc) { esc = false; continue; }
        if (c === '\\') { esc = true; continue; }
        if (c === '"') inStr = false;
        continue;
      }
      if (c === '"') { inStr = true; out += c; continue; }
      if (c === '/' && line[i + 1] === '/') break;
      out += c;
    }
    return out;
  }).join('\n');
}
const allText = allSrcs.map((s) => codeOnly(s.lines.join('\n'))).join('\n');

// 协议/系统回调: 由系统按名字调用, 源码里找不到调用点属正常
const PROTOCOL_MEMBERS = new Set([
  'makeCoordinator', 'makeUIViewController', 'updateUIViewController', 'dismantleUIViewController',
  'numberOfPreviewItems', 'previewController', 'itemsForBeginning', 'urandom',
  'application', 'scene', 'intents', 'run', 'body', 'init', 'deinit',
  // UNUserNotificationCenterDelegate: 系统按名回调。同名方法有多个声明 (didReceive/willPresent)
  // 会让计数 ≥2 蒙混过关, 所以它必须走名单而不是靠计数
  'userNotificationCenter',
  // CBCentralManager 的 isConnected 辅助口 —— 由 CoreBluetooth 生命周期调用，不是本仓调用点。
  // 注: 名单只加"**确实被系统调**"的名字; 加了就等于承认这里有个盲区，所以每个名字都附一行理由 (第九十一批补)。
  'peripheralIsReady',
  // 第九十二批: 成员级"限定计数"上线后浮出来的一批系统按名调用口。每一条都是协议要求的方法,
  // 本仓不可能有调用点 —— 调用方是 SwiftUI / AppIntents / CoreBluetooth 运行时。
  'makeBody',                  // ButtonStyle / 自定义样式
  'perform',                   // AppIntent 六个 Intent 的入口
  'centralManager',            // CBCentralManagerDelegate / CBPeripheralDelegate 的一组重载
  'centralManagerDidUpdateState',
  'transferRepresentation',    // Transferable
  'encode', 'decode',          // Codable / Transferable
]);
// 注: 不豁免"可能被字符串/Selector 间接调用"的名字 —— handleNotificationAction 这类
// 到底有没有人接, 正是要扫出来的东西, 豁免等于把线索自己抹掉。

const funcRe = /^\s*(?:@\w+\s+)*(?:public|private|fileprivate|internal|open|static|class|final|mutating|\s)*func\s+([A-Za-z_]\w*)\s*\(/;
const typeRe = /^(?:public |private |internal |final )*(enum|struct|actor|protocol|class)\s+([A-Z]\w*)/;
// 顶层类型/扩展声明 (第 0 列起) —— 用来给每个 func 找"它挂在谁身上"。
// 第九十一批加的：只按**裸名字**计数会让 `CredentialOrg.enqueue(` 冒充 `WriteQueue.enqueue(` 的调用点，
// 于是一个连写入方都没有的死引擎被算成"有引用 = 活着"。成员必须按限定形式计。
const topTypeRe = /^(?:public |private |internal |final |extension )*(enum|struct|actor|protocol|class|extension)\s+([A-Z]\w*)/;
// 第九十三批加：**枚举里的 `static let` 常量**也纳入成员级计数。
// 起因是第九十二批核 idea 211（"三档时长令牌全 App 引用"）时手工数出来的：`DS.Duration.slow` 零引用，
// 而本工具报不出来 —— 它只认 `func` 声明，把"死常量"整类留在了盲区。
// 范围**刻意只收 enum 宿主**：枚举在这个 App 里就是命名空间 (`DS.Duration`/`DS.Metric`/`HotCache`…)，
// 里面的 static let 零引用就是纯死值；struct/class 的 static let 常是协议要求 (`PreferenceKey.defaultValue`)
// 或被 SwiftUI/反射按名读取，收进来会造噪音 —— 而噪音正是本工具第九十二批split成 A/B 两档要避免的东西。
const constRe = /^\s*(?:@\w+\s+)*(?:public |private |internal |open |final )*\bstatic\s+let\s+([A-Za-z_]\w*)\s*[:(]/;

const decls = [];
for (const s of srcs) {
  let owner = '';           // 当前顶层类型 (含 extension)
  let ownerKind = '';      // 它的声明关键字 (enum / struct / …)，用来限定"死常量"只判枚举命名空间
  let ownerStart = -1;
  const ranges = [];        // 每个顶层类型的行区间 [start, end)
  const kindAt = new Map(); // 类型名 -> 声明关键字
  s.lines.forEach((line, i) => {
    const tt = line.match(topTypeRe);
    if (tt && !line.trimStart().startsWith('//')) {
      if (owner && ownerStart >= 0) ranges.push({ name: owner, a: ownerStart, b: i });
      ownerKind = tt[1]; owner = tt[2]; ownerStart = i;
      if (!kindAt.has(owner)) kindAt.set(owner, ownerKind);
    }
  });
  if (owner && ownerStart >= 0) ranges.push({ name: owner, a: ownerStart, b: s.lines.length });
  const ownerAt = (i) => { const r = ranges.find((x) => i >= x.a && i < x.b); return r ? r.name : ''; };

  s.lines.forEach((line, i) => {
    const t = line.match(typeRe);
    if (t && !line.trimStart().startsWith('//')) {
      // `@main` 的类型是系统入口, 源码里永远零调用 —— 报它只会稀释清单。判据是**声明行或紧邻上一行**
      // 带 @main 属性 (不是"全仓随便有 @main 就算", 那样会误豁免同名类型)。
      const atMain = /@main/.test(line) || (i > 0 && /@main/.test(s.lines[i - 1]));
      if (!atMain) decls.push({ kind: 'type', name: t[2], where: s.f + ':' + (i + 1) });
    }
    const fmatch = line.match(funcRe);
    if (fmatch && !line.trimStart().startsWith('//')) {
      // 缩进即身份: 0 列 = **文件级函数** (不属于任何类型，走裸名计数)；4 列 = 类型成员 (走限定计数)；
      // ≥8 列 = 函数体内套的局部函数 —— 它不是 API，报"零引用"没有意义 (第九十二批把 `RecordSearch.rank`
      // 这种局部辅助函数当成员报出来就是假阳性)。
      const indent = line.match(/^\s*/)[0].length;
      if (indent >= 8) return;
      decls.push({
        kind: 'func', name: fmatch[1], where: s.f + ':' + (i + 1),
        owner: indent === 0 ? '' : ownerAt(i), file: s.f, line: i,
      });
    }
    // 枚举命名空间里的 `static let` 死常量 (第九十三批新增盲区覆盖)
    const cmatch = line.match(constRe);
    if (cmatch && !line.trimStart().startsWith('//')) {
      const indent = line.match(/^\s*/)[0].length;
      const own = ownerAt(i);
      // 缩进只排除 <4 (文件级常量走裸名计数那一路)。**不套用 func 那套"≥8 是局部"**：
      // Swift 里函数体内不能声明 `static let`，所以 8 列只会是**嵌套枚举** (`enum DS { enum Duration { static let slow } }`)
      // —— 第九十三批一开始按 indent===4 收，结果整组 DS.Duration/DS.Metric 常量全在盲区外，`slow` 那条就是这么漏的。
      if (indent >= 4 && own && kindAt.get(own) === 'enum') {
        decls.push({ kind: 'const', name: cmatch[1], where: s.f + ':' + (i + 1), owner: own, file: s.f, line: i });
      }
    }
  });
}

// 本仓声明过的类型集合 —— 只有挂在这些类型上的成员才走"限定计数"，
// 挂在系统类型 (extension Color 等) 上的仍走裸名计数，避免把系统协议实现误报。
const repoTypes = new Set(decls.filter((d) => d.kind === 'type').map((d) => d.name));
const allCode = allSrcs.map((s) => codeOnly(s.lines.join('\n'))).join('\n');

// —— 证据表一次扫完。 (第一版给每条声明各自重扫一遍全源码并在里面套 90 次正则替换，
//    1500 条成员直接把工具跑到超时被杀 —— 工具自己也要能被跑完，这不算是优化而是及格线。)
// qual[name][T]  = `T.name` 出现次数;  dot[name] = `.name` 出现次数 (含 T.name);
// ownBody[owner|name] = 该成员在**自己类型体内**被裸调的次数 (Swift 里 self 调用常省前缀)。
const qual = new Map(), dot = new Map(), ownBody = new Map(), bareOwn = new Map();
// 回溯取接收者时**不能**对 2MB 源码做 slice(0, idx) (那是 O(n²))，按字符往回读即可。
function recvBefore(txt, idx) {
  let j = idx - 1;
  while (j >= 0 && (txt[j] === ' ' || txt[j] === '\t')) j--;
  const end = j + 1;
  while (j >= 0 && /[A-Za-z0-9_$]/.test(txt[j])) j--;
  return txt.slice(j + 1, end);
}
// 用"点 + 名"扫描并回溯取接收者，而不是 `X\.Y` 整对匹配：
// 非重叠的 `X\.Y` 会把 `self.lock.fpStart(` 吃成 (self,lock) 而**漏掉 lock.fpStart** ——
// 第一版就是这样，于是一堆活成员被误报成死码 (fpStart / syncTime / StatsKit.kindOrder …共 76 条假阳性)。
for (const m of allCode.matchAll(/\.([A-Za-z_]\w*)/g)) {
  const nm = m[1];
  const recv = recvBefore(allCode, m.index);
  if (recv) {
    if (!qual.has(nm)) qual.set(nm, new Map());
    const byT = qual.get(nm);
    byT.set(recv, (byT.get(recv) || 0) + 1);
  }
  dot.set(nm, (dot.get(nm) || 0) + 1);
}
// 注: 这里**不再**补一遍 `\.name(` 的计数 —— 第一版补了，于是 `CredentialOrg.enqueue(` 被计两次
// (pass A 一次、pass B 一次)，减掉"别的仓内类型 1 次"后还剩 1，把本该报出来的死成员 `WriteQueue.enqueue`
// 又放过了。限定形态已经在 pass A 里覆盖，链式裸 `.name(` 在 Swift 里几乎都是 builder 尾点，
// 真漏了也只是少报一条线索，不该靠重复计数换覆盖率。
// 类型体内的裸调用。**两条精度规则** (第九十二批被这两条坑过):
//  ① 声明行也可能带同一行的函数体 (`static func rcFriendly(_ rc: Int) -> String { rcHint(rc) ?? … }`)
//     —— 只因为它是声明行就整行跳过，会把 `StatusParser.rcHint` 这种"体内确实调了"的活成员报成死的;
//  ② 体内引用可以不带括号 (`.map(dongleValue)`、`sorted { rank($0) }` 的传参写法) —— 只匹配 `name(`
//     会把 `BackupCanonical.dongleValue/gatewayValue/memberValue` 报错。
// 所以证据只认两种形状 (不放宽到"裸名出现"，否则同名局部变量会把死成员洗白):
//   调用 `name(` ； 传值 `(`/`,` + name + `,`/`)` (如 `map(dongleValue)`)。
// 声明行也不算整行跳过: 它可能带同一行的函数体 (`func rcFriendly(_ rc: Int) -> String { rcHint(rc) }`)，
// 只因为它是声明行就跳过，会把 `StatusParser.rcHint` 这种"体内确实调了"的活成员报成死的。
for (const s of allSrcs) {
  let ownerName = '';
  const bump = (nm) => { const k = ownerName + '|' + nm; ownBody.set(k, (ownBody.get(k) || 0) + 1); };
  s.lines.forEach((raw) => {
    const code = codeOnly(raw);
    const tt = raw.match(topTypeRe);
    if (tt && !raw.trimStart().startsWith('//')) ownerName = tt[2];
    if (!ownerName) return;
    const dm = code.match(funcRe);
    let scan = code;
    if (dm) {
      const key = ownerName + '|' + dm[1];
      if (!ownBody.has(key)) ownBody.set(key, 0);         // 先登记声明本身 (0 次调用)
      const bi = code.indexOf('{');
      scan = bi >= 0 ? code.slice(bi + 1) : '';           // 只扫声明之后的同一行函数体
    }
    // 三种证据形状: 调用 `name(`、传尾闭包 `name {`、把函数当值传 `name)`/`, name`/`: name`
    // (尾闭包与传值都是第九十二批补的: `guardOrBackup { … }`、`onPick: pickDay`、`applyAppearance { … }`
    //  此前一律看不见，把活成员报成死的。)
    for (const m of scan.matchAll(/(?<![\w$.])([A-Za-z_]\w*)\s*[({]/g)) bump(m[1]);
    // 值读取证据 (第九十三批为 `static let` 补的第四种形状): 常量不"被调用"，它**被读到**就是活的。
    // 逐 token 计到 owner|token，报告时减掉声明行自身那一次 (下面 constDeclCount)。
    // 已知过头的地方: 类型体内写 `let table = …` 这种同名局部绑定也会 +1 —— 那会让死常量躲进 B 档而不是 A 档，
    // 方向是"少报"，而 B 档本来就是给人读的线索栏，不拿它换误报。
    for (const m of code.matchAll(/(?<![\w$.])([A-Za-z_]\w*)\b/g)) {
      const k = ownerName + '|' + m[1];
      bareOwn.set(k, (bareOwn.get(k) || 0) + 1);
    }
    for (const m of scan.matchAll(/[(,=:]\s*([A-Za-z_]\w*)\s*[,)]/g)) bump(m[1]);
    for (const m of scan.matchAll(/(?:^|[\s(,:])(let|var|func|case)\s+([A-Za-z_]\w*)/g)) {
      // 只有**绑定**关键字后的名字不是调用 (let/var/func/case)。
      // 第一版把 if/guard/for 也一起扣，于是 `if variance() < 阈值` 被扣成 0 ——
      // 那是用一条假阳性去修另一条，判据要收窄到"确实不是调用"的那四个关键字。
      const k = ownerName + '|' + m[2];
      ownBody.set(k, (ownBody.get(k) || 0) - 1);
      void m[1];
    }
  });
}

// 成员的"活"证据: ① OwnType.name 明确限定调用; ② `.name(`/`.name{` 且**不能全部**归给别的仓内类型;
// ③ 自己类型体内真的调了它。 不这么做的话 `CredentialOrg.enqueue(` 会冒充 `WriteQueue.enqueue` 的调用点 ——
// 这正是第九十一批查出的那个假"活着" (WriteQueue 连写入方都没有，注释却写着"221 scenePhase 接线")。
function memberIsLive(owner, name) {
  const byT = qual.get(name) || new Map();
  if ((byT.get(owner) || 0) > 0) return true;
  const foreign = [...byT.entries()].filter(([T]) => T !== owner && repoTypes.has(T))
    .reduce((a, [, c]) => a + c, 0);
  if ((dot.get(name) || 0) - foreign > 0) return true;
  return (ownBody.get(owner + '|' + name) || 0) > 0;
}

const hits = [];      // A 档: 连裸名字在全库都只出现一次 = 确证的零引用
const weak = [];      // B 档: 限定证据没有，但同名在别处出现 (同名成员/自由函数混淆) ⇒ 只能当线索
// 声明行自身那次"读"要减掉: owner|name -> `static let` 声明条数
const constDeclCount = new Map();
for (const d of decls) if (d.kind === 'const') {
  const k = d.owner + '|' + d.name;
  constDeclCount.set(k, (constDeclCount.get(k) || 0) + 1);
}
function constIsLive(owner, name) {
  const byT = qual.get(name) || new Map();
  if ((byT.get(owner) || 0) > 0) return true;                       // Owner.name 限定读
  const key = owner + '|' + name;
  const reads = (bareOwn.get(key) || 0) - (constDeclCount.get(key) || 1);
  if (reads > 0) return true;                                       // 类型体内被读到
  const foreign = [...byT.entries()].filter(([T]) => T !== owner && repoTypes.has(T))
    .reduce((a, [, c]) => a + c, 0);
  return (dot.get(name) || 0) - foreign > 0;                        // 有点号读且不能全归别人
}
for (const d of decls) {
  if (PROTOCOL_MEMBERS.has(d.name)) continue;
  const bareRe = new RegExp('(?<![\\w$])' + d.name + '(?![\\w$])', 'g');
  const bareN = (allCode.match(bareRe) || []).length;
  if (d.kind === 'const' && d.owner && repoTypes.has(d.owner)) {
    if (constIsLive(d.owner, d.name)) continue;
    if (bareN <= 1) hits.push(d); else weak.push(d);
    continue;
  }
  if ((d.kind === 'func' || d.kind === 'const') && d.owner && repoTypes.has(d.owner)) {
    if (memberIsLive(d.owner, d.name)) continue;
    if (bareN <= 1) hits.push(d); else weak.push(d);
    continue;
  }
  // (?<!\w) 而不是 (?<![\w.]): 后者会把 Type.member / x.member 限定调用一起排掉, 造过 15 条假阳性
  if (bareN <= 1) hits.push(d);
}

if (process.argv.includes('--json')) {
  console.log(JSON.stringify({ certain: hits, sameNameSuspect: weak }, null, 0));
} else if (hits.length === 0 && weak.length === 0) {
  console.log('零引用扫描: App/ 下所有顶层类型与 func 都能找到调用点 ✓');
} else {
  console.log('A 档 · 确证零引用 ' + hits.length + ' 条 (全库连裸名都只出现一次; 逐条判定: 接线 / 删除 / 写清为什么留着):');
  for (const h of hits) console.log('  ' + h.kind.padEnd(4) + ' ' + (h.owner ? h.owner + '.' : '') + h.name + '  ' + h.where);
  // B 档存在的理由: 成员限定计数会把"同名不同主"的情况判成无证据 (confirmDestructive 在别的类型上被调)，
  // 而把它们全部塞进 A 档就是 20 条假阳性 —— 假阳性会把清单变成噪音, 噪音会让人整份不看。
  // 分成两档既保住新信号 (WriteQueue.enqueue 落在 B 档, 我逐条读代码后确认它是真的), 又不拿噪声糊人。
  console.log('\nB 档 · 同名混淆线索 ' + weak.length + ' 条 (该成员找不到限定调用，但同名在别处出现 ⇒ 必须人读):');
  for (const h of weak) console.log('  ' + h.kind.padEnd(4) + ' ' + (h.owner ? h.owner + '.' : '') + h.name + '  ' + h.where);
  console.log('\n注: 已排除名单里的协议成员与字符串间接入口见 tools/deadscan.js 顶部。');
}
process.exit(0);
