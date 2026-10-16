# PARITY-APK — 原版 APK 功能 ↔ iOS 离线版 对照（2026-10-17）

回答一个问题：**这台 iOS App 是否把原版 APK 的功能都装下了（离线可做的部分）？**

口径先钉死（三条，缺一条这份表就会变成自证）：

1. **只算离线**：需要账号 / 厂商云 API / 云推送 / 云下载的，一律不计入"该有"。
   依据是用户已定案的"不做在线功能"（厂商云 urlcsapi.zelkova.cn 虽存活但已停服意图明确）。
2. **证据只取原件**：`apk_raw/assets/www/build/main.js`（AOT 视图指令 + 页面类方法与它们真正调用的命令/API）、
   `ui-replica/pages/*.html`（51 页逐页推演）、`ui-replica/_src/extract-report.md`、`REVERSE_REPORT.md`、
   `docs/CAPABILITY.md`、`vendor/app/**`（JS 核心，25 套测试锁定）。
   **不拿截图与记忆当证据**。
3. **判"有"要能指到地方**：每个 ✅ 都给出 iOS 侧落点（文件或服务方法）；给不出落点的写 ✗ 或 ⧉ 并写明差在哪。

复算命令（都在 `ios-app/` 下）：

```bash
node tools/cmdsshadow.js            # 32 条命令帧与 vendor 逐字节一致 + 未纳入差分的 8 条清单
node tools/parseshadow.js           # 回包解析面
node tools/featuremap.js            # 1050 项创意台账 × 判定 × 代码标注
node tools/uicoverage.js            # 77 个目的地 / 缝覆盖率 / 换页漏斗
node tools/destmap.js               # 目的地枚举与台账对账
grep -rn "cmd12Echo" App/           # 例：本条命令有没有调用点 (判"建帧器有、界面没接"靠它)
```

---

## 1. 页面级对照（51 页，原包 `page-*` 组件全集）

判定记号：**✅ 已落 · ⧉ 等价物（形态不同、能力在） · ✗ 联网不算 · ⛔ 原版自己没做**

