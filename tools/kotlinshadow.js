// 安卓端 Kt 的字节面影子对拍 —— Android 侧没有本地编译, CI 的 gradle 只保证"编得过",
// 不保证"发出去的帧与 vendor JS 权威口径逐字节相同"。这个工具补的正是后者。
//
// 三条判定, 全部判失败:
//   A. 结构性对拍 (正则抠 Kt 源码): injectToken 的长度窗口、rc 表的键集合、KLV 键常量。
//      —— 直接咬住 2026-10-17 那个 rc=13 的坑: 长度字段被从"字节 2..3"读成了"字节 1..2"
//         (hex 字符 4..8 写成了 2..6), 令牌 KLV 被静默丢掉, 帧照样发得出去、锁照样回 13。
//   B. 数值对拍 (逐行复刻纯函数到 node): 与 vendor/app/utils/kernel 同输入逐字节比。
//      复刻口径与 tools/cmdsshadow.js / tools/parseshadow.js 一致 —— 手抄, 但两侧都是**同一夹具**,
//      改错任何一处都会在这里红, 不必等真机。
//   C. 自动开锁判据 (AutoOpenKit.kt) 与 iOS AutoOpenKit 的 F3/F5 公式对拍 + 一条不变式:
//      信号停在门口 (恒强于解除线) 时, 一次接近事件只允许发一次 04。
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const KT_DIR = path.join(ROOT, 'android-app', 'app', 'src', 'main', 'java', 'com', 'aapk', 'kfkey');
const P = require(path.join(ROOT, 'vendor', 'app', 'utils', 'kernel', 'protocol.js'));
const C = require(path.join(ROOT, 'vendor', 'app', 'utils', 'kernel', 'cmds.js'));
const golden = JSON.parse(fs.readFileSync(path.join(ROOT, 'fixtures', 'golden.json'), 'utf8'));

const readNorm = (p) => fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n');   // 行尾与判定结果解耦 (见上)
const kt = (f) => readNorm(path.join(KT_DIR, f));
const kf = kt('KfProtocol.kt');
const ao = kt('AutoOpenKit.kt');

let fails = 0;
const bad = (m) => { fails++; console.log('FAIL  ' + m); };
const good = (m) => console.log('ok    ' + m);

// ============================ A. 结构性对拍 ============================
console.log('--- A. 源码结构 ---');

// A1: injectToken 必须按"字节 2..3"读长度 = hex 字符 4..6 / 6..8
const inj = kf.slice(kf.indexOf('fun injectToken'), kf.indexOf('data class Frame'));
if (!inj) bad('A1 找不到 injectToken');
else {
  const readsLen = /substring\(4,\s*6\)/.test(inj) && /substring\(6,\s*8\)/.test(inj);
  if (!readsLen) bad('A1 injectToken 的长度字段没有从 hex 字符 4..6 / 6..8 (字节 2..3) 读 —— 这正是 rc=13 那个坑');
  else good('A1 injectToken 长度窗口 = 字节 2..3 (LE16)');
  if (/substring\(2,\s*4\)/.test(inj) || /substring\(2,\s*6\)/.test(inj))
    bad('A1 injectToken 里又出现从字节 1 起读长度 (substring(2,4)/(2,6)) —— 会把版本字节拼进长度');
  // 长度必须**重算**, 不能沿用入参帧的旧长度字节
  if (!/klv\.length \/ 2/.test(inj) && !/n = klv\.length/.test(inj))
    bad('A1 injectToken 没按新 KLV 长度重建帧头 (追加 KLV#EE 之后 len 必须 +4)');
  else good('A1 injectToken 追加后重算长度');
}

