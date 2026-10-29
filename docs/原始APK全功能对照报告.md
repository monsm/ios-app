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


---

## 7. 本轮代码修复（10 项）

| # | 修复 | 文件 | 性质 |
|---|---|---|---|
| 1 | BLE 错误码补 `1008`「不支持的ssToken方式」 | `App/Services/BLEService.swift` | 枚举缺口 |
| 2 | 网关配网 WiFi 名：iOS 无 entitlement，改为手输 + 如实提示 | `App/UI/Sheets.swift` | 平台限制 |
| 3 | **「安全模式 A/B」页面不可达** —— `SafemodeIntroView` 只以 `mode:"otp"` 构造过 | `App/UI/SettingsView.swift` + `Destination.swift` | **真缺口** |
| 4 | 补 A/B 模式的定义说明（APK 有，iOS 只写「当前已是 B」） | `App/UI/SettingsView.swift` | 文案完整性 |
| 5 | **录指纹页缺屏幕常亮** —— `Mascot.swift:126` 注释写着会调用，实际零调用 | `App/UI/CredentialStudio.swift` | **真缺口** |
| 6 | DFU 加 `UIBackgroundModes: [bluetooth-central]`（Android 有前台服务） | `project.yml` | 可靠性 |
| 7 | **`PidMap.productNames[7873]` 型号名错** —— 写成 V1 Pro，应为 JZ | `App/Core/PidMap.swift` | **字节级 bug** |
| 8 | **硬件台账 MAC 用错序** —— `scanForDongle`/`provisionGateway` 用 `macRaw`（线上序） | `App/Services/HardwareService.swift` | **字节级 bug** |
| 9 | **`rcKLV` 漏登记 `0x23`** —— 配网握手 rc 恒为 0，失败当成功 | `App/Services/LockService.swift` | **字节级 bug** |
| 10 | 空 token 防护 —— 只判 KLV#02 存在、没判非空 | `App/Services/LockService.swift` | 健壮性 |

## 8. 复核掉的「疑似 bug」（经代码核实不触发）

| 子代理怀疑 | 核实结果 |
|---|---|
| `cmd0A` 非 ASCII 密码被 `&0xff` 截断 | UI 校验 `pwd.allSatisfy { $0.isNumber }` ⇒ 密码恒 6–8 位数字，永不触发 |
| `pinToLEOrNil` 8 位十进制 PIN 被当 hex | `KeyGen.genPin()` 生成的是 `HexKit.hex([b3,b2,b1,b0])` = **8 位 hex 且本身已是 LE**，直接返回正确 |
| `cmd21SetBkey` 硬编码 skeyLen `"10"` | `KeyGen.genBkey()` = `randomBytes(16)` ⇒ 恒 16 字节，`0x10` 正确 |
| 明文 `cmd03` 缺 KLV#01 EKey 包 | APK `getDeviceInfo` 用的是 **0x88 包络**（对应 iOS `cmd03StatusWrap`）；iOS 的 `cmd03StatusPlain` 只在台账缺 skey 的异常场景用，不影响正常流程 |

## 9. 剩余协议健壮性待办（不影响正常功能）

以下来自逐行比对，均为**边界条件**或**诊断精度**问题，正常流程不触发：

| # | 项 | 影响 | 优先级 |
|---|---|---|---|
| 1 | `request` 的 8s timer 覆盖「写+收」两段（Java 是每片 8s + 收包 8s） | 极弱信号下长帧（cmd08 13 分片）可能提前报 1007 | P1 |
| 2 | `parseAdv` 帧控制门禁用 `(fc & 0x0C) == 0x0C`，Java 用 `adData[2] >= 12` | fc=0x10 时 Java 接受/iOS 拒绝 | P2（待真机） |
| 3 | `StatusParser.logTypes` 与 APK `We` 表部分编号不同（11/17/19 等） | 若锁按 APK 表发事件，iOS 显示「未知(N)」 | P2（待真机） |
| 4 | `StatusParser.intHex` 是整串解析，JS 是前缀解析 | `"01zz"` → JS 1 / iOS 0 | P3 |
| 5 | `broadcastMode` iOS 归一化为 0/1，JS 是 0/2 | C 模式判定显示差异 | P3 |
| 6 | `buildKLV` >255 字节截断（Java 是长度取低 8 位、值全量） | 未来塞固件分片才会触发 | P3 |
| 7 | `BLEError` 的 1006/6001/6004 枚举存在但从未抛出 | 排障时错误码语义丢失 | P2 |
| 8 | `KLV#36` 未解析 | 新固件字段缺失 | P3 |