| 原版页 | 原版做什么 | iOS 落点 | 判定 |
|---|---|---|---|
| page-home / page-tabs | 首屏 + 主框架 | `DeviceHomeView` + 根视图四标签 | ✅ |
| page-devicelist | 设备列表 | `DeviceManageView`（信号格/分组/移入） | ✅ |
| page-devicetypelist | 设备类型选择 | `AddDeviceView`（型号表来自 `PidMap` 本地表；原版从 `getProductList` 云端拉） | ✅ |
| page-adddevice | 扫描 + 配网 | `AddDeviceView`（251/253/255/257/258/774） | ✅ |
| page-devicereset | 重置设备 = 取交换方式(23) → 换钥(05) | `LockService.pair` 七步链（23 → 05 → 08 PIN 池 → 41 写钥落库） | ✅ |
| page-deviceinfo | 设备信息 | `DeviceInfoView`（锁信息名片） | ✅ |
| page-modifydevicename | 改设备名 | `SettingsView` 改名（`DB.saveKeychain`） | ✅ |
| page-opendevice | 开锁 | `DeviceHomeView` / `UnlockGateView` / `UnlockDial` | ✅ |
| page-synctime | 同步时间(0E) | `SyncTimeView`（先读锁钟补偿再下发） | ✅ |
| page-setsafemode / page-safemodeintroduce | 安全模式 = 单/双验(20) | `SecurityLockConfigView` / `SafemodeIntroView` | ✅ |
| page-defend / page-defendhome | 一键布防(25) | `DefendView` | ✅ |
| page-tailgate | 防尾随 | `TailgateView`（锁命令面无此命令 ⇒ 本机落本地偏好 + 型号/固件门禁，与 `CAPABILITY.md` §5 同口径） | ✅ |
| page-addpwd / page-updatepwd / page-modifypwd / page-clearpwd | 密码增改删清 | `AddPwdView` / `CredentialStudio` / `CredentialsView`（0A/0B/清空） | ✅ |
| page-startaddfp | 录指纹(13/14) | `StartAddFpView` | ✅ |
| page-fpdetail / page-modifyfpname | 指纹详情/改名 | `CredentialsView` / `CredentialStudio`（15 删、本地台账命名） | ✅ |
| page-addmember / page-manage / page-detail / page-modifyname | 成员增改查 | `MembersView` / `MemberCenterView` / 成员 360 详情（本机成员是**纯本地台账**；原版成员存云端） | ✅ |
| page-otpopen / page-otpclose / page-otpgenerate | 临时密码开关(19)/生成 | `ZOTP` + `CredentialStudio`（离线本地自增 idx，同窗生成） | ✅ |
| page-message | 动态/消息 | `AlarmCenterView`（原版内容来自 `getDeviceMsg` 云端；本机 = 本机日志 + 告警流） | ✅ |
| page-my | 我的 | `MemberCenterView` | ✅ |
| page-lockmore | 门锁更多（设备名称/设备信息/清空密码/防尾随/一键布防/检查固件更新/协议测试/使用帮助/删除设备） | 前六项与"使用帮助/删除设备"都在；**协议测试**见 §5 | ✅（除协议测试） |
| page-checkfirmwareupdate | 检查固件更新 | `FirmwareView`（DFU 编排 + 本地 zip 导入 + 版本并排） | ✅（升级包来源改本机导入，云下载那半不算） |
| page-rominfo | 固件信息（手机时间/锁内时间/时差/电量/安全模式/固件版本/**Boot版本**/产品名称） | `DeviceInfoView` + `SyncTimeView` + `DiagReferenceView`；Boot/键盘版本**本轮补上** | ✅ |
| page-romlist | 固件列表（扫 ZK* + 信号强度 + **cmd12 回声探活**后进锁页） | `DeviceManageView`（已配对 RRSI 格）+ `AddDeviceView`（扫描列表）；**连通探测本轮补上** | ✅ |
| page-addgw / page-addgwsetwifi / page-gwstate / page-gwreset / page-gwresetexplain | 网关：配网(31)/状态(38)/重启(35)/重置引导 | `GatewayView`（`HardwareService.provisionGateway/readGatewayState/rebootGateway`） | ✅ |
| page-gwupgrade | 网关升级 | 原版这一页 `btnUpdate` 与 `getVersion` **都是空函数**（`main.js` 里字面 `l.prototype.btnUpdate=function(){}`）⇒ 规格里没有这条路径 | ⛔ |
| page-addkeychain / page-keychaindetail | 创建蓝牙钥匙 / 钥匙串详情 | `KeychainHWView`（43 状态 / 41 写钥删钥 / 44 查钥） | ✅ |
| page-testlockrom | 协议测试：把锁内日志倒出来进一个可复制文本框（pageSize 5，上限 100 条，含原始 JSON） | 等价物：记录页翻页取回（16）+ 诊断页长按任意行「查看原始报文」（完整帧 + 字段解析）。**不另做文本框**，理由见 §5 | ⧉ |
| page-login | 手机号 + 短信码登录 | —— | ✗ 联网 |
| page-userinfo | 个人信息（云端账号） | —— | ✗ 联网 |
| page-firstmodify / page-secondmodify | 更换绑定手机号（两步） | —— | ✗ 联网 |
| page-searchuser / page-addblekey | 给成员添加"手机钥匙"（云端 `retrieveDeviceMemberInfo` 取 ekeyList/pin） | —— | ✗ 联网（本机对应物是本地成员台账 + 钥匙串写入，见上） |
| page-delblekey | 删除成员手机钥匙（云端 `updateShareDevice`） | —— | ✗ 联网 |

**51 / 51 逐页有判定** —— 联网 7 页（login / userinfo / firstmodify / secondmodify / searchuser / addblekey / delblekey）、
原版空壳 1 页（gwupgrade）、等价物 1 页（testlockrom）、**其余 42 页已落**。
复算：`comm -3 <(ls /d/aapk/ui-replica/pages/ | sed 's/\.html$//' | sort) <(grep -o "page-[a-z]*" docs/PARITY-APK.md | sort -u)` 只该剩下字面量 `page-`。

