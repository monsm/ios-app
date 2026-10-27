# EVIDENCE-ANDROID — Android 现状取证（现有 App + 厂商 APK 基线）


> ⚠ **本档是历史台账，不是当前代码的说明书。**
> 里面的 `文件:行号` 指针记录的是**写档当时**的位置；后续精简/重构后部分文件已删或行号已移，
> 那些失效指针是台账的**正常内容**（它记的就是"某批删了什么"），不是错误。
> 想知道某个功能现在还在不在，请看 `docs/feature-web/features.json`（那份由工具从 inventory 重算）。

> 取证人：ev-android（task-2）· 取证日：2026-10-18 · 只读取证，未修改任何源码/配置/测试
> 证据口径：所有事实均给 `文件:行号`。路径相对工作区 `D:\aapk`。文本文件行号 = 物理行号（.kt/.xml/.kts/.swift/.js 均为多行文本）。
> **一条勘误先说在前面**：任务描述里的 `D:\aapk\jzzns22561_v2\resources` 实测为 **0 文件 / 0 目录**（见 §3.1 证据），因此厂商资源证据全部取自 `jzzns22561_out/resources`。

---

## 0. 结论先行（10 条）

1. **现有 Android 工程是「极简单屏 Compose App」，不是「厂商 App 的安卓移植」**：833 行的 MainActivity 里 1 个 Activity、1 个 Composable 根、无导航库；开锁协议只覆盖 cmd 01/03/04 三条。
2. **iOS 侧的完整能力面（cmd 13/14/15/16/0E/0A/0B/18/19/20/21/22/24/25/41/43/44/网关 30-38）在 Android 侧 0 实现**——iOS 有 31 个命令构造器，Android 只有 3 个帧构造方法。
3. **两端唯一"设计好"的契约是二维码 `KFA1:{v,n,m,p,e}`**：iOS 生成（`AndroidPair.payload`）、Android 解析（`LockStore.parseQr`），字段级对齐已验证。
4. **协议字节面是同源的**：NUS 服务/特征 UUID、KLV 结构、令牌 KLV#0xEE、广播厂商段 0x98ED、rc 表 0..27 在两端逐项一致。
5. **Android 有独立于 iOS 的本地存储命名空间**：`kf_key_v1`（SharedPreferences）里只存 `lock` / `proximity` 两个键；iOS 的 `kf_*` 键在本仓有 **336 个不同键名**，两端**互不识别**。
6. **备份格式两端零共享**：iOS 是 `BackupEnvelope v1 / aes-128-cbc+hmac-sha256` 信封 + 坚果云 WebDAV；Android 侧无任何备份/恢复代码。
7. **厂商 APK 基线 = Cordova + Ionic 3.9.2 + Angular 5.2.9 的 H5 单页应用**，Java 层只是壳（BLE 插件 + 推送 + DFU）；**不是 Compose、不是 Flutter、不是 React Native**（判定依据与反证见 §3.2）。
8. **厂商 App 的"页面"是 Ionic 路由页，不是 Android Activity**：AndroidManifest 里真正的业务 Activity 只有 4 个（Main/2 个推送落地页/2 个 DFU 页），资源 `res/layout` 只有 1 个文件——**18 页 UI 全在 H5**。
9. **iOS/A 端已有三道"防漂移"闸门覆盖 Kotlin**：`tools/kotlinshadow.js`（字节面影子对拍，含 MainActivity 正则结构检查）、`tools/kotlinlocal.js`（本地真编译 4 个非 UI 文件）、CI `android` job（gradle assembleDebug + 编译期戳核对）——**UI 层（MainActivity/SignalArrow）本地无编译闸门，只有 CI**。
10. **第三方功能对账来源是小程序（22 页）**：`miniprogram-app` 的页面清单可作为"功能全集"的第三方参照，但不含 BLE 开锁链路（其页面里没有开锁台）。

---

## 1. 取证方法与覆盖度

| 项 | 做法 | 覆盖 |
|---|---|---|
| Android 工程 | 全量读 11 个文件（6 个 .kt + 3 个 .xml + 2 个 .kts + gradle.properties），Kotlin 共 2124 行 | 100%（工程内仅 19 个受版本管理文件） |
| 厂商 APK | 只读清单：`sources` 目录树、`*Activity*.java` glob、解码后 Manifest、`res/layout`+`res/values`、`assets/www` 树、`build/main.js` 中文串抽取 | 结构级（未通读 1810 个 Java 文件） |
| 资源 | `jzzns22561_out/resources`（2150 文件）：Manifest / layout / values / assets | 关键面 |
| 小程序 | `app.json` + 22 个页面 json 标题 + 2 个关键 wxml | 清单级 |
| 对账基线 | `REVERSE_REPORT.md`（既有权威产物，复用不重做）+ iOS 侧 grep 锚点 | 交叉验证 |

**未做的事（诚实边界）**：没有通读厂商 Java 反编译源码；没有反编译 `main.js`（压缩单行，仅做中文串抽取与结构判定）；没有对 APK 做全量字符串扫描（"无 Flutter/RN"是**基于 assets 树**的判定，非字节级排除）。

---

## 2. 现有 Android 工程（`ios-app/android-app/`）

### 2.1 结论