**结论：以上 8 项都不影响「功能是否存在」，只影响极端条件下的表现或诊断精度。按「原始 APK 除互联网的全部功能都要在 iOS 实现」的口径，功能面已经完整。**

---

## 10. 第三路独立核对（main.js 全量功能提取）

另派一名子代理从 `main.js` 独立提取全部用户可见功能（不依赖 CSV），口径：
**51 个 `page-*` selector（含 5 个空壳/死页）→ 排除互联网后 72 个业务功能点**。

结论：**iOS 已实现 61 / 部分或偏差 5 / 缺失 6**（61+5+6=72 自校验通过）。

### 已修的 3 项

| # | 项 | 性质 | 修复 |
|---|---|---|---|
| 1 | **防尾随档位 off-by-one** | **安全相关** | APK `getCurrentChooseSecond()` 返回索引 2–6 **直接当秒数**；iOS 原来 `ForEach(2...7)` + `seconds-1` ⇒ 选 6 秒实发 5 秒、多出 7 秒档。已改 `2...6` + `setAutoLock(seconds)` |
| 2 | **「临时密码」快捷格指向介绍页** | 入口错误 | APK `imgClick(3)` → `page-otpgenerate` 直达生成；iOS `QuickPool:132` 原来给 `SafemodeIntroView(mode:"otp")`（纯说明）。已改 `TempCodeStudio()` |
| 3 | **网关缺三条使用须知** | 文案缺失 | APK `GwstatePage` 三条（五米内/无需配对/只能收状态不能远程操作）。已补到 `GatewayView`，第 2 条按本地口径改写 |

### 复核掉 3 项（不适用）

| 子代理列为 | 核实结果 |
|---|---|
| P0 开锁页「钥匙有效期」横幅 | APK 依赖云端 `deviceData.dState/createTime/expireTime`：`dState=1` 是**别人分享的钥匙**、`dState=2` 是钥匙失效。iOS 纯离线没有「分享进来的钥匙」概念，`Device`/`Keychain` 也没有这三个字段（全仓零命中）。iOS 的等价能力在 `MobileKeyView`（手机钥匙「永久 / 自定义到期」已显示）——**架构差异，不是缺口** |
| 钥匙串「添加未知钥匙」`addOtherKeyChain` | 所在页 `page-keychaindetail` 是**空壳**（子代理自己确认「模板只有 padding 容器」），方法虽在但**不可达** |
| 钥匙串「按锁查钥」`getNowEKeyInfo` | iOS `DongleView` 的「查看已写入的钥匙」→ `HardwareService.cmd44GetEkeyInfo` 已实现 |

### 仍不适用

- 协议测试页 `page-testlockrom` / RomList：APK `showTest = !1` 硬编码，从未置 true
- 设备类型列表 `page-devicetypelist`：APK 走云端 `getProductList`（互联网）
- 网关「更换其他 WiFi」：iOS 无公开 API 直达 WiFi 面板，已加提示

### 反向确认：iOS 独有功能

子代理用 `main.js` 全文计数证明：**记录 / 历史 / 备份 / 二维码 / 自动开锁 / 应用锁 / 胁迫 / 访客 / 长辈 / 主题 / 导出 CSV** 在 APK 里全部 **0 次**。

⇒ iOS 的记录页、备份恢复、应用锁+胁迫码、分享给安卓、凭证工坊、成员中心、AutoOpen、
手势偏好、外观系统、诊断、`kf://` 深链、电池档案、锁档案、锁钟偏差、只读试验模式、
固件包本地校验 **全部是 iOS 独有**，不是 APK 移植。

**这条很重要**：之前那份「未修 20 项」清单里 19 项「缺口」正是这一类 —— 它们是 iOS 自己长出来的功能，
按「原始 APK 除互联网」的口径根本不该算缺口。

---

## 11. 最终状态（2026-10-29 收尾）

### 11.1 iOS 后台 ↔ 前台：deadscan A 档 67 → 3

