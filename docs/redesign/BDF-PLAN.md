# BDF 三棱柱重构方案

> 2026-10-21 定稿。技术栈 iOS 27 / Swift 6 / SwiftUI。
> 每一条都标注了**代码依据**或**已验 CI 结果**，不写没根据的话。

---

## 一、三域划分（定稿）

| 域 | 一句话 | 内容 |
|---|---|---|
| **B 管家台** | 设置等一切 | 偏好、备份、凭证管理、成员管理、安全、硬件配置 |
| **D 就近** | 门 + 锁的物理形态 | 门、刃锁体、开锁、锁的实时状态 |
| **F 仪表** | **锁的数据** + **人的数据** | 锁的统计 + 成员的统计 |

### 数据边界（已从代码确认）

**锁的数据** —— 来自 `StatsKit`：
- `hourBuckets` 每小时开门分布
- `coverageDays` 数据覆盖天数
- `weekSummary` / `lastWeekDigest` 周报
- `isIdleLock` 长期未用

**人的数据** —— `StatsKit` 已有专门实现（**已核过签名**）：

这些是 `StatsKit.StatModel` 的**实例方法**，不是静态方法：

```swift
let m = StatsKit.build(mac: mac, week: w, window: days)
m.memberCounts(days: 30)      // [(id, name, approx)] 每成员开门次数
m.memberBubbles(days: 30)     // [MemberBubble] 气泡图数据
m.memberDaily(days: 30)       // [(id, name, perDay: [String: Int])] 逐日
m.memberTodayCount(id: "…")   // Int 今日某人次数
m.kindOwnerBreakdown()        // [String: [(id, name, n)]] 类型 × 成员
m.homeProxyHours(from:to:)    // Int 在家时长代理
m.weekSummary()               // [String] 周报
```

锁侧指标则是 `StatsKit` 的**静态方法**（不需要实例）：
```swift
StatsKit.hourBuckets(rows)    // 每小时开门分布
StatsKit.coverageDays(logs)   // 数据覆盖天数
StatsKit.isIdleLock(mac)      // 长期未用
```

**这个发现很重要**：不是"要做人的数据可视化"，而是"**数据层早就有了，只是没可视化**"。
（现在这些 member* 方法只出现在导出 CSV 和文字摘要里。）

> ⚠ 修正记录：初稿把 member* 全写成 `StatsKit.memberCounts` 静态调用 —— 错的。
> 它们缩进 8 空格，在 `enum StatsKit` 内部的 `struct StatModel` 里，必须用实例。

---

## 二、D 域：门 + 锁（核心创新）

### 2.1 布局

```
┌─────────────────────────────┐
│  锁名（一行）                │
│                             │
│      ╔═══════════╗          │  ← 门占满整屏
│      ║           ║          │     07 竖条阵列
│      ║     ⬛    ║          │     1050 × 2300 × 88 mm
│      ║           ║          │
│      ║           ║          │     锁按真实比例 5.7% 门宽
│      ╚═══════════╝          │     = 画面上很小
└─────────────────────────────┘
         ↑ 触摸锁体 → 放大
```

### 2.2 比例与放大（你提出的方案）

**问题**：真实比例下锁只有门宽的 5.7%，约 27px 宽，看不清。

**解法**（你的提议，我补细节）：

```swift
@State private var lockFocused = false

// 门全屏，锁按真实比例很小
XLockBlade(isOpen: ..., ...)
    .scaleEffect(lockFocused ? 3.2 : 1.0, anchor: .center)
    .animation(.spring(response: 0.42, dampingFraction: 0.82), value: lockFocused)
    .onTapGesture { lockFocused.toggle() }
    .background(
        // 点其他位置归位
        Color.clear.contentShape(Rectangle())
            .onTapGesture { lockFocused = false }
            .allowsHitTesting(lockFocused)
    )
```

**放大幅度算过**：3.2× 时锁宽 = 27 × 3.2 ≈ 86pt，接近现在 `LockPlate` 的可读尺寸。
放大后锁体会**超出画面**，用 `clipShape` 裁掉，视觉上像"镜头推近门锁"。

