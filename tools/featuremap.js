#!/usr/bin/env node
// 功能点覆盖台账 (顾问级, 不判失败) — node tools/featuremap.js [--verbose] [--ids=1,93,390]
//
// 起因: 目标是"1050 项功能点全部实现"。docs/IDEA-BANK.md 是这 1050 条的权威清单 (经核 1..1050 无缺号)，
// docs/FEATURE-TRIAGE.md 只判了**可行性** (✅能做 / ⚠有条件 / ❌做不到)，而写了实现状态的行不到 30 条
// —— 也就是说"**做没做**"这件事 97% 没有任何证据回答过。逐条人读 1050 条会耗尽一整轮审计照样漏，
// 所以先做一张**可复算的覆盖表**: 本仓的实现证据统一是**编号标注** (`// 390 伪装口令`、文案 `(403)`)，
// 把标注抓出来就能分档，人只读候选而不读全量。
//
// 口径: **宁可少认也不要错认**。错认 = 把没做的说成做过，直接掩盖缺陷；少认只是多一条待人读的候选。
//   · `§N` 一律不当编号 —— 本仓的 `§` 是**文档章节** (CAPABILITY §2/§6、AUDIT-CODE §104)。
//     首版把 §6 当成 #6 的证据，判 ❌ 的第 6 项因此凭空长出三条"已实现"。
//   · 字符串按**引号奇偶**切，不用正则在整行上搜: 否则 `"已删 " + String(mac.prefix(6)) + " 的…"`
//     里两个真字面量**之间的那段代码**会被当成文案，`prefix(6)` 就读成了"界面上写着 (6)"。
//   · 注释里 1–2 位数只在"紧跟 //"时认，且后面不得接数量单位 (40 条 / 8 点 / -70 dBm)。
// 已知会漏 (所以定顾问级): ① 实现时没写编号的功能点会落进 A 档，需人读分辨"真没做"还是"只是没标注";
// ② 横杠区间只在跨度 ≤ 40 时展开 (见 expand 上方说明)，超出只认端点; ③ 字符串内部含 `//` 会把该行后半当注释
// (只会少认，不会错认)。
// 第九十五批把三个**错认**的口子堵了: 横杠区间无界展开 (凭空给几百个编号发"已实现")、判定行整行搜符号
// (被依据列覆盖)、`:` 当前导允许 (`:122` 这种源码行号冒领编号 122)。修完后 A/B/C/D 的数才是能用的数。
'use strict';
const fs = require('fs');
const path = require('path');

const MAX = 1050;
const argIds = (() => {
  const a = process.argv.find((x) => x.startsWith('--ids='));
  return a ? new Set(a.slice(6).split(',').map(Number)) : null;
})();
const VERBOSE = process.argv.includes('--verbose');
const read = (p) => (fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : '');

// 范围/列举展开: 957-957..963、389/398、306/307
// **带前导零的段一律丢** —— `06:00`、`0x07`、`08 分` 这种是时间/字节，不是创意编号 (#6 曾被 `06:00` 冒领过一次)。
// **跨度 > 40 的横杠只当分隔符，不展开成区间** (第九十五批)。判据是实测出来的: 全表 1036 条判定行里
// 最大跨度就是 40 (`683-722` 导出包)，而代码侧的 `264-466`/`460-795`/`457-916` 是成员中心页头注释里
// 把横杠当顿号用的产物 —— 它们凭空给 203/336/459 个编号发了"已实现"，featuremap 首版的
// 【有标注合计】924 条里大半是这么来的。**区间展开一旦超过这个宽度就必然在发假证据**:
// 真实收录包的宽度有上限，笔误的宽度没有上限。超出时退回只认端点 (与文件头 :16 那条口径一致)。
const MAXSPAN = 40;
function expand(raw) {
  const out = [];
  for (const seg of String(raw).split(/[/、,]/)) {
    const s = seg.trim();
    if (/^0\d/.test(s)) continue;
    const rg = /^(\d{1,4})[-–—](\d{1,4})$/.exec(s);
    if (rg) {
      const [lo, hi] = [+rg[1], +rg[2]];
      if (hi - lo > MAXSPAN) { if (lo <= MAX) out.push(lo); if (hi <= MAX) out.push(hi); continue; }
      for (let i = lo; i <= hi; i++) if (i <= MAX) out.push(i);
      continue;
    }
    const one = /^(\d{1,4})$/.exec(s);
    if (one) out.push(+one[1]);
  }
  return out;
}