---

## 2. 原生插件对照（`config.xml` 19 项）

| 插件 | 用途 | iOS 落点 | 判定 |
|---|---|---|---|
| `ZKurlcsPlugin` | BLE 锁通信（82 处调用） | `App/Services/BLEService.swift` + `LockService` + `ZKCmdBuilder` | ✅ |
| `URLCSDfuPlugin`（Nordic 12.x 移植） | `startDfu` + 进度 0-7 | `App/Services/DFUKit.swift`（分段/校验在视图层编排） | ✅ |
| `brightness` | **`setKeepScreenOn`** —— 用在"检查固件更新"与"添加指纹"两页 | 本轮补上：`ScreenCare.swift` 的 `keepingScreenAwake(_:)` 挂在 `FirmwareView`（`running`）与 `StartAddFpView`（`busy`） | ✅（本轮） |
| `clipboard` | 复制 | `ClipboardCare`（码值脱敏口径） | ✅ |
| `native-settings` | 打开系统设置 | `UIApplication.openSettingsURLString`（`LinkSenseKit.swift:54` / `DiagnosticsView.swift:69`） | ✅ |
| `appversion` | 应用版本 | 设置页 `CFBundleShortVersionString`（`SettingsView.swift:1333`）+ 诊断报告 | ✅ |
| `sqlite-storage` | 本地库 | `App/Core/Store.swift`（键值 + 家族表） | ✅ |
| `file` / `file-transfer` | 本机文件 / 下载 | 导出与备份走本机文件；**下载**不做（云停服） | ✅ / ✗ |
| `network-information` | 有无网络（原版用它拦"没网"） | 本机无网络依赖，网络状态不进任何判据 | ⛔ 不适用 |
| `permissions` | Android 运行时权限 | iOS 权限由系统在首次使用时询问（蓝牙提示见 `BLEService.readyMessage`） | ✅ 形态不同 |
| `keyboard` / `statusbar` / `splashscreen` | WebView 时代的外观补丁 | SwiftUI 原生由系统处理 | ⛔ 不适用 |
| `advanced-http` | HTTP 客户端（全部业务 API） | —— | ✗ 联网 |
| `app-update`（com.vaenow） | 应用自更新（OSS APK） | 不适用（App Store 渠道），更新说明页 `ChangelogView` 在 | ⛔ / ✅ 替代 |
| `URLCSPushPlugin` | 手机号绑定 + 常驻推送 | —— | ✗ 联网 |
| `WifiNamePlugin` | `getWifiInfo` → 预填 SSID（**只在网关配网页**用了一次，`main.js:619235`） | iOS 读当前 SSID 需要 `com.apple.developer.networking.wifi-info` 权限（Apple 按用途审批）；拿不到权限时 `fetchCurrent` 恒为 nil ⇒ 写一个恒失败的入口就是假功能。`GatewayView` 改为手动输入并已写明 2.4GHz | ✗ 平台权限所限（**不是漏做**） |

---

## 3. 命令面对照（32 条确证命令）

口径：全部 32 条在 `App/Core/ZKCmdBuilder.swift` 都有建帧器，且 `tools/cmdsshadow.js` 与 vendor 基线**整帧逐字节一致 32/32**。
但"有建帧器"不等于"界面能用到" —— 下面第三列是**调用点**（判据：`grep -rn "<建帧器名>" App/ | grep -v ZKCmdBuilder.swift`）。