- 单模块 Gradle 工程（`:app`），Kotlin + **Jetpack Compose**（无 XML 布局、无 Fragment、无 Navigation 组件）。
- `compileSdk 35 / minSdk 33 / targetSdk 34`，Java 17，Compose BOM `2024.10.01`。
- 一个 Activity（`MainActivity`）承载全部界面；**导航 = 状态变量 + AnimatedVisibility**，没有 NavHost。
- 主题只有"窗口底色 + 状态栏"（避免启动白闪），全部配色是 Compose 里的 8 个 `internal val`。

### 2.2 构建与 SDK

| 事实 | 证据 |
|---|---|
| 根工程名 `KfKey`，只含 `:app` | `ios-app/android-app/settings.gradle.kts:15-16` |
| AGP `8.7.3`；Kotlin `2.0.21`；Compose 编译器插件 `2.0.21` | `ios-app/android-app/build.gradle.kts:3-5` |
| `compileSdk = 35` | `ios-app/android-app/app/build.gradle.kts:54` |
| `minSdk = 33`（注释：用户口径"最低 Android 13"） | `app/build.gradle.kts:58-59` |
| `targetSdk = 34`（**刻意停在 34**：35 强制 edge-to-edge 而本界面未做 inset 适配） | `app/build.gradle.kts:60` |
| `namespace = applicationId = com.aapk.kfkey` | `app/build.gradle.kts:52,57` |
| `versionCode` = 距 2026-01-01 东八区的秒数（截断前判溢出） | `app/build.gradle.kts:63-68` |
| `versionName = "1.0.<yyyyMMdd.HHmmss>"`，**与 iOS CFBundleVersion 同一个串** | `app/build.gradle.kts:19,43-44,71` |
| 编译期打印 `KfBuildStamp ...` 供 CI 核对 | `app/build.gradle.kts:49` |
| 固定签名 `keystore/kfkey.p12`（PKCS12，随仓库走，保证原地覆盖安装） | `app/build.gradle.kts:74-86` |
| debug/release 同一签名；release `isMinifyEnabled = false` | `app/build.gradle.kts:88-97` |
| Java 17 / jvmTarget 17 | `app/build.gradle.kts:99-105` |
| `buildFeatures { compose = true }` | `app/build.gradle.kts:106-108` |
| AndroidX 开、非传递 R 类 | `ios-app/android-app/gradle.properties:2,4` |

### 2.3 依赖清单（全部 9 条）

| 依赖 | 版本 | 证据 |
|---|---|---|
| `androidx.compose:compose-bom` | `2024.10.01` | `app/build.gradle.kts:115` |
| compose ui / ui-graphics / ui-tooling-preview | BOM 管理 | `app/build.gradle.kts:116-118` |
| `androidx.compose.material3:material3` | BOM 管理 | `app/build.gradle.kts:119` |
| `androidx.activity:activity-compose` | `1.9.3` | `app/build.gradle.kts:120` |
| `androidx.lifecycle:lifecycle-runtime-compose` | `2.8.7` | `app/build.gradle.kts:121` |
| `kotlinx-coroutines-android` | `1.9.0` | `app/build.gradle.kts:122` |
| `com.journeyapps:zxing-android-embedded`（扫码，不依赖 GMS） | `4.3.0` | `app/build.gradle.kts:123-124` |
| `androidx.compose.ui:ui-tooling` | debugImplementation | `app/build.gradle.kts:125` |

**注意**：**没有** Navigation、没有 DataStore、没有 Room/SQLite、没有 WorkManager、没有 Accompanist。所有持久化走 SharedPreferences（§2.6）。

### 2.4 权限与 Manifest

| 事实 | 证据 |
|---|---|
| `BLUETOOTH_SCAN`（`neverForLocation`，注释：只认锁不做位置推断） | `app/src/main/AndroidManifest.xml:5-7` |
| `BLUETOOTH_CONNECT` | `AndroidManifest.xml:8` |
| `CAMERA`（扫码） | `AndroidManifest.xml:9` |
| `uses-feature bluetooth_le required=true`；`camera required=false` | `AndroidManifest.xml:11-12` |
| `allowBackup="false"`（**与 iOS 的备份体系形成反差**） | `AndroidManifest.xml:15` |
| 主题 `@style/Theme.KfKey`；图标 `@mipmap/ic_launcher`；label `@string/app_name` | `AndroidManifest.xml:16-19` |
| **唯一 Activity**：`.MainActivity`，exported，`screenOrientation="portrait"` | `AndroidManifest.xml:21-30` |
| 运行时申请：SCAN + CONNECT +（SDK≥33）CAMERA | `MainActivity.kt:149-154` |

**缺口**：Manifest 里**没有** `POST_NOTIFICATIONS`、没有前台服务、没有 `FOREGROUND_SERVICE_CONNECTED_DEVICE`——即当前 Android 端**不具备后台常驻能力**（与 iOS 侧的后台/通知体系不对等；iOS 侧对齐项见 §5）。

### 2.5 主题与配色

