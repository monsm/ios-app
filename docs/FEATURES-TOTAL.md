# 全量功能点总表 · 供你逐条决定删留

> **统计：iOS 530 条（UI）+ 388 条（Core/Services）+ Android 117 条 = 1035 条功能点**
>
> 三份明细（每条都带源码行号证据）：
> - [ios-ui.md](FEATURES/ios-ui.md) —— 51 个 UI 文件，530 条，含「是否可达 / 是否重复 / 冗余嫌疑」三列
> - [ios-core.md](FEATURES/ios-core.md) —— 56 个 Core/Services 文件，388 条，含「零调用声明」统计
> - [android.md](FEATURES/android.md) —— 9 个 Kotlin 文件，117 条，含 13 项协议对账
>
> 分析方法：剥离注释后建立全仓符号引用索引，对每个声明统计「本文件内引用 / 跨文件引用 / 仅测试引用」。
> 零跨文件引用且零测试引用 → 冗余「高」。
> **局限**：本机无 Swift/Kotlin 工具链，无法编译验证；结论全部来自源码静态阅读 + grep。

---

## 一、可直接删除：7 个整文件（898 + 135 = 1033 行）

**证据都是「零实例化」——grep 全仓无任何调用点。**

| 文件 | 行数 | 说明 |
|---|---|---|
| `FpOwnerPicker.swift` | 116 | 零实例化，AddFingerPage 自己重写了一套归属选择 |
| `XLockBlade.swift` | 233 | 3D 锁体四件套之一，从未挂上任何页面 |
| `BladeGeometry.swift` | 296 | 3D 锁体四件套之一 |
| `BladeMesh.swift` | 109 | 3D 锁体四件套之一 |
| `RealityAPIProbe.swift` | 259 | 3D 锁体四件套之一（API 探针） |
| `DeviceStripCard.swift` | 12 | 只有注释的空文件 |
| `LockOverviewView.swift` | 7 | 只有注释的空文件 |

**3D 锁体四件套合计 897 行**：它们互相引用形成闭环（XLockBlade→BladeMesh→BladeGeometry），
但**没有任何页面把 XLockBlade 挂到界面上** —— 做了一个 3D 组件却从未接入 App。

---

## 二、整页级重复（5 组）——每组建议删一个

| # | 页面 A | 页面 B | 重复程度 |
|---|---|---|---|
| 1 | `FeedPage`（动态）406 行 | `EventsPage`（事件记录）904 行 | **读同一批日志、同样按天分组、同样的"只看告警"开关** |
| 2 | `BackupPage`（备份与恢复）697 行 | `BackupStudio`（备份工作室）1419 行 | 两个向导（导出向导 / 恢复向导）**每个动作各有一份** |
| 3 | `SecurityPeekView`（防窥与遮蔽） | `PrivacyDashboard`（隐私看板） | **5 个开关逐项一一对应** |
| 4 | `AlarmsPage`（告警中心）466 行 | `EventsPage` | AlarmsPage 本质是 EventsPage 的**告警子集 + 处置按钮** |
| 5 | `SecurityPage`（本机保护）364 行 | 系统组页 + MePage | SecurityPage 的 5 行入口在**两处各有平行入口** |

---

## 三、半成品 / 未接入（4 项）

| 项 | 文件 | 行数 | 证据 |
|---|---|---|---|
| `DevModules.swift` | Core | 18 | **非注释行只有 1 条 import** |
| `SettingsGroups.swift` | Core | 53 | 定义了五组分区枚举 + `settingsSectionShown()`，**该函数全仓零调用** |
| `SpeechKit.swift` | Core | 9 | 零引用 |
| `FindArrowLayer.swift` | UI | 40 | 零引用（Android 有完整实现，iOS 版只有骨架）|

---

## 四、零调用函数/开关（10 项，来自 UI 层分析）

| 项 | 说明 |
|---|---|
| `StudioTools.parseOtpAuth` | 解析 otpauth:// URI —— **无 UI 入口**（没有 OTP 录入页）|
| `StudioTools.totp` + `base32Decode` | TOTP 计算 —— 同样无入口 |
| `CodeBigCard` | 配合上面 OTP 引擎的展示卡，零使用 |
| `renameFingerprint` | 零调用 |
| `confirmDestructiveTyped` | 零调用 |
| `kf_scred_2nd` 开关 | 零调用 |
| `访客隐藏敏感成员` 开关 | 源码自注"判据口已就位等数据侧" → **实际不生效** |
| `LockOverviewView` / `DeviceStripCard` | 空文件（见第一节）|
| `AlarmCenterView.toneColor` | 半死（旧页删除后残留的扩展）|

---

## 五、同一图表多份实现（重复造轮子）

| 图表 | 实现份数 |
|---|---|
| 24 小时柱图 | **3 份** |
| 趋势图 | **2 份** |
| 三环比例环 | **6 份** |
| 电量读数 | **5 处** |

---

## 六、Core 层「零调用声明」Top 10（最该清理的）

| 文件 | 行数 | 零调用声明数 | 嫌疑 |
|---|---|---|---|
| `CredentialOrg` | 1539 | **43 个函数** | 高 |
| `RecordSearch` | 1018 | **18 函数 + 1 类型** | 高 |
| `StatsKit` | 1088 | **13 函数** | 高 |
| `Milestones` | 617 | **9 函数 + 1 类型** | 高 |
| `LockStats` | 438 | 7 函数 | 中 |
| `QuickPool` | 172 | **6 函数** | 高 |
| `AccessibilityKit` | 336 | 5 函数 + 1 类型 | 中 |
| `LinkSenseKit` | 959 | 3 函数 | 中 |
| `MemberHub` | 333 | 3 函数 | 中 |
| `DiagKit` | 696 | 2 函数 + 5 类型 | 中 |

---

## 七、Android 端（117 条）

**零引用 6 项**：`distanceMeters()` / `KfTokens.canvasGradient` / `cardSurface` / `Type.displayNumber` / `Type.body·hero·small` / `KfTokens.Space.xsm`

**Android 独有（iOS 没有）10 条**，最硬的三条：
1. **AirTag 精确查找全屏层** —— iOS 的 `FindArrowLayer.swift` 只有 39 行注释，零 UI
2. **变速提示音** —— iOS 只有固定 systemSound，无随 RSSI 变速
3. **连接层测距驱动信号流** —— iOS 有函数但无周期调用点

**顺手发现的 3 个真缺陷**：
- `AutoUnlockCard` 阈值文案是**假的**（写死 −38/8秒/−55，真实是 −40/−43/6秒）
- `Tokens.kt` 两处注释与值不符（Radius.card 注释 24 值 26）
- 信号/武装态在主屏**出现 3 次**（KfChip + SignalMetric + AutoUnlockCard）

---

## 八、怎么用这份表

**建议的决策顺序**：

1. **先删第一节（7 个整文件 1033 行）** —— 零风险，全是零实例化死代码
2. **再定第二节（5 组重复页）** —— 每组告诉我保留哪个，我删另一个
3. **第三节半成品** —— 要么接入，要么删，不要留着占位
4. **第四节零调用函数** —— 基本都是「功能做了一半没接 UI」，可整批删
5. **第五节图表重复** —— 收敛成一份实现，各页复用

---

**要我开始执行吗？** 你按上面编号告诉我删哪些，我逐项改并跑 34 道闸门。
