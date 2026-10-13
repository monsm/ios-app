#!/usr/bin/env node
// tools/lockpair.js — 「发出去改锁」与「本机这一半」的对账线索表（第一百五十四批新增，**顾问级，不判失败**）
//
// 为什么要有它：第一百五十二、三批连着两次撞上同一族的谎 ——
//   · 撤销/还原改了本机台账，却没管锁端那条待下发的删除 (152)；
//   · 删成员只动本机，弹窗没说锁里还能开门 (153)。
// 两个方向其实是同一条不变式：**改了一侧，另一侧要么一起改，要么当场说清不改**。
// delsweep 管"本机改 → 锁端怎么交代"；这一道管反方向："发过一条会改锁状态的命令 → 本机记了什么"。
//
// 三类正当答案：
//   ① 台账跟着写 (DB.add/del/set/re…、store.set、CredentialOrg.snapshot/enqueue)；
//   ② 只记敏感流水或里程碑 (SensitiveLedger / Milestones) —— 那也是"本机有交代"；
//   ③ 故意不落本机：附近注释里写 `留存口径：` 说明为什么（例如"以锁端为准，本机不另存一份"）。
//
// ⚠ 这不是判据：±30 行窗口是启发式，会把隔壁函数的写库算进来，也看不见写在很远之外的交代；
//    "找到配对"那一档同样要人读。报线索、退 0，与 deadscan/keydead/delsweep 同族。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
// 会改锁状态的命令（读类 getStatus/getLogs/log/ensureConnected 与开门动作 unlock/lock 不在内）
const MUTATE = /app\.lock\.(pwdAdd|pwdModify|pwdExpire|pwdDelete|pwdClear|fpStart|fpConfirm|fpDelete|fpModify|setDefence|setAutoLock|setSilent|setZotp|setValidationMode|syncTime|dongleAdd|dongleDel)\s*\(/;
const LOCAL = /DB\.(add|del|set|re|clear|save)[A-Za-z]*\s*\(|DB\.store\.set\s*\(|DB\.setCodable\s*\(|CredentialOrg\.(snapshot|enqueue|markDisabled|addToBin|reclaim)|SensitiveLedger\s*\(|\.record\s*\(|\.audit\s*\(|Milestones\s*\./;
const DECLARE = /留存口径\s*[:：]|来源口径\s*[:：]/;   // 两个方向的"我故意不跟着改"都用这一族声明

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
    if (!MUTATE.test(ln)) return;
    const verb = MUTATE.exec(ln)[1];
    const win = L.slice(Math.max(0, i - 8), i + 31).join('\n');
    const rel = path.relative(ROOT, f).replace(/\\/g, '/');
    const local = LOCAL.exec(win);
    const declared = DECLARE.test(win);
    const tag = `${rel}:${i + 1}  ${verb.padEnd(15)}`;
    if (local) rows.push({ k: 'paired', t: `${tag} ← ${local[0].replace(/\s+/g, '').slice(0, 34)}` });
    else if (declared) {
      const why = (win.match(/留存口径\s*[:：][^\n]*/) || [''])[0].replace(/\*/g, '').trim().slice(0, 70);
      rows.push({ k: 'declared', t: `${tag} ← 已声明「${why}」` });
    } else rows.push({ k: 'needread', t: tag + ln.trim().slice(0, 60) });
  });
}
const need = rows.filter(r => r.k === 'needread');
console.log(`改锁命令对账 (顾问级, 不判失败): 共 ${rows.length} 处 · 附近找得到本机交代 ${rows.filter(r => r.k === 'paired').length} · 已写明不落本机 ${rows.filter(r => r.k === 'declared').length} · **需要人读 ${need.length}**`);
if (need.length) {
  console.log('\n【附近既没写库也没声明的改锁点 ⇒ 逐条读：这条命令改完锁，本机到底记了什么/该不该记】');
  need.forEach(r => console.log('  ' + r.t));
}

// ---------- 反方向：本机凭空多出一条凭证，锁那边是什么来源 ----------
// 台账里出现一条锁上不存在的凭证，界面就会显示"某人能用密码 #7 开门"而实际开不了 ——
// 与 152/154 那族 ("改了一侧没管另一侧") 是同一件事的反面，所以并到这一道里报。
const SOURCE = /pwdAdd\s*\(|fpStart\s*\(|fpConfirm\s*\(|pwdModify\s*\(|fpModify\s*\(|queueRestore\s*\(|enqueue\s*\([^)]*"restore"|sendQueued\s*\(/;
const ADDSITE = /DB\.add(Pwd|Fp)\s*\(/;
const rows2 = [];
for (const f of swiftFiles(path.join(ROOT, 'App'))) {
  const L = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  L.forEach((ln, i) => {
    if (!ADDSITE.test(ln)) return;
    const win = L.slice(Math.max(0, i - 22), i + 13).join('\n');
    const rel = path.relative(ROOT, f).replace(/\\/g, '/');
    const src = SOURCE.exec(win);
    const declared = DECLARE.test(win);
    const tag = `${rel}:${i + 1}  ${ln.trim().slice(0, 46)}`;
    if (src) rows2.push({ k: 'paired', t: `${tag}  ← ${src[0].replace(/\s+/g, '').slice(0, 22)}` });
    else if (declared) rows2.push({ k: 'declared', t: tag + '  ← 已声明来源' });
    else rows2.push({ k: 'needread', t: tag });
  });
}
const need2 = rows2.filter(r => r.k === 'needread');
console.log(`\n台账写入对账 (同一道, 反方向): DB.addPwd/addFp 共 ${rows2.length} 处 · 附近找得到锁端来源 ${rows2.filter(r => r.k === 'paired').length} · 已声明来源 ${rows2.filter(r => r.k === 'declared').length} · **需要人读 ${need2.length}**`);
if (need2.length) {
  console.log('【本机写入而附近没有锁端来源 ⇒ 逐条读：这条凭证凭什么在台账里 (恢复/迁移/演示数据都要写明)】');
  need2.forEach(r => console.log('  ' + r.t));
}
console.log('\n注: 窗口是启发式 (-22/+12 与 ±30)，"找到配对"那一档同样要人读 (写库或发命令可能属于隔壁函数)。');