**这一条解决了"真实比例 vs 可读性"的矛盾**，且不违背物理 —— 因为放大发生在触摸时，是"看细节"而非"锁这么大"。

### 2.3 门面信息：只留 4 项

| 项 | 位置 |
|---|---|
| 锁名 | 顶部一行 |
| 电量 | 锁体旁小字，< 20% 才醒目 |
| 已锁/已开/未连接 | 锁体下方 |
| 锁体本身 | 中心 |

**不放**：快速操作、固件/网关入口、开门记录、任何卡片列表。全部归 B 或 F。

### 2.4 交互

- **点锁体** → 放大聚焦（切换）
- **放大状态下点其他位置** → 归位
- **按住锁体** → 充能开锁（沿用 `DoorFront` 现有逻辑）
- **边缘热区右滑** → 转到 F
- **边缘热区左滑** → 转到 B

---

## 三、三棱柱（定稿：C 侧面呼吸）

### 3.1 为什么是 C

已实测六种（`prism-anim.html`），C 的唯一优势：
**缩放不是遮羞布，而是几何必然** —— 三棱柱转到 60° 时棱正对观察者、投影确实最窄。
观众会把缩小的原因归给"它转过来了"，而不是"它被缩小了"。

### 3.2 精确算法（已验证）

```swift
// 缓动：easeInOutSine（不是 Quint —— Quint 前段太陡，t=0.25 只转 1.9°，像"先缩后转"）
let e = -(cos(.pi * t) - 1) / 2

// 旋转：每次 120°
let rotY = -faceAngle[from] - delta * e

// 缩放：由当前朝向**推导**，不是独立曲线
let relToEdge = (rotY - faceBase) + .pi / 3
let narrow = (abs(cos(relToEdge)) - 0.5) / 0.5   // 归一化到 [0,1]
let scale = 1 - 0.20 * narrow
let zOffset = -0.35 * narrow
```

**归一化那一步是关键**：三面均分 120°，面正对时 `|cos(60°)| = 0.5` 不是 0。
不归一化的话 `t=0` 时缩放就是 0.90，**循环起点会跳变**。

### 3.3 实测端点

```
t=0    转 -120°  缩放 1.000  Z  0.00
t=0.5  转 -180°  缩放 0.800  Z -0.35   ← 棱正对，最窄
t=1    转 -240°  缩放 1.000  Z  0.00
```

### 3.4 手势（复用现有边缘热区）

现有 `DoorStage` 已有 `edgeGrabWidth = 24` 的左边缘热区。
三棱柱需要**左右两个**：
- 左边缘左滑 → 上一个面
- 右边缘右滑 → 下一个面

**为什么不改全屏手势**：`DoorStage.swift:35` 的注释记录了历史决策 ——
全屏拖拽会抢 `NavigationStack` 的返回手势。边缘热区 24pt 正是为此设计的。

### 3.5 reduceMotion 降级（必须保留）

现有代码有完整降级：不挂 `rotation3DEffect`，只做交叉淡入 + 微缩放。
三棱柱**必须保持**这条路径，否则前庭敏感用户无法使用。

---

## 四、B 域：底部液态玻璃分组导航

### 4.1 为什么需要

21 个设置类页面（`MePage` / `SettingsView` / `BackupPage` / `KeysPage` / `FirmwarePage` / `GatewayPage` / `DonglesPage` / `SecurityCenterView` / `MemberWizardView` …）
塞进一个面会变成"入口列表"，又回到普通 App 的样子。

### 4.2 方案：浮动液态玻璃 Tab Bar

```
┌────────────────────────────┐
│  B 管家台                   │
│                            │
│  （分组内容滚动区）          │
│                            │
│   ╭──────────────────╮     │
│   │ 台账  设备  安全  ⋯ │     │  ← 液态玻璃浮动胶囊
│   ╰──────────────────╯     │
└────────────────────────────┘
```

**技术已有**：`AccessibilityKit.swift` 的 `axGlass(.capsule)` 内部就是
`content.glassEffect(.regular, in: Capsule())`，且有完整的降低透明度/高对比降级。

**分组建议**（5 组，每组 3–5 页）：