| 阶段 | A 档零引用 | 动作 |
|---|---|---|
| 起点 | **67** | — |
| 第一轮（用户逐条勾选） | 67 → 26 | 删 A 类 18 UI 死代码 + B2 19 已放弃链路 + 孤儿 5 |
| 第二轮 | 26 → 16 | 接 6 项：记录前后上下文 / 最近开门查记录 / 停用原因 ×2 / 批量前缀 / 弱口令 / 同类型计数；删废弃 `Dot` 枚举 |
| 第三轮（用户全选 7 项新 UI） | 16 → 8 | 月历 / 组筛选 / 成员摘要 / 多 PIN / 时段 / 环境结论（6 项做完；排序项按用户决策不恢复） |
| 第四轮 | 8 → 6 | 删 `inferredLastUseMap` / `stateString` / `openTimes` |
| 第五轮 | 6 → **3** | 删 `onceDone` / `markOnce` / `isLock` |

**剩下 3 条全部是有意保留，不是死代码：**

| 项 | 判定 |
|---|---|
| `HexKit.strictBytes` | 用户明确选「暂不改」的严格解析备用口径 |
| `BackupDoc.fileWrapper` | `FileDocument` 协议方法，导出备份时由系统调用 |
| `ShakeEffect.effectValue` | `GeometryEffect` 协议方法，抖动动画每帧由系统调用 |

### 11.2 协议健壮性 8 项：复核结论

| # | 项 | 复核结论 | 处置 |
|---|---|---|---|
| 1 | `request` 8s timer 覆盖写+收 | `writeFrameHex` 内部每片 8s，13 分片实际耗时几十 ms；8s 总窗足够 | 不改（改动需真机验证长帧） |
| 2 | `parseAdv` 帧控制门禁 | iOS 用 `(fc & 0x0C) == 0x0C`，Java 用 `adData[2] >= 12`（byte signed） | 需真机 |
| 3 | `logTypes` 枚举差异 | iOS 与 APK 可能是两套固件枚举 | 需真机 |
| 4 | `intHex` 整串 vs 前缀解析 | 锁端回包是合法 hex，两者一致；只有脏数据才分叉 | 不改（实际不触发） |
| 5 | `broadcastMode` 0/1 vs 0/2 | **子代理误判**：唯一消费方 `Sheets.swift:710` 只判 `== 0`，0/1 与 0/2 等价 | 不改 |
| 6 | `buildKLV` >255 截断 | 23 个调用点，当前最大值 ekey 30B / WiFi 64B，不触发；改签名风险大于收益 | 不改 |
| 7 | `BLEError` 1006/6001/6004 从未抛出 | 诊断精度问题，不是功能缺失 | 不改 |
| 8 | `KLV#36` 未解析 | 新固件字段 | 需固件 |

**结论：8 项里 4 项经复核为「理论差异、实际不触发」或「子代理误判」，3 项需真机/固件，1 项需真机验证长帧。没有可安全直接改的。**

### 11.3 原版 APK 功能落地：72/72 有交代

| 分类 | 数量 |
|---|---|
| iOS 已实现 | 61 |
| 本轮修复 | 3（防尾随 off-by-one / 临时密码入口 / 网关三条建议） |
| 架构差异或平台限制 | 5（钥匙有效期云端字段 / 按锁查钥已实现 / 更换 WiFi 平台限制 / 设备类型列表云端 / 安全模式 A 已补双向） |
| APK 自身不可达 | 3（协议测试页 / RomList 的 `showTest=false` / 添加未知钥匙的空壳页） |
| **合计** | **72** |

### 11.4 本轮新增的功能（用户勾选）

- 凭证到期月历（`CredentialCalendarView.swift` 新建）
- 设备组筛选（顺带修 `pageOrder` 从未赋值 + `groupFilter` 没人读）
- 成员 360「最近开锁」
- 多 PIN 选择
- 记录详情「时段」
- 锁信息名片「连接环境」
- Face ID 解应用锁（设了胁迫码时不显示）
- 钥匙有效期档、添加设备选型号、安全模式 B→A、协议测试页（含 RomList）

### 11.5 仍待用户决策/真机

| 项 | 为什么 |
|---|---|
| `parseAdv` 门禁口径 | 需真机确认哪些固件会发 `fc=0x10` 这类边界值 |
| `logTypes` 枚举 | 需真机看锁按哪套表发事件 |
| `KLV#36` | 需新固件样本 |
| `request` 超时窗口 | 需真机跑长帧（cmd08 13 分片）验证 |
| 距离标定（`AutoOpen.autocal`） | 需真机采样 RSSI |
| APK 4 项协议疑点（cmd24 尾门档位 / 0x88 信封变体 / cmd13 orderIdx / 广播门禁） | 需真机 |
