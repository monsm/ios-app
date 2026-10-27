# Android 按功能点精简方案（待批红）


> ⚠ **本档是历史台账，不是当前代码的说明书。**
> 里面的 `文件:行号` 指针记录的是**写档当时**的位置；后续精简/重构后部分文件已删或行号已移，
> 那些失效指针是台账的**正常内容**（它记的就是"某批删了什么"），不是错误。
> 想知道某个功能现在还在不在，请看 `docs/feature-web/features.json`（那份由工具从 inventory 重算）。

> 上一版我按"死代码"精简，方向错了。**这一版按功能点**：先问「Android 该提供哪些功能」，
> 再问「哪些功能不做」，最后才落到代码。
>
> 数据来源：`docs/feature-web/features.json`（Android 参与的功能点 79 个）+ 逐文件代码勘察。
>
> **Android 现状**：2466 行 Kotlin / 391 个声明 / 79 个功能点。
> 定位是「一个人、一把门」的极简钥匙（`LockStore` 注释原文）。

---

## 一、Android 功能全貌（79 个功能点，按域）

| 域 | Android 独有 | 双方都有 | 合计 |
|---|---:|---:|---:|
| unlock（开锁） | 36 | 3 | 39 |
| device（设备/外壳） | 22 | 1 | 23 |
| protocol（协议/链路） | 11 | 13 | 24 |
| data（本机存储） | 4 | 1 | 5 |
| **credential / member / record / security / backup / care / diagnostic / settings** | **0** | **0** | **0** |

> ⚠ 最后一行的意思：Android 在 8 个域里**一个功能都没有**。这是刻意的（极简版），不是遗漏。

---

## 二、功能分组（这是本次精简的决策单位）

我把 79 个功能点归成 9 个功能组，按「外围 → 核心」排序：

| 组 | 功能 | 代码位置 | 行数 | Android 有？ | iOS 有？ |
|---|---|---|---:|---|---|
| **F1** | **AirTag/FindMy 查找族**（信号箭头、朝向、距离、峰值方位、提示音、全屏层） | `SignalArrow.kt` 全 225 行 + MainActivity 约 120 行 | ~345 | ✅ | ❌ |
| **F2** | 靠近自动开锁（回差/闩锁/冷却/预热/前后台闸） | `AutoOpenKit.kt` 52 + MainActivity 约 90 | ~142 | ✅ | ✅ |
| **F3** | 手动开锁 + 结果状态机 + 触觉 | MainActivity 约 80 + `Haptics.kt` 72 | ~152 | ✅ | ✅ |
| **F4** | 扫码绑定（QR 解析/首次绑定/覆盖换绑/校验） | `LockStore.kt` 98 + MainActivity 约 100 | ~198 | ✅ | ✅（签发端） |
| **F5** | 设置抽屉（靠近开关/重新扫码/解绑） | MainActivity 约 60 | ~60 | ✅ | ✅ |
| **F6** | 设备外壳（标题/齿轮/空态/返回键层级） | MainActivity 约 120 | ~120 | ✅ | ✅ |
| **F7** | 协议与链路（帧/KLV/令牌/建链/分片/重试） | `KfProtocol.kt` 231 + `BleUnlocker.kt` 683 | ~914 | ✅ | ✅ |
| **F8** | 本机存储（LockInfo/键/清理） | `LockStore.kt` 98（与 F4 共用） | — | ✅ | ✅ |
| **F9** | 外壳基建（主题/令牌/权限/生命周期/构建） | `Theme.kt` 28 + `Tokens.kt` 81 + `KfTheme.kt` 79 + manifest + gradle | ~200 | ✅ | 部分 |

---

## 三、按功能点的删除候选（按「外围 → 核心」排）

### 🟥 第一层：Android 独有、且与「极简钥匙」定位冲突

#### F1-AirTag/FindMy 查找族 —— **最该先谈的一项**

| 维度 | 事实 |
|---|---|
| 代码量 | `SignalArrow.kt` 225 行（整文件）+ `MainActivity` 约 120 行 = **约 345 行 / 14%** |
| 功能点 | 17 个（`unlock.finder.*` 6 个 + `unlock.airtag.*` 5 个 + 相关 L4 6 个） |
| iOS 有吗 | **完全没有**（图谱 `iosOnly` 计数里这 17 个全在 Android 侧） |
| 技术依赖 | 需要 `Sensor.TYPE_ROTATION_VECTOR`（方向传感器）+ 实时 RSSI 流向 |
| 与核心功能的关系 | **只是"怎么找到锁"的辅助**。没有它，手动圆盘 + 靠近自动开锁照常工作 |
| 删掉的代价 | 用户失去"精确查找"能力；但如果锁就在门口，这个能力的边际价值存疑 |

**这一项我不替你决定**，因为它是**唯一有真实用户价值的 Android 独有能力**（iOS 没有）。
删 = Android 更纯粹（"一个人一把门"），留 = Android 比 iOS 强的一点差异化。

---

### 🟧 第二层：死代码 / 未接线（上一版方案，仍然有效）

这些是**功能点上"声称有、实际没有"**的东西，删了不影响任何现有行为：