| 组 | 页面 |
|---|---|
| **台账** | KeysPage / AddKeyPage / AddFingerPage / CredentialStudio |
| **设备** | DevicePage / LockProfilePage / LocksPage / FirmwarePage / GatewayPage / DonglesPage / SyncTimeView |
| **成员** | MembersPage / MemberWizardView / MergeMembersView / MemberArchivedView |
| **安全** | SecurityCenterView / SecurityAuditView / SecurityDestroyView / SafemodeIntroView |
| **备份外观** | BackupPage / BackupView / BackupStudioView / ExportWizardView / RestoreWizardView / SettingsView / MePage |

### 4.3 与三棱柱的关系

B 域的**底部 Tab 是域内导航**，不参与三棱柱旋转。
三棱柱只负责 B ↔ D ↔ F 三个面之间的切换。

**层次**：
```
三棱柱（顶层，3 面）
  └─ B 面 ─→ 底部液态玻璃 Tab（5 组）─→ 页面
  └─ D 面 ─→ 门 + 锁
  └─ F 面 ─→ 数据可视化
```

---

## 五、F 域：仪表（锁数据 + 人的数据）

### 5.1 结构：顶部液态玻璃分段 + 海量数据可视化

```
┌────────────────────────────┐
│  ╭────────────╮            │
│  │ 这把锁 │ 这些人 │        │  ← 液态玻璃分段控件
│  ╰────────────╯            │
│                            │
│  （可视化区，见下）          │
└────────────────────────────┘
```

### 5.2 「这把锁」—— 锁的数据

| 可视化 | 数据源 |
|---|---|
| **24 小时热力环** | `StatsKit.hourBuckets`（静态） |
| **本周 vs 上周** | `StatModel.weekSummary()` `lastWeekDigest()`（实例） |
| **数据覆盖天数** | `StatsKit.coverageDays`（静态） |
| **闲置提醒** | `StatsKit.isIdleLock`（静态） |

### 5.3 「这些人」—— 人的数据

**这是本次方案里最有价值的发现**：`StatsKit` 已经有专门为「人」做的统计，
但**一个都没可视化**（现在只出现在导出 CSV 和文字摘要里）。

| 可视化 | 数据源 | 现状 |
|---|---|---|
| **成员开门次数排行** | `m.memberCounts(days:)` | 只有 CSV |
| **成员气泡图** | `m.memberBubbles(days:)` | 未使用 |
| **成员逐日活跃** | `m.memberDaily(days:)` | 未使用 |
| **今日谁来过** | `m.memberTodayCount(id:)` | 未使用 |
| **在家时长代理** | `m.homeProxyHours(from:to:)` | 未使用 |
| **凭证类型 × 成员** | `m.kindOwnerBreakdown()` | 未使用 |

**动作**：把这些做成 2–3 个可视化（不用全做，选最有力的）：

1. **成员时间线**：横轴 30 天，每个成员一条彩色带，色块密度 = 当天开门次数
2. **成员占比环**：本月开门次数按成员分，用成员色（`Member.color` 已有）
3. **今日在场**：谁今天开过门，头像 + 次数

### 5.4 海量数据的处理（你说的）

数据量大时不能一次画完。方案：

- **时间窗口降级**：30 天 → 7 天 → 今日，按数据量自动选
- **抽稀**：超过 200 个数据点时按小时聚合
- **分页加载**：成员时间线按月分页，横向滚动

---

## 六、实施路径（4 步，每步可回退）

### Step 1｜接刃锁体进首屏（零风险）

```swift
// DoorFront 加开关
@AppStorage("kf_use_3d_lock") private var use3DLock = false

if use3DLock {
    XLockBlade(isOpen: ..., isFailed: ..., isDeadbolted: ..., charge: ..., diameter: plateDiameter)
} else {
    LockPlate(...)   // 现有，保底
}
```

**验证**：CI 编译 + 你真机看效果。**不满意就关掉开关，零损失。**

### Step 2｜门 + 锁真实比例 + 触摸放大

- 加 `XGateDoor`（07 竖条阵列门，`MeshResource` 实现）
- 锁按 5.7% 门宽放置
- 点击锁体 3.2× 放大聚焦

