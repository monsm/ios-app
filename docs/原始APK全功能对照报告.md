# 原始 APK 全功能对照报告（除互联网）

生成：2026-10-28
目标：`D:\aapk\jzzns22561_out`（jadx 反编译的完整 APK）→ iOS 全部实现，排除互联网

---

## 0. 权威源清单（这次首次完整覆盖）

| 层 | 路径 | 规模 | 之前状态 |
|---|---|---|---|
| Web 业务层 | `resources/assets/www/build/main.js` | 677,556 B（SHA-256 `D096AFBC…6E9121`） | 已分析（与 `vendor/apk-baseline` 同一份） |
| 原生协议层 | `sources/cn/zelkova/ZKurlcsPlugin/lockprotocol/` | **29 个 .java** | ❌ `vendor` 里只有 **2 个** → 本次已同步全部 29 个 |
| Cordova 桥 | `sources/cn/zelkova/ZKurlcsPlugin/ZKurlcsPlugin.java` | 191 行，8 个 action | ❌ 未覆盖 |
| WiFi 插件 | `sources/cn/justree/wifinamePlugin/WifiNamePlugin.java` | 43 行 | ❌ 未覆盖 |
| DFU 插件 | `sources/com/plugin/urlcsDfuPlugin/` | 30+ 文件（含 Nordic DFU 库） | 部分 |
| 推送 / 自更新 | `urlcspushPlugin` / `com/vaenow/appupdate` | — | 互联网，排除 |
| Manifest | `resources/AndroidManifest.xml` | 12,294 B | 部分 |
| 插件清单 | `resources/assets/www/cordova_plugins.js` | 19 个 pluginId | ❌ 未覆盖 |

---

## 1. 页面级覆盖：51 个 selector → 46 个真页面 → **iOS 全覆盖**

已逐个把 `page-*` selector 映射到 iOS 页面。重点确认过 4 个容易漏的：

| APK 页面 | 真实用途 | iOS 对应 | 状态 |
|---|---|---|---|
| `page-devicetypelist` | **添加设备页**（`addNewDevice()` → push） | `AddDeviceView` | ✅ |
| `page-lockmore` | **锁更多 / 设置抽屉**（`openMore()`） | 设置 Tab + 各入口 | ✅ |
| `page-detail` | **成员详情页**（`pereentMemberDetailPage()`） | `MemberDetail360View` | ✅ |
| `page-gwupgrade` | 网关 OTA **空壳**（`getVersion()` 是空函数、`btnUpdate` 只改本地状态） | 不需要 | ✅ APK 自己也没实现 |

**APK 自己不可达的 3 个页面**（不是 iOS 缺口）：
- `page-testlockrom` / `page-romlist`：`showTest = !1` 硬编码，从未置 true
- `page-home`：Ionic starter 残留（`["Pokémon Yellow","Super Metroid"…]`）

---

## 2. 协议层逐项核对结果

### 2.1 帧结构 `0x87` —— **完全一致**

| | Java `LockCommBase.getBytes()` | iOS `ZKProtocol.buildFrame(header: 8)` |
|---|---|---|
| byte 0 | `-121` = **0x87** | `"87"` |
| byte 1 | `temp \| 0`（temp=0x100）= **0x00** | `"00"` |
| byte 2-3 | `writeShort(len)` = **LE u16** | `hexPair(len & 0xff) + hexPair((len>>8)&0xff)` |
| byte 4 | `cmdId` | `hexPair(cmd)` |
| byte 5-7 | `new byte[3]` = **00 00 00** | `"000000"` |
| byte 8+ | KLV 串 | KLV 串 |
| `HEAD_LEN` | **8** | `header: 8` |

### 2.2 KLV 编码 —— **完全一致**

`KLVContainer.getBytes()` = `writeByte(key)` + `writeByte(val.length)` + `val`
iOS `buildKLV` = `hexPair(key)` + `hexPair(len)` + `v`
→ key/len 各 **1 字节**，一致。（iOS 另加 len>255 截断保护 + 遥测。）

### 2.3 会话令牌 —— **完全一致（关键验证）**

Java：`needSessionToken()` 时 `mKLVList.add((byte)-18, ssToken)` → `-18 = 0xEE`，
且 `KLVListContainer.add` 是 `super.add()` = **追加到末尾**。

iOS `ZKProtocol.injectToken`：`let klv = body + buildKLV(0xEE, tokenHex)` → **同样末尾** ✅

### 2.4 广告解析 —— **偏移完全一致**

Java `BLEAdData`（相对自定义广告 `adData`）：

| 字段 | Java 偏移 | iOS `parseAdv` 偏移 | 一致 |
|---|---|---|---|
| 帧控制 | `adData[2]` | `seg[0]`（= 98ed 后第 0 字节） | ✅ |
| PID（LE16） | `adData[4..5]` | `seg[2..3]` | ✅ |
| MAC（6B） | `adData[6..11]` | `seg[4..9]` | ✅ |
| resetStatus | `bit0` | `frameCtrl & 0x01` | ✅ |
| containNotify | `bit1` | `& 0x02` | ✅ |
| containPid | `bit2` | `& 0x04` | ✅ |
| containMac | `bit3` | `& 0x08` | ✅ |
| dfuState | `bit5` | `& 0x20` | ✅ |