| 组 | 内容 | 行数 | 为什么必须删（而不是留） |
|---|---|---:|---|
| **D1** | `Theme.kt` 整文件（8 个固定色） | 28 | 8 个 val 零引用，只在注释里被提；`KfDarkColors` 已逐字重写同值 |
| **D2** | `Tokens.kt` 15 个零引用槽位 | ~56 | 声称"与 iOS 逐字同源"，但 22/24 槽位没人用 —— **这句承诺是空的** |
| **D3** | `Tokens.kt` 剩余 3 常量内联 | ~25 | 只剩 `Space.l`/`Radius.card`/`Curve.soft`，各 1–2 次使用 |
| **D4** | `Haptics.kt` 3 个 Compose 辅助 | ~10 | `rememberKfHaptics`/`KfTick`/`KfConfirm` 零引用 |
| **D5** | `BleUnlocker.isReady()` | 1 | 零引用（`OPEN-ISSUES` 原判"无法判定"，现判为遗漏没接线） |
| **D6** | `MainActivity` 3 个未用 import | 3 | `Context`/`CompositionLocalProvider`/`HapticFeedbackType` |

**小计约 123 行（5%）**

---

### 🟨 第三层：功能上"有但极薄"，需要你判是否保留

| 组 | 项 | 说明 |
|---|---|---|
| **T1** | `unlock.dial.press` 按压回弹 | 纯视觉，约 10 行 |
| **T2** | `device.multi-lock` 单锁边界 | 这是**约束**不是功能（"不支持多锁"），删了约束就不存在了 —— **建议保留** |
| **T3** | `android.theme.palettes` 深浅双模 | `KfTheme.kt` 79 行；iOS 有对应能力，Android 侧是真在用（8 处 `LocalKfColors`） |
| **T4** | `android.haptics` 触觉三档 | `KfHaptics` 四档里只有 `ok`/`fail` 被调用；`tick`/`trigger` 零引用但属同族 |

---

## 四、明确**不删**（附理由，避免反复问）

| 项 | 理由 |
|---|---|
| F2 靠近自动开锁 | 极简版的两个核心能力之一；有 `kotlinshadow.js` 对拍锁着 |
| F3 手动开锁 | 核心能力 |
| F4 扫码绑定 | 唯一的凭证获取入口 |
| F5 设置抽屉 | 三个必需动作的容器（开关/重扫/解绑） |
| F6 设备外壳 | 唯一的界面骨架 |
| F7 协议与链路 | 没有它开不了锁 |
| F9 的 `KfTheme.kt` | `LocalKfColors` 8 处真实使用 |
| F9 的 manifest 权限 | 4 条全部有据（BLE 必需 / VIBRATE 有真机事故记录 / CAMERA 扫码） |
| F9 的 gradle 依赖 | 逐个核实过，全部有引用 |

---

## 五、三个方案（请你选一个）

### 方案 ①「保守」—— 只删死代码
- 删 D1–D6（约 123 行）
- **保留** F1 AirTag 族
- 结果：Android **2343 行**
- 特点：零风险，但只解决"死代码"，不解决"定位漂移"

### 方案 ②「彻底」—— 删死代码 + 删 AirTag 族
- 删 D1–D6 + F1（约 468 行 / **19%**）
- 结果：Android **1998 行**
- 连带删除：
  - `SignalArrow.kt` 整个文件（225 行）
  - `MainActivity` 的 `AirTagLayer`/`ProximityBeep`/`CircleIconButton`（约 120 行）
  - 状态：`azimuth`/`peakRssi`/`peakAz`/`pitch`/`roll`/`airTagDismissed`/`findSound`（7 个）
  - `HeadingSense.attitude()` 传感器流（`SignalArrow.kt:96`）
  - 图谱 17 个功能点
  - `OPEN-ISSUES` 里相关条目
- 特点：Android 回到"一个人一把门"的纯粹定位，但失去唯一的差异化能力

### 方案 ③「更彻底」—— 方案 ② + 弱化主题/令牌体系
- 方案 ② 再删：`Tokens.kt`（整个）、`Theme.kt`（整个）
- 结果：Android **约 1930 行**
- 特点：`KfTheme.kt` 保留（8 处真实使用），但不再有"与 iOS 同源"的令牌层

---

## 六、我的建议

**方案 ②**。理由：

1. **D 组是必须删的**（死代码 + 空承诺），无论选哪个方案
2. **F1 AirTag 族是唯一需要"决策"的**，而它恰好与 Android 的定位冲突：
   - `LockStore` 注释原文：「极简版的定位就是"一个人、一把门"」
   - 而 AirTag 精确查找是**给"锁找不到"场景**设计的能力 —— 一个人一把门、锁就在门口时，这个场景不成立
   - 它需要方向传感器 + 实时 RSSI，是**整套能力**（345 行），不是顺手的小功能
3. 但我必须说清：**这是 Android 唯一比 iOS 强的地方**。删了之后，Android 就是一个纯粹的"能开锁的遥控器"。

**如果你认为 AirTag 族有价值 → 选方案 ①，我不再提第二次。**

---

## 七、无论选哪个，都要连带做的（删完立即做，否则误导后人）

| 项 | 内容 |
|---|---|
| V1 | 图谱同步：`features.json` 里被删的功能点要移除或标 `removed` |
| V2 | `OPEN-ISSUES.md` 的 E1–E4 四条要翻案（原判"可忽略"，其中 E3/E4 的事实判断本身有误） |
| V3 | `README.md` 的 Android 模块清单 |
| V4 | `docs/INDEX.md` 登记本次精简文档 |
| V5 | `tools/kotlinshadow.js` 若引用被删符号，要同步改（已核实：只引用 `AutoOpenKit` 常量，**不受影响**） |
| V6 | 重跑 41 个闸门 |
| V7 | CI 的 Android job 确认仍能编译（本地无 Android SDK，**这一步只能靠 CI 验证**） |