// A5: 8B/10B 头型自适应不能被写死成 16 (头型判错 → 取体错位 → 帧损坏)
{
  const usesBodyStart = /substring\(bodyStart/.test(inj) || /\[bodyStart/.test(inj);
  const hardCoded16 = /substring\(16,\s*16 \+ len/.test(inj);
  if (!usesBodyStart || hardCoded16) bad('A5 injectToken 取体没有用判别出来的 bodyStart (10B 头帧会错位 2 字节)');
  else good('A5 取体按头型自适应 (bodyStart)');
}

// A6: 长度字段不许超界 —— KLV 的 len 只有 1 字节, 帧长 2 字节; ekey 上界必须 ≤510 hex 字符
{
  const ls = kt('LockStore.kt');
  const m = ls.match(/ekey\.length >\s*(\d+)/);
  if (!m) bad('A6 LockStore 没有给 ekey 设上界 (超长二维码会把 KLV 长度字节写回绕)');
  else if (+m[1] > 510) bad('A6 ekey 上界 ' + m[1] + ' 超过 KLV 1 字节长度上限 (510 个 hex 字符)');
  else good('A6 ekey 上界 = ' + m[1] + ' hex 字符 (≤510, KLV len 1B)');
}

// A7: rc 必须走 intHex 前缀语义 (空值/非 hex = 0, 与 iOS/JS 同结论), 不能退回 toInt(16) ?: -1
{
  const rcFn = kf.slice(kf.indexOf('fun rc(f: Frame)'), kf.indexOf('/** 锁端结果码 (JS'));
  if (!/intHex\(it\)/.test(rcFn)) bad('A7 rc 没有走 intHex (退化帧两端口径会相反)');
  else if (/runCatching \{ it\.toInt\(16\)/.test(rcFn)) bad('A7 rc 里仍留着 toInt(16) 抛错回落 -1 的旧口径');
  else good('A7 rc@KLV#03 走 intHex 前缀语义');
}

// A2: rc 键集合必须覆盖 vendor RC_MSG 的每一个键 (缺一个就是"锁回了码而人看不到")
const lockJs = fs.readFileSync(path.join(ROOT, 'vendor', 'app', 'services', 'lock.js'), 'utf8');
const rcBlock = lockJs.slice(lockJs.indexOf('const RC_MSG'), lockJs.indexOf('const CMD_NAME'));
const vendorRc = new Set([...rcBlock.matchAll(/(\d+)\s*:/g)].map(m => +m[1]));
const rcNameBlock = kf.slice(kf.indexOf('RC_NAME = mapOf'), kf.indexOf('RC_HINT'));
const ktRc = new Set([...rcNameBlock.matchAll(/(\d+)\s+to\s+"/g)].map(m => +m[1]));
const missRc = [...vendorRc].filter(k => !ktRc.has(k));
if (missRc.length) bad('A2 KfProtocol.RC_NAME 缺这些权威码: ' + missRc.join(','));
else good('A2 rc 表覆盖 vendor RC_MSG 全部 ' + vendorRc.size + ' 个键');
if (!ktRc.has(13)) bad('A2 rc=13 (通讯过期) 不在表里 —— 这次事故就会被报成"错误码 13"没人知道含义');

// A3: rc 必须从 KLV#03 读 (RC_KLV: 0x03/0x04 → 3), 且缺项才是 -1
const rcFn = kf.slice(kf.indexOf('fun rc(f: Frame)'), kf.indexOf('/** 锁端结果码 (JS'));
if (!/klvs\[0x03\]/.test(rcFn)) bad('A3 rc 没有从 KLV#03 读');
else if (!/\?: -1/.test(rcFn)) bad('A3 rc 缺项没有回落 -1');
else good('A3 rc@KLV#03, 整项缺失 = -1');

// A4: 0xEE 令牌通道 (不是 0xE、不是 0xEF)
if (!/klv\(0xEE, tokenHex\)/.test(kf)) bad('A4 令牌 KLV 键不是 0xEE');
else good('A4 令牌通道 KLV#0xEE');

// A8: 回差 + 闩锁必须**接在线上**。
//   为什么单独一条: C 段那个"站在门口只发一次"的模拟用的是本工具自己的 JS 复刻,
//   所以 Kt 里把 rssiSample 改成"恒武装"时它照样绿 —— 那是自证。接线检查只能看源码。
{
  const body = ao.slice(ao.indexOf('fun rssiSample'), ao.indexOf('/** F5 冷却'));
  if (!/prevArmed/.test(body) || !/if \(prevArmed\) rssi > disarm else rssi >= arm/.test(body))
    bad('A8 rssiSample 没有按 prevArmed 走回差 (解除线没用上 → 门口来回走会逐样本翻转)');
  else good('A8 rssiSample 回差双阈值');

  const ma = kt('MainActivity.kt');
  // ① 武装位必须**回灌**给下一次判定 (局部 val 就等于没滤波)
  if (!/armed = AutoOpenKit\.rssiSample\(prevArmed = armed/.test(ma))
    bad('A8 MainActivity 没有把 armed 回灌给 rssiSample (回差滤波等于没接)');
  else good('A8 武装位跨样本回灌');
  // ② 一次性闩锁: 2026-10-27 审核后改成「信号掉到解除线以下 3dB 才放开」（与 iOS 同口径）。
  //    旧写法是「!armed 就放开」—— 而 armed 在回差带内就会变 false，退半步再进一步会再开一次。
  if (!/if\s*\(r < AutoOpenKit\.disarmThreshold\(\)\s*-\s*3\)\s*\{\s*fired = false/.test(ma))
    bad("A8 缺少「走远放开闩锁」那一步 (一次事件之后再也开不了，或被回差带内抖动放开)");
  else good('A8 走远才放开闩锁');
  if (!/if \(!armed \|\| fired\) return/.test(ma)) bad('A8 缺少 fired 拦截 (人站在门口会反复下发 04)');
  else good('A8 一次接近事件只发一次');
  if (!/AutoOpenKit\.coolReady\(lastAuto, now\)/.test(ma)) bad('A8 没读 60s 冷却');
  else good('A8 冷却闸在链上');
  // 抠意图而不是字面: 监测的 key 里必须有 busy (开锁在途要撤监测), 可以有更多 (warming 也进了 key,
  //   预热同样要撤监测) —— 断言写死整串会在每次合理扩展 key 时假红。
  const leKey = (ma.match(/LaunchedEffect\(proximity,([^)]*)\)/) || ['', ''])[1];
  if (!/\bbusy\b/.test(leKey))
    bad('A8 RSSI 监测没有随 busy 撤下 (安卓一边扫一边连 = GATT 133 头号成因, 且 scanForLock 的 stopScan 会把监测一起停掉)');
  else good('A8 监测随 busy 撤下 (key: ' + leKey.trim() + ')');

  // ② 预热 (秒开的关键): prewarm 只许建链, 一个命令都不发; 且**绝不自己起扫描** ——
  //    监测流正在扫时另起 startScan 会顶掉它, 收尾那句 stopScan 又把监测一起停掉,
  //    那就是本轮刚修过的那个坑 (表现 = "当前信号再也不更新")。句柄必须来自缓存。
  const blPrewarm = (kt("BleUnlocker.kt").match(/suspend fun prewarm[\s\S]*?\n    \}/) || [""])[0];
  if (!blPrewarm) bad("A8 找不到 prewarm 函数 (改名或删除会让这一整组断言失效 —— 必须同步改这里)");
  else {
    for (const [cmd, name] of [["tokenFrame()", "01 取令牌"], ["unlockFrame(", "04 开锁"], ["statusFrame()", "03 认锁"]]) {
      if (blPrewarm.includes(cmd)) bad('A8 prewarm 里发了 ' + name + ' —— 预热只许建链, 发命令就不是「预热」而是真开锁了');
      else good("A8 prewarm 不发 " + name);
    }
    if (/scanForLock\(/.test(blPrewarm)) bad("A8 prewarm 自己起扫描 —— 会和监测流抢那唯一一路扫描 (本轮刚修的坑)");
    else good("A8 prewarm 用缓存句柄, 不自起扫描");
    if (!/freshSeen\(lock\.mac\)/.test(blPrewarm)) bad("A8 prewarm 没有从广播缓存取句柄");
    else good("A8 prewarm 复用广播句柄");
  }
  // 开锁冷路径同样不许在监测还在扫时另起扫描: 必须先试缓存句柄
  const blUnlock = (kt("BleUnlocker.kt").match(/suspend fun unlock[\s\S]*?\n    \}/) || [""])[0];
  if (!blUnlock) bad("A8 找不到 unlock 函数 (同样会让下面几条断言静默失效)");
  else {
  // 判意图不判写法: 冷路径必须在**自己起扫描之前**先问一次缓存句柄。
  // (run 175 的 FAIL 是尺子太字面: 把 `freshSeen(…) ?: try {…}` 改成显式 if/else 之后,
  //  意图没变、写法变了就判红。用 indexOf 比位置, 不再绑某种句法形状。)
  const seenPos = blUnlock.indexOf("freshSeen(lock.mac)");
  const coldScanPos = blUnlock.indexOf("scanForLock(lock,");
  if (seenPos < 0 || (coldScanPos >= 0 && seenPos > coldScanPos)) bad("A8 冷路径没在自起扫描之前先吃缓存句柄 (白付一次扫描的时间, 秒开就没了)");
  else good("A8 冷路径优先复用广播句柄");
  // 热链路必须能被拆: 复用不留出口 = 解绑/退出后那条 GATT 一直占着锁
  if (!/suspend fun release\(/.test(kt("BleUnlocker.kt"))) bad("A8 没有 release() 出口 (热链路拆不掉)");
  else good("A8 release() 出口在");
  if (!/unlocker\.release\(\)/.test(ma)) bad("A8 MainActivity 没在解绑/销毁时拆链路");
  else good("A8 解绑与销毁都会拆链路");
  // 预热在途也必须撤监测: 安卓同时只跑一路扫描, prewarm 建链时监测还在扫 = 边扫边连 (133)。
  // 上一条只查 busy 在不在 key 里 (合理扩展 key 时不该假红), 所以 warming 单独钉一条。
  if (!/\bwarming\b/.test(leKey)) bad("A8 预热在途时监测没撤下 (warming 不在 LaunchedEffect 的 key 里)");
  else if (!/if \(!proximity \|\| busy \|\| warming[^)]*\) return@LaunchedEffect/.test(ma)) bad("A8 warming 进了 key 但早退那行没带上它 (撤不下监测)");
  else good("A8 预热在途同样撤下监测");
  // 掉回解除线时要连 prewarmStarted 一起放开, 否则一次 App 生命周期内只会预热一次,
  //   第二次靠近就没有热链路 —— "秒开"退化成只有第一次快。
  if (!/if \(!armed\)[^\n]*prewarmStarted = false/.test(ma) && !/prewarmStarted = false[^\n]*\n[^\n]*fired = false/.test(ma)) bad("A8 信号掉线时没有放开 prewarmStarted (第二次靠近不再有热链路)");
  else good("A8 掉线同时放开闩锁与预热位");
  if (!/unlocker\.prewarm\(/.test(ma)) bad('A8 MainActivity 没发起预热 (那「秒开」就只剩省了拆链那一半)');
  else good("A8 预热被 UI 调用");
  // 热链路复用前必须核过身份 (prewarm 刻意不核, 开锁这次非核不可)
  if (!/verifyIdentity\(reuse, lock, trace\)/.test(blUnlock)) bad("A8 走热链路时跳过了身份复核 (预热建的链没核过!)");
  else good("A8 热链路开锁前补身份复核");
  }

  // ③ 帧必须**经过** injectToken 再落地 —— 直接写 unlockFrame 就等于回到裸发
  const bl = kt('BleUnlocker.kt');
  if (!/KfProtocol\.injectToken\(KfProtocol\.unlockFrame/.test(bl))
    bad('A8 开锁帧没有过 injectToken (裸发 04 → 锁回 rc=13)');
  else good('A8 04 走 injectToken');
  if (!/hex\.endsWith\(tokKlv\)/.test(bl)) bad('A8 缺少"令牌确实落在帧尾"的护栏');
  else good('A8 注入结果有帧尾护栏');
  if (/writeChunked\(g, write, KfProtocol\.bytes\(KfProtocol\.unlockFrame/.test(bl))
    bad('A8 存在绕过 injectToken 直发 unlockFrame 的写点');
  else good('A8 没有绕过护栏的直发点');
}

// A9: 01 的响应里 KLV#03 是"令牌有效秒数", 不是结果码 (vendor lock.js RC_KLV 没有 0x01 这一项,
//     iOS extractRc 对 01 恒返 0)。把 #03 印成 rc= 会把 45 秒 TTL 念成 "rc=45" 那种假线索。
{
  const bl = kt('BleUnlocker.kt');
  const seg = bl.slice(bl.indexOf('if (token == null)'), bl.indexOf('trace.append("01→'));
  if (!seg) bad('A9 找不到 01 无令牌那段');
  else {
    if (/KfProtocol\.rc\(tokenFrame\)/.test(seg))
      bad('A9 01 分支把 KLV#03 当 rc 读了 (那是 TTL 秒数, 会在真机上印出 "rc=45" 之类的假线索)');
    else good('A9 01 分支不读 rc (TTL 不当结果码)');
    if (!/klvShape\(tokenFrame\)/.test(seg))
      bad('A9 01 失败路径没带回包形状 —— 真机排障只剩"门锁未给会话令牌"这一句空话');
    else good('A9 01 失败路径打印回包形状');
  }
  // klvShape 的输出形状本身也要对得住 iOS: "#%02x=%dB"
  if (!/"#\" \+ String\.format\("%02x", it\.key\) \+ "="/.test(kf.replace(/"/g,'\\\"')) && !/%02x/.test(kf))
    bad('A9 klvShape 的键格式与 iOS 漂移');
  else good('A9 klvShape 键格式 #02x=NB');
}

// A10: 编译号 = 构建时刻那套不变量 (build.gradle.kts + workflow)。
//   查的是"构建号会不会静默退化" —— 下面三种退化都装得上、看着正常:
//     ① versionCode 被改回 yyyyMMddHHmm (int32 溢出 = 装不上) 或那道上界闸被删;
//     ② workflow 的 needs/env 接线被改名 → gradle 静默回落 Instant.now(),
//        号照样单调、照样能装, 只有"ipa 与 apk 时刻不再相同"一个后果, 而那正是唯一要解决的问题;
//     ③ iOS 只注入 App 不注入 Widget (extension 与容器版本不一致, 安装被拒, 报得像签名问题)。
{
  const gradle = readNorm(path.join(ROOT, "android-app", "app", "build.gradle.kts"));
  const wfText = readNorm(path.join(ROOT, ".github", "workflows", "ios.yml"));
  const hasIntGuard = /versionCode\s*=\s*run\s*\{/.test(gradle) && /Int\.MAX_VALUE - 1L/.test(gradle);
  if (!hasIntGuard) bad("A10 build.gradle.kts 少了 int32 上界那道闸 (versionCode 溢出是静默回绕, 先转再查等于没查)");
  else good("A10 versionCode 有截断前的 int32 上界闸");
  const brokenQuote = gradle.indexOf("yyyyMMdd''HHmmss") >= 0;
  const literalDot = gradle.indexOf("yyyyMMdd'.'HHmmss") >= 0;
  if (brokenQuote || !literalDot) bad("A10 versionName 的时刻格式里那个点不是字面量 (要写成 '.') —— 与 iOS 的 %Y%m%d.%H%M%S 差一个字符, 覆盖安装会被判成没换号");
  else good("A10 versionName 格式 = yyyyMMdd.HHmmss (点为字面量, 与 iOS 同串)");
  if (!/ZonedDateTime\.of\(2026, 1, 1, 0, 0, 0, 0, buildZone\)/.test(gradle)) bad("A10 versionCode 的基准时刻 (2026-01-01 东八区) 不见了");
  else good("A10 基准 = 2026-01-01 00:00 东八区");
  if (!/project\.providers\.environmentVariable\("KF_BUILD_TS"\)/.test(gradle)) bad("A10 没有从 KF_BUILD_TS 取时刻 (或退回 System.getenv, 开 configuration cache 后不会失效)");
  else good("A10 时刻取自注入的 KF_BUILD_TS (providers 登记为输入)");
  if (!/^  stamp:$/m.test(wfText)) bad("A10 workflow 里没有 stamp 作业 (两端各取 now 必然差几十秒)");
  else good("A10 stamp 作业在");
  const needs = (wfText.match(/needs: stamp/g) || []).length;
  if (needs !== 2) bad("A10 needs: stamp 出现 " + needs + " 次, 应为 2 (build 与 android 各一)");
  else good("A10 两个构建作业都 needs stamp");
  if (wfText.indexOf("KF_BUILD_TS: ${{ needs.stamp.outputs.kf_build_ts }}") < 0) bad("A10 android 的 env 没接 KF_BUILD_TS");
  else good("A10 KF_BUILD_TS → gradle");
  if (wfText.indexOf("KF_BUILD_STAMP: ${{ needs.stamp.outputs.kf_build_stamp }}") < 0) bad("A10 缺 KF_BUILD_STAMP (改名步骤会产出 KfKey-.apk, 而上传通配照样命中)");
  else good("A10 KF_BUILD_STAMP → 改名步骤");
  const injStep = (wfText.slice(wfText.indexOf("注入编译号"), wfText.indexOf("注入编译号") + 1400));
  if (!injStep.includes("App/Info.plist") || !injStep.includes("CFBundleVersion")) bad("A10 iOS 没给 App/Info.plist 注入 CFBundleVersion");
  else good("A10 App/Info.plist 注入编译号");   // 927 小组件扩展已随大删波 2 移除, 不再有第二份 plist
  if (!/dump badging/.test(wfText)) bad("A10 没有从 APK 产物本身核对编译号 (日志只证明 gradle 算过, 不证明写进了 APK)");
  else good("A10 产物级核对在");
  if (gradle.indexOf("KfBuildStamp") < 0) bad("A10 gradle 配置期那行 KfBuildStamp 打印被删 (aapt 缺席时就没有退路核对)");
  else good("A10 gradle 配置期打印编译号 (ASCII 标记)");
}

// ============================ B. 数值对拍 ============================
console.log('--- B. 纯函数逐字节 ---');
const hp = v => ('00' + (v & 0xff).toString(16)).slice(-2);
const kbytes = h => { const n = h.length / 2, o = new Uint8Array(n); for (let i = 0; i < n; i++) o[i] = parseInt(h.substr(i * 2, 2), 16); return o; };
const khex = b => Array.from(b).map(hp).join('');
const kklv = (k, v) => hp(k) + hp((v.length / 2) & 0xff) + v;
const kframe = (cmd, klv) => ('87' + '00' + hp((klv.length / 2) & 0xff) + hp(((klv.length / 2) >> 8) & 0xff) + hp(cmd & 0xff) + '000000' + klv).toUpperCase();
function kinject(frameHex, tokenHex) {
  if (!tokenHex || frameHex.length < 16) return frameHex;
  const f = frameHex.toUpperCase();
  const len = parseInt(f.substring(4, 6), 16) | (parseInt(f.substring(6, 8), 16) << 8);
  const cmd = parseInt(f.substring(8, 10), 16);
  const header10 = f.length >= 20 + len * 2;
  const bs = header10 ? 20 : 16;
  if (f.length < bs + len * 2) return f;
  const body = f.substring(bs, bs + len * 2);
  const klv = body + kklv(0xEE, tokenHex);
  if (!header10) return kframe(cmd, klv);
  const n = klv.length / 2;
  return ('87' + '00' + hp(n & 0xff) + hp((n >> 8) & 0xff) + hp(cmd & 0xff) + f.substring(10, 14) + '000000' + klv).toUpperCase();
}
function kparseKlv(hex) {
  const b = kbytes(hex), m = new Map(); let off = 0;
  while (off < b.length) {
    if (off + 2 > b.length) return null;
    const key = b[off], len = b[off + 1];
    if (off + 2 + len > b.length) return null;
    m.set(key, hex.substring((off + 2) * 2, (off + 2 + len) * 2));
    off += 2 + len;
  }
  return m;
}
function kparse(hexIn) {
  const hex = hexIn.toLowerCase();
  if (hex.length < 14) return null;
  const b = kbytes(hex);
  const len = b[2] | (b[3] << 8), cmd = b[4], ver = b[1];
  const orders = ver === 0x01 ? [8, 7, 10] : [8, 10, 7];
  for (const off of orders) {
    if (b.length < off + len) continue;
    const m = kparseKlv(hex.substring(off * 2, (off + len) * 2));
    if (!m) continue;
    return { cmd, klvs: m, raw: hex.substring(0, (off + len) * 2) };
  }
  return null;
}
const kintHex = h => { let v = 0n, n = 0; for (const ch of h) { const d = parseInt(ch, 16); if (Number.isNaN(d)) break; v = v * 16n + BigInt(d); n++; if (v > 0xffffffffn) v = 0xffffffffn; } return n === 0 ? 0 : Number(v > 0x7fffffff ? 0x7fffffff : v); };
const kunlock = e => kframe(0x04, kklv(0x01, '0'.repeat(32)) + kklv(0x02, e.toLowerCase()));
const jintHex = v => parseInt(v || '0', 16) || 0;

let nB = 0;
const eqB = (name, a, b) => { nB++; if (String(a).toUpperCase() !== String(b).toUpperCase()) bad('B ' + name + '\n        kt=' + a + '\n        权威=' + b); };

for (const key of Object.keys(golden.cmds)) {
  const want = golden.cmds[key];
  if (typeof want !== 'string' || !/^87/i.test(want)) continue;
  // 用 vendor 现场构造同一命令, 再要求 Kt 复刻给出同一串
  const gen = { cmd01Session: () => C.cmd01Session().hex, cmd03StatusPlain: () => C.cmd03StatusPlain('fbb993c5cc95').hex,
    cmd04Open_klv01: () => C.cmd04Open('cafebabe'.repeat(4)).hex, cmd12Echo: () => C.cmd12Echo().hex }[key];
  if (!gen) continue;
  eqB('请求帧 ' + key + ' 与 golden 一致', gen(), want);
}
eqB('Kt tokenFrame == vendor', kframe(0x01, ''), golden.cmds.cmd01Session);
eqB('Kt statusFrame == vendor', kframe(0x03, ''), golden.cmds.cmd03StatusPlain);
eqB('Kt unlockFrame == golden', kunlock('cafebabe'.repeat(4)), golden.cmds.cmd04Open_klv01);
for (const [nm, mk] of [['12echo', () => C.cmd12Echo().hex], ['01', () => P.cmd01Session(8).hex], ['03', () => P.cmd03Status(8, 'aabbccddeeff', false).hex]]) {
  eqB('Kt injectToken(' + nm + ') == vendor', kinject(mk(), 'beef'), P.injectToken(mk(), 'beef'));
}
eqB('Kt injectToken(04) == vendor', kinject(kunlock('cafebabe'.repeat(4)), 'd241'), P.injectToken(C.cmd04Open('cafebabe'.repeat(4)).hex, 'd241'));
eqB('Kt injectToken 命中 golden withToken', kinject(C.cmd12Echo().hex, 'beef'), golden.cmds.withToken);
eqB('Kt injectToken 空令牌 = 原帧', kinject(kframe(0x01, ''), ''), kframe(0x01, ''));
eqB('Kt injectToken 10B 头保留 ssToken', kinject('870005001200BEEF0000000103123456', 'beef'), P.injectToken('870005001200BEEF0000000103123456', 'beef'));

// 帧尾必须真带 KLV#EE (护栏本身的形状)
{
  const got = kinject(kunlock('cafebabe'.repeat(4)), 'd241');
  eqB('注入后帧尾 = EE04+token', got.endsWith(kklv(0xEE, 'd241').toUpperCase()), 'true');
  const bare = kunlock('cafebabe'.repeat(4));
  eqB('未注入的裸帧不含 KLV#EE (对拍有鉴别力)', bare.includes('EE04'), 'false');
}
for (const v of [golden.parse.status_frame, golden.parse.log_frame, golden.parse.header8, golden.parse.header7, golden.parse.header10]) {
  const mine = kparse(v), their = P.parseResponse(v);
  eqB('parse ok? ' + v.slice(0, 12), !!mine, their.ok);
  eqB('parse cmd ' + v.slice(0, 12), mine ? mine.cmd : -1, their.ok ? their.cmd : -1);
}
for (const v of [golden.parse.status_frame, golden.parse.log_frame]) {
  const m = kparse(v), t = P.parseResponse(v);
  const their = new Map(t.klvs.map(k => [k.key, k.val.toLowerCase()]));
  let same = their.size === m.klvs.size;
  for (const [k, val] of m.klvs) if (their.get(k) !== val.toLowerCase()) same = false;
  eqB('KLV 全表 ' + v.slice(0, 10), same, 'true');
}
eqB('pid(status_frame KLV#34)', kparse(golden.parse.status_frame).klvs.get(0x34), 'a13f0000');
for (const c of ['', '00', '0d', 'd2', 'ff', 'ffff', 'zz', '100', '0e']) eqB('intHex("' + c + '") == JS', kintHex(c), jintHex(c));
if (!fails) good('B 共 ' + nB + ' 项与 vendor / golden 逐字节一致');

// ============================ C. 自动开锁判据 ============================
console.log('--- C. AutoOpenKit F3/F5 ---');
const arm = b => b;
const disarm = b => Math.round(b + 10 * Math.log10(0.5));
if (!/fun armThreshold\(base: Int = BASE\): Int = base/.test(ao)) bad('C 武装线公式漂移 (应为 base)');
if (!/10 \* log10\(0\.5\)/.test(ao)) bad('C 解除线不再是线性功率域换算 (10·log10(0.5)) —— dBm 上直接乘系数会把方向搞反');
else good('C 解除线 = base + 10·log10(0.5) (与 iOS disarmThreshold 同式)');
if (!/const val COOLDOWN_MS = 6_000L/.test(ao)) bad('C 冷却时长不是 6_000L (用户 2026-10-17: 开完锁等 6 秒恢复自动扫锁; iOS cooldownSeconds 必须同步改 6)');
else good('C 冷却 6s (与 iOS AutoOpenKit.cooldownSeconds=6 同口径)');

function sample(prev, r, b) { return prev ? r > disarm(b) : r >= arm(b); }
// 不变式: 信号恒强 (站在门口不动) ⇒ 逐样本只武装一次, 不反复翻转
// 2026-10-27 审核修复 (C 线)：本组原先 5 处硬编码 -38，而 AutoOpenKit.BASE 实际是 -40 ——
// 于是 BASE 改成任何值这组断言都全绿，**它测的是它自己**。改成从 Kotlin 源码实时读。
const KT_PATH = path.join(__dirname, "..", "android-app", "app", "src", "main", "java", "com", "aapk", "kfkey", "AutoOpenKit.kt");
const KT_SRC = fs.readFileSync(KT_PATH, "utf8");
const BASE_M = /const val BASE = (-?\d+)/.exec(KT_SRC);
if (!BASE_M) { console.error("✗ 未能从 AutoOpenKit.kt 解析 const val BASE"); process.exit(1); }
const RB = parseInt(BASE_M[1], 10);   // 真实武装线
{
  let armed = false, fired = false, fires = 0;
  for (let t = 0; t < 40; t++) {
    armed = sample(armed, -35, RB);
    if (!armed) fired = false;
    if (armed && !fired) { fired = true; fires++; }
  }
  if (fires !== 1) bad('C 站在门口 (-35 恒定) 触发了 ' + fires + ' 次, 应为 1 次 (F5 一次性)');
  else good('C 一次接近事件只发一次 04');
  // 走开再回来: 掉到解除线以下 → 放开闩锁 → 可再发一次
  let armedB = true, firedB = true, firesB = 0;
  for (const r of [-50, -60]) { armedB = sample(armedB, r, RB); if (!armedB) firedB = false; }
  for (let t = 0; t < 10; t++) { armedB = sample(armedB, -34, RB); if (armedB && !firedB) { firedB = true; firesB++; } }
  if (firesB !== 1) bad('C 走开再靠近没有再触发 (=' + firesB + '), 应恰好 1 次');
  else good('C 离开后重新靠近可再触发一次');
  // 回差带内来回抖动不翻转
  let a = true;
  for (const r of [-40, RB, -40, -39, -40]) a = sample(a, r, RB);
  if (!a) bad('C 回差失效: -40..-38 抖动把武装位翻掉了 (解除线应≈ ' + disarm(RB) + ')');
  else good('C 回差带 [' + (disarm(RB) + 1) + ',' + RB + '] 内抖动不翻转');
}
console.log('--- C 公式校验: BASE=' + RB + ' 武装线=' + arm(RB) + ' 解除线=' + disarm(RB) + ' ---');

console.log(fails ? '\n影子对拍不通过 (' + fails + ')' : '\n全部通过');
process.exit(fails ? 1 : 0);
