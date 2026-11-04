#!/usr/bin/env node
// capability.js - gate 41: 能力守恒对账
//
// 2026-11-05（对抗审查驱动）：43 个 Dest 迁 V8 的过程中，丢了两整块能力 ——
//   · DeleteDeviceSheet（删除一台锁的本机数据，含 DB.removeDevice 的 20+ 数据族清理）
//   · door 页的 attentionCard（密钥未绑定 / 未校时 / 低电 / 凭证即将到期）
// 第二块让 CredentialOrg.dueSoonPwds 变成零调用函数，而 40 道闸门**全绿**。
//
// 为什么闸门没抓到：所有闸门查的是「现有代码内部的一致性」，
// 没有一道闸门知道「曾经有过什么」。删掉一整个调用点，剩下的一切仍然自洽。
//
// 本闸门的判据：维护一份**必须始终有调用点**的引擎能力清单（CAPABILITIES）。
// 每一条都记着：能力名、被谁用过、丢了会怎样。清单里的每个符号在当前源码里
// 必须至少出现在一处「非定义、非注释」的位置。
//
// 清单只增不减。删掉某个能力必须同时改这里，并在提交信息里说明为什么这个能力
// 可以消失 —— 让「悄悄消失」变成一个必须显式签字动作。
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const APP = path.join(ROOT, 'App');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.swift')) out.push(p);
  }
  return out;
}

const files = walk(APP).map((f) => ({
  rel: path.relative(APP, f).split(path.sep).join('/'),
  src: fs.readFileSync(f, 'utf8'),
}));

// 能力清单：symbol 是「调用形态」，至少要在某处出现
const CAPABILITIES = [
  // —— 删除设备（整族清理）——
  { symbol: 'DB.removeDevice', why: '删除一台锁的本机数据：20+ 数据族一次清干净（含回收站/版本快照/手机钥匙的钥匙串副本）。丢了 = 删除锁的能力整段消失。' },
  // —— 门页异常提醒 ——
  { symbol: 'CredentialOrg.dueSoonPwds', why: '门页「需要留意」卡的凭证到期判据（2 小时内到期 / 已过期 1 小时内）。丢了 = 用户看不到临时码即将失效。' },
  // —— 快捷操作三件套 ——
  { symbol: 'QuickPool.ordered', mustAppearIn: 'Features/Door/DoorHomeScreen.swift', why: '门页快捷操作排序。丢了 = 「常用操作自动排前」开关失效。' },
  { symbol: 'QuickPool.recordTap', mustAppearIn: 'Features/Door/DoorHomeScreen.swift', why: '记录一次快捷操作点击。丢了 = 排序的计数永远是空的。' },
  // —— 手机钥匙 ——
  { symbol: 'MobileKeyService.revoke', why: '撤销一把手机钥匙（cmd08 delPins 真下发）。丢了 = 钥匙撤不掉。' },
  { symbol: 'MobileKeyService.issue', why: '签发一把手机钥匙（本地签 ekey + 落台账）。丢了 = 签不出钥匙。' },
  // —— 成员删除 ——
  { symbol: 'MemberOpsStore.cascadeDelete', why: '删成员时把名下凭证先放回收站再解除归属。丢了 = 用户以为删干净了，凭证还在台账里。' },
  // —— 凭证 ——
  { symbol: 'CredBinStore.purge', why: '回收站彻底删除（含 Keychain 口令副本与派生状态）。丢了 = 彻底删除只是从列表消失。' },
  // —— 备份 ——
  { symbol: 'BackupStudio.restore', why: '恢复备份。丢了 = 备份只能生成不能还原。' },
  // —— 界面文案承诺过的动作（文案说「可整组还原」就必须真有整组还原）——
  { symbol: 'CredBinStore.restoreBatch', mustAppearIn: 'Features/Keys/CredentialStudioHomeScreen.swift', why: '回收站四处文案承诺「可整组还原」。丢了 = 文案又是一句空话。' },
  { symbol: 'LockArchive.isHidden', mustAppearIn: 'Features/Door/DoorHomeScreen.swift', why: '「在翻页里隐藏这把锁」的唯一判据 —— 而且必须是门页在读（设置面板读它只够显示开关状态）。' },
  { symbol: 'DevModuleStore.hidden', mustAppearIn: 'Features/Door/DoorHomeScreen.swift', why: '「版面 → 模块显隐」三个开关的判据，且必须由门页执行（否则面板是死开关）。' },
  { symbol: 'DevLayout.order', mustAppearIn: 'Features/Door/DoorHomeScreen.swift', why: '「版面」三槽排序的判据，且必须由门页执行（面板自己读它只够画顺序）。' },

  // —— 只读护栏 ——
  { symbol: 'ZKProtocol.assertReadOnly', why: '只读试验模式对所有 BLE 下发的唯一收口。丢了 = 只读模式形同虚设。' },
  // —— 空壳 ——
  { symbol: 'DB.isDecoy', why: '空壳（胁迫码）模式的判据。丢了 = 胁迫码下把真实数据摊开。' },
];

// 找到每个能力所属类型的定义文件 —— 类型内自引用不算「有调用点」。
// 反例：DevLayout.order 在 DoorLayout.swift 里被 move()/setOrder() 用到，
// 即使门页不再读它，计数依然 > 0。所以必须排除定义文件。
function definingFile(typeName) {
  for (const f of files) {
    if (new RegExp('(enum|struct|final class|class|actor) ' + typeName + '\\b').test(f.src)) return f.rel;
  }
  return null;
}

const findings = [];
for (const cap of CAPABILITIES) {
  const typeName = cap.symbol.split('.')[0];
  const own = definingFile(typeName);
  let n = 0;
  for (const { rel, src } of files) {
    if (own && rel === own) continue;   // 定义文件内的自引用不算
    for (const line of src.split(/\r?\n/)) {
      const t = line.trim();
      if (t.startsWith('//') || t.startsWith('///')) continue;
      if (line.includes(cap.symbol)) n++;
    }
  }
  if (n < 1) { findings.push({ symbol: cap.symbol, n, own, why: cap.why }); continue; }
  if (cap.mustAppearIn) {
    const target = files.find((f) => f.rel === cap.mustAppearIn);
    const ok = target && target.src.split(/\r?\n/).some((line) => {
      const t = line.trim();
      if (t.startsWith("//") || t.startsWith("///")) return false;
      return line.includes(cap.symbol);
    });
    if (!ok) findings.push({ symbol: cap.symbol, n, own, missingIn: cap.mustAppearIn, why: cap.why });
  }
}
if (findings.length === 0) {
  console.log('capability: OK — ' + CAPABILITIES.length + ' 条必须保留的能力都有调用点');
  process.exit(0);
}
console.log('capability: FAIL — ' + findings.length + ' 条能力没有调用点');
for (const f of findings) {
  console.log('  ' + f.symbol + '（定义文件 ' + f.own + ' 之外的非注释引用 ' + f.n + ' 次）');
  if (f.missingIn) console.log('     缺少执行点：' + f.missingIn);
  console.log('     ' + f.why);
}
process.exit(1);