`98ed` 前缀判别 + `adData[2] >= 12` 的类型改写规则也在 iOS `parseAdv` 里 ✅

### 2.5 产品表 / 错误码表 —— **全覆盖**

| 表 | APK | iOS | 状态 |
|---|---|---|---|
| pid 型号表 | **12 个**（K1/KX/V1/V1_Pro/GW/GW_commercial/GW2_commercial/JZ/Z3/Z3NFC/Z3AL/ZKBBV1） | `PidMap` **12 个** | ✅ |
| `resultCodeToMessage` | **26 条**（1–27，缺 0/4） | `StatusParser.rcMsg` **28 条**（多 0="成功"、24 等） | ✅ 全覆盖 |
| `bleCodeMsg` | **10 条**（1001/1003/1004/1006/1007/1008/2003/5001/6001–6005） | 原有 8 条，**本次补 1008** | ✅ 现 9 条（1003/1004 在 APK 里是空串，无需） |
| 日志类型名 | **27 类**（0–27，含 27「设置zkBeacom密钥」） | `StatusParser.logTypes` **27 类** | ✅ |
| `Un` 业务错误码 | 0/20000/20010/20020/20030/20040/20050 | 仅 20000 用于配网拦截（其余是云端 API 码） | ✅ 互联网类 |

### 2.6 开锁链路 —— **等价架构，不是缺口**

APK `openNext(ekeyFromCloud)`：
```js
var t = this.deviceData.ekey;         // 本地存的 ekey
if (0 != this.dState) t = ekeyFromCloud;  // 否则用云端 getBLELockKey 取的
var e = Base64.parse(t).toString(Utf8);   // ekey 是 Base64
var i = new ae(e, "0000").getParams();    // ssToken = "0000"
i.mac = this.deviceData.mac; i.keep = false;
ZKurlcsPlugin.sendData(i, ...)
```
→ ekey 是**预签好的 Base64 串**，由云端 `getBLELockKey` 下发。

iOS `LockService.unlock`：用本机 `skey` + PIN **现场签 ekey**（`buildEkey`），不发任何网络请求。

**这是架构差异**：APK 依赖云端预签，iOS 本地现签。功能等价且 iOS 更可靠（无网也能开）。
`getBLELockKey` 属互联网，按目标排除。

### 2.7 `Kn` 密钥交换方式 —— **APK 也未使用**

APK 声明 `clear=1` / `ecdh=2`，但 `ecdh` 在 677KB 的 main.js 里**只有枚举定义一处**，无任何调用。
→ iOS 只实现 clear 是**正确的**，不是缺口。

---

## 3. 原生插件：19 个 → 7 个排除 / 12 个核对

| # | 插件 | 用途 | 判定 | iOS |
|---|---|---|---|---|
| 1 | `com.plugin.urlcsDfuPlugin` | DFU | 本地 | `DFUKit`/`DFUView` ✅ |
| 2 | `cordova-clipboard` | 剪贴板 | 本地 | `Clip` ✅ |
| 3 | `cordova-open-native-settings` | 跳系统设置 | 本地 | `UIApplication.openSettingsURLString` ✅ |
| 4 | `cordova-plugin-file` | 文件 | 本地 | `FileDocument`/`fileExporter` ✅ |
| 5 | `cordova-plugin-android-permissions` | Android 权限 | **Android 专属** | 不适用（iOS 按需申请） |
| 6 | `cordova-plugin-appversion` | 版本号 | 本地 | `Bundle.main` ✅ |
| 7 | `cordova-plugin-device` | 设备信息 | 本地 | `UIDevice` ✅ |
| 8 | `cordova-plugin-ionic-keyboard` | 键盘 | **Android/iOS 壳** | 不适用（SwiftUI 原生） |
| 9 | `cordova-plugin-network-information` | 网络状态 | 本地检测 | iOS 纯离线不需要 ✅ |
| 10 | `cordova-plugin-splashscreen` | 启动屏 | 本地 | 不需要 |
| 11 | `cordova-plugin-statusbar` | 状态栏 | 本地 | SwiftUI 原生 |
| 12 | `cordova-sqlite-storage` | SQLite | 本地 | `DB`（UserDefaults JSON）✅ |
| 13 | `cordova-plugin-brightness` | **屏幕常亮**（`setKeepScreenOn`） | 本地 | `keepingScreenAwake` ✅（DFU/指纹页已用） |
| 14 | `cn.justree.wifinamePlugin` | **读当前 WiFi 名**（网关预填） | 本地 | ⚠️ **平台限制**：需 `com.apple.developer.networking.wifi-info` entitlement + 定位权限，本工程都没有 → 改为手输 + 如实提示（本次已加文案） |
| 15 | `cn.justree.urlcspushPlugin` | 推送 | **互联网** | 排除 |
| 16 | `cn.zelkova.ZKurlcsPlugin` | BLE | 本地 | `BLEService`/`LockService` ✅ |
| 17 | `cordova-plugin-advanced-http` | HTTP | **互联网** | 排除 |
| 18 | `cordova-plugin-app-update` | 自更新 | **互联网** | 排除 |
| 19 | `cordova-plugin-file-transfer` | 上传下载 | **互联网** | 排除 |

