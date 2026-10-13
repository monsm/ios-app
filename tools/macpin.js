#!/usr/bin/env node
// 活读全局选中态的检查 (顾问级, 不判失败) — node tools/macpin.js
// 起因 (第八十七批): 多个页面写的是 `private var mac: String { app.current?.mac ?? "" }` 这种**计算属性**，
// 然后在同一个异步流程里读它好几次 —— `ensureConnected(mac: mac)` 之后 await，再 `DB.delPwd(mac, …)`。
// 两次 await 之间当前锁是可以被外部改掉的 (本 App 有 AppIntents 与 kf:// 深链两条路径都会动 app.current)，
// 于是"命令发向 A 锁、台账写进 B 锁"；而 current 变 nil 时 `?? ""` 会静默写出一条没有锁的台账记录
// —— 最硬的一条是 SettingsView.doClearPwd: 它清的是**整本密码台账**。
// 判据 (刻意保守): 一个函数体里同时出现 ①`await app.lock.` ②以裸 `mac` (非 kc.mac / 非局部捕获) 为首参的
// 本机写库或入队调用 ⇒ 报线索。首版跑法证明它有牙齿: 修之前 6 个函数命中, 逐条改成入口捕获后归 0。
// 已知局限 (所以定成顾问级): 函数边界用"下一个顶层 func"粗切, 视图 body 里的行会被算进上一个 func ——
// 实测就把 `DB.readStatus(mac)` 这种**视图里的正确读**误归过一次; 因此写库名单只收会改台账的入口。
// 误报的处理方式是读本行再判定, 不放宽规则也不加白名单: 放宽会让下一处真错也一起静音。
//
// 规则② (第九十二批): **无 mac 参数的命令方法**调用点前必须有 `ensureConnected(mac: …)`。
// 服务层里 `setZotp/pwdAdd/getLogs/fpConfirm/…` 这些方法不收 mac，成帧用 `curMac`、发链用当前 GATT 连接 ——
// 两者可以各自"留着上一次的值"，于是出现最脏的一种错锁：**键是 B 锁的、帧从 A 锁的链路发出去**。
// 起因是 `RecordsView.fetch()`：`getStatus(mac:)` 会绑 curMac，但它是 `try?` 且**不建链**，紧随的分页 getLogs
// 就在旧链路上跑。动词名单**从 LockService 源码现场解析**（签名里没有 `mac:` 参数的 func 才算），
// 不手抄 —— 手抄动词这件事本文件已经犯过一次 (漏 `markQueue`)。
'use strict';
const fs = require('fs');
const path = require('path');

const roots = process.argv[2] ? [process.argv[2]] : ['App'];
const files = [];
(function walkAll() {
  for (const r of roots) {
    if (!fs.existsSync(r)) continue;
    (function walk(x) {
      for (const e of fs.readdirSync(x, { withFileTypes: true })) {
        const f = path.join(x, e.name);
        if (e.isDirectory()) walk(f);
        else if (f.endsWith('.swift')) files.push(f);
      }
    })(r);
  }
})();

// 写库名单**不靠手抄动词** (手抄的第一版就漏过 `CredentialOrg.markQueue`，那条正好是真缺陷):
// 规则取"任何 DB./CredentialOrg. 的调用、首参是裸 mac"，再排除**明确是读**的动词前缀。
// 取向是故意的: 多报几行读操作只要人多看一眼，漏报一处写操作就是静默的错锁台账。
const CALL = /\b(?:DB|CredentialOrg)\.[A-Za-z_]\w*\s*\(\s*mac\b/;
const READISH = /\b(?:DB|CredentialOrg)\.(?:read|get|list|bin|count|has|peek|find|summary|history|day|week|otpStatus|status|all|of)\w*/;
const AWAIT = /await\s+app\.lock\./;
let hits = 0;
for (const f of files) {
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  // 函数边界 = 从 `func` 那行起按**花括号配平**走到闭合。
  // (第一版用"下一个顶层 func"粗切, 结果把隔壁视图 body 里的读操作算进上一个函数, 报了 7 处里有一半是噪声 ——
  //  噪音会让顾问闸门失去可信度, 所以配平这一步不是奢侈而是必需。)
  const bodies = [];
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^\s*(?:private\s+)?func\s+([A-Za-z0-9_]+)\s*\(/);
    if (!m) continue;
    let depth = 0, seen = false, end = i;
    for (let j = i; j < lines.length; j++) {
      for (const ch of lines[j]) {
        if (ch === '{') { depth++; seen = true; }
        else if (ch === '}') depth--;
      }
      if (seen && depth <= 0) { end = j; break; }
    }
    bodies.push({ start: i, name: m[1], lines: lines.slice(i, end + 1) });
  }
  for (const b of bodies) {
    const body = b.lines;
    if (!body.some((l) => AWAIT.test(l))) continue;
    const bad = body.map((l, i) => [b.start + i + 1, l]).filter(([, l]) => CALL.test(l) && !READISH.test(l));
    if (!bad.length) continue;
    // 豁免条件收窄成一条能被证伪的事实: **这个 `mac` 不是活读的计算属性**。
    // 判据 = 函数签名带 `mac:` 形参 (由调用方钉住后传入)，或函数体内有本地 `let/var mac = …` 遮蔽。
    // 第八十八批的第一版不是这样: 它写"函数体里任何一行出现过 kc.mac / 出现过 em|target 这类名字"就整体豁免 ——
    // 那是含糊条件当严格条件用, 一个不相关的 `em` 就能让真缺陷静音, 而它当时正好把 retryQueueItem 放过了。
    const sig = lines[b.start];
    const joined = body.join('\n');
    const pinned = /\(\s*[^)]*\bmac\s*:/.test(sig) || /^\s*(?:let|var)\s+mac\s*=/m.test(joined);
    if (pinned) continue;
    hits++;
    console.log(`${f}:${b.start + 1}  func ${b.name}: 跨 await 仍以裸 mac (活读计算属性) 写本机 (${bad.length} 处)`);
    bad.forEach(([ln, l]) => console.log(`      ${ln}: ${l.trim().slice(0, 108)}`));
  }
}
console.log(`活读 mac 写库: ${hits} 处 (规则①, 顾问级, 不判失败。命中不代表必错, 代表要人读一遍)`);

