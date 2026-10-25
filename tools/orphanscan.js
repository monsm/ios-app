#!/usr/bin/env node
// 删页残留符号检查 — node tools/orphanscan.js [--base <commit>] [--self]
//
// 为什么加这条 (2026-10-25, 大删第 4 次踩同一脚):
//   删掉一整页 .swift 文件时, 那个文件里往往还住着**别的页面在用**的小构件:
//     · HelpCenter.swift 里的 cjkSpaced       → DeviceHomeView 在调
//     · AccessibilityView.swift 的 CaptionStepBar → DeviceHomeView 在用
//     · ExportCenter.swift 的 ExportDir        → BackupStudio 在用
//     · CareViews.swift 的 BatterySwapGuide    → AlarmCenterView 在用
//   每一次都是**本地 26 道闸门全绿、CI 才红**, 因为闸门只看语法形状, 不看符号生死。
//   本工具把这件事变成提交前就能答的一句话: 被删文件里声明的符号, 还有谁在引用?
//
// 口径:
//   · 只认「被删的 .swift 文件里声明过的」类型/协议/枚举/结构/函数/常量;
//   · 只报**当前工作树里仍有代码级引用**且**全仓已无同名声明**的 —— 两者同时成立才算悬空;
//   · 通用成员名 (reload/start/rows/menu…) 一律跳过: 它们撞名是常态, 报了只会淹没真信号;
//   · 注释与字符串里的引用不计。
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const git = (args) => {
  try { return execFileSync('git', ['-C', ROOT, ...args], { encoding: 'utf8', maxBuffer: 1 << 28 }); }
  catch { return ''; }
};

const argv = process.argv.slice(2);
const baseIdx = argv.indexOf('--base');
const BASE = baseIdx >= 0 ? argv[baseIdx + 1] : 'HEAD~1';

// 1. 被删的 swift 文件
const deleted = git(['log', '--diff-filter=D', '--name-only', '--pretty=format:', `${BASE}..HEAD`])
  .split(/\r?\n/).filter((f) => f.endsWith('.swift'));

// 2. 这些文件里声明过的符号 (带上它最后所在的提交, 便于 --base 取到内容)
const DECL = /^(?:@\w+(?:\([^)]*\))?\s+)*(?:public |private |internal |fileprivate |final |open |static )*(?:struct|enum|class|actor|protocol)\s+(\w+)/gm;
const FN = /^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public |private |internal |fileprivate |static |mutating |nonisolated |override )*func\s+(\w+)/gm;
const CONST = /^(?:public |private |internal |fileprivate )?(?:let|var)\s+(\w+)\s*[:=]/gm;
const skip = new Set(['reload','start','cancel','complete','retry','rows','menu','subtitle','vertex','persist','onDone','update','reset','load','save','body','init','main','perform','apply','clear','handle','open','close','show','dismiss','send','read','write','build','parse','format','render','draw','layout','tick','sync','refresh']);

const syms = new Map();
for (const f of deleted) {
  const src = git(['show', `${BASE}:${f}`]) || git(['show', `HEAD:${f}`]);
  if (!src) continue;
  for (const re of [DECL, FN, CONST]) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(src))) {
      const n = m[1];
      if (n.length < 4 || skip.has(n)) continue;
      if (!syms.has(n)) syms.set(n, f);
    }
  }
}

// 3. 当前工作树: 谁还声明了同名符号 / 谁还在引用
const live = git(['ls-files', '--', '*.swift']).split(/\r?\n/).filter(Boolean);
const rawBodies = new Map();   // 保留注释与空行: 属性悬空检查要看原始形状
const bodies = new Map();
for (const f of live) {
  const full = path.join(ROOT, f);
  if (!fs.existsSync(full)) continue;
  const rawText = fs.readFileSync(full, 'utf8');
  rawBodies.set(f, rawText.split(/\r?\n/));
  bodies.set(f, rawText.split(/\r?\n/).map((l) => l.replace(/\/\/.*$/, '')).join('\n'));
}

const dangling = [];
for (const [name, origin] of syms) {
  const esc = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`\\b${esc}\\b`);
  // 全仓是否仍有人**声明**它 (搬走了 = 合法)
  let stillDeclared = false;
  for (const [, body] of bodies) {
    if (new RegExp(`(?:struct|enum|class|actor|protocol|func|let|var)\\s+${esc}\\b`).test(body)) { stillDeclared = true; break; }
  }
  if (stillDeclared) continue;
  const users = [];
  for (const [f, body] of bodies) if (re.test(body)) users.push(f);
  if (users.length) dangling.push({ name, origin, users });
}

// ---- 第二种伤: 属性悬空 (删函数时最容易留下) ----
// 形状: `@ViewBuilder` / `@MainActor` 后面紧跟空行, 再接一段无关的声明。
// Swift 会把那个属性算到**下一个**声明头上 (或者干脆报 Expected declaration),
// 本轮删减里就这样踩了 5 次, 而所有语法闸门都看不见它。
const orphans = [];
for (const [f, ls] of rawBodies) {
  if (!f.startsWith('App/')) continue;   // fixtures 是闸门的样本, 不按产品码要求
  for (let i = 0; i < ls.length - 1; i++) {
    const t = ls[i].trim();
    if (!/^@\w+(\([^)]*\))?$/.test(t)) continue;
    // 属性与声明之间允许夹注释 (合法写法), 所以跳过空行与注释行, 看第一个真内容行
    let j = i + 1;
    let sawBlank = false;
    while (j < ls.length) {
      const u = ls[j].trim();
      if (u === '') { sawBlank = true; j++; continue; }
      if (u.startsWith('//')) { j++; continue; }
      break;
    }
    if (!sawBlank) continue;
    if (j >= ls.length) { orphans.push(`${f}:${i + 1}  ${t} (文件末尾悬空)`); continue; }
    const nxt = ls[j].trim();
    // 下一处真内容若仍是声明/属性/右括号, 说明属性有归属; 否则才是悬空
    // 属性只对 func / var / 类型 / subscript / init / case 合法 —— 挂到 `let` 或语句上是非法归属
    if (/^(@|#|private |public |internal |fileprivate |static |final |class |override |mutating |nonisolated |lazy |weak |func |var |subscript|init|deinit|case |struct |enum |extension |\})/.test(nxt)) continue;
    orphans.push(`${f}:${i + 1}  ${t}  → 下一行是 「${nxt.slice(0, 36)}」`);
  }
}

if (!dangling.length && !orphans.length) {
  console.log(`删页残留检查 ✓ (${syms.size} 个被删符号有着落; 无属性悬空)`);
  process.exit(0);
}
if (orphans.length) {
  console.log(`✗ 属性悬空 ${orphans.length} 处 —— 属性后面紧跟空行, 它挂不到任何声明上:`);
  for (const o of orphans) console.log('  ' + o);
  console.log('  多半是删函数时注释与 @属性 没跟着一起删。');
}
if (dangling.length) {
  console.log(`✗ 悬空符号 ${dangling.length} 个 —— 定义随文件删了, 但还有代码在引用:`);
  for (const d of dangling) {
    console.log(`  ${d.name}  (原 ${d.origin})`);
    console.log(`     仍在用: ${d.users.slice(0, 4).join(', ')}${d.users.length > 4 ? ` …共 ${d.users.length} 处` : ''}`);
  }
}
console.log('');
console.log('处理方式: ① 符号还有消费者就搬进存活文件 ② 连同调用点一起删 ③ 悬空属性连注释一起删。');
console.log('不要留在原地 —— CI 编译到那一行才会红, 而闸门全绿会让你以为没事。');
process.exit(1);