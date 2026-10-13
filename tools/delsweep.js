#!/usr/bin/env node
// tools/delsweep.js — 「本机删掉一条凭证」与「锁端那一半」的对账线索表（第一百五十三批新增，**顾问级，不判失败**）
//
// 为什么要有它：第一百五十二批改撤销那条路时看清了一件事 ——
// 台账侧删一条凭证有 15 条不同的路径，而"锁端怎么处理"只有三种正当答案：
//   直发命令 (pwdDelete/fpDelete) / 排一条待下发 (enqueue "del_pwd"|"del_fp") / 换槽 (pwdModify 把旧 alias 让出来)。
// 第四种答案是**只动本机**，那必须写下来（界面上也得写），否则用户读到的就是"我收回了这人的开门权"。
// 这条不变式没有类型：编译器看不见，形状闸门也看不见，只有把"删除点"与"它附近做了什么"摊开给人读。
//
// 所以这一道**不是判据，是阅读清单**：
//  · 数不出配对、又没有声明的站点 ⇒ 必须人读（报线索，退 0，不判失败）。
//  · 声明写法：站点附近任意一行注释里带 `撤权口径:` （沿用本仓 `指针检查:忽略` 那一族的自_documenting 惯例），
//    工具会把那句话原文打出来，让下一个人读到同一句解释。
//  · ±25 行的窗口是**启发式**：它会漏（配对写在很远之外）也会误配（隔壁函数的词被算进来）——
//    第一百五十二批第一版就把还原侧的 reclaim 误当成了删除侧的配对，所以还原类的词整个不进配对表。
//    因此这里没有一条结论可以不看代码就采信。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SITE = /DB\.del(Pwd|Fp|Card)\(/;
const PAIR = /(pwdDelete|fpDelete|cardDelete)\s*\(|enqueue\s*\([^)]*"del_(pwd|fp|card)"|pwdModify|fpModify/;
const DECLARE = /撤权口径\s*[:：]/;      // 中英冒号都认：注释是中文行文，写全角冒号是自然结果

function swiftFiles(d, out = []) {
  if (!fs.existsSync(d)) return out;
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) swiftFiles(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const rows = [];
for (const f of swiftFiles(path.join(ROOT, 'App'))) {
  const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  L.forEach((ln, i) => {
    if (!SITE.test(ln) || /^\s*(?:private |public |static )*func del/.test(ln)) return;
    const win = L.slice(Math.max(0, i - 25), i + 9).join('\n');
    const rel = path.relative(ROOT, f).replace(/\\/g, '/');
    const paired = PAIR.exec(win);
    const declared = DECLARE.test(win);
    if (paired) rows.push({ k: 'paired', t: `${rel}:${i + 1}  ${ln.trim().slice(0, 52)}  ← ${paired[0].slice(0, 30)}` });
    else if (declared) {
      const why = (win.match(/撤权口径\s*[:：][^\n]*/) || [''])[0].replace(/\*/g, '').trim().slice(0, 76);
      rows.push({ k: 'declared', t: `${rel}:${i + 1}  ${ln.trim().slice(0, 52)}  ← 已声明「${why}」` });
    } else rows.push({ k: 'needread', t: `${rel}:${i + 1}  ${ln.trim().slice(0, 52)}` });
  });
}
const needread = rows.filter(r => r.k === 'needread');
console.log(`删除点对账 (顾问级, 不判失败): 共 ${rows.length} 处 · 找到锁端配对 ${rows.filter(r => r.k === 'paired').length} · 已写明只动本机 ${rows.filter(r => r.k === 'declared').length} · **需要人读 ${needread.length}**`);
if (needread.length) {
  console.log('\n【未声明的本地删除点 ⇒ 逐条开代码确认锁端那一半怎么交代的】');
  needread.forEach(r => console.log('  ' + r.t));
}
console.log('\n注: ±25 行窗口是启发式, "找到配对"那一档同样要人读一遍才可信 (配对可能属于隔壁函数)。');

// ---------- 第二张清单：UI 层的不可汇点有没有走二次确认 (第一百六十七批) ----------
// 为什么挂在道同一支里：这一族与上面那条是同一件事的两半 —— 上面管"删完之后锁端那一半怎么交代"，
// 这里管"**按下那一下**有没有先问一句"。本仓的不可逆动作有统一入口 (`confirmDestructive` /
// `confirmDestructiveTyped` / SwiftUI 的 `.confirmationDialog`)，所以"直接调汇点的按钮"就是漏了问。
// 同样是**阅读清单不是判据**：确认可能写在十行外的外层按钮里，也可能这个动作本来就可逆 (移到回收站)。
// 声明写法沿用同一族：站点附近注释里带 `确认口径:` 说明为什么不需要再问一次。
const UI_SINK = /\b(DB\.removeDevice|DB\.delPwd|DB\.delFp|DB\.delCard|CredentialOrg\.purgeBin|DemoKit\.clearAll|AuditChain\.destroyAll|RecordSearch\.deleteNamedView|DiagKit\.purgeOrphanLogCaches)\s*\(/;
const CONFIRM = /confirmDestructive(Typed)?\s*\(|\.confirmationDialog|\.alert\s*\(/;
const CDECLARE = /确认口径\s*[:：]/;
const crows = [];
for (const f of swiftFiles(path.join(ROOT, 'App/UI'))) {
  const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  L.forEach((ln, i) => {
    if (!UI_SINK.test(ln) || /^\s*(?:@\)?\s*)?(?:private |public |static )*func /.test(ln)) return;
    if (/^\s*\/\//.test(ln)) return;
    const win = L.slice(Math.max(0, i - 14), i + 4).join('\n');
    const rel = path.relative(ROOT, f).replace(/\\/g, '/');
    const conf = CONFIRM.exec(win);
    const declared = CDECLARE.test(win);
    if (conf) crows.push({ k: 'asked', t: `${rel}:${i + 1}  ${ln.trim().slice(0, 46)}  ← ${conf[0].slice(0, 22)}` });
    else if (declared) {
      const why = (win.match(/确认口径\s*[:：][^\n]*/) || [''])[0].replace(/\*/g, '').trim().slice(0, 70);
      crows.push({ k: 'declared', t: `${rel}:${i + 1}  ${ln.trim().slice(0, 46)}  ← 已声明「${why}」` });
    } else crows.push({ k: 'needconfirm', t: `${rel}:${i + 1}  ${ln.trim().slice(0, 46)}` });
  });
}
const needc = crows.filter(r => r.k === 'needconfirm');
console.log(`\n二次确认对账 (顾问级, 不判失败): UI 层不可逆汇点 ${crows.length} 处 · 附近有确认 ${crows.filter(r => r.k === 'asked').length} · 已写明不需要 ${crows.filter(r => r.k === 'declared').length} · **需要人读 ${needc.length}**`);
if (needc.length) {
  console.log('\n【没在附近找到确认的不可逆调用 ⇒ 逐条开代码看：这个动作可逆吗？确认写在外层吗？还是真漏了一问】');
  needc.forEach(r => console.log('  ' + r.t));
}

// ---------- 第三张清单：远端删除的"删除面"有没有交代 (第一百六十八批) ----------
// 与第二张清单的分界线：那张管"按下之前问不问"，这张管**"删的是谁的东西"**。
// 起因：`pruneRemote` 原本把 PROPFIND 列表里"超出 N 份"的条目一律 DELETE，
// 而它读的 `webdavRoot` 默认值是整个坚果云根目录 —— 于是它删的是用户的照片与子目录 (§10.40)。
// 这类缺陷静态判不了 (要跨文件读默认值)，但"**一个远程删除点有没有写清它只动哪一族对象**"能查：
// 站点附近 (上 30 行 / 下 8 行) 注释里带 `删除面：` 就算交代过，否则进名单交人读。
// 同样是顾问级阅读清单，不判失败：写了不等于写对，`删除面：` 那句话本身要读。
const NET_DEL = /httpMethod\s*=\s*"DELETE"/;
const nrows = [];
for (const f of swiftFiles(path.join(ROOT, 'App'))) {
  const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  L.forEach((ln, i) => {
    if (!NET_DEL.test(ln) || /^\s*\/\//.test(ln)) return;
    const win = L.slice(Math.max(0, i - 30), i + 8).join('\n');
    const rel = path.relative(ROOT, f).replace(/\\/g, '/');
    const why = (win.match(/删除面\s*[:：][^\n]*/) || [''])[0].replace(/\*/g, '').trim().slice(0, 76);
    nrows.push({ t: `${rel}:${i + 1}  ${ln.trim().slice(0, 44)}`, declared: !!why, why });
  });
}
const netNeed = nrows.filter(r => !r.declared);
console.log(`\n远端删除面 (顾问级, 不判失败): 网络 DELETE 站点 ${nrows.length} 处 · 已交代删除面 ${nrows.length - netNeed.length} · **需要人读 ${netNeed.length}**`);
if (nrows.length - netNeed.length) {
  console.log('\n【每个远程删除点都得写明它只动哪一族对象】');
  nrows.filter(r => r.declared).forEach(r => console.log(`  ${r.t}  ← 已声明「${r.why}」`));
}
if (netNeed.length) {
  console.log('\n【没交代删除面的远程 DELETE ⇒ 打开它读的每个配置默认值，确认删除集合只含本 App 自己的数据】');
  netNeed.forEach(r => console.log('  ' + r.t));
}