| 名称 | 值 | 证据 |
|---|---|---|
| 窗口/状态栏/导航栏底色 | `#0A0C10` | `app/src/main/res/values/themes.xml:3-8` |
| 启动图标背景色 `ic_bg` | `#0A0C10` | `app/src/main/res/values/colors.xml:2` |
| 自适应图标（前景 = 钥匙孔矢量） | — | `app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml:3-4`、`res/drawable/ic_fg.xml:8-12`（`#E8B45C`） |
| App 名 | `离线锁钥匙` | `app/src/main/res/values/strings.xml:2` |
| `BgTop` / `BgBottom` / `Surface` / `Ink` / `InkSub` | `#0A0C10` / `#141A22` / `#161C24` / `#F3F6FA` / `#8B96A8` | `app/src/main/java/com/aapk/kfkey/Theme.kt:10-14` |
| `Accent`（暖金）/ `Ok` / `Bad` | `#E8B45C` / `#6EE7A8` / `#F87171` | `Theme.kt:15-17` |
| 主题抽出的原因 | `SignalArrow.kt` 需要同一套色（顶层 private 不可跨文件） | `Theme.kt:5-9` |

**设计语言事实**：暗色 + 暖金强调（注释明说"钥匙/黄铜的联想，不是科技蓝紫"，`Theme.kt:8`）；与小程序配色（`#0E1B34/#3D8BFF` 蓝系，`miniprogram-app/app.json:27-30`）**是两套不同语言**。

### 2.6 屏幕结构与导航

| 事实 | 证据 |
|---|---|
| `MainActivity : ComponentActivity`；`setContent { KfApp(unlocker) }`；`BleUnlocker` 由 `by lazy` 持有 | `MainActivity.kt:81-90` |
| `onDestroy` 起线程 `runBlocking { release() }` 拆链路 | `MainActivity.kt:92-103` |
| 全部 UI 状态 = 20+ 个 `remember { mutableStateOf(...) }`（lock/status/busy/rssi/proximity/azimuth/pitch/roll/showSettings/airTagDismissed…） | `MainActivity.kt:113-141` |
| **无 NavHost / 无路由表**：二级"门锁设置"用 `showSettings` 布尔 + `AnimatedVisibility` sheet | `MainActivity.kt:383-424` |
| 根布局：纵向渐变背景 + Column（padding 24/28dp） | `MainActivity.kt:306-316` |
| 三态：未绑定 = `EmptyState`（扫码引导） | `MainActivity.kt:319-320,574-601` |
| 已绑定 = Header(名称+MAC) + SignalArrow(可选) + `UnlockDial`（300dp 圆盘 + 232dp 可点圆） | `MainActivity.kt:317,325-337,483-504,507-572` |
| 状态行三档配色：Bad / Ok（含"成功"/"已开锁"）/ InkSub | `MainActivity.kt:339-349` |
| 第二提示行：未开靠近→" "；找锁→"正在寻找门锁…"；已武装→"信号已满…马上自动开" | `MainActivity.kt:351-360` |
| 调试 trace 行（等宽字体小字） | `MainActivity.kt:361-370` |
| 右下齿轮按钮（Canvas 画的 8 齿）→ 打开设置 sheet | `MainActivity.kt:377-379,680-709` |
| 设置 sheet = `ProximityCard`（靠近开关 Switch + 重新扫码 + 解绑 + 完成） | `MainActivity.kt:603-677` |
| 换锁/覆盖凭证二次确认 `AlertDialog` | `MainActivity.kt:427-454` |
| **AirTag 式找锁全屏层**（绿底、大字距离/方向、✕/🔊 按钮、蜂鸣） | `MainActivity.kt:459-480,733-794,796-808,811-833` |
| 状态音：`ToneGenerator`，按 fill 分 4 档（240/420/700/1100ms） | `MainActivity.kt:811-833` |
| 成功震动 28ms | `MainActivity.kt:724-730` |
| 生命周期：ON_RESUME 复位 fired/airTag；ON_PAUSE 置 `foreground=false`、`armed=false`、`release()` | `MainActivity.kt:202-225` |

**屏幕清单（结论）**：Android 端 **实际只有 2 个"屏" + 3 个覆盖层**——
① 未绑定空态；② 已绑定开锁台；③ 设置 sheet；④ AirTag 找锁层；⑤ 换锁确认弹窗。

### 2.7 与 iOS 共享的协议边界（Android 侧实现层）

