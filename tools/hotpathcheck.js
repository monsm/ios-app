#!/usr/bin/env node
// hotpathcheck —— 热路径里新建的裸 Task 必须带**同步前置判断**（判失败）。
//
// 正控：把 `App/Core/LinkSenseKit.swift` 的 `if AutoOpen.on {` 去掉 ⇒
//       报出「saveRssi 里的 Task 没有同步前置判断（每个 RSSI 事件都新建一次）」。
// 负控：全仓零误报 —— `autoReconnectTick` 里那两处裸 Task 是**回调/阶梯驱动**（低频），
//       已在 HOTPATH_TASKS 白名单里写明理由。
//
// 2026-10-31（第 68 轮）：`saveRssi` 末尾原来是每个 RSSI 事件都 `Task { @MainActor in feedRssi(...) }`。
// 扫描时 RSSI 事件每秒 5~10 次，而 `feedRssi` 内部的 `guard AutoOpen.on` 是**在 Task 里**才检查的
// ⇒ 开关关着也在白建 Task、白 hop MainActor；MainActor 忙（渲染/滚动）时会堆积。
// 第 68 轮改成「先同步判 `AutoOpen.on`，开着才建 Task」。
//
// 判据：扫「函数名命中热路径关键词」的函数体，其中的**裸 Task**（不带 `xTask =` 句柄）
//       必须在**同一函数内**、**Task 之前**出现过同名的开关判断（`if <flag> {` / `guard <flag>`）。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIRS = ['App', 'App/Core', 'App/Services', 'App/UI'];

// 热路径关键词：函数名命中即视为「每事件都会跑」
const HOT_FN = /saveRssi|feedRssi|updateRssi|didDiscover|didUpdateValue|onRssi|autoReconnectTick/i;

// 白名单：这些「热路径函数里的裸 Task」是**回调/阶梯驱动**（低频），不需要前置判断。
// 新增白名单必须写清理由 —— 否则本闸门就成了摆设。
const ALLOW = [
  {
    file: 'App/Core/LinkSenseReconnect.swift', fn: 'autoReconnectTick', line: 81,
    why: '在 readLinkRSSI 的**回调**里 —— 回调频率受 2s tick 限制（每 2s 最多一次），不是每事件',
  },
  {
    file: 'App/Core/LinkSenseReconnect.swift', fn: 'autoReconnectTick', line: 89,
    why: '重连阶梯，已有 `nextLadderInterval()` 节流；且这是重连动作本身，本来就要低频执行',
  },
];

const bad = [];
const okList = [];

for (const d of DIRS) {
  const dir = path.join(ROOT, d);
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.swift')) continue;
    const rel = d + '/' + f;
    const src = fs.readFileSync(path.join(dir, f), 'utf8');
    const L = src.split(/\r?\n/);

    for (let i = 0; i < L.length; i++) {
      const c = L[i].replace(/\/\/.*$/, '');
      if (!c.trim()) continue;
      // 裸 Task（不带句柄赋值）
      if (!/\bTask\s*\{/.test(c)) continue;
      if (/=\s*Task\s*\{/.test(c)) continue;

      // 往上找最近的 func
      let fn = '', fnLine = -1;
      for (let k = i; k >= Math.max(0, i - 60); k--) {
        const m = L[k].replace(/\/\/.*$/, '').match(/\bfunc\s+(\w+)/);
        if (m) { fn = m[1]; fnLine = k; break; }
      }
      if (!fn || !HOT_FN.test(fn)) continue;

      // 白名单
      const allowed = ALLOW.find(a => a.file === rel && a.fn === fn && Math.abs(a.line - (i + 1)) <= 12);
      if (allowed) { okList.push(`${rel}:${i + 1} [${fn}] 白名单：${allowed.why}`); continue; }

      // 检查：fnLine..i 之间是否有同步开关判断
      const region = L.slice(fnLine, i).join('\n').replace(/\/\/.*$/gm, '');
      const hasSyncGuard = /if\s+[^\n]*\b(AutoOpen\.on|isReady|foreground|sceneActive|enabled)\b/.test(region)
        || /guard\s+[^\n]*\b(AutoOpen\.on|isReady|foreground|sceneActive|enabled)\b/.test(region);

      if (!hasSyncGuard) {
        bad.push(`${rel}:${i + 1} [${fn}] 裸 Task 没有同步前置判断 —— 热路径里每事件新建一次，会洪泛 MainActor\n      ${c.trim().slice(0, 76)}`);
      } else {
        okList.push(`${rel}:${i + 1} [${fn}] 有同步前置判断`);
      }
    }
  }
}

if (bad.length) {
  console.log(`✗ 热路径里的裸 Task 缺同步前置判断 ${bad.length} 处：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：`Task { @MainActor in ... }` 里再判开关已经晚了 —— Task 已经建好、已经排队。');
  console.log('修法：把开关判断提到 Task **外面**（同步判，很便宜），关着就不建 Task。');
  console.log('      若该 Task 确实由回调/阶梯驱动（低频），把它加进本闸门的 ALLOW 并写明理由。');
  process.exit(1);
}
okList.forEach(x => console.log('ok    ' + x));
console.log(`\n✓ 热路径裸 Task ${okList.length} 处均有同步前置判断或已白名单`);