// ---------- 1. 编号与名称 ----------
const titles = new Map();
for (const m of read('docs/IDEA-BANK.md').matchAll(/^(\d{1,4})\.\s*\*{0,2}([^*（(\n]+)/gm)) {
  const n = +m[1];
  if (n >= 1 && n <= MAX && !titles.has(n)) titles.set(n, m[2].trim());
}

// ---------- 2. 可行性判定 ----------
// 判定**只读表格第二格** (`\| 编号 \| 判定 \| …`)。首版是在整行上搜符号，而 FEATURE-TRIAGE 里还嵌着
// 形状相同的决策单行 (`| 119 | 充电状态显示 | 协议无充电状态字段 | … |`) —— 整行搜会把**依据列**里的
// 符号当成判定，把已经判过的 ✅ 覆盖掉。
// 第二格用的是一套**双轴词汇** (FEATURE-TRIAGE.md:47-52 已写明): `✖ 已舍弃` / `⛔ 不适用` /
// `⛔ 退回 MISS` / `⛔ 已合并到 N` / `⚠ PART` 都是独立结论，首版只认 `✅⚠❌` 三个，
// 于是这 6 条 (201/203/217/218/222/277) 被报成"判定台账没覆盖这些编号"—— 台账没错，是尺子瞎了。
const VERD = /(✅|⚠|❌|✖|⛔)/;
const verdict = new Map();
const ledgerWired = new Map();   // 编号 → 判定格里自带的 `file:line` 证据
for (const m of read('docs/FEATURE-TRIAGE.md').matchAll(
  /^\|\s*([0-9]{1,4}(?:\s*[–—-]\s*[0-9]{1,4}|(?:\s*,\s*[0-9]{1,4})*)?)\s*\|\s*([^|\n]*)\|/gm)) {
  const cell = m[2] || '';
  const v = VERD.exec(cell);
  if (!v) continue;
  // 判定格自带 `已接线 @file:line` ⇒ 台账自己给了实现证据，不再依赖代码里的编号标注。
  // 这是"能不能"轴之外的**第二条腿**，专治"做时没写编号"被误报成没做 (A 档里一大半是这种)。
  const wired = /已接线\s*@\s*([\w./\\-]+:\d+)/.exec(cell);
  const sym = wired ? 'W' : (/⛔\s*未实现/.test(cell) ? 'N' : v[1]);
  for (const n of expand(m[1].replace(/\s+/g, ''))) {
    if (n < 1 || n > MAX) continue;
    verdict.set(n, sym);
    if (wired) { if (!ledgerWired.has(n)) ledgerWired.set(n, []); ledgerWired.get(n).push(wired[1]); }
  }
}

// ---------- 3. 代码标注 ----------
const files = [];
for (const r of ['App', 'Widget', 'Tests']) {
  if (!fs.existsSync(r)) continue;
  (function w(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) w(p); else if (p.endsWith('.swift')) files.push(p);
    }
  })(r);
}
const cites = new Map();
const add = (n, where, line) => {
  if (!(n >= 1 && n <= MAX)) return;
  if (!cites.has(n)) cites.set(n, []);
  const hit = cites.get(n);
  if (!hit.some((h) => h.where === where)) hit.push({ where, line: line.trim().slice(0, 140) });
};
const UNIT = /^(?:条|个|位|秒|分钟|分|小时|天|周|月|年|次|项|组|套|档|层|路|元|字节|KB|MB|GB|ms|pt|%|px|dpi|行|列|栏|起|以内|外|dBm|v|x)/;
const TOKEN = '[0-9]{1,4}(?:[\\s]*[-–—/][\\s]*[0-9]{1,4})*';
// **`:` 与 `：` 故意不在允许集** (第九十五批)。本仓注释里 `LinkSenseKit :75/:122/:150/:237/:417`、
// `ExportItem.linkMetadata() (201)`、`ZKProtocol.swift:54/57` 这类**源码行号**到处是，首版把 `:` 当合法前导，
// 于是 D 档 8 条"判 ❌ 却有标注"全是行号冒领的假冲突 (122 就是这么从 `:122` 长出来的)。
const OK_BEFORE = /^[\s\-—>#（(、]$/;
const isYear = (n) => n >= 1900 && n <= 2100;

// 真字符串字面量: 屏蔽 `\"` 后按引号奇偶取奇数段; 再把**插值** `\(…)` 整段摘掉 ——
// `"「\(mac.prefix(6))」最近 \(n) 条"` 里的 `prefix(6)` 是代码，不是界面上写着的编号 (首版就把它认成了 #6)。
const stripInterp = (s) => {
  let out = '', i = 0;
  while (i < s.length) {
    if (s[i] === '\\' && s[i + 1] === '(') {
      let d = 0;
      for (i += 1; i < s.length; i++) { if (s[i] === '(') d++; else if (s[i] === ')') { d--; if (!d) { i++; break; } } }
      out += ' ';
      continue;
    }
    out += s[i++];
  }
  return out;
};
const literalsOf = (line) => line.replace(/\\"/g, '\u0001').split('"').filter((_, i) => i % 2 === 1).map(stripInterp);
// `cmds.js:119-120` / `ZKProtocol.swift:54/57` 这类**别处源码的行号**不是创意编号 (本仓到处在引 JS 权威核心)。
const JSREF = /\.(js|swift|py|ts):[\s]*$/;

for (const f of files) {
  const rel = f.replace(/\\/g, '/');
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  lines.forEach((raw, i) => {
    // **否定行整行不算实现证据** (第九十六批)。`// 725 (胁迫全屏确认卡) 判 ❌，本文件不提供` 这类
    // 免责声明里出现的编号，首版被当成"做了"—— 于是 D 档 (判 ❌ 却有标注) 永远消不掉。
    // 第一百零七批起把 `PART`/`那一半没做` 也算否定: 595 的月界大字就是这种情形 ——
    // 静态大字做了、"上滑跨月渐显"那一半没做。整行不认比"认成完成"诚实 (宁可少认也不要错认)。
    if (/判\s*❌|已判\s*❌|未建|未实现|不提供|没做|未做|不做|划掉|已删|零调用|零引用|零写入方|零读取方|无人读|无消费|恒为默认值|PART|那一半没做|未接线|没接线|先不画|尚无|待实测|挂起|暂缓|舍弃|不硬接|未编译/.test(raw)) return;
    const where = `${rel}:${i + 1}`;
    const qi = raw.indexOf('//');
    const code = qi < 0 ? raw : raw.slice(0, qi);
    // 剥掉 `///` 文档注释残留的那根斜杠 —— 规则② (紧跟 // 的编号) 的首版就是被它吃掉的:
    // `/// 8 密码强度条: …` 切掉 `//` 之后剩 `/ 8 密码强度条`，强约定正则从 `/` 起就匹配不上。
    // 全仓 `/// N 名称` 这种写法有几百处，于是 #8/#12/#63/#207/#588/#679 这类**早就做了**的条目
    // 成片掉进 A 档 (第九十六批靠名称反查才发现，根因在这儿)。
    const comment = qi < 0 ? '' : raw.slice(qi + 2).replace(/^\/+/, '');
    // (a) 文案里的 (N) / （N）: 只看真字面量
    for (const lit of literalsOf(code)) {
      for (const m of lit.matchAll(new RegExp('[(（](' + TOKEN + ')[)）]', 'g'))) {
        for (const n of expand(m[1])) add(n, where, raw);
      }
    }
    if (!comment.trim()) return;
    // (b) 注释: 紧跟 // 的编号 (最强约定 `// 390 伪装口令`、`// ---------- 389 … ----------`)。
    //     编号后面**必须接冒号或一个名字**才算: `case completed // 6` 这种行尾裸数字、
    //     `//   1. **只在剪贴板…**` 这种散文里的有序列表 (全仓 21 处) 都不是创意编号。
    //     数量单位照样要挡: `//   6 位密码 = AES-ECB(…)` 是长度说明，不是 #6。
    const strong = new RegExp('^\\s*(?:[-—#>\\s]*|[{（(])(' + TOKEN + ')(?=[:：、]|\\s+[\\u4e00-\\u9fa5A-Za-z])').exec(comment);
    if (strong) {
      const strongIds = expand(strong[1]);
      const rest = comment.slice(strong.index + strong[0].length).replace(/^\s+/, '');
      const unit = UNIT.exec(rest);
      // 数量单位守卫**只对两位数生效** (第九十七批口径)，第一百零七批放宽:
      // `// 6 位密码 = AES-ECB(…)` 这种是长度说明，必须挡；但 `// 588 组头计数徽标`、`// 679 年份大字分隔`
      // 里的"组头/年份"是**复合名词**，不是数量单位 —— 首版按第一个字判，把这些正经标注吃掉了
      // (实据: 补了标注的 588/679 连续两批仍然报"零标注")。
      // 判据: 单位字后面紧跟汉字 ⇒ 是名词的一部分，放行；跟标点/空格/结尾 ⇒ 是"多少个"的口径，拦住。
      const glued = unit !== null && /^[\u4e00-\u9fa5]/.test(rest.slice(unit[0].length));
      if (!(unit && (strongIds.some((n) => n < 100) || !glued))) {
        for (const n of strongIds) add(n, where, raw);
      }
    }
    // (c) 注释里其它位置: 只认 ≥3 位、非年份、前导字符在允许集、后不接单位，且不是 `x.js:119-120` 这种别处行号
    for (const m of comment.matchAll(new RegExp('([\\s\\-—>#（(、:：]?)(' + TOKEN + ')(?=([^0-9]))', 'g'))) {
      const nums = expand(m[2]);
      if (!nums.length) continue;
      if (nums.some((n) => n < 100 || isYear(n))) continue;
      if (!OK_BEFORE.test(m[1])) continue;
      const head = comment.slice(0, m.index + m[1].length);
      if (JSREF.test(head)) continue;
      const after = comment.slice(m.index + m[0].length).replace(/^\s+/, '');
      if (UNIT.test(after)) continue;
      for (const n of nums) add(n, where, raw);
    }
  });
}

// ---------- 5. 台账侧下落 (docs/AUDIT-*.md 的逐条判定) ----------
// A 档只说明"代码里没有编号标注"，它**分不清**"真没做"与"做时没写编号"。而本仓每批审计都在
// AUDIT-*.md / DEFERRED.md 的表里逐条写过下落 (`| 707 | 报告语言跟随 | PART | 证据… |`)。
// 把这张表按编号抓出来，A 档的每条就自动带上"上一次人读过它的结论"，人只需读**台账没下落**的那些。
// 注意这是**二手证据**: 台账本身也会过期 (第九十五批就撞上过 `✅ 可行 · 第九十三批前 ⛔ 未实现 → 现已补闸门`
// 这种把历史塞进判定格的行)，所以下落只用来缩小人读范围，不能当"已实现"记账。
const DOCFILES = ['docs/AUDIT-CODE.md', 'docs/AUDIT-GAP-CAUSES.md', 'docs/AUDIT-A.md', 'docs/AUDIT-B.md',
  'docs/AUDIT-C.md', 'docs/AUDIT-D.md', 'docs/AUDIT-E.md', 'docs/AUDIT-DEADCODE.md',
  'docs/DEFERRED.md', 'docs/ROADMAP-DRAFT.md', 'docs/VERIFY-CHECKLIST.md'];
// **归一化**而不是直接取匹配到的格子: AUDIT-E 的表有 8 列，第 4 列是**照抄 FEATURE-TRIAGE 的可行性判定**
// (`✅`), 第 3 列才是本批下落 (`候选 MISS` / `H 包内舍弃`)。首版把符号列当下落列，
// 于是 233/235/239 这三条**包7 已舍弃**的条目被归进"台账记着已落"，A0 的分档整个失真。
// 规则: 从左往右找**第一个含下落词**的格; 只含判定符号的格跳过; 下落词按语义映射成五档。
const DISCARD = /舍弃|划掉|不实现|暂缓|降级|排除/;
const DONE = /DONE|已落|已接|已补|已修|做完|真生效|默认档就是/;
const PARTW = /PART|补一半|一半/;
const MISSW = /MISS|漏做|无命中/;
// 第一百六十三批补的两档"有下落的等待/合并"。起因: 本轮施工面 (A0-t) 名单里混进了
// 台账其实早写过"为什么不在这轮做"的条目 —— 339 写着「已合并到既有切换器」、643 写着
// 「挂起，不是漏做：没有 iPad 也没有模拟器」、595/826 写着「无编译器时先不做」、990 写着「等一句拍板」。
// 这些句子里一个 DISCARD/DONE 词都没有，`classify` 返回 null ⇒ 条目回落到 FEATURE-TRIAGE 的
// MISS/PART，被报成"确认没做，本轮施工面"。照着这份名单施工，就会把作者已经否决或已经挂起的东西再做一遍
// (与第九十七批那次同族，只是方向相反：那次是改判行没被读到，这次是下落句没有固定用词)。
// 分成两档而不是并进 A0-x: 「已合并」= 不要重做；「等窗口/等拍板」= 想做，但条件不在本机。
const MERGED = /已合并|归并到|并入既有|不再另造|不另建|不再另立|已经是事实/;
const HELD = /等一句拍板|等拍板|等首编译|需要一次真编译|无编译器时先|先不做|挂起，不是漏做|没有 iPad|没有模拟器|需要真机|需要一次真机/;
function classify(cells) {
  // 只写 `PART` / `MISS` 的格子是**判定**，不是下落。第一百六十三批实撞：595 那行是
  // `| 595 | 月界渐显大标 | PART | ……先不做…… |`，旧写法在第三格就返回 PART，永远读不到
  // 第四格里"在等什么"。所以命中裸判定时先攥着，继续往后找更实的下落，找不到才用它。
  let verdictHit = null;
  for (let j = 1; j < cells.length; j++) {
    const c = cells[j];
    if (/^[✅⚠❌✖⛔\s]*$/.test(c)) continue;          // 纯判定列 = 可行性轴，不是下落
    if (MERGED.test(c)) return { status: '已合并', why: c };
    if (HELD.test(c)) return { status: '有下落·等待', why: c };
    if (DISCARD.test(c)) return { status: '舍弃', why: c };
    if (DONE.test(c)) return { status: '已落', why: c };
    if (!verdictHit) {
      if (PARTW.test(c)) verdictHit = { status: 'PART', why: c };
      else if (MISSW.test(c)) verdictHit = { status: 'MISS', why: c };
      else if (/需人核|待核|待实测|待做/.test(c)) verdictHit = { status: '待核', why: c };
    }
  }
  return verdictHit;
}
// 同一编号在多份台账里各有一行。**旧的"第一条命中即定"是错的**：DOCFILES 把 AUDIT-B/C/GAP-CAUSES
// 这些历史审计排在前面，于是 339/595/643 带着当年的 `MISS` 就定了案，而 DEFERRED 里后来写的
// 「已合并到既有切换器」「挂起，不是漏做：没有 iPad 也没有模拟器」「无编译器时先不做」永远读不到 ⇒
// 这三条被报成"确认没做，本轮施工面"。(第一百六十三批实撞：14 条施工面里有 7 条台账其实写过下落。)
// 现在的优先级 = **活的台账赢**：DEFERRED > VERIFY-CHECKLIST > ROADMAP-DRAFT > 历史审计；
// 同文档内后写的行赢 (DEFERRED 是逐批往上追加的)。不再给"改判要做"开无条件特例 ——
// 那条特例在第一百六十三批会压过更晚写的「停在等一次真编译门后」，让名单又开始骗人。
const SRC_RANK = (rel) => (rel === 'docs/DEFERRED.md' ? 3
                          : rel === 'docs/VERIFY-CHECKLIST.md' ? 2
                          : rel === 'docs/ROADMAP-DRAFT.md' ? 1 : 0);
const ledger = new Map();
for (const rel of DOCFILES) {
  const lines = read(rel).split(/\r?\n/);
  // DEFERRED/ROADMAP 的「舍弃」小节用 `| 编号 | 名称 | 为什么不做 |` 的形状记账，第二格是名称而不是
  // 状态词 —— 规则① 抓不到它。于是 A 档会把**已被有理由地划掉**的条目报成"真没做"，
  // 照着施工就是把作者已经否决过的方案再做一遍 (第九十七批实撞: 手势族 52/53/54/55/58 都在 `DEFERRED.md:36-41`)。
  let discardSection = false;
  // 「停在等一次真编译门后的六条」这类小节：行形状与舍弃表一样是 `| 编号 | 原句 | 为什么现在不动 |`，
  // 但语义不是"不做"而是"想做，条件不在本机"。第一百六十三批实撞：40 那格写着"与**已落地**的 806 重叠"，
  // 被 DONE 抓成"已落"⇒ 报进 A0-d 让人以为这条已经做完了。小节标题说了算 (与 discardSection 同机制)。
  let holdSection = false;
  // 「拍板变更登记」小节的行首格写成 `| 52 旋钮充能 | 旧结论 | 新定案 |` —— 编号后面跟着名字。
  // 这两件事都是第九十七批撞出来的: ① 首格正则只收裸编号，登记行整批看不见；
  // ② 就算看见了，"第一条命中即定"会让**上文那条旧"舍弃"**赢过下文的改判，
  //   于是本工具会反过来告诉下一批"52/53/233/235/917/920 不要做"，而那些正是当天拍板要做的。
  let ratifySection = false;
  lines.forEach((ln, i) => {
    if (/^#{2,4}\s/.test(ln)) {
      discardSection = /舍弃|划掉|不实现|暂缓|降级|排除/.test(ln);
      holdSection = /等一次真编译|门后的.{0,4}条|不是不做|等拍板|挂起/.test(ln);
      ratifySection = /拍板|变更|改判|定案/.test(ln);
    }
    if (!ln.startsWith('|')) return;
    const cells = ln.split('|').slice(1, -1).map((c) => c.trim());
    if (cells.length < 3) return;
    if (!/^\d{1,4}(?:\s*[/、,]\s*\d{1,4})*(\s+[^\d|]{1,26})?$/.test(cells[0])) return;   // 首格=编号(可带短名，名里不许有数字)，排除 `| 编号 |` 表头
    // 首格允许"编号 + 短名" (`| 52 旋钮充能 | … |` 的登记表形状)，取编号部分时要**先剥掉名字**:
    // expand() 按 `/、,` 切段，`52旋钮充能` 既不是一串编号也不是区间，整段被丢 ⇒ 改判行一条都进不了台账
    // (第一版就是这样，52/53/233/235/917/920 明明拍板要做，工具还在说"不要重做")。
    // 第二版仍漏：剥名字用的是 `/^(\d{1,4})/` 只取**头一个**编号，于是
    // `| 31/32/33/34/35/214 外观族 | … | 全做 … |` 只登记了 31 —— 32/34/35 至今被报成"台账从未记过"，
    // 而它们第一百四十批就拍板要做了 (第一百六十三批实撞)。270 行已保证首格形如 `编号表[ 短名]`，
    // 所以按空白切第一段就是那个编号表。
    const ids = expand(cells[0].split(/\s+/)[0]);
    if (!ids.length) return;
    let found;
    // 拍板登记表与普通下落表在 DEFERRED 里可以**同属一个 `##` 小节** (595 那行就紧接在登记表后面)，
    // 只按小节标题定性会把普通行误读成改判行。登记表行有固定形状可用：首格是 `编号 + 名称`
    // (台账约定的列序是 编号+名 / 旧结论 / 新定案 / 口径)，而普通下落表首格是裸编号。
    const ratifyShape = /^\d{1,4}(?:\s*[/、,]\s*\d{1,4})*\s+[^\d|]/.test(cells[0]);
    if (ratifySection && ratifyShape) {
      // 登记表的列序是 `| 编号+名称 | 旧结论 | 新定案 | 落地口径 |` —— 只读**新定案**那一格。
      // 整行扫是不行的: 旧结论格里全是"舍弃/划掉"这些词，扫出来的永远是旧结论，改判就白登记了。
      const d = cells[2] || '';
      found = /不做|不建|划掉|不改行|不新建|不另造/.test(d)
        ? { status: '舍弃', why: cells.slice(1).join(' | ') }
        : /等一句拍板|等拍板|等首编译|需要一次真编译|无编译器时先|先不做|挂起|需要真机/.test(d)
          ? { status: '有下落·等待', why: cells.slice(1).join(' | ') }
          : { status: '改判要做', why: cells.slice(1).join(' | ') };
    } else {
      found = classify(cells);
      // 「舍弃」小节的行形状是 `| 编号 | 名称 | 为什么不做的理由 |` —— 第二格是名称、第三格是自由文案，
      // 里面未必含下落词，所以按**小节标题**而不是按格子里的词定性。
      if (!found && discardSection) found = { status: '舍弃', why: cells.slice(1).join(' | ') };
      // 「等一次真编译/等拍板」小节里，除非这一行自己写了"不建/已合并"这种硬结论，
      // 否则它的下落就是"在等条件" —— 小节标题赢过格子里那些顺带出现的"已落地"字样。
      if (holdSection && (!found || found.status === '已落' || found.status === 'PART' || found.status === 'MISS' || found.status === '待核'))
        found = { status: '有下落·等待', why: (found ? found.why + ' ‖ ' : '') + cells.slice(1).join(' | ') };
    }
    if (!found) return;
    const rec = { status: found.status, where: `${rel}:${i + 1}`, why: found.why.slice(0, 96), rank: SRC_RANK(rel) };
    for (const n of ids) {
      if (n < 1 || n > MAX) continue;
      const old = ledger.get(n);
      // 优先级只有一条：更活的文档赢，同文档里后写的行赢 (见 SRC_RANK 上方)。
      // 第一百六十三批把旧那句"改判行无条件覆盖"删掉了 —— 有了 rank 之后它就是多余的，
      // 而且会反向出错：外观族在登记表里被改判"全做"，后面「停在等一次真编译门后」那张表又把这六条
      // 明确停下；无条件覆盖会让"要做"压过更晚的"在等条件"，名单就又开始骗人。
      if (!old || rec.rank >= old.rank) ledger.set(n, rec);
    }
  });
}

// ---------- 6. 名称证据 (专治"做时没写编号") ----------
// ---------- 6. 名称证据 (专治"做时没写编号") ----------
// 1–99 号在注释**中段**一律不认 (规则③ 要求 ≥3 位)，而本仓有大量 `三态语义胶囊 (64) + 63 信号格 + 67 耗时`
// 这种把小序号写在注释中间的写法 —— 于是 #63/#64 这种**早就做了**的条目成片落进 A 档，
// 照着 A 档施工就把同一功能再做一遍。第二档证据: 拿 IDEA-BANK 标题名词去搜代码，命中就带 file:line
// 列出来给人读 (只缩小人读范围，**不**算已实现记账)。只对 A 档跑: 全量 1050×3.5 万行要跑几分钟。
const STOP = /^(系统|原生|官方|新版|旧版|可选|建议|优先|默认|其他|一个|两种|三类|Apple|iOS|iPad|iPhone|Watch|Widget|Wallet|SF|Charts|Notion|Telegram|Spotify|Duolingo|Flighty|Apollo|Things|HomeKit|Linear|Gusto|Bear|NFC|OTP|CSV|JSON|PDF|RSSI|URL|HEX|Mac|App|SDK|Dark|Light)$/;
const nameTokens = (t) => {
  const ws = (t || '').replace(/[⚠❌✅⛔✖]/g, ' ')
    .split(/[\s·、,，/()（）\-—:.：]+/)
    .filter((w) => w.length >= 3 && !STOP.test(w) && !/^\d+$/.test(w));
  // 中文偏正结构**中心语在后** ("三态语义色" vs 代码里写的 "三态语义胶囊")，整词相等会漏。
  // 补一个 4 字前缀变体：命中"前 4 字相同"的词，代价是噪音略增，但 A1 本来就只是"给人读的候选"。
  const out = [...ws];
  for (const w of ws) if (/[\u4e00-\u9fa5]/.test(w) && w.length >= 5) out.push(w.slice(0, 4));
  return out;
};
const nameHits = new Map();
function scanNames(ids) {
  const corpus = files.map((f) => ({ rel: f.replace(/\\/g, '/'), text: fs.readFileSync(f, 'utf8') }));
  for (const n of ids) {
    const toks = nameTokens(titles.get(n));
    if (!toks.length) continue;
    const hits = [];
    for (const { rel, text } of corpus) {
      if (!toks.some((t) => text.includes(t))) continue;          // 整文件先过一遍，不逐行扫
      const lines = text.split(/\r?\n/);
      for (let i = 0; i < lines.length && hits.length < 2; i++) {
        const t = toks.find((x) => lines[i].includes(x));
        // 把**撞上的那个词**一起打出来：第一百六十九批读完 9 条 A1，八条的"证据"是标题词落在隔壁域
        // (如 #830 TipKit 撞在致谢文案、#354 归档撞在成员归档上)。只给 file:line 的话，
        // 下一个人还得点开文件重读一遍才知道是假线索 —— 词就在行里，顺手打出来最便宜。
        if (t) hits.push(`${rel}:${i + 1} 撞词「${t}」 ${lines[i].trim().slice(0, 52)}`);
      }
      if (hits.length >= 2) break;
    }
    if (hits.length) nameHits.set(n, hits);
  }
}

// ---------- 6.9 区间/包头证据单独成档 (2026-10-12 对抗式复核后新增) ----------
// 起因: `// 收录 478/548/683-709/712/714-722`、`// 包9 告警中心 (723-724/726-743/745-747)`、
// `// ---------- VoiceOver (846-857) ----------` 这类**包头/分节行**，会给区间里每个编号都发一张
// "已实现"票。可包头只声明"本文件收录了这一包"，逐条做没做它一个字都没说。
// 实测依据 (state/recon/coverage-adversarial-2026-10-12.md): 只靠区间拿到标注的 30 条逐条读后
// **16 条其实没做、9 条半做、5 条真做** —— 谎报率 >50%，而随机抽样 179 条的整体谎报率是 6.5%。
// 口径: 一个编号的**全部**证据行都是"带横杠区间的包头行" ⇒ 不计入实现证据，改列 R 档等人读。
// 只做降级不做判定 —— 到底做没做仍要人读，这条改的是"不许拿包头发已实现"。
const HEADER_HINT = /(收录|覆盖\s*idea|包\s*\d|区段|功能包|^\s*[/#*\s>*=]*\s*[-=]{3,})/;
const isRangeHeader = (h) => /[0-9]{1,4}\s*[-–—]\s*[0-9]{1,4}/.test(h.line) && HEADER_HINT.test(h.line);

// ---------- 7. 分档 ----------
const cat = { noVerdict: [], okNoCite: [], cited: [], warnNoCite: [], badNoCite: [], badCited: [],
              dropNoCite: [], dropCited: [], declared: [], wired: [], rangeOnly: [] };
for (let n = 1; n <= MAX; n++) {
  if (argIds && !argIds.has(n)) continue;
  const v = verdict.get(n) || '?';
  const all = cites.get(n) || [];
  const c = all.filter((h) => !isRangeHeader(h)).length;
  // 只有区间包头给的票 ⇒ 不算实现证据 (上面 6.9)
  if (all.length && c === 0) { cat.rangeOnly.push(n); continue; }
  if (v === '?') cat.noVerdict.push(n);
  else if (v === 'N') cat.declared.push(n);
  else if (v === 'W') { if (c) cat.cited.push(n); else cat.wired.push(n); }
  else if (v === '✅') { if (c) cat.cited.push(n); else cat.okNoCite.push(n); }
  else if (v === '⚠') { if (c) cat.cited.push(n); else cat.warnNoCite.push(n); }
  else if (v === '✖' || v === '⛔') { if (c) cat.dropCited.push(n); else cat.dropNoCite.push(n); }
  else { if (c) cat.badCited.push(n); else cat.badNoCite.push(n); }
}
const list = (a) => (a.length <= 60 ? a.join(',') : a.join(','));
scanNames(cat.okNoCite);
console.log(`编号权威 IDEA-BANK ${titles.size} 条 · 判定权威 FEATURE-TRIAGE 覆盖 ${verdict.size} 条 · 扫了 ${files.length} 个 Swift 文件`);
console.log('');
console.log('【A · 判 ✅ 可行却零编号标注 ⇒ 未实现候选】' + cat.okNoCite.length + ' 条');
{
  const named = cat.okNoCite.filter((n) => nameHits.has(n));
  const bare = cat.okNoCite.filter((n) => !nameHits.has(n));
  console.log(`  A1 · 标题词在代码里能搜到 ⇒ 疑似"做时没写编号"，${named.length} 条 (逐条人读，别重做):`);
  for (const n of named) console.log(`    #${n} ${(titles.get(n) || '').slice(0, 16)} ⇒ ` + nameHits.get(n).slice(0, 2).join(' ‖ '));
  console.log(`  A0 · 标注与名称**都**无证据 ⇒ 真没做候选:`);
  const out = { gone: [], held: [], done: [], todo: [], unknown: [] };
  for (const n of bare) {
    const r = ledger.get(n);
    if (!r) out.unknown.push(n);
    else if (/舍弃|划掉|不实现|暂缓|降级|已合并/.test(r.status)) out.gone.push(n);
    else if (/有下落/.test(r.status)) out.held.push(n);
    else if (/^✅|已落|已接线|做完|OK/.test(r.status)) out.done.push(n);
    else out.todo.push(n);
  }
  console.log(`    A0-x · 已被有理由地划掉、或**已合并到既有实现** (DEFERRED/ROADMAP 记着理由) ⇒ **不要重做** ${out.gone.length} 条: ` + list(out.gone));
  for (const n of out.gone) console.log(`      #${n} ${(titles.get(n) || '').slice(0, 16)} ← ${ledger.get(n).why} 【${ledger.get(n).where}】`);
  console.log(`    A0-w · 台账写明在等什么 (等拍板 / 等一次真编译 / 等真机·iPad·模拟器) ⇒ 条件不在本机，**不在本轮凭空做** ${out.held.length} 条: ` + list(out.held));
  for (const n of out.held) console.log(`      #${n} ${(titles.get(n) || '').slice(0, 16)} ← ${ledger.get(n).why} 【${ledger.get(n).where}】`);
  console.log(`    A0-d · 台账其实记着"已落"⇒ 标注形式没被抓到，人读确认 ${out.done.length} 条: ` + list(out.done));
  console.log(`    A0-t · 台账判 MISS/PART 且**没写下落** ⇒ 本轮施工面 ${out.todo.length} 条: ` + list(out.todo));
  console.log(`    A0-u · 台账从未记过 ⇒ 只能人读 ${out.unknown.length} 条: ` + list(out.unknown));
  for (const n of [...out.todo, ...out.unknown]) console.log(`      #${n} ${(titles.get(n) || '').slice(0, 22)}`);
}
console.log('【B · 判 ⚠ 且零标注 ⇒ 与"有条件/待实测"一致】' + cat.warnNoCite.length + ' 条');
console.log('【C · 判 ❌ 且零标注 ⇒ 与协议或平台硬缺口一致，不是缺陷】' + cat.badNoCite.length + ' 条');
console.log('【D · 判 ❌ 却有标注 ⇒ 台账与代码打架，必须逐条人读】' + cat.badCited.length + ' 条: ' + list(cat.badCited));
console.log('【E · FEATURE-TRIAGE 里查不到判定行 ⇒ 判定台账本身没覆盖这些编号】' + cat.noVerdict.length + ' 条: ' + list(cat.noVerdict));
console.log('【F · 判 ✖ 已舍弃 / ⛔ 不适用·退回·已合并 ⇒ 作者定性出局，不是缺陷】' +
  (cat.dropNoCite.length + cat.dropCited.length) + ' 条 (零标注 ' + cat.dropNoCite.length +
  ' · 有标注 ' + cat.dropCited.length + ': ' + list(cat.dropCited) + ')');
console.log('【G · 判定行自己写着"⛔ 未实现"⇒ 不用猜，台账已认账】' + cat.declared.length + ' 条: ' + list(cat.declared));
console.log('【R · 只拿到"区间/包头"标注 ⇒ 不算实现证据，逐条人读】' + cat.rangeOnly.length + ' 条: ' + list(cat.rangeOnly));
for (const n of cat.rangeOnly) {
  const hs = cites.get(n) || [];
  console.log(`    #${n} ${(titles.get(n) || '').slice(0, 18)} ← ` + hs.map((h) => `${h.where} ${h.line.slice(0, 60)}`).join(' ‖ '));
}
console.log('【W · 判定行自带"已接线 @file:line"，但代码里没有编号标注 ⇒ 采信台账，抽样复核】' + cat.wired.length + ' 条');
for (const n of cat.wired) console.log(`    #${n} ${(titles.get(n) || '').slice(0, 18)} @` + (ledgerWired.get(n) || []).join(','));
console.log('【实现证据合计】代码标注 ' + (cat.cited.length + cat.badCited.length + cat.dropCited.length) +
  ' 条 + 仅台账 file:line ' + cat.wired.length + ' 条 = ' +
  (cat.cited.length + cat.badCited.length + cat.dropCited.length + cat.wired.length) + ' 条 (顾问级, 不判失败)');
if (VERBOSE) {
  for (const n of cat.okNoCite) console.log(`  A #${n} ${titles.get(n) || ''}`);
  for (const [n, hs] of [...cites.entries()].filter(([n]) => !argIds || argIds.has(n)).sort((a, b) => a[0] - b[0])) {
    console.log(`  C #${n} ${(titles.get(n) || '').slice(0, 22)} [${verdict.get(n) || '?'}] ` + hs.slice(0, 3).map((h) => h.where).join(' , '));
  }
}

// ---------- 8. 分档判据的常驻正控/反控 (第一百六十三批) ----------
// 这批一次改了四处判据 (MERGED/HELD 词表、文档优先级、登记表行形状、"等编译"小节定性)，
// 每处都可能被下一次改台账的人顺手碰坏，而分档错了**不报错**、只是把"不要重做/在等条件"的东西端回施工面。
// 所以把**已在 DEFERRED 写明下落**的编号钉成断言，台账或判据一改就先红。
// 默认就会跑 (不靠谁记得加 --selftest)，只是逐条 ✓ 只在 --selftest 下打印；回归时退出码 2。
// 反控 #299 (必须是"已落") 证明"等一次真编译"那一档没有把整张表一把抓。
{
  const SELF = process.argv.includes('--selftest');
  // 2026-10-11 拍板后重钉: 235 做 (最小实现, 已落地) ⇒ 改判要做 (与 54 同档);
  // 276/278/297/416/447/990 判 ❌ 定案 ⇒ 舍弃 (A0-x 不要重做档)。这七条原来钉的是"有下落·等待"。
  const want = [[339, '已合并'], [144, '舍弃'], [235, '改判要做'], [276, '舍弃'],
                [278, '舍弃'], [297, '舍弃'], [447, '舍弃'], [416, '舍弃'],
                [48, '有下落·等待'], [40, '有下落·等待'], [595, '有下落·等待'], [643, '有下落·等待'],
                [54, '改判要做'], [299, '已落'], [990, '舍弃']];
  let bad = 0;
  for (const [n, s] of want) {
    const got = (ledger.get(n) || {}).status || '(无记录)';
    if (got !== s) { console.log(`✗ 分档回归: #${n} 期望「${s}」实际「${got}」`); bad++; }
    else if (SELF) console.log(`  ✓ #${n} ${s}`);
  }
  if (SELF) console.log(bad ? `✗ featuremap 分档自测失败 ${bad} 条` : `featuremap 分档自测 ✓ (${want.length} 条，含 1 条反控)`);
  if (bad) process.exit(2);
}
