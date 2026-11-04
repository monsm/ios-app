#!/usr/bin/env node
// auditindex.js —— 第 23 道闸门：docs/AUDIT-INDEX.md 必须与「从 AUDIT-ROUND-*.md 重新生成」的结果一致。
//
// 为什么：索引的价值全在「不会漂」。只生成一次而靠人记得重跑，等于没有。
// 这道闸门把「索引是最新的」变成可判红的机械事实：加了新的一轮文档却没重生成 → 红。
//
// 用法：node Gates/auditindex.js          # 只校验
//       node Gates/auditindex.js --write  # 就地重生成
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DOCS = path.join(ROOT, 'docs');
// 2026-11-04：AUDIT-ROUND-*.md 已移入 docs/archive/audit-rounds/（337 份，根目录无法浏览）。
// 闸门跟着搬：索引仍从同一批文件生成，只是目录变了。
const ROUNDS = path.join(DOCS, 'archive', 'audit-rounds');
const OUT = path.join(DOCS, 'AUDIT-INDEX.md');

const HEAD = [
  '# 审计总索引（AUDIT-INDEX）',
  '',
  '> 本文件由脚本从 docs/archive/audit-rounds/AUDIT-ROUND-*.md 的标题生成，**不含手写内容**，所以不会漂。',
  '> 轮次号是这些文档自己的编号（跨会话连续累计），与本会话的 goal-round 计数不是同一套。',
  '',
  '**共 __N__ 轮** 审计文档。',
  '',
  '## 怎么用这份索引',
  '',
  '| 你想知道 | 去哪里 |',
  '|---|---|',
  '| 某个领域查过没有 | 在本文件里搜关键词（备份 / 凭证 / 通知 / 时间 / 闸门 / CI…） |',
  '| 某类缺陷的处置范式 | 见下面「方法论入口」 |',
  '| 还剩什么只能真机验 | 见文末「真机专属」 |',
  '',
  '## 方法论入口（跨轮沉淀）',
  '',
  '| 判据 | 出处 |',
  '|---|---|',
  '| 「唯一落点」只能证明覆盖，不能证明语义 | 第 229 轮 |',
  '| 「有实现」≠「有消费」，最后一步要 grep 入口 | 第 293 轮 |',
  '| 派生数据：删的时候要清、算的时候要跟 | 第 227 / 244 轮 |',
  '| 一个字段两种口径（id vs 名字）要三层一起定 | 第 237 / 238 轮 |',
  '| 文案断言了没做的事 = 缺陷 | 第 241 / 260 / 283 / 286 轮 |',
  '| 同一份判据出现在两层，要同时维护 | 第 250 轮 |',
  '| 集合差能证明覆盖，证明不了映射正确 | 第 292 轮 |',
  '| 升级链要逐级问「这级改了什么」 | 第 296 轮 |',
  '| 恢复是两条链：正向导入 + 反向撤销 | 第 297 轮 |',
  '| 不该用文案内容决定状态色 | 第 223 / 287 轮 |',
  '',
  '## 全部轮次',
  '',
];

const FOOT = [
  '',
  '## 真机专属（静态无法验证）',
  '',
  '| 项 | 为什么只能真机 |',
  '|---|---|',
  '| 开锁 rc=2（无效 PIN）的最终归因 | 需要看「设备信息页 PIN 池 vs 锁端已用」的实际读数 |',
  '| 锁钟「未读到」的固件行为 | 需要确认该固件是否真的不回 lockTime |',
  '| 指纹录入全流程 | 需要真实按压 8 次与 cmd14 确认窗口 |',
  '| DFU 中断后的锁状态 | 需要真机复现「刷一半断链」 |',
  '| WebDAV 实网连通 | 需要一台真实 WebDAV 服务器 |',
  '| 12 小时制/大字号下的布局 | 需要看实际渲染 |',
  '| 玻璃/触感反馈 | 需要真机手感 |',
  '',
];

function build() {
  const files = fs.readdirSync(fs.existsSync(ROUNDS) ? ROUNDS : DOCS).filter(f => /^AUDIT-ROUND-\d+\.md$/.test(f));
  const items = files.map(f => {
    const n = parseInt(f.match(/ROUND-(\d+)/)[1], 10);
    const s = fs.readFileSync(path.join(fs.existsSync(ROUNDS) ? ROUNDS : DOCS, f), 'utf8').split(/\r?\n/);
    const t = (s.find(l => l.startsWith('# ')) || '').replace(/^# /, '').replace(/^AUDIT-ROUND-\d+ · /, '').trim();
    return { n, t };
  }).sort((a, b) => a.n - b.n);
  const out = HEAD.map(l => l.replace('__N__', String(items.length)));
  const maxN = items.length ? items[items.length - 1].n : 0;
  for (let start = 1; start <= maxN; start += 50) {
    const slice = items.filter(i => i.n >= start && i.n <= start + 49);
    if (!slice.length) continue;
    out.push('### 第 ' + start + '-' + (start + 49) + ' 轮', '');
    for (const it of slice) out.push('- **' + it.n + '** ' + it.t);
    out.push('');
  }
  out.push(...FOOT);
  return out.join('\n') + '\n';
}

const want = build();
const write = process.argv.includes('--write');
if (write) {
  fs.writeFileSync(OUT, want, 'utf8');
  console.log('auditindex: 已重生成 docs/AUDIT-INDEX.md');
  process.exit(0);
}
let have = '';
try { have = fs.readFileSync(OUT, 'utf8'); } catch { have = ''; }
if (have !== want) {
  console.log('  docs/AUDIT-INDEX.md 与重新生成的结果不一致 —— 跑 node Gates/auditindex.js --write 更新');
  process.exit(1);
}
console.log('auditindex: OK — 索引与 ' + (want.match(/\*\*共 (\d+) 轮\*\*/) || [])[1] + ' 份审计文档一致');
