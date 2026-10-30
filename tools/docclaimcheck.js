#!/usr/bin/env node
// docclaimcheck —— 文档里的**绝对化断言**是否与代码事实矛盾（判失败）。
//
// 正控：把 `docs/解锁速度优化.md` 的「Android 自动开锁」行改回「**不存在**」⇒
//       报出「文档说 Android 无自动开锁，但 MainActivity.kt 里有 maybeAutoUnlock()」。
// 负控：全仓 docs/*.md 零误报（只查**白名单内的具体断言**，不做自然语言推断）。
//
// 2026-10-31（第 67 轮）：`docs/解锁速度优化.md` 有两处过时陈述会误导后人 ——
//   · 「Android 自动开锁**不存在**」—— 而 `MainActivity.kt` 有完整 F3-F6 + 预热
//   · 「Android **不可**重编译（只有反编译产物）」—— 而 `android-app/` 是真实 Kotlin 工程，CI 每次构建
//
// 为什么不能靠通用自然语言检查：那会误报一片。这里只维护**少数几条已知会漂移的断言**，
// 每条都写清「断言原文 → 反证的文件 + 特征串」。新增时照抄这个结构。
//
// 判据：若文档里仍出现「断言原文」，而反证文件的特征串**存在** ⇒ 矛盾 ⇒ 判失败。
//
// 正控：把 `docs/解锁速度优化.md` 的「自动开锁」表格行改回「**不存在**」⇒
//       报出「仍写着『Android 自动开锁』的过时断言，而 MainActivity.kt 里『fun maybeAutoUnlock(』存在」，退出码 1。
// 负控：全仓 docs/*.md 零误报 —— 判据只查 CLAIMS 里两条**已知会漂移**的断言，
//       并排除「原文写 / 修正 / ~~删除线~~ / 已可改」这类**留痕说明**（第一版就是被自己的修正段落误报的）。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

// 已知会漂移的断言：{ doc, claim, proofFile, proofNeedle, why }
const CLAIMS = [
  {
    doc: 'docs/解锁速度优化.md',
    claim: 'Android 自动开锁',
    // 该行若同时含这些词，说明又写回「不存在」了
    lineMatch: /自动开锁.*不存在|不存在.*自动开锁/,
    proofFile: 'android-app/app/src/main/java/com/aapk/kfkey/MainActivity.kt',
    proofNeedle: 'fun maybeAutoUnlock(',
    why: 'MainActivity.kt 有完整的自动开锁（F3-F6 + 预热预取）',
  },
  {
    doc: 'docs/解锁速度优化.md',
    claim: 'Android 可重编译性',
    lineMatch: /不可重编译|只有反编译产物/,
    proofFile: 'android-app/app/build.gradle.kts',
    proofNeedle: 'android {',
    why: 'android-app/ 是真实可编译的 Kotlin 工程，CI 的 Build (Android 13+, APK) 每次构建',
  },
];

const bad = [];
const okList = [];

for (const c of CLAIMS) {
  const docP = path.join(ROOT, c.doc);
  const proofP = path.join(ROOT, c.proofFile);

  if (!fs.existsSync(docP)) { okList.push(`${c.doc} 不存在（跳过：${c.claim}）`); continue; }
  if (!fs.existsSync(proofP)) { okList.push(`${c.proofFile} 不存在（反证文件缺失，跳过：${c.claim}）`); continue; }

  const docSrc = fs.readFileSync(docP, 'utf8');
  const proofSrc = fs.readFileSync(proofP, 'utf8');
  const proofExists = proofSrc.includes(c.proofNeedle);

  if (!proofExists) {
    // 反证不成立 —— 这时文档的断言可能是对的，不该判失败
    okList.push(`${c.claim}: 反证特征串已不存在（${c.proofFile} 里找不到「${c.proofNeedle}」）—— 若确实删了功能，请更新本闸门的 CLAIMS`);
    continue;
  }

  // 2026-10-31（第 67 轮，**本闸门第一版误报了自己写的修正说明**）：
  // 修正段落会**引用**旧原文（「原文写『…不存在』—— 错」），那种行不该算过时断言。
  // 判据：跳过含「原文写 / 修正 / —— 错 / 过时」的行，只查**当前生效**的陈述。
  const hitLines = docSrc.split(/\r?\n/).filter(l => {
    if (!c.lineMatch.test(l)) return false;
    if (/原文写|修正|—— 错|过时|第 \d+ 轮修正/.test(l)) return false;
    // 删除线 ~~…~~ 表示该说法已作废（本仓惯用的「留痕但不生效」写法），不算当前陈述。
    if (/~~/.test(l)) return false;
    // 「已可改 / 已实现 / 已修」这类改判说明也不算过时断言。
    if (/已可改|已实现|已修|已补/.test(l)) return false;
    return true;
  });
  if (hitLines.length) {
    bad.push(`${c.doc}: 仍写着「${c.claim}」的过时断言，而 ${c.proofFile} 里「${c.proofNeedle}」存在`
      + `\n      文档原文: ${hitLines[0].trim().slice(0, 80)}`
      + `\n      事实: ${c.why}`);
  } else {
    okList.push(`${c.claim}: 文档未写过时断言`);
  }
}

if (bad.length) {
  console.log(`✗ 文档断言与代码事实矛盾 ${bad.length} 处：`);
  bad.forEach(x => console.log('  ' + x));
  console.log('\n为什么查这个：过时文档比没有文档更糟 —— 后人会照着它做决策。');
  console.log('修法：改文档陈述使之与代码一致；若功能确实删了，则改本闸门的 CLAIMS（并写明为何）。');
  process.exit(1);
}
okList.forEach(x => console.log('ok    ' + x));
console.log('\n✓ 文档里已知会漂移的绝对化断言都与代码事实一致');