| 事实 | 证据 |
|---|---|
| 文件规模：MainActivity 833 / BleUnlocker 683 / KfProtocol 231 / SignalArrow 220 / LockStore 88 / AutoOpenKit 52 / Theme 17 行 | 逐文件读取所得（`wc -l` 等价） |
| NUS 服务/写/通知 UUID | `KfProtocol.kt:11-13`（与 `ios-app/App/Services/BLEService.swift:13` 同串） |
| 帧头 `87 00 len(LE16) cmd 000000 + KLV` | `KfProtocol.kt:36-40` |
| 令牌注入 KLV#0xEE + 8B/10B 头型自适应（`header10`/`bodyStart`） | `KfProtocol.kt:52-68` |
| 响应解析：按 version 选择 KLV 起点顺序（`0x01 → 8,7,10`；否则 `8,10,7`） | `KfProtocol.kt:77-92` |
| KLV 解析（key 1B + len 1B + value） | `KfProtocol.kt:94-107` |
| rc 提取 = KLV#0x03 | `KfProtocol.kt:139` |
| 结果码表 0..27（中文名） | `KfProtocol.kt:142-150` |
| **Android 独有**：rc 用户提示 `RC_HINT`（1/3/5/6/9/11/13/21/25/27） | `KfProtocol.kt:153-167` |
| 开锁帧 `unlockFrame`：cmd 04 + KLV#01="0"*32 + KLV#02=ekey | `KfProtocol.kt:180-183` |
| `tokenFrame()`=cmd01、`statusFrame()`=cmd03（均无载荷） | `KfProtocol.kt:185,192` |
| 广播解析：厂商段首字节 `fc & 0x0C == 0x0C`；pid = 字节 2-3 LE；MAC = 字节 4..9 逆序 | `KfProtocol.kt:216-227` |
| MAC 归一化（去冒号/横线、小写） | `KfProtocol.kt:230` |
| 扫描→连接→发现服务→CCCD→requestMtu(256)；断连由 `Session.onLinkDown` 统一complete | `BleUnlocker.kt:386-448,94-100` |
| 开锁主流程：热链路复用（60s）→ scanForLock(3000ms) → buildLink → **身份复核** → runUnlock | `BleUnlocker.kt:131-212,221-227` |
| 分片写 **20 字节**（注释：与 iOS/Java 同一分片大小），每片等 write ACK（4s） | `BleUnlocker.kt:587-609`（分片见 :595） |
| 会话过期（rc 3/13）自动重取令牌重发一次（`for attempt in 1..2`） | `BleUnlocker.kt:330-381` |
| 身份复核：发 cmd03 读 KLV#0x34 pid，不等则拒开 | `BleUnlocker.kt:453-478` |
| 广播厂商段兜底：scanRecord 里找不到时按 `0x98ED` companyId 二次切分 | `BleUnlocker.kt:651-669` |

### 2.8 存储与配对（Android 侧）

| 事实 | 证据 |
|---|---|
| SharedPreferences 文件名 `kf_key_v1`；键 `lock` / `proximity` | `LockStore.kt:17-19` |
| `lock` 内容是紧凑 JSON `{n,m,p,e}` | `LockStore.kt:21-40` |
| 载入校验：mac 长度 12 且 ekey 非空，否则视为无绑定 | `LockStore.kt:31` |
| 解绑 = 移除 `lock` 键（**不动 proximity**） | `LockStore.kt:54-56` |
| 二维码前缀 `KFA1:`；要求 `v==1`、mac 12 位 hex、ekey 16..510 且偶数长度、名称截断 40 字 | `LockStore.kt:62-87` |

---

## 3. 厂商 APK 基线（`jzzns22561.apk`）

### 3.1 结论 + 一条勘误

- **包名 `cn.justree.jingzao`，versionName `1.3.2`，versionCode `903191`；minSdk 19 / targetSdk 26。**
- **UI 框架 = Cordova + Ionic 3.9.2 + Angular 5.2.9 的 H5 单页应用**，Java 层是薄壳。**不是 Compose / Flutter / RN**。
- **勘误**：`jzzns22561_v2\resources` 实测 **0 文件**（下面有据），资源证据改用 `jzzns22561_out\resources`。

