// 本地 Kotlin 编译通道: 在 CI 之前把协议/链路那一层真编译一遍 (编出 error 就判失败)。
//
// 为什么需要它: 本仓 Kotlin 只在 CI 编译, 一轮五分钟起步; 而安卓历史上真正红过的
// 几乎全在这一层 (run 169 的 `Unresolved reference 'not'`)。这一层**不依赖 Compose**,
// 只用 android.* + kotlinx.coroutines + org.json, 恰好能拿 gradle 缓存里的
// kotlin-compiler-embeddable + SDK 的 android.jar 直接编, 十几秒出结果。
//
// 边界 (诚实写清):
// · 只编那 4 个非 UI 文件。MainActivity.kt 要 Compose/androidx 的 aar, 本地 classpath 凑
//   不齐, 硬编会刷一屏 Unresolved reference 噪音 —— 那还不如不编。UI 层仍只有 CI 能验。
// · 语言级别钉 2.0: CI 用 AGP 内置 Kotlin 2.0.21, 缓存里能拿到的 embeddable 是 2.0.20,
//   同一个 2.0 前端, 语法/类型结论一致。实测 run 176 那条 opt-in 警告本地一字不差复现。
// · 缺 SDK / 缺缓存 jar 时退出 0 并说明原因, 不判失败 —— 有的机器压根没 Android SDK,
//   做成判失败的闸门等于给所有人制造红灯。
//
// 用法: node tools/kotlinlocal.js   |   --quiet 只报结论行
// 缺标准环境变量时用: KF_ANDROID_SDK=<sdk 根> · KF_GRADLE_CACHE=<…files-2.1> · KF_JDK_HOME=<jdk 根>
// (仓里不写死任何人的用户名或盘符 —— 三个都靠 env, 缺了就退 0 说明原因)
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, 'android-app', 'app', 'src', 'main', 'java', 'com', 'aapk', 'kfkey');
const FILES = ['KfProtocol.kt', 'AutoOpenKit.kt', 'LockStore.kt', 'BleUnlocker.kt'];
const quiet = process.argv.includes('--quiet');
const say = (...a) => { if (!quiet) console.log(...a); };
const EXE = process.platform === 'win32' ? 'java.exe' : 'java';

function findAndroidJar() {
  const roots = [];
  for (const k of ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) if (process.env[k]) roots.push(process.env[k]);
  roots.push(process.env.KF_ANDROID_SDK || '', path.join(process.env.LOCALAPPDATA || '', 'Android', 'Sdk'));
  let best = null;
  for (const r of roots) {
    const plats = r ? path.join(r, 'platforms') : null;
    if (!plats || !fs.existsSync(plats)) continue;
    for (const p of fs.readdirSync(plats)) {
      const aj = path.join(plats, p, 'android.jar');
      if (!fs.existsSync(aj)) continue;
      const api = parseInt(p.replace(/\D/g, ''), 10) || 0;
      if (!best || api > best.api) best = { aj, api };
    };
  };
  return best;
}

// 缓存布局: group/artifact/version/<hash>/artifact-version.jar
function findJars() {
  // USERPROFILE/HOME 在某些执行环境里是空的 (我这边的沙箱就是), 所以再兜两个常见绝对路径 ——
  // KF_GRADLE_CACHE 可以显式指定; 否则走 HOME/USERPROFILE 的标准位置。
  // (不在仓里写死任何人的用户名 —— 这台机上我用 KF_GRADLE_CACHE 指过去就行。)
  const cacheRel = ['.gradle', 'caches', 'modules-2', 'files-2.1'];
  const cands = [process.env.KF_GRADLE_CACHE, process.env.USERPROFILE, process.env.HOME]
    .filter(Boolean).map(h => process.env.KF_GRADLE_CACHE && h === process.env.KF_GRADLE_CACHE ? h : path.join(h, ...cacheRel));
  const mods = cands.find(p => fs.existsSync(p));
  if (!mods) return null;
  const one = (g, a, prefer) => {
    const d = path.join(mods, g, a);
    if (!fs.existsSync(d)) return null;
    const vers = fs.readdirSync(d).sort();
    const ordered = [...(prefer || []), ...vers.filter(v => !(prefer || []).includes(v))];
    for (const v of ordered) {
      const dir = path.join(d, v);
      if (!fs.existsSync(dir)) continue;
      const want = a + '-' + v + '.jar';
      const stack = [dir];
      while (stack.length) {
        const p = stack.pop();
        for (const e of fs.readdirSync(p, { withFileTypes: true })) {
          const fp = path.join(p, e.name);
          if (e.isDirectory()) stack.push(fp); else if (e.name === want) return fp;
        };
      };
    };
    return null;
  };
  return {
    kc: one('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', ['2.0.21', '2.0.20']),
    stdlib: one('org.jetbrains.kotlin', 'kotlin-stdlib', ['2.0.21', '2.0.20', '1.9.24']),
    reflect: one('org.jetbrains.kotlin', 'kotlin-reflect', ['1.9.24', '1.9.20']),
    script: one('org.jetbrains.kotlin', 'kotlin-script-runtime', ['2.0.21', '2.0.20']),
    daemon: one('org.jetbrains.kotlin', 'kotlin-daemon-embeddable', ['2.0.21', '2.0.20']),
    trove: one('org.jetbrains.intellij.deps', 'trove4j'),
    // 编译器**自己**要协程与注解: K2JVMCompiler 的 IR 后端会去工具 classloader 找 @NotNull,
    // 少这两个拿到的是 NoClassDefFoundError 而不是编译错误 —— 本轮踩过两次。
    coroTool: one('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', ['1.9.0', '1.6.4']),
    annot23: one('org.jetbrains', 'annotations', ['23.0.0']),
    annot13: one('org.jetbrains', 'annotations', ['13.0']),
    coroSrc: one('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', ['1.9.0', '1.6.4']),
    json: one('org.json', 'json', ['20240303']),
  };
}