### Step 3｜三棱柱替换双面翻转

- 新建 `DoorPrism.swift`
- `DoorRoot` 加开关切换
- **保留旧 `DoorStage`**，可回退

### Step 4｜三域划分 + B/F 面填充

- `DoorDomain` 改三值
- B 域：底部液态玻璃分组
- F 域：锁数据 + 人的数据可视化

---

## 七、必须记录的三个技术事实

### 7.1 液态玻璃 API 已可用且有降级

`AccessibilityKit.swift` 的 `GlassModifier`：
- 正常：`content.glassEffect(.regular, in: Capsule())`
- 降低透明度 / 高对比：降为实底 `XPalette.surface` + `hairlineStrong` 描边

**直接复用 `axGlass(.capsule)`，不要自己写 `glassEffect`。**

### 7.2 手势必须走边缘热区

`DoorStage.swift:35` 注释记录：全屏拖拽会抢 `NavigationStack` 返回手势。
`edgeGrabWidth = 24` 是为此设计的，三棱柱沿用。

### 7.3 刃锁体的三层已编译通过

`run #443 SUCCESS` 证明：
- `BladeGeometry.swift`（纯数学）✓
- `BladeMesh.swift`（MeshDescriptor 组装）✓
- `XLockBlade.swift`（9 零件 + 状态着色）✓

**但 `XLockBlade` 目前孤立无人引用** —— Step 1 就是把它接上。

---

## 八、风险与对策

| 风险 | 对策 |
|---|---|
| 3D 锁体真机效果不如预期 | Step 1 加开关，可随时关掉 |
| 三棱柱动画手感不对 | HTML 已实测六种，选定 C；真机再调时长 |
| 真实比例下锁太小 | 触摸放大 3.2×（你的方案） |
| B 域 21 页太挤 | 底部液态玻璃 5 组分组 |
| F 域数据量大卡顿 | 时间窗口降级 + 抽稀 + 分页 |
| 我看不到真机效果 | 每步都留回退开关，由你验证 |

---

## 九、不做的事（明确划界）

- ❌ 不做服务端 / 云同步（iCloud 只做文件选择器，方案 a）
- ❌ 不改锁的协议层（`ZKProtocol` 一行不动）
- ❌ 不做实时 3D 光照追踪（性能）
- ❌ 不做 iPad / Mac 适配
- ❌ 不做多语言

---

## 九点五、API 核实记录（15 条逐条查过）

方案初稿引用了 15 个 API，我写了个脚本逐条在源码里查，**6 条是错的**：

| 引用 | 实际 | 修正 |
|---|---|---|
| `StatsKit.memberCounts` | `StatModel.memberCounts` | 实例方法 |
| `StatsKit.memberBubbles` | `StatModel.memberBubbles` | 实例方法 |
| `StatsKit.memberDaily` | `StatModel.memberDaily` | 实例方法 |
| `StatsKit.memberTodayCount` | `StatModel.memberTodayCount` | 实例方法 |
| `StatsKit.homeDurationProxy` | `StatModel.homeProxyHours` | 名字也不同 |
| `StatsKit.kindOwnerBreakdown` | `StatModel.kindOwnerBreakdown` | 实例方法 |

正确的 9 条：`hourBuckets` / `coverageDays` / `weekSummary` / `isIdleLock` /
`axGlass` / `glassEffect` / `Member.color` / `edgeGrabWidth` / `DoorDomain`。

**这条记录的用意**：我上一轮就是因为"凭记忆写 API"在 CI 连挂两次
（`generateCylinder(radialSegments:)`、`SimpleMaterial.emissiveColor`）。
方案阶段也犯了同样的错，靠脚本查出来了。**写方案的每个 API 引用都要核。**

---

## 十、下一步

**Step 1 可以立刻开始**，因为它：
- 不碰导航结构（零回归风险）
- `XLockBlade` 已编译通过
- 加开关，可回退
- 能立刻让你看到 3D 锁体的真机效果

**如果 Step 1 的效果你不满意，整个 3D 方向要重新考虑 —— 后面三步都建立在它上面。**
