# 对抗式地毯扫: 简易安卓端 (2026-10-17 第四轮)

触发: 真机仍报"错误码 13"。方法: 逐行读 `android-app/**` 全部 5 个 .kt + manifest + gradle,
每个判定都对着 `vendor/app/**` (JS 权威核心) 与 `App/**` (iOS 逐字节端口) 取证, 不以既有文档结论为依据。
新增闸门 `tools/kotlinshadow.js` 并把变异体喂进去验其鉴别力 (§5)。

## 0. 结论摘要

| # | 问题 | 表现 | 状态 |
|---|---|---|---|
| 1 | `injectToken` 把 LE16 长度读偏一个字节 → 自己那行长度守卫必然成立 → **令牌被静默丢掉** | 恒 rc=13「错误码 13」 | **已修 (根因)** |
| 2 | 01 无令牌分支把 KLV#03 当 rc 读 | 真机印出 "rc=45" 这类查不着的假线索 | **已修** |
| 3 | `CONNECTED` 但 status≠0 时没有分支完成 `connected` | 白等 10 秒 → 报成"连接超时", 盖掉真因 | **已修** |
| 4 | `disconnect()` 后立刻 `close()` | 泄漏 clientIf, 若干次后每次连接都失败 | **已修** |
| 5 | `awaitFrame` 解析成功即整块 clear | 帧粘连时丢掉下一帧开头 → 偶发"门锁没有回应" | **已修** |
| 6 | 自动开锁只看"RSSI≥-38 且距上次>8s" | 站在门口每 8 秒重发 04 (电机连触发) | **已修 (补 F3 回差 + F5 一次性 + 60s 冷却)** |
| 7 | 开锁在途时 RSSI 监测仍在扫 | 安卓"边扫边连"= GATT 133 头号成因; 且被 scanForLock 的 stopScan 连带停掉 | **已修** |
| 8 | 身份复核缺失 | 广播是谁都能发的; iOS 连上后用 03 自报 pid 复核 | **已修 (明文 03, 免 skey)** |
| 9 | 无 rc=13 与 22 的文案; rc=3 文案让用户去 iOS 校时 | 用户看到"错误码 13"无从下手 | **已修 (逐字搬 StatusParser)** |
| 10 | `writeDescriptor`/`writeCharacteristic` 同步被拒仍空等满超时 | 白等 4 秒 | **已修** |
| 11 | `runCatching` 吞掉 `CancellationException` | 界面销毁被报成"扫描失败/开锁失败" | **已修** |
| 12 | 权限被当场收回时 SecurityException 没人接 | 闪退 | **已修** |
| 13 | 二维码 ekey 无上界 | 被改过的码把 KLV 长度字节写回绕 → 存下一把开不了的钥匙 | **已修 (510)** |
| 14 | MTU 注释宣称"抬上去之后 1 片写完" | 假能力宣称 (分片恒 20B) | **已修 (改如实)** |
| 15 | 近场文案"信号强于 -38 时自动开锁" | 与 #6 修后的行为不符 | **已修** |

## 1. 根因 (#1): 长度字段读偏一字节 = 令牌凭空消失

`KfProtocol.kt` 修前:
```kotlin
val len = frameHex.substring(2, 4).toInt(16) or (frameHex.substring(4, 6).toInt(16) shl 8)
```
`substring` 是**字符**下标, 而帧长度在**字节 2..3** = 字符 4..8。修前那两句取的是字节 1..2
(= "版本字节 00" + 长度低字节): 开锁帧真实 len=0x34 时读成 `0x3400` = **13312**。

致命的不是读错数, 而是**读错之后没人发现** —— 下一行自己那句守卫:
```kotlin
if (frameHex.length < bodyStart + len * 2) return frameHex   // 13312*2 必然超界 → 原帧返回
```
于是 `injectToken` **原帧返回**, KLV#EE 从未被追加, 04 裸发。锁按 Java 侧那句"通讯会话无效"
回 rc=13 (对照 `vendor/app/services/lock.js:580` 的实机裁定: "裸发 05 会被锁回 rc=13")。
用户视角: 扫描到了、连上了、令牌也拿到了、帧也写进去了 —— 然后永远是 13。

