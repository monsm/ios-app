#!/usr/bin/env node
// allgates.js —— 一次跑全部闸门。
'use strict';
const { execFileSync } = require('child_process');
const path = require('path');

// callsig 已退役（2026-10-31）：它只扫 App/Design/Components 的旧组件，V7 页面根本不调用它们，
// 实测恒为「检查 0 处具名调用」= no-op。真正的调用签名闸门是 callsig2（7 类判据 + 成员表）。
// privacy 是第 16 道（2026-10-31 安全审计后新增）：把 AUDIT-F 的 7 类回归判据做成**判红**闸门 ——
// 剪贴板直写 / 备份明文 / 空壳只清界面 / 帧脱敏只处理首个 hex= / WebDAV http / 密钥文件无文件保护 / CSV 公式注入。
// tests 是第 17 道（G-07）：证明测试目标存在、金标夹具真的打进 bundle、且覆盖了协议层关键面。
// CI 镜像缺 iOS 27 模拟器 runtime，xcodebuild test 在那边跑不了 —— 这道闸门是本地可证的代理。
// feedback 是第 18 道：用户动作里的 `try? await` 必须有错误通道。
// 依据 HIG `feedback`："Show people when a command can't be carried out and help them understand why."
// 这一类缺陷不崩不报错，只让用户"点了没反应"——本轮实测两处。
const GATES = ['swiftparse', 'types', 'swiftcheck', 'tokens', 'contrast', 'glass', 'motion', 'a11y', 'dynamictype', 'reducedmotion', 'crosprivate', 'callsig2', 'lineage', 'workflow', 'destmap', 'privacy', 'tests', 'feedback'];

let failed = 0;
for (const g of GATES) {
  const p = path.join(__dirname, g + '.js');
  try {
    const out = execFileSync(process.execPath, [p], { encoding: 'utf8' });
    console.log(out.trim().split('\n')[0]);
  } catch (e) {
    failed++;
    console.log((e.stdout || '').trim());
    console.log((e.stderr || '').trim());
  }
}
console.log('');
if (failed === 0) {
  console.log(`allgates: 全部 ${GATES.length} 道闸门通过`);
  process.exit(0);
}
console.log(`allgates: ${failed}/${GATES.length} 道闸门失败`);
process.exit(1);