| Cmd | 名称 | iOS 调用点 | 判定 |
|---|---|---|---|
| 01 | GETSESSIONTOKEN | `LockService.ensureToken` | ✅ |
| 02 | GETBLEMAC | 无调用点 —— **原版也不发**（`CAPABILITY.md` §1 已确证） | ⛔ 等价 |
| 03 | GETSTATUS | `getStatus`（明文/密文两支） | ✅ |
| 04 | OPEN | `unlock` | ✅ |
| 05 | EXSECURITYKEY | `pair` 第 3 步（换钥 + 回显比对） | ✅ |
| 08 | SYNCPINS | `pair` 内批量同步（≤20/批） | ✅ |
| 0A / 0B | SYNCPWD / 改期 | `pwdAdd/pwdModify/pwdDelete/pwdClear/pwdExpire` | ✅ |
| 0C / 0D | 冻结策略 / OTP 周期 | 无构造、无调用 —— 与原版一致（原版零构造零调用） | ⛔ 等价 |
| 0E | SYNCTIME | `syncTime` | ✅ |
| 12 | ECHO | **本轮接入**（`probeEcho` + 添加设备长按"连通探测"） | ✅（本轮） |
| 13 / 14 / 15 | 录指纹 / 确认 / 删指纹 | `fpStart/fpConfirm/fpDelete` | ✅ |
| 16 | GETLOG | `getLogs`（记录页翻页） | ✅ |
| 18 | SETSOUNDVOLUMN | `setSilent` | ✅ |
| 19 | OPENZOTP | `setZotp` | ✅ |
| 20 | SETVALIDATIONMODE | `setValidationMode`（安全模式页） | ✅ |
| 21 | SETBEACONKEY | `pair` 内写 bkey | ✅ |
| 22 | ENABLEDFU | `enableDfu`（FirmwareView） | ✅ |
| 23 | GETEXSECURITYKEYWAY | `pair` 第 1 步 | ✅ |
| 24 / 25 | 自动上锁 / 布防 | `setAutoLock` / `setDefence` | ✅ |
| 30 | GWGETDEVICENAME | 无调用点 —— 原版拿它是为了喂**云端**核对（`getDeviceName → checkDeviceBinding`），离线无用途；建帧器保留 | ⛔ 离线无用途 |
| 31 / 35 / 38 | 网关配网 / 重启 / 状态 | `provisionGateway` / `rebootGateway` / `readGatewayState` | ✅ |
| 32 | GWSETIOT | 构造器保留、**不下发**（云端档案，厂商云停服） | ⛔ 有意不发 |
| 41 / 43 / 44 | 写钥 / 钥匙串状态 / 查钥 | `writeDongleKey` / `deleteDongleKey` / `readDongleState` / `dongleKeys` | ✅ |

**唯一"建帧器有、界面零调用"的可做项就是 12 回声** —— 本轮已接。

---

## 4. 本轮补齐的三处（都是离线可做、原版有、本机缺）

1. **连通探测（cmd12 回声）** —— `LockService.probeEcho(deviceId:)`
   原版 `RomlistPage.echo`：扫描列表里对每台 ZK* 设备先发一次回声，`rc=0` 才进那把锁。
   接在 `AddDeviceView` 的发现列表**长按菜单**里（点行本身仍是开始配对，两件事不做成同形）。
   它的独特之处：**免令牌明文**，不需要 skey ⇒ **对还没配对的设备**也发得出去；而且不写本机台账
   （读 03 状态会落快照 + 电量采样 + 固件观测三处），探完即撤掉临时链路，且不写 `DB.lastDevice`。
2. **Boot 版本 / 键盘版本（03 状态 KLV#32 / KLV#33）** —— `DeviceInfoView`
   原版 `page-rominfo` 的「Boot版本」。本机解析器一直有 `verDFU/verKeyboard` 两个字段，但**从未有界面消费**。
   现在只在锁真报了（>0）才出这两行 —— 没报就不出，不拿 0 冒充版本号。
3. **长任务常亮** —— `ScreenCare.swift` 新增 `keepingScreenAwake(_:)`
   原版在"检查固件更新"与"添加指纹"两页调 `brightness.setKeepScreenOn(true/false)`。
   在 iOS 上这不是装饰：DFU 连续传输几分钟、录指纹要用户把手指按在锁上几十秒，
   屏幕一自动锁定系统就会**挂起本进程**，蓝牙链路当场断，而屏上还停在"正在传输"。
   只覆写 `isIdleTimerDisabled` 一个公开开关，只在这两页的任务进行中置位，离开或结束即恢复。