// ---------- 规则②: 无 mac 参数的命令方法, 调用前必须 ensureConnected(mac:) ----------
// 动词名单**现场解析** LockService, 分两步收紧 (都实际踩过噪声):
// ① 手抄名单犯过过错, 所以不抄 —— 从源码取 `func` 名与参数表;
// ② 光看"没有 mac: 参数"会把 `log(...)` 这种**根本不碰锁**的本地方法也算成命令面 (首跑就报了 3 条)。
//    可证伪的判据是"这个方法最终会不会发帧": 函数体直接调 exec/execOk/request，或**传递地**调到一个会发帧的方法。
const svc = files.find((f) => path.basename(f) === 'LockService.swift');
const noMacVerbs = new Set();
if (svc) {
  const sl = fs.readFileSync(svc, 'utf8').split(/\r?\n/);
  const defs = [];   // { name, params, body }
  for (let i = 0; i < sl.length; i++) {
    const m = sl[i].match(/\bfunc\s+([A-Za-z_]\w*)\s*\(/);
    if (!m) continue;
    let depth = 0, sig = '', j = i;
    for (; j < sl.length; j++) {
      for (const ch of sl[j]) { if (ch === '(') depth++; else if (ch === ')') depth--; }
      sig += sl[j] + '\n';
      if (depth <= 0) break;
    }
    const startBody = j;
    let bd = 0, seen = false, body = '', k = startBody;
    for (; k < sl.length; k++) {
      for (const ch of sl[k]) { if (ch === '{') { bd++; seen = true; } else if (ch === '}') bd--; }
      body += sl[k] + '\n';
      if (seen && bd <= 0) break;
    }
    defs.push({ name: m[1], params: sig.slice(sig.indexOf('(')), body });
  }
  const emits = new Set(defs.filter((d) => /\b(?:exec|execOk|request)\s*\(/.test(d.body)).map((d) => d.name));
  for (let grew = true; grew;) {
    grew = false;
    for (const d of defs) {
      if (emits.has(d.name)) continue;
      for (const other of emits) {
        if (new RegExp('\\b' + other + '\\s*\\(').test(d.body)) { emits.add(d.name); grew = true; break; }
      }
    }
  }
  for (const d of defs) if (emits.has(d.name) && !/\bmac\s*:/.test(d.params)) noMacVerbs.add(d.name);
}
// 服务层内部自己调用的不算消费点: 只看 `.lock.` 前缀。
let hits2 = 0;
for (const f of files) {
  if (f === svc) continue;
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/\.lock\.([A-Za-z_]\w*)\s*\(/);
    if (!m || !noMacVerbs.has(m[1])) continue;
    let bound = false;
    for (let j = i; j >= 0 && i - j <= 160; j--) {
      if (/ensureConnected\(\s*mac:\s*[A-Za-z_][\w.]*/.test(lines[j])) { bound = true; break; }
    }
    if (bound) continue;
    hits2++;
    console.log(`${f}:${i + 1}  .${m[1]}( 无 mac 参数, 而前 160 行内没有 ensureConnected(mac: …) ⇒ 键取 curMac、链取现挂, 两者可能不同锁`);
    console.log(`      ${lines[i].trim().slice(0, 108)}`);
  }
}
console.log(`未绑锁的命令调用: ${hits2} 处 (规则②, 顾问级。动词=解析自 LockService 且**传递地会发帧**的无 mac 参数方法 ${noMacVerbs.size} 个)`);