为什么 `gradle` 全绿、CI 全绿: 这是**语义**错, 不是类型/语法错。所以 §5 那条闸门锁的是字节面。
修后与 `vendor/app/utils/kernel/protocol.js:155` 同口径 (含 8B/10B 头型自适应 + ssToken 保留)。

## 2. 我在本轮自己制造又自己抓出来的两个 (值得记下)

- **#2**: 我给"01 没给令牌"加分支时, 顺手用了 `KfProtocol.rc(tokenFrame)`。但 01 的响应里
  KLV#03 是**令牌有效秒数** (`vendor/app/utils/session.js:2`, u16 LE), 不是结果码 ——
  `RC_KLV` 表里根本没有 0x01 这一项, iOS `extractRc` 对 01 恒返 0。45 秒 TTL 会被念成"rc=45"。
  取证后才改成打印 `klvShape` (iOS LockService:178 同一句)。
- **#8 第一版更险**: 我起初把 pid 复核放在**扫描那一跳**拿广播 pid 比。对着 `fixtures/golden.json`
  才看清广播 `parseAdv` 的 pid 与状态 KLV#34 的 pid **不是同一套编号** (夹具里 7970 vs 16289),
  而二维码的 `p` 抄的是 status 那一套 (`AndroidPair.swift:31` ← `LockService.swift:975 st.pid`)。
  那一版会把**真锁**误杀成"pid 不符" —— 一个比 rc=13 更难查的新故障。改成 iOS 原本的 03 复核。

教训: 加固项也要对着权威逐字节验, 否则"修一个 13"顺手换来一个假的 pid 不符。

## 3. 与 iOS 的行为分歧 (#6 自动开锁)

| 面 | iOS `AutoOpen.swift` | 安卓修前 | 修后 |
|---|---|---|---|
| 武装 | F3 按锁标定 P95 + 回差 (解除线 = base+10·log10(0.5)) | 无滤波, 逐样本翻转 | 固定 base=-38, **同公式回差** |
| 一次事件 | F5 `eventFired`: 每个接近事件只发一次 04 | 无 | `fired` 闩锁, 掉回解除线放开 |
| 冷却 | F5 60s | 8s | 60s |

安卓侧没有标定页 (极简版定位), 所以用固定 -38 = 原代码那条数值; 变的不是阈值而是重复触发。
dBm 是**对数单位**: 解除线只能在功率域换算 —— iOS 那段 0.7×/0.5× 的旧公式教训 (`AutoOpen.swift`
F3 注释) 原样带过来, 并在 §5 的 C 段用不变式锁住 (直接乘系数会被抓到, 实测: 变异"解除线乘 0.5" → 红)。

## 4. 未修 / 有意不动 (如实记)

- **rc=22「不能重复验证」**: iOS 有完整 `doubleVerify` 态 (`UnlockDial.swift:424` "请用指纹或密码开门"),
  安卓端没有第二因子入口, 只能回落权威原文。**没**写"请再点一下" —— 那条链上再点一次只是把同一条
  04 重发, 双验不在本机完成。RC_HINT 里刻意不给 22 编一句做不到的话。
- **rc=-1 (回了帧但没带 rc)**: JS `lock.js:290` 当成功放行, iOS `LockService:345` 判"无法确认、请重试"。
  两端本就不同。开锁这条不赌"当成成功" (门可能根本没开), 也不说"没开" (门可能已经开了),
  改成如实: "先看一眼门有没有开, 再重试"。