## 5. 明确**不补**的，以及理由

- **联网族（6 页 + 全部 API 业务）**：`login/getVerifycode/updateUserInfo/updateBindPhone/retrieveDeviceMemberInfo/updateDeviceMember/updateDeviceMemberLockKey/setDeviceSetting/getDeviceSetting/searchzkaccount/loginOut/updateShareDevice/retrieveDeviceInfo/checkDeviceBinding/addLock/removeDevice/renameDevice/getBLELockKey/getDeviceFirmwareProfile/addGateway/getDeviceMsg/getDeviceStatus/clearPwd/getProductList`。
  这不只是"没做"，是**用户已定案不做**：厂商云停服，做出来也连不上（`AGENTS.md` 已确立事实第 1 条）。
- **固件云下载**：原版 DFU 的 zip 来自 `getDeviceFirmwareProfile` 返回的 URL。本机改成**本机导入 Nordic zip**
  （原件就在仓里：`vendor/fixture/KX_V5.2.9_180503183402.zip`），协议与包格式一字不改。能离线的那半做完了。
- **WiFi 名称自动预填**：见 §2，iOS 权限所限；写一个恒失败的入口等于假功能（本仓纪律）。
- **协议测试那个可复制文本框**：原版把锁内日志连原始 JSON 一起倒进 `textarea`。
  本机**刻意不给这个出口** —— 完整帧含 skey/ekey/PIN 明文，本仓的判据是"可以看，不可以复制走、
  不写进任何报告/导出"（`DiagnosticsView` 的「查看原始报文」就是这条判据的落地）。能力在（翻页取回 + 逐行原始报文），
  只是收口方式不同 ⇒ 记 ⧉ 而不是 ✅。

## 5b. 锁通讯层差分审计（2026-10-17，真机 rc13 现场倒查）

现场：锁键盘重置（3 声）→ App 显示绿色可配网 → 点配对 → **rc=13（通讯过期）**，锁随即退出可配网态，重做重置后反复同样 rc13（信号 −50 dBm 内，不是距离问题）。
倒查方法：把原 APK 的**通讯代码全链**（JS 命令类 + Java 插件）与 iOS 侧逐字段对齐。

### 权威取证件

| 层 | 文件 | 作用 |
|---|---|---|
| JS 命令构造 | `apk_raw/assets/www/build/main.js`（命令类 `ht` 子类 + `kt` 0x88 包络类） | 决定每条命令的 KLV 布局、`needSSToken` 标志 |
| Java 帧/传输 | `jzzns22561_v2/sources/cn/zelkova/ZKurlcsPlugin/lockprotocol/*.java` | 决定**线上真字节**: 8B 头、令牌注入位置、分片、重试 |

### 结论 1（真机 rc13 的根因）：cmd 05 必须带会话令牌

原 APK 的 05 构造器 `Et` 逐字：

```js
l.call(this, Jn.ZKCCOMM_EXSECURITYKEY, !0, "0000")   // 第二实参 = needSSToken = true
```

Java 侧 `BleLockConnector.doExecute` 照此执行：`if (data.needSessionToken()) { doRefreshSsToken(); token = ssToken.getToken(); }`，
再由 `LockCommBase.getBytes(ssToken)` 把令牌作为 **KLV#0xEE 追加到帧尾**。
真机真序是 **23（免令牌）→ 01（取令牌）→ 05（带 KLV#00xEE）→ 08/21/03…**。

本机（与 `vendor/app/utils/kernel/cmds.js:cmd05Exchange` 的"免令牌明文"模型）一直把 05 裸发 ⇒ 锁回 **rc=13「通讯过期」**
（报的是*通讯会话*无效；命令时间不对才是 rc=3）⇒ 配网链在第 3/7 步断，而锁会就此退出可配网态。
**rc≠0 ⇒ 锁没有执行换钥（锁内 skey 未动），因此 rc13 是唯一可安全重试的时机。**