---

## 4. 关键边界澄清：之前记录的「未修 20 项」

逐条在 APK `main.js` 里搜关键词，结果：

| 之前记的「缺口」 | APK 里是否存在 | 结论 |
|---|---|---|
| 月历到期（`monthDeadlines`） | `月历`/`calendar` **零命中** | iOS 自造功能，**不在 APK 范围** |
| 批量前缀备注（`batchPrefixNote`） | `前缀`/`批量备注` **零命中** | 同上 |
| 记录前后上下文（`RecordSearch.context`） | `上下文`/`前后` **零命中** | 同上 |
| 借用登记（`saveBorrow`） | `借用` **零命中** | 同上 |
| 本周轮值（`setDuty`） | `轮值` **零命中** | 同上 |
| 停用原因回显 | `disableMark` **零命中** | 同上 |
| 推断最近使用 | `inferredLastUse` **零命中** | 同上 |
| 近 30 天告警锁 | `recentAlarmMacs` **零命中** | 同上 |
| 成员摘要 | `recentExcerpts` **零命中** | 同上 |
| 多 PIN 选择 | `pinpick` **零命中** | 同上 |
| 设备组筛选 | `groupFilter` **零命中** | 同上 |
| 设备隐藏 | `isHidden` **零命中** | 同上 |
| 首用引导 | `HintOnce` **零命中** | 同上 |
| 过期临时码提示 | `expiredTemporary` **零命中** | 同上 |
| 空台账发第一张临时码 | `genFirstOtp` **零命中** | 同上 |
| 重录继承 | `replaceOld` **零命中** | 同上 |
| 彻底删除双验 | `guardedPurge` **零命中** | 同上 |
| 记录认领 | `claim` **零命中** | 同上 |
| 日志清理 | `pruneNow` **零命中** | 同上 |
| 连接遥测 | `successRate` **零命中** | 同上 |
| **改造密码** | `page-updatepwd` **命中** | ✅ APK 有，iOS `PwdStudio(editAlias:)` 已实现 |

**结论：那 20 项里只有 1 项是 APK 功能，且已实现。其余全是 iOS（或 Android 参考版）自造的功能，不属于本次目标。**

---

## 5. 互联网类功能清单（按目标排除）

| 类别 | APK 证据 |
|---|---|
| 手机号+短信登录 / 换手机号 | `page-login` / `page-firstmodify` / `page-secondmodify`，`LOGIN`/`GET_VERIFY_CODE`/`UPDATE_BIND_PHONE` |
| 个人信息 / 我的 / 消息 | `page-userinfo` / `page-my` / `page-message` |
| 按手机号查找用户 | `page-searchuser`，`SEARCH_ZK_ACCOUNT` |
| 云端设备清单 | `retrieveDeviceInfo` / `getDeviceState` / `removeDevice` / `renameDevice` / `checkDeviceBinding` / `addLock` |
| **云端取开锁 ekey** | `getBLELockKey`（每次开锁前 HTTP） |
| 云端设备设置 | `getDeviceSetting`/`setDeviceSetting`（tailgate/security/silent/OTP 状态） |
| 云端成员与凭证 | `retrieveDeviceMemberInfo`/`updateDeviceMember`/`updateDeviceMemberLockKey`/`updateShareDevice` |
| 云端固件版本 | `getDeviceFirmwareProfile` |
| 云端网关 | `addGateway` |
| 云端消息 | `getDeviceMsg` |
| 阿里云推送 | `urlcspushPlugin` |
| App 自更新 | `com.vaenow.appupdate`（检查 XML / 下载 APK / 安装） |

**iOS 的替代实现**：设备/成员/设置/OTP 全部本地持久化（`DB`），开锁用本地 skey 现签 ——
功能等价，且离线可用。

---

## 6. 结论

| 维度 | 结论 |
|---|---|
| 页面覆盖 | 46/46 真页面 ✅ |
| 协议命令 | `0x87` 表 32 声明 / 29 有实现 → iOS 29/29 ✅ |
| 帧结构 | byte 级一致 ✅ |
| KLV 编码 | 一致 ✅ |
| 会话令牌 | 一致（KLV#0xEE 末尾）✅ |
| 广告解析 | 偏移逐字段一致 ✅ |
| pid / 错误码 / 日志类型表 | 全覆盖 ✅（本次补 BLE 1008） |
| Cordova 插件 | 12 个本地能力全部有 iOS 对应 ✅；1 项平台限制（WiFi 名）已如实提示 |
| 之前记的「20 项缺口」 | 19 项非 APK 功能；1 项（改造密码）已实现 ✅ |

**按「原始 APK 除互联网」的标准，iOS 实现是完整的。**
`vendor/apk-baseline/lockprotocol/` 本次从 2 个文件补到 **29 个**，这是之前审计的最大盲区，现已闭合。