| 事实 | 证据 |
|---|---|
| `jzzns22561_v2\sources` 文件数 = 1810 | 目录递归计数 |
| **`jzzns22561_v2\resources` = 0 文件、0 目录** | 目录递归计数（任务描述写"resources 资源"与此不符） |
| `jzzns22561_v2\sources` 顶层包：`android anet anetwork cn com io okhttp3 okio org` | 目录列表 |
| 厂商自有包：`cn\justree\{jingzao,urlcs,urlcspushPlugin,wifinamePlugin}`、`cn\zelkova\ZKurlcsPlugin\lockprotocol` | 目录树 |
| 完整解码资源在 `jzzns22561_out\resources`（2150 文件）+ `jzzns22561_out\sources` | 目录计数 |
| 未解码原件在 `apk_raw\`（含二进制 `AndroidManifest.xml`、`classes.dex` 3.8MB） | `apk_raw` 目录列表 |

### 3.2 UI 框架判定（依据 + 反证）

| 判定 | 证据 |
|---|---|
| Cordova 壳：`assets/www/index.html` 加载 `cordova.js` → `build/polyfills.js` → `vendor.js` → `main.js`，根组件 `<ion-app>` | `jzzns22561_out/resources/assets/www/index.html:22,39,42-48` |
| Ionic 3.9.2 + Angular 5.2.9（版本在 HTML 内联注入，非猜测） | `index.html:4-6` |
| 19 个 Cordova 插件（含 `cn.zelkova.ZKurlcsPlugin`、`com.plugin.urlcsDfuPlugin`、`cordova-sqlite-storage` 等） | `assets/www/plugins/` 目录清单（19 个子目录） |
| 业务代码在 H5：`build/main.js` 677,556 B，`vendor.js` 733,203 B（含 CryptoJS），`main.css` 653,476 B | 文件长度 |
| **反证（无 Flutter）**：`assets` 下无 `flutter_assets`、无 `libflutter.so` 迹象 | `assets` 树（仅 pushresources / tae_sdk_plugins / www） |
| **反证（无 RN）**：无 `index.android.bundle`，HTML 用的是 webpack 产物 `build/*.js` | `assets/www` 树 + `main.js:1`（`webpackJsonp(...)`） |

### 3.3 身份与 Manifest（解码后）

| 事实 | 证据 |
|---|---|
| `versionCode="903191"` `versionName="1.3.2"` | `jzzns22561_out/resources/AndroidManifest.xml:3-4` |
| `package="cn.justree.jingzao"` | 同上 `:6` |
| `minSdkVersion=19` / `targetSdkVersion=26` | 同上 `:9-11` |
| Application = `cn.justree.jingzao.MyApplication` | 同上 `:52` |
| Alibaba 推送 appkey/appsecret 明文内嵌 | 同上 `:56-61` |
| 权限 20+：INTERNET / REQUEST_INSTALL_PACKAGES / 定位 / BLUETOOTH(+ADMIN) / 存储 / READ_PHONE_STATE / GET_TASKS / GET_ACCOUNTS / RECEIVE_BOOT_COMPLETED / WRITE_SETTINGS 等 | 同上 `:19-39` |
| 自定义权限 MIPUSH_RECEIVE / C2D_MESSAGE | 同上 `:40-48` |
| 启动 Activity = `cn.justree.jingzao.MainActivity`（`Theme.DeviceDefault.NoActionBar`，singleTop） | 同上 `:62-73` |

### 3.4 Activity 清单（Android 侧真实页面）

| Activity | 性质 | 证据 |
|---|---|---|
| `cn.justree.jingzao.MainActivity` | CordovaActivity，加载 index.html，**唯一业务入口** | Manifest:65；`REVERSE_REPORT.md:34` |
| `cn.justree.urlcspushPlugin.PopupPushActivity` | 推送弹窗落地页 | Manifest:83-85 |
| `cn.justree.urlcspushPlugin.SecondActivity` | 推送二级落地页 | Manifest:86-88 |
| `com.plugin.urlcsDfuPlugin.NotificationActivity` | DFU 通知页（portrait） | Manifest:92-95 |
| `com.plugin.urlcsDfuPlugin.DfuActivity` | DFU 进度页（portrait） | Manifest:96-99 |
| 另：`com.plugin.urlcsDfuPlugin.DfuService`（service） | 固件升级服务 | Manifest:89-91 |

> 说明：`glob *Activity*.java` 共 34 个命中，其中绝大多数是 `android.support.v4`、华为/淘宝/阿里推送 SDK 的**第三方** Activity；厂商自有的只有上表 + `cn.justree.urlcs.MainActivity`（旧包名遗留壳，`REVERSE_REPORT.md:36`）。

### 3.5 厂商 App 的信息架构（H5 路由页）

| 事实 | 证据 |
|---|---|
| H5 是"真正的应用"，Java 层只做 Cordova 桥 + 推送 + BLE + DFU | `REVERSE_REPORT.md:20-30` |
| 导航根：无 token → 登录页（手机号 + 短信码 + 60s 倒计时 + 定位权限门）；有 token → 主框架 | `REVERSE_REPORT.md:94` |
| **~42 个页面**（从 `ionViewDidLoad` 日志提取）：Devicelist / Devicetypelist / Adddevice / Devicereset / Testlockrom / Opendevice / Detail / Deviceinfo / Modifydevicename / Modifyname / Synctime / Setsafemode / Safemodeintroduce / Defend / Defendhome / Addpwd / Updatepwd / Clearpwd / Startaddfp / Modifyfpname / Fpdetail / Addmember / Searchuser / Manage / Delblekey / Addkeychain / Keychaindetail / Otpopen / Otpgenerate / Rominfo / Romlist / Checkfirmwareupdate / Addgw / Addgwsetwifi / Gwstate / Gwreset / Gwresetexplain / Gwupgrade / Message / My / Lockmore / Tailgate | `REVERSE_REPORT.md:96` |
| 设备型号 PID：K1=8097 / KX=8098 / V1=7857 / V1_Pro=7858 / JZ=7873 / GW=12193 / GW2=12194 / GW_commercial=12209 / Z3=7891 / Z3NFC=7892 / Z3AL=7893 / ZKBBV1=16289 | `REVERSE_REPORT.md:102` |
| 本地存储键（H5 侧）：userData / deviceData / memberData / bindAccount / fpkey / ekeyinfo / phone / wifiName / wifiPassword | `REVERSE_REPORT.md:106` |
| 中文 UI 串：`main.js` 内 **555 个不同中文串**（Top：知道了 96、确定 37、取消 29、布防 14、撤防 12、智能锁 10、榉树智能网关 10…） | `assets/www/build/main.js`（**单行压缩文件，无行号**，按正则抽取统计） |
| 开锁页 UI 串可见："点击开锁"、"正在开锁"、"手机钥匙"、"添加手机钥匙"、"请将手机靠近门锁" | 同上抽取结果 |

**信息架构结论（层次）**：设备列表 → 设备详情（开锁/记录/设置）→ 凭证域（密码/指纹/手机钥匙/OTP/钥匙串）→ 网关域（添加/配网/状态/复位/升级）→ 成员与分享 → 消息 → 我的。**这些域在现有 Android 端一个都没有。**

---

## 4. 反编译资源（`jzzns22561_out/resources`）

### 4.1 结论

- **`res/layout` 只有 1 个 XML**（`appupdate_progress.xml`）——再次证明"页面不在 Android 侧"。
- **`res/values/strings.xml` 只有 47 行、且全是英文 + DFU/自更新文案**，App 名 `京造智能锁`；**没有一条业务中文串**（业务串全在 `main.js`）。
- 真正的"资源"是 `assets/www`：191 张 UI 图 + 6 个构建产物 + 19 个插件目录。

### 4.2 证据表

| 事实 | 证据 |
|---|---|
| `res/layout/` = 1 个文件（427 B） | `jzzns22561_out/resources/res/layout` 清单 |
| `res/values/` = `public.xml`(3846B) + `strings.xml`(3109B) | `res/values` 清单 |
| `strings.xml` 共 47 行；`app_name = 京造智能锁` | `res/values/strings.xml:4` |
| 其余串为 DFU（`dfu_status_*`）与自更新（`update_*`、`download_complete_*`）——**第三方/壳文案** | `res/values/strings.xml:5-46` |
| 本地化目录 11 个（bn/de/en/es/fr/it/ko/pl/pt/ru/zh），每语言 14 条，均为自更新 UI | `REVERSE_REPORT.md:249`；`res/values-*` 目录清单 |
| `assets/www/assets/pic/` 分 7 个型号族目录：`common gw gwjz jz kx v1 v1_pro`（部分含 `defend`） | 目录树 |
| 关键图标名反推功能：`icon_kaojinmensuo`(靠近门锁) `icon_mensuo` `icon_membermanage_*` `icon_lockstatus_open/close` `icon_jingshi`(警示) `fp_default`(指纹) | `assets/www/assets/pic/common/` 文件清单 |
| `assets/www/build/`：`main.js` 677,556 / `vendor.js` 733,203 / `main.css` 653,476 / `polyfills.js` 97,180 / `sw-toolbox.js` 15,793 B | 文件长度 |

> **对任务描述第 3 条的修正**：「strings.xml 里的中文串能反推页面名」在本 APK 上**不成立**——中文业务串不在 `strings.xml`，而在 `main.js`（§3.5）。页面名的权威来源是 `REVERSE_REPORT.md:96`。

---

## 5. 小程序参考（`miniprogram-app`）——功能对账第三方来源

### 5.1 结论

小程序是**离线的第二实现**，共 **22 页 + 4 个自定义 Tab**，覆盖"设备/凭证/记录/设置"四大域，可作为**功能全集清单**。

**开锁台不是一个独立路由页，而是首页内的 `unlock-card`**（`devicelist.wxml:57-72`：`clickOpen` + 5 态资源 nor/shine/spin/suc/fail，另有 gray）——所以"22 页"里数不到开锁页，但开锁交互确实存在，可作为**开锁台交互的对账来源**。

### 5.2 页面清单（22 页，标题取自各页 json）

| # | 路径 | 标题 | 证据（`miniprogram-app/pages/<p>/<p>.json:2`） |
|---|---|---|---|
| 1 | devicelist | 智能锁 | `pages/devicelist/devicelist.json:2` |
| 2 | credentials | 凭证管理 | `pages/credentials/credentials.json:2` |
| 3 | records | 记录 | `pages/records/records.json:2` |
| 4 | settings | 设置 | `pages/settings/settings.json:2` |
| 5 | addpwd | 添加密码 | `pages/addpwd/addpwd.json:2` |
| 6 | startaddfp | 指纹录入 | `pages/startaddfp/startaddfp.json:2` |
| 7 | backup | 钥匙串备份 | `pages/backup/backup.json:2` |
| 8 | adddevice | 扫描配网 | `pages/adddevice/adddevice.json:2` |
| 9 | devicereset | 配网流程 | `pages/devicereset/devicereset.json:2` |
| 10 | safemodeintroduce | 安全模式说明 | `pages/safemodeintroduce/…json:2` |
| 11 | deviceinfo | 设备信息 | `pages/deviceinfo/deviceinfo.json:2` |
| 12 | testlockrom | 门锁记录 | `pages/testlockrom/testlockrom.json:2` |
| 13 | tracelog | LOCK 日志恢复 | `pages/tracelog/tracelog.json:2` |
| 14 | devstorage | 本地存储自检 | `pages/devstorage/devstorage.json:2` |
| 15 | mydata | 我的数据 | `pages/mydata/mydata.json:2` |
| 16 | passcode | 密码保护 | `pages/passcode/passcode.json:2` |
| 17 | members | 成员档案 | `pages/members/members.json:2` |
| 18 | keychain | 蓝牙钥匙串 | `pages/keychain/keychain.json:2` |
| 19 | addgw | 添加网关 | `pages/addgw/addgw.json:2` |
| 20 | gwstate | 网关状态 | `pages/gwstate/gwstate.json:2` |
| 21 | checkfirmwareupdate | 检查固件更新 | `pages/checkfirmwareupdate/…json:2` |
| 22 | messages | 动态 | `pages/messages/messages.json:2` |

| 结构事实 | 证据 |
|---|---|
| 页面注册顺序（22 条） | `miniprogram-app/app.json:2-25` |
| 自定义 TabBar：设备 / 凭证 / 记录 / 设置 | `app.json:26-37` |
| 配色：导航 `#0E1B34`、选中 `#3D8BFF`、未选 `#8CA3CE`、背景 `#0A1428` | `app.json:28-30,38-43` |
| 首页结构：`glass-nav` + 蓝牙未开警示 + 空态（"还没有门锁" / "绑定新门锁" / "从备份恢复"）+ 设备切换 chip 条 + "设备头等舱"（电量、连接 pill、验证模式、开门方式数、时间未校准警示） | `pages/devicelist/devicelist.wxml:3,7,10-18,22-55` |
| 凭证页结构：锁内存量行 + 数据源标签 `<srctag src="local">` + "未读到锁内状态…不代表锁上全部凭证" 的诚实提示 | `pages/credentials/credentials.wxml:14-23,30-38` |
| **开锁台**（首页内）：`unlock-stage` + 环形态 `ring-ok/ring-fail` + 5 态图（nor/shine/spin/suc/fail，双主题） | `pages/devicelist/devicelist.wxml:57-67` |
| 开锁台文案分档：已连接→"点击锁体执行开锁（双验模式需继续指纹/密码）"；未连接→"点击锁体执行开锁 · 开启蓝牙并保持靠近门锁" | `pages/devicelist/devicelist.wxml:71-72` |

**对账价值**：小程序的**诚实口径措辞**（"不代表锁上全部凭证"，`credentials.wxml:37`）正是现有 Android 端最缺的一类话术——Android 的 `AirTagLayer`/状态行只会说成功/失败（`MainActivity.kt:339-360`），**从不标注"这份数据只是本机台账"**。重设计若给 Android 引入凭证/记录域，"数据源标注 + 不完整声明"要一并搬过来。

---

## 6. Android 必须与 iOS 对齐的能力清单

> 判定口径：**已实现 / 部分 / 缺失**。iOS 侧证据只给锚点，不展开（本任务只取证 Android）。

| # | 能力 | iOS 权威锚点 | Android 现状 | Android 证据 | 判定 |
|---|---|---|---|---|---|
| 1 | 配对载荷 `KFA1:{v,n,m,p,e}` | `App/Core/AndroidPair.swift:11,24-33` | 完整解析 + 字段校验 | `LockStore.kt:62-87` | ✅ 已对齐 |
| 2 | BLE NUS 服务/写/通知 UUID | `App/Services/BLEService.swift:13` | 同串 | `KfProtocol.kt:11-13` | ✅ |
| 3 | 帧头 + KLV + 令牌 KLV#0xEE（含 8B/10B 头型自适应） | `App/Core/ZKProtocol.swift:159-167` | 同结构 | `KfProtocol.kt:36-68` | ✅ |
| 4 | 广播厂商段 0x98ED / pid / MAC | `App/Core/ZKProtocol.swift:256-259` | 同解析 + companyId 兜底 | `KfProtocol.kt:216-227`、`BleUnlocker.kt:651-669` | ✅ |
| 5 | 结果码表 0..27 | `App/Core/StatusParser.swift:155-157` | 同表（中文名）+ 独有提示语 | `KfProtocol.kt:142-150,153-167` | ✅（Android 多一层文案） |
| 6 | 20 字节分片写 + 每片 ACK | （iOS 侧注释互指） | 20B + 4s ACK | `BleUnlocker.kt:595,587-609` | ✅ |
| 7 | 自动开锁：基准 -40 dBm + 线性域回差 0.5× | `App/Core/AutoOpen.swift:135,142-143,152-155` | 同公式 | `AutoOpenKit.kt:19,26-36` | ✅ |
| 8 | 自动开锁冷却（一次靠近只开一次） | `App/Core/AutoOpen.swift:162`（eventFired 口径） | 6s 冷却 + armed 回差 + fired 位 | `AutoOpenKit.kt:48-51`、`MainActivity.kt:243-279` | ⚠️ 数值是否同值**未证实** |
| 9 | 开锁主链路（01→注入→04→rc） | `App/Services/LockService.swift:206` | 同链路 + rc3/13 自动重试一次 | `BleUnlocker.kt:326-382` | ✅ |
| 10 | 身份复核（cmd03 pid 比对） | （iOS 侧同类加固） | 有 | `BleUnlocker.kt:453-478` | ✅ |
| 11 | **命令面覆盖**：01/03/04 | — | 仅 3 条 | `KfProtocol.kt:180-192` | — |
| 11a | cmd 05/08/21（密钥交换、同步 PIN、beacon key） | `App/Core/ZKCmdBuilder.swift:76,132,140` | **无** | — | ❌ 缺失 |
| 11b | cmd 0A/0B/0C（密码新增/有效期/冻结策略） | `ZKCmdBuilder.swift:145,169` | **无** | — | ❌ |
| 11c | cmd 0E（时间同步）、12（ECHO）、23 | `ZKCmdBuilder.swift:186,69,66` | **无** | — | ❌ |
| 11d | cmd 13/14/15（指纹录入/确认/删除） | `ZKCmdBuilder.swift:191,199,206` | **无** | — | ❌ |
| 11e | cmd 16（读开门记录） | `ZKCmdBuilder.swift:210` | **无** | — | ❌ |
| 11f | cmd 18/19/20/22/24/25（音量/OTP/验证模式/DFU/自动落锁/布防） | `ZKCmdBuilder.swift:217,221,225,229,233,237` | **无** | — | ❌ |
| 11g | 钥匙串 41/43/44 | `ZKCmdBuilder.swift:243,257,251` | **无**（Android 只扫码，不写钥匙串） | — | ❌ |
| 11h | 网关 30/31/32/35/38 | `ZKCmdBuilder.swift:282,267,275,279,264` | **无** | — | ❌ |
| 12 | 固件升级（DFU） | `App/Services/DFUKit.swift` | **无** | — | ❌ |
| 13 | 备份包格式（信封 v1 + aes-128-cbc+hmac-sha256 + 键白名单） | `App/Services/BackupKit.swift:9,95,184` | **无**（`allowBackup=false`） | `AndroidManifest.xml:15` | ❌ |
| 14 | 备份编排/自检/恢复历史 | `App/Services/BackupStudioKit.swift` | **无** | — | ❌ |
| 15 | `kf_*` 存储键空间 | 本仓 **336 个不同 `kf_*` 键**（`App/Core/*`、`App/UI/*`、`App/Services/*`） | **只有 1 个偏好文件、2 个键**：prefs `kf_key_v1` 内的 `lock` / `proximity` | `LockStore.kt:17-19` | ❌ 命名空间不同源 |
| 16 | 记录/统计/成员/审计链等域 | `App/Core/{RecordSearch,LockStats,MemberHub,AuditChain}.swift` | **无** | — | ❌ |
| 17 | 无障碍（对比度/动态字体/减弱动效） | `App/Core/AccessibilityKit.swift` | 仅 1 处：读 `ANIMATOR_DURATION_SCALE==0` 关扫描动画 | `SignalArrow.kt:141-145` | ⚠️ 部分 |
| 18 | 版本号同串（ipa/apk 同一次 push 同一时刻） | `build.gradle.kts:19,71` + CI | 已实现 | `app/build.gradle.kts:32-38,63-71`、`.github/workflows/ios.yml:287,325,351` | ✅ |

### 6.1 结论：对齐缺口排序

1. **命令面**：iOS 31 个命令构造器 vs Android 3 个 ⇒ 现有 Android 只能"开锁"，连"读状态"都只有身份复核那一处。
2. **存储/备份**：两端键空间与备份格式完全不共享 ⇒ 若目标是"iOS 生成、Android 消费"，**目前只有二维码这一条通道**（`AndroidPair.swift:24-36` → `LockStore.kt:62-87`）。
3. **通知/后台**：Android Manifest 无通知权限与前台服务（`AndroidManifest.xml:5-12` 全文仅 3 个权限）⇒ 与 iOS 的提醒/后台体系不对等。
4. **UI 能力**：Android 只有 2 屏 + 3 层；小程序 22 页、iOS 侧 160 个 Swift 文件（其中 `App/UI/*` 未逐一清点）。**重设计必须先把"Android 要不要复刻凭证域/记录域"定下来。**

---

## 7. 未证实 / 风险 / 待确认

| # | 项 | 状态 | 说明 |
|---|---|---|---|
| 1 | `jzzns22561_v2/resources` 内容 | **未证实（实测为空）** | 递归计数 0 文件 0 目录；任务描述与该事实冲突，已改用 `jzzns22561_out/resources` |
| 2 | 厂商 42 个页面的**当前字节级存在性** | 未证实 | 页面名来自 `REVERSE_REPORT.md:96` 的 `ionViewDidLoad` 日志提取，本次未在压缩 `main.js` 中逐条复核 |
| 3 | Android UI 层能否本地编译 | **未证实（无本地闸门）** | `tools/kotlinlocal.js:9-10` 明说只编 4 个非 UI 文件；`tools/kotlinshadow.js:104` 对 MainActivity 只做正则结构检查；UI 仅 CI 可验 |
| 4 | Android 自动开锁冷却 6s 与 iOS 是否同值 | 未证实 | iOS 侧只核到回差与 eventFired 口径（`AutoOpen.swift:142-155,162`），未核冷却常量 |
| 5 | iOS 是否也有 rc 用户提示语（`RC_HINT`） | 未证实 | 只在 Android `KfProtocol.kt:153-167` 见到；iOS `StatusParser.swift:155-157` 只见名称表 |
| 6 | APK 内是否含 Flutter/RN 残留 | 未证实（倾向"无"） | 依据仅为 `assets` 树；未做全量字节扫描 |
| 7 | `ios-app/docs/redesign` 既有产出 | 已核 | 仅 `DECISIONS.md`(12828B) 与 `PART1-LOCKFACE.md`(16358B)；**本文是第 3 个文件** |
| 8 | Android `targetSdk=34` 是否满足重设计后的 inset/edge-to-edge 需求 | 风险 | `app/build.gradle.kts:60` 明写"35 会强制 edge-to-edge，而本界面没有做 inset 适配"——重设计若上 35，必须补 inset |
| 9 | Android 端"零后台"与自动开锁 | 风险 | `MainActivity.kt:214-219` ON_PAUSE 即 `release()` 并复位 armed ⇒ 后台不预热、不开锁；这是**设计选择**，重设计要明确是否保留 |

---

## 8. 附：一句话交接

> **对重设计最有用的三句话**：① Android 现在是"扫码 → 存一把锁 → 靠近自动开"的单功能 App，**任何 iOS 已有多域功能都要从零长**；② 两端唯一稳定的机器可读契约是 `KFA1` 二维码与协议字节面（两者都有影子对拍闸门看着）；③ 厂商基线是 **Ionic H5 单页应用**，其"页面"不能当 Android 屏幕清单用，只能当**功能全集**用，且中文串在 `main.js` 而非 `strings.xml`。
