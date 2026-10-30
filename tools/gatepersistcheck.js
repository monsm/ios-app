#!/usr/bin/env node
// gatepersistcheck —— 「自动开锁门控的数据源必须可跨会话恢复」闸门（判失败）。
//
// 2026-10-31（第 51-53 轮，**三轮都栽在同一模式**）：
//   · F6 锁态: 快照只在 `rc==0` 时写 ⇒ 锁报 rc=25/26 时读到旧值 ⇒ 这道门永远放行
//   · F5 冷却(iOS): `lastDispatch` 纯内存 ⇒ 重启清零 ⇒ 可能双开
//   · F5 冷却(Android): `lastAuto` 纯内存 ⇒ 同上
// 三次都是「**门写得对，喂门的数据是错的**」，且都只能靠人工读数据链发现。
//
// 判据（两平台各查一遍）：
//   iOS  `App/Core/AutoOpen.swift` 的 `makeContext()`：
//     · `lastDispatch[mac]` 读取处必须**同时**有 `persistedLastDispatch` 回落
//     · `snap` 来源 `DB.readStatus` 必须持久化（这个天然是），且 `writeStatus` 不得被 rc 条件包裹
//   Android `MainActivity.kt` 的 `maybeAutoUnlock()`：
//     · `lastAuto` 声明必须从 `lock?.lastAutoMs` 取初值，且更新处必须有 `LockStore.save`
//     · `lastRc` 声明必须从 `lock?.lastRc` 取初值
//
// 不查：F0 前台态（瞬时，本就该是内存）、F1 面容（fail-closed，重启保守拒）
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const bad = [];
const ok = [];

// ── iOS ──
{
  const p = path.join(ROOT, 'App', 'Core', 'AutoOpen.swift');
  if (!fs.existsSync(p)) {
    ok.push('iOS AutoOpen.swift 不存在（跳过）');
  } else {
    const src = fs.readFileSync(p, 'utf8');

    // ① F5 冷却：读取处必须有持久化回落
    const readSite = /let lastAt = lastDispatch\[mac\] \?\? AutoOpen\.persistedLastDispatch\(mac\)/.test(src);
    if (!readSite) bad.push('iOS F5: `lastAt` 没有持久化回落（`lastDispatch[mac] ?? AutoOpen.persistedLastDispatch(mac)`）—— 重启后冷却清零，可能双开');
    else ok.push('iOS F5: 冷却基准有持久化回落');

    // ② F5 冷却：写入处必须落盘
    const writeSite = /AutoOpen\.setPersistedLastDispatch\(mac,/.test(src);
    if (!writeSite) bad.push('iOS F5: `lastDispatch` 更新后没有 `setPersistedLastDispatch` —— 落盘缺失，回落读到 0');
    else ok.push('iOS F5: 冷却写入已落盘');

    // ③ 持久化 accessor 必须存在
    if (!/static func persistedLastDispatch/.test(src) || !/static func setPersistedLastDispatch/.test(src)) {
      bad.push('iOS F5: 缺少 persistedLastDispatch / setPersistedLastDispatch accessor');
    } else ok.push('iOS F5: 持久化 accessor 齐备');

    // ④ F6：writeStatus 不得被 rc 条件包裹（与 autoopenshadow 同判据，这里再守一次）
    const opsP = path.join(ROOT, 'App', 'Services', 'LockServiceOps.swift');
    if (fs.existsSync(opsP)) {
      const ops = fs.readFileSync(opsP, 'utf8').split(/\r?\n/);
      let guarded = false;
      for (let k = 0; k < ops.length; k++) {
        if (!/DB\.writeStatus\s*\(/.test(ops[k])) continue;
        let j = k - 1;
        while (j >= 0 && /^\s*(\/\/|\*)/.test(ops[j])) j--;
        if (j >= 0 && /if\s+.*\.rc\s*==\s*0\s*\{/.test(ops[j])) guarded = true;
      }
      if (guarded) bad.push('iOS F6: `DB.writeStatus` 被 rc==0 条件包裹 —— 锁报 rc=25/26 时不写快照，F6 永远放行');
      else ok.push('iOS F6: 快照无条件写入');
    }
  }
}

// ── Android ──
{
  const p = path.join(ROOT, 'android-app', 'app', 'src', 'main', 'java', 'com', 'aapk', 'kfkey', 'MainActivity.kt');
  if (!fs.existsSync(p)) {
    ok.push('Android MainActivity.kt 不存在（跳过）');
  } else {
    const src = fs.readFileSync(p, 'utf8');

    // ① F5 冷却初值
    const initOK = /var lastAuto by remember \{ mutableStateOf\(lock\?\.lastAutoMs \?: 0L\) \}/.test(src);
    if (!initOK) bad.push('Android F5: `lastAuto` 初值不是 `lock?.lastAutoMs ?: 0L` —— 重启后冷却清零，可能双开');
    else ok.push('Android F5: 冷却初值从 LockInfo 读回');

    // ② F5 冷却落盘
    const saveOK = /LockStore\.save\(ctx, l\.copy\(lastAutoMs = now\)\)/.test(src);
    if (!saveOK) bad.push('Android F5: `lastAuto = now` 后没有 `LockStore.save(... lastAutoMs = now)` —— 落盘缺失');
    else ok.push('Android F5: 冷却写入已落盘');

    // ③ F6 lastRc 初值
    const rcOK = /var lastRc by remember \{ mutableStateOf\(lock\?\.lastRc \?: 0\) \}/.test(src);
    if (!rcOK) bad.push('Android F6: `lastRc` 初值不是 `lock?.lastRc ?: 0` —— 重启后 F6 忘记锁态');
    else ok.push('Android F6: 锁态初值从 LockInfo 读回');

    // ④ LockStore 里三个字段都要有存/取
    const lsP = path.join(ROOT, 'android-app', 'app', 'src', 'main', 'java', 'com', 'aapk', 'kfkey', 'LockStore.kt');
    if (fs.existsSync(lsP)) {
      const ls = fs.readFileSync(lsP, 'utf8');
      for (const [field, key] of [["lastRc", "lr"], ["rssiP95", "p95"], ["lastAutoMs", "la"]]) {
        // 用 indexOf 而不是动态正则 —— 动态正则的转义在模板字符串里极易写错（本闸门第一版就栽在这）。
        const hasRead = ls.includes('optInt("' + key + '"') || ls.includes('optLong("' + key + '"');
        const hasWrite = ls.includes('.put("' + key + '"');
        if (!hasRead) bad.push("Android LockStore: 缺读取键 \"" + key + "\"（字段 " + field + "）");
        if (!hasWrite) bad.push("Android LockStore: 缺写入键 \"" + key + "\"（字段 " + field + "）");
      }
      if (!bad.length) ok.push("Android LockStore: lastRc / rssiP95 / lastAutoMs 三个字段存取齐备");
      if (!bad.length) ok.push('Android LockStore: lastRc / rssiP95 / lastAutoMs 三个字段存取齐备');
    }
  }
}

if (bad.length) {
  console.log(`✗ 门控数据源跨会话问题 ${bad.length} 处：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n判据说明：自动开锁的门控判据若读到「重启会清零」的变量，就会出现');
  console.log('  · 该拦不拦（F6 读到旧 rc=0）');
  console.log('  · 双开（F5 冷却清零后立刻再发 04）');
  console.log('这类缺陷**门本身写得对**，错的是喂门的数据。');
  process.exit(1);
}
ok.forEach(x => console.log('ok    ' + x));
console.log('\n✓ 自动开锁门控数据源跨会话齐备');
