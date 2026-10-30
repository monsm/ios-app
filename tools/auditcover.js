#!/usr/bin/env node
// auditcover —— 审计覆盖台账的进度计算器。
//
// 2026-10-30 新增（第 103 轮）：用户要求「每次汇报下，距离完成目标还有多少工作要做」。
// 把「还剩多少」从口头估计变成**可计算数字**：
//   docs/审计覆盖台账.json 里每条是一个「检查维度」，status 四态。
//   本工具算完成率，并列出**还没做完的具体条目**。
//
// 为什么不用「已修 N 项」当进度：那个数字只增不减，且无法回答"还有多少"。
// 台账回答的是「**检查面**覆盖了多少」—— 它才是"地毯式"的真实分母。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const P = path.join(ROOT, 'docs/审计覆盖台账.json');
const ledger = JSON.parse(fs.readFileSync(P, 'utf8'));

let done = 0, partial = 0, todo = 0, blocked = 0, total = 0;
const pending = [];
const blockedList = [];

for (const cat of ledger.categories) {
  for (const it of cat.items) {
    total++;
    switch (it.status) {
      case 'done': done++; break;
      case 'partial': partial++; pending.push({ cat: cat.name, ...it }); break;
      case 'todo': todo++; pending.push({ cat: cat.name, ...it }); break;
      case 'blocked': blocked++; blockedList.push({ cat: cat.name, ...it }); break;
      default: console.log('⚠ 未知 status: ' + it.status + ' @' + it.id);
    }
  }
}

const actionable = total - blocked;          // 本机能做的分母
const finished = done;                        // 完整做完的
const ratio = actionable ? (finished / actionable) : 0;

console.log('════ 审计覆盖台账 ════');
console.log(`维度总数 ${total}（本机可做 ${actionable}，本机做不了 ${blocked}）`);
console.log(`  done ${done} · partial ${partial} · todo ${todo} · blocked ${blocked}`);
console.log(`\n完成度：${finished}/${actionable} = ${(ratio * 100).toFixed(1)}%`);

const bar = (n, t) => {
  const w = 30;
  const f = Math.round((n / t) * w);
  return '█'.repeat(f) + '░'.repeat(w - f);
};
console.log('  [' + bar(finished, actionable) + ']');

if (pending.length) {
  console.log(`\n还剩 ${pending.length} 条要做：`);
  for (const p of pending) {
    console.log(`  [${p.status === 'partial' ? '部分' : '未做'}] ${p.cat} · ${p.name}`);
    if (p.evidence) console.log(`        ${p.evidence}`);
  }
}
if (blockedList.length) {
  console.log(`\n本机做不了 ${blockedList.length} 条（需真机/外部信息）：`);
  for (const b of blockedList) console.log(`  [阻塞] ${b.cat} · ${b.name} —— ${b.evidence}`);
}

// 有 todo/partial 时退出码 0（这是进度报告，不是闸门失败）
process.exit(0);
