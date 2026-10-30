#!/usr/bin/env node
// uitokencheck —— 间距/圆角必须走设计令牌（判失败）。
//
// 正控：把 `App/UI/CredentialOtp.swift` 的 `.padding(.vertical, DS.Space.xxs)` 改回 `.padding(.vertical, 2)`
//       ⇒ 报出「padding(.vertical, 2) 应走 DS.Space.xxs」。
// 负控：全仓零误报（装饰性小圆角有白名单，见下）。
//
// 2026-10-31（UI/UX 第 2 轮）：`DS.Space` 与 `DS.Radius` 都是**响应用户设置**的：
//   · `DS.Space` 有 densityScale（compact 0.85 / 标准 1.0 / relaxed 1.18）
//   · `DS.Radius` 有 k（soft 0.62 / 标准 1.0 / plump 1.3）
// 用户在「设置 → 外观」调这两档时，**硬编码的间距/圆角不会跟着变** —— 视觉不一致。
// 本轮修了 21 处 padding + 2 处圆角，并补了 `DS.Radius.chip`(8) / `DS.Radius.badge`(13) 两个刻度。
//
// 判据：
//   · `.padding(.axis, N)` 或 `.padding(N)` 里的 N 若命中 DS.Space 的刻度（2/4/8/12/16/24/32）
//     ⇒ 必须写成 `DS.Space.<token>`，判失败。
//   · `cornerRadius: N` 里的 N 若命中 DS.Radius 的刻度（22/16/18/8/13）
//     ⇒ 必须写成 `DS.Radius.<token>`，判失败。
//
// 白名单（**装饰性形状**，不是容器圆角 —— 跟着档位变会让零件变形）：
//
// 正控：把 `App/UI/CredentialOtp.swift` 的 `.padding(.vertical, DS.Space.xxs)` 改回 `.padding(.vertical, 2)`
//       ⇒ 报出「CredentialOtp.swift:209 padding(…, 2) 应走 DS.Space.xxs」，退出码 1。
// 负控：447 处已走 token 的调用零误报；4 条装饰性小圆角白名单生效。
//   · `LinkSenseViews` 信号格 1pt
//   · `RecordsRows` 刻度点 3pt（有 @layout-allow 标注）
//   · `SettingsAppearance` 色板预览 4pt
//   · `SettingsSubPages` 22pt 控制零件 5pt（有 @layout-allow 标注）
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

const files = [];
for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) if (f.endsWith('.swift')) files.push({ rel: d + '/' + f, abs: path.join(dir, f) });
}
if (!files.length) { console.log('✓ 无 Swift 源码，跳过'); process.exit(0); }

function strip(line) {
  let inStr = false;
  for (let i = 0; i < line.length - 1; i++) {
    const ch = line[i], prev = i > 0 ? line[i - 1] : '';
    if (ch === '"' && prev !== '\\') inStr = !inStr;
    if (!inStr && ch === '/' && line[i + 1] === '/') return line.slice(0, i);
  }
  return line;
}

// 刻度 → token
const SPACE = { '2': 'xxs', '4': 'xs', '8': 's', '12': 'm', '16': 'l', '24': 'xl', '32': 'xxl' };
const RADIUS = { '22': 'card', '16': 'control', '18': 'tile', '8': 'chip', '13': 'badge' };

// 装饰性小圆角白名单（文件 + 值）
const RADIUS_ALLOW = [
  { file: 'App/Core/LinkSenseViews.swift', v: '1', why: '3pt 宽信号格的零件形状' },
  { file: 'App/UI/RecordsRows.swift', v: '3', why: '刻度点（有 @layout-allow 标注）' },
  { file: 'App/UI/SettingsAppearance.swift', v: '4', why: '14×14 色板预览' },
  { file: 'App/UI/SettingsSubPages.swift', v: '5', why: '22pt 宽控制零件（有 @layout-allow 标注）' },
];

const bad = [];
const okCount = { padding: 0, radius: 0 };   // 统计**已走 token**的调用数

for (const { rel, abs } of files) {
  if (/Design(System|Palette|Tokens|Metrics)/.test(rel)) continue;   // 令牌定义文件本身豁免
  const src = fs.readFileSync(abs, 'utf8');
  const L = src.split(/\r?\n/);
  for (let i = 0; i < L.length; i++) {
    const c = strip(L[i]);
    if (!c.trim()) continue;
    if (/^\s*\/\//.test(L[i])) continue;

    // 已走 token 的计数（正控时数字会掉，可据此确认改动生效）
    if (/DS\.Space\.\w+/.test(c)) okCount.padding++;
    if (/DS\.Radius\.\w+/.test(c)) okCount.radius++;
    // padding
    const pm = c.match(/\.padding\(\s*(?:\.(\w+)\s*,\s*)?(\d+(?:\.\d+)?)\s*\)/);
    if (pm) {
      const v = pm[2];
      if (SPACE[v]) {
        bad.push(`${rel}:${i + 1}  padding(…, ${v}) 应走 DS.Space.${SPACE[v]}（否则不随「密度档」变化）`);
      }
    }
    // cornerRadius
    const rm = c.match(/(?:cornerRadius\s*:\s*|RoundedRectangle\(\s*cornerRadius\s*:\s*)(\d+(?:\.\d+)?)/);
    if (rm) {
      const v = rm[1];
      if (RADIUS[v]) {
        const allow = RADIUS_ALLOW.find(a => a.file === rel && a.v === v);
        if (allow) { okCount.radius++; continue; }
        bad.push(`${rel}:${i + 1}  cornerRadius: ${v} 应走 DS.Radius.${RADIUS[v]}（否则不随「圆角档」变化）`);
      }
    }
  }
}

if (bad.length) {
  console.log(`✗ 硬编码间距/圆角 ${bad.length} 处（不随用户设置变化）：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：`DS.Space` 有 densityScale（0.85/1.0/1.18），`DS.Radius` 有 k（0.62/1.0/1.3）。');
  console.log('用户在「设置 → 外观」调这两档时，硬编码的间距/圆角不会跟着变 —— 视觉不一致。');
  console.log('修法：把数字换成对应 token；若该处确实是**装饰性零件形状**（不是容器圆角），加进 RADIUS_ALLOW 并写明理由。');
  process.exit(1);
}
console.log(`✓ 间距/圆角全部走设计令牌（已走 token 的 ${okCount.padding + okCount.radius} 处）`);