### 结论 2：`needSSToken` 全表（原 APK JS 实参，逐条 `l.call(this, Jn.*, !0/!1, "0000")`）

| 令牌=true | 令牌=false |
|---|---|
| 03 状态、04 开锁、**05 换钥**、08 PIN 池、0A/0B 密码、0E 校时、13/14/15 指纹、16 日志、18 音量、19 ZOTP、20 验证模式、21 bkey、22 DFU、24 自动锁、25 布防 | 12 回声、23 交换方式、钥匙串 41/43/44、网关 30/31/32/35/38 |

iOS 侧现状：除 05 外全部一致；05 已改为 `needToken: true`（`LockService.pair` 步骤 3/7）并追加"rc13 重开会话重试一次"。

### 结论 3：已核对**一致**的部分（不重复改）

- 帧头：Java `LockCommBase.getBytes` = `87 | 00 | len(u16 LE) | cmd | 00 00 00 | KLV`（8B 头）—— iOS `buildFrame(header: 8)` 一致。
  JS 里那套 10B 头（`ssToken` 进头、`ZKCCOMM_SESSIONTOKENKEY="F0"`）在混合架构里是**死代码**（H5 只把 `getParams()` JSON 交给 Java），不必跟。
- 0x88 包络：`88 | 00 | MAC 反转 | TrackId LE4 | ValidFrom LE4 | ValidTo LE4 | Cmd | body`，命令用 TrackId=0 —— 一致。
  （`ValidFrom/ValidTo` 默认串 APK 用**本地** 2010/2118，本机用 0 与 UTC-2118；两者都包住"现在"，锁的有效期判据不受影响 ⇒ 记差异不改。）
- 08 body `addCount(1B)+delCount(1B)+addPins+delPins`、首批 `delPins=[0xFFFFFFFF]` —— 一致。
- 21 body `skeyLen(1B)+bkey` —— 一致；且 `KeyGen.genBkey()` 已实现 APK 的"相邻字节差 ≤2 就 +6"整形，与原版逐行相同。
- 01 响应解析（#01 安全类型 / #02 令牌 / #03 有效期秒）；令牌在每个需令牌命令前**无条件刷新**（Java doExecute 亦无条件刷新）—— 一致。
- 传输：20 字节分片、每片等 ACK、连接就绪 = CCCD 写完成 —— iOS `BLEService` 一致（还额外做了 30 ms 片间隔与写槽串行）。

### 结论 4：仍存在的**非阻塞**差异（记录在案）

- PIN 分批：APK 每批 **20**（`o>20?20:o`），iOS 用 16。64 个 PIN 都是 4 批，语义等价 ⇒ 不改（改了要重跑金标，收益为零）。
- APK 的 03 有一个变体（KLV#02=`"31"` 读 ROM 版本）；本机只发 KLV#02 空（全量状态，固件版本取自状态 KLV#0E）。
- APK 在进入配网页后有 1 s 静默再发 23（`setTimeout(...,1e3)`）；iOS 由 `connect()` 等 CCCD 就绪，未再加固定静默。

## 6. 边界（这份表**不**证明什么）

- 不证明真机上每条命令都会被锁接受：整帧比对是**字节级**证据，锁端固件认不认要真锁在场（`cmdsshadow` 自己就这么写）。
- 不证明 8 条未纳入差分的向量（`withToken/buildEkeyShare/cmd30/cmd31×2/cmd32/cmd35/cmd38`）在**Swift 侧**也对 ——
  差分工具只复刻了 32 条；剩下 8 条的证据目前只在 vendor 基线夹具里。
- 不替代 XCTest：云 runner 自 2026-09 起没有模拟器设备，仓里那批测试**从未执行过**（`ios.yml` 头注已写明），
  编译闸门只保证它们不会腐坏。真机行为一律见 `docs/VERIFY-CHECKLIST.md`。
