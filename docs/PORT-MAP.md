# 原小程序 → iOS 移植对照（**已逐项核实版**）

> 基准：`D:\aapk\jzzns22561_out`（ZK 门锁 Cordova/Ionic，**59 个页面**）
> 现状：iOS **24 个页面**
> 口径：原 App 有的必须能用；原 App 没有的可以删

---

## 一、原 App 的 7 个功能分组

| 图片目录 | 图数 | 含义 |
|---|---|---|
| `common` | 67 | 通用（开关锁/电量/指纹/头像） |
| `jz` | 32 | 智能锁主流程 |
| `kx` | 16 | 钥匙串 |
| `gw` | 11 | 网关 |
| `gwjz` | 7 | 网关+锁配网 |
| `v1` / `v1_pro` | 15+15 | 设备型号 |

---

## 二、🔴 关键缺口：原 App 有、iOS **只有数据层没界面**

| # | 功能 | 原 App 页面 | iOS 现状（grep 实证） |
|---|---|---|---|
| **1** | **布防/撤防** | `DefendPage`（选开始/结束时间）<br>`DefendhomePage`（布防状态+按钮） | `DB.defend` / `DB.saveDefend` / `AutoOpenKit.defendActive` / `PidMap.canDefend` / `ZKCmdBuilder 0x25` **全都有**，但 **UI 层 0 处调用** —— 用户无法设置布防时段 |
| **2** | **尾随门** | `TailgatePage`（设置开关与延时） | `DB.tailgate` / `DB.saveTailgate` / `PidMap.canTailgate` **都有**，**UI 层 0 处调用** |
| 3 | 临时开锁密码 | `presentOpenDevicePage`（A 模式有效，可复制） | 仅 1 处提及（SettingsView:27），无独立生成界面 |
| 4 | 手机号找钥匙 | `presentBlekeyAddPage` | **完全没有** |
| 5 | 修改手机号 | `presentModifyPhonePage` | **完全没有** |
| 6 | 固件版本列表 | `presentRomListPage` | **完全没有**（只有单版本检查） |
| 7 | 测试锁 ROM | `TestlockromPage` | **完全没有** |
| 8 | OTP 开关锁 | `OtpopenPage` | 有 9 处（`SafemodeIntroView(mode:"otp")`）✓ |

**第 1、2 项是"接线断在最后一米"**：协议构造器、状态判定、存储读写、备份序列化全部实现好了，
**唯独没有那一屏 UI 去调用 `DB.saveDefend`** —— 这是本仓典型的"做了后端没做前端"。

---

## 三、✅ 已移植到位（43 项）

设备类：`DevicelistPage`→`LocksPage` · `DevicetypelistPage`/`AdddevicePage`/`RomlistPage`→`AddLockPage` ·
`RominfoPage`/`DeviceinfoPage`→`DevicePage` · `ModifydevicenamePage`/`LockmorePage`/`DeviceresetPage`→`LockProfilePage` ·
`SynctimePage`→`SyncTimeView` · `CheckfirmwareupdatePage`→`FirmwarePage`

成员类：`ManagePage`→`MembersPage` · `AddmemberPage`→`MemberWizardView` · `pereentMemberDetailPage`→`MemberDetail360View` ·
`ModifynamePage`/`ModifyfpnamePage`→`MemberCenterView`/`KeysPage` · `SearchuserPage`→`MembersPage`

凭证类：`AddpwdPage`/`UpdatepwdPage`→`AddKeyPage` · `ClearpwdPage`→`CredentialBinView` ·
`StartaddfpPage`→`AddFingerPage` · `FpdetailPage`→`KeysPage 凭证详情` ·
`OtpgeneratePage`/`OtpopenPage`/`SafemodeintroducePage`/`SetsafemodePage`→`SafemodeIntroView`

钥匙串：`AddkeychainPage`/`KeychaindetailPage`/`DelblekeyPage`→`DonglesPage`

网关：`AddgwPage`/`AddgwsetwifiPage`/`GwstatePage`/`GwresetPage`/`GwresetexplainPage`/`GwupgradePage`→`GatewayPage`

其他：`rootPage`→`HomeConsole` · `MyPage`→`MePage` · `MessagePage`→`StatsPage` · `skipToLoginPage`→本地版无登录（合理）

---

## 四、⚠️ iOS 有、原 App 没有（12 项）

| iOS 页面 | 功能 | 判断 |
|---|---|---|
| `AppearancePage` | 主题/密度/周起始 | 用户已裁定不提供配色 |
| `IconPicker` | 换 App 图标 | 原 App 无 |
| `CarePage`/`CareRemindersView`/`CareViews` | 保养/关怀/换电 | 原 App 无 |
| `BackupPage` | 备份导出 | 已精简为文件存取 |
| `CredentialBinView` | 凭证回收站 | 原 App 无 |
| `SecurityCenterView` | 审计流水 | 原 App 无 |
| `StatsPage` | 开门统计 | 原 App 无 |
| `ShareToAndroidView` | 分享给安卓 | 原 App 无 |
| `DiagnosticsPage` | 诊断自检 | 原 App 无 |
| `AppLockSetupView` | App 应用锁 | 原 App 用系统登录 |
| `MembersPage` 角色/代管/归档 | 家谱扩展 | 原 App 只有成员列表 |
| `LockProfilePage` 锁牌/符号/颜色 | 视觉扩展 | 原 App 只有简单改名 |

---

## 五、结论

**按「保证有用的移植」这个口径，最该做的是补第 1、2 项（布防 + 尾随门）。**

它们不是"新功能"，而是**原 App 的核心安防功能**，iOS 侧协议与存储全做完了，只缺一屏 UI。
补上之后，iOS 才真正等价于原 App 的安防能力。

第 4-7 项（手机号找钥匙/改手机号/固件列表/测试ROM）属于边缘功能，
原 App 是「账号体系 + 云」才需要的，iOS 本地版没有登录体系，可以不做。

第 四 节 12 项要不要删，等你决定。