function findJava() {
  if (process.env.JAVA_HOME) { const p = path.join(process.env.JAVA_HOME, 'bin', EXE); if (fs.existsSync(p)) return p; };
  const w = spawnSync(process.platform === 'win32' ? 'where' : 'which', ['java'], { encoding: 'utf8' });
  const line = (w.stdout || '').split(/\r?\n/)[0];
  if (line && fs.existsSync(line.trim())) return line.trim();
  if (process.env.KF_JDK_HOME) {
    const p = path.join(process.env.KF_JDK_HOME, 'bin', EXE);
    if (fs.existsSync(p)) return p;
  }
  for (const g of [process.env.KF_JDK_PARENT].filter(Boolean)) {
    if (!fs.existsSync(g)) continue;
    for (const e of fs.readdirSync(g)) { const p = path.join(g, e, 'bin', 'java.exe'); if (fs.existsSync(p)) return p; };
  };
  return null;
}

const android = findAndroidJar();
const jars = findJars();
const java = findJava();
const lack = [!java && 'java', !jars && 'gradle 缓存', jars && !jars.kc && 'kotlin-compiler-embeddable',
  jars && !jars.stdlib && 'kotlin-stdlib', !android && 'android.jar'].filter(Boolean);
if (lack.length) {
  console.log('本地 Kotlin 编译: 跳过 (缺 ' + lack.join(' / ') + ')');
  console.log('  判不了 ≠ 不合格: 这条分支退 0。工具链齐了它才开火 (编出 error 退 1)。');
  process.exit(0);
}

const toolCp = [jars.kc, jars.stdlib, jars.reflect, jars.script, jars.daemon, jars.trove,
  jars.coroTool, jars.annot23, jars.annot13].filter(Boolean).join(path.delimiter);
const srcCp = [android.aj, jars.stdlib, jars.coroSrc, jars.json, jars.annot23].filter(Boolean).join(path.delimiter);
const outDir = path.join(ROOT, '.kotlinlocal');
fs.rmSync(outDir, { recursive: true, force: true });
fs.mkdirSync(outDir, { recursive: true });
say('本地 Kotlin 编译: android-' + android.api + ' | ' + FILES.join(', '));

const r = spawnSync(java, ['-Xmx1536m', '-cp', toolCp,
  'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
  '-no-stdlib', '-language-version', '2.0', '-api-version', '2.0',
  '-classpath', srcCp, '-d', outDir, ...FILES.map(f => path.join(SRC, f))],
  { encoding: 'utf8', timeout: 400000 });

const out = ((r.stdout || '') + (r.stderr || '')).replace(/\r/g, '');
const diag = out.split('\n').filter(l => /(error|warning):/.test(l));
const errs = diag.filter(l => /error:/.test(l));
for (const l of diag.slice(0, 40)) console.log('  ' + l.trim());
if (r.status === 0 && !diag.length) console.log('  零诊断 ✓');
console.log('结果: exit=' + r.status + ' | error ' + errs.length + ' | warning ' + (diag.length - errs.length)
  + ' | 覆盖协议/链路层 (android-' + android.api + '); UI 层与真 APK 打包由 CI 判。');
// 判失败口径 (三条, 各对应一种事实):
// · 真编出 error ⇒ 退 1。这不是'本地尺子说了算': 这类错误 CI 的 gradle 同样会报,
//   区别只是快几分钟。变异测试验过它开火: 注入 run 169 的真实错误 (对非可空值用 !)、
//   未闭合字符串、不存在的方法、Int 当 String ⇒ 四种全部抓到, 第一条逐字复现 CI 的报错文本。
// · 缺 java / gradle 缓存 / android.jar ⇒ 退 0 (上面那条分支) —— 判不了不等于不合格。
// · 只有 warning ⇒ 退 0: CI 也不因警告失败, 而且本地 embeddable 2.0.20 与 CI 的 2.0.21
//   在警告面上本就不完全一致, 拿它判失败会造出与 CI 不同的红线。
process.exit(errs.length ? 1 : 0);