- **pid<=0 (老二维码)**: 沿用 iOS 口径跳过复核 (`LockService.swift:112`), 只记 trace 不拦。
- **03 复核读不到 (老固件不回 KLV#34)**: 记 trace 继续开锁 —— 加固不能变成新闸门。
- **targetSdk=34**: 刻意停在 34 (35 强制 edge-to-edge 而界面没做 inset 适配), 见 `build.gradle.kts` 注释。
  这是已裁定的取舍, 不动。
- **keystore 随仓库 + 默认口令**: 已在注释里写明是自签**安装用**密钥不是 Play 上传密钥。仓库私有的
  前提下不动 (动它会让已装的机器无法原地覆盖安装, 正是它想解决的问题)。
- **`AnimatedVisibility` 未使用**: 改动前就存在的死 import, 与本轮无关, 没顺手清 (留给 lint 那一支)。

## 5. 新闸门 tools/kotlinshadow.js (判失败, CI 排在 gradle 之前)

安卓端没有本地编译, `gradle assembleDebug` 只证明"编得过", 不证明"发出去的字节与权威一致"
—— 本轮那个 rc=13 正是编译全绿、真机全废。三段判定:

- **A 源码结构 (20 项)**: injectToken 长度窗口必须是字符 4..6/6..8; 取体必须用判别出的 bodyStart;
  rc 必须读 KLV#03 且走 intHex 前缀语义; RC_NAME 键集合必须覆盖 vendor RC_MSG 全部 27 个;
  令牌通道必须是 0xEE; ekey 上界必须 ≤510; **接线检查** (04 必须经 injectToken、必须有帧尾护栏、
  armed 必须跨样本回灌、fired 必须拦截、监测必须随 busy 撤下)。
- **B 数值对拍 (38 项)**: 把 Kt 纯函数逐行复刻进 node, 与 `vendor/protocol.js`/`cmds.js` 及
  `fixtures/golden.json` 同输入逐字节比 (含 `cmds.withToken` 那帧、真开锁帧注入 EE04、8B/10B 头)。
- **C 判据公式**: F3 双阈值公式 + 三条不变式 (恒强信号只发一次 / 走开再靠近可再发 / 回差带内抖动不翻转)。

**A8/A9 是被变异测试逼出来的**: C 段最初那几条"站在门口只发一次"用的是本工具自己的 JS 复刻,
所以 Kt 里把 `rssiSample` 改成恒武装、把 `fired` 拦截删掉、把监测不随 busy 撤下 —— 全都照样绿。
那是**自证**, 不是对拍。加了 A8 接线检查后: 变异体 15/15 被抓到 (含上一轮漏掉的 1 项)。

## 6. 复核口径 (改动后跑过)

- `node tools/kotlinshadow.js` → exit 0 (A 20 项 / B 38 项 / C 6 项)。
- 变异测试: 15 个变异体 (含"退回 bug 版长度窗口""裸发 unlockFrame""去掉帧尾护栏""恒武装"
  "armed 不回灌""去掉 fired 拦截""ekey 无上界""监测不随 busy 撤") 全部被抓到, 还原后 exit 0。
- `.kt` ×5 结构机检 (注释与字符串里的括号不计数): 花/圆/方括号全平衡, 无未闭合字符串。
- `ios.yml`: `python -c "import yaml; yaml.safe_load(...)"` OK; 换行统一回 CRLF (与 HEAD 一致);
  步骤名无裸冒号 (与新加那条无关, CI 自检那条 grep 不会红)。
- import 面: 移除 coroutines 1.9 已 deprecated 的 `kotlinx.coroutines.flow.collect`
  (`Flow.collect { }` 走成员 + SAM, 全仓 Compose 代码都是这个写法); 无未使用 import。

## 7. 真机验证清单 (改完必须实测, 闸门替代不了锁)

1. 手动点一次开锁: 期望 trace 变长 —— 出现 `03→pid=… 01→xxxx 04→rc=0`, 不再出现 13。
2. 若仍 rc=13: 看 trace 里有没有 `01→`。没有 = 令牌没拿到 (距离/锁侧);
   有 `01→` 但仍 13 = 令牌被锁拒 (可能锁已不在可配网态, 或 ekey 与锁内不符 → 关注 rc=6/12)。
3. 若出现"内部错误: 会话令牌没能装进开锁帧": 那是 §5-A8 那条护栏生效, 说明 injectToken 又漂移了 ——
   这时候**不要**再猜锁的问题, 直接跑 `node tools/kotlinshadow.js`。
4. 自动开锁: 靠近 → 开一次; 站在门口不动 3 分钟 → 只该开一次; 走开 (信号掉到 -41 以下) 再靠近 → 再开一次。
5. 连续开关自动开锁 5 次 + 手动 5 次: 不应出现"再也连不上"(clientIf 泄漏的表征)。
6. 故意扫一张改过的超长 ekey 码: 应判"这不是本 App 的钥匙码", 且不落库。

参照: `docs/PARITY-ADVERSARIAL-2026-10-17.md` (本机↔APK 第三轮), `docs/PARITY-APK.md`, `REVERSE_REPORT.md` §5.6 (rc 表)。
