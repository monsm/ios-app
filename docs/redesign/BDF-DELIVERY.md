# BDF 架构交付验证

> 2026-10-21。M1–M5 完成后的端到端验证记录。
> 每条结论都有代码依据，不写推测。

---

## 一、架构链路（已逐层核实）

```
LockKeeperApp
  WindowGroup
    RootView().environmentObject(app)        ← 全局唯一注入点（第 14 行）
      rootChrome
        rootCore
          rootGroup
            mainTabsChrome                   ← 名字是历史遗留，曾装 TabView
              DoorRoot()
                DoorPrism(face: $face)
                  ├─ faceB  → ManagerFace      B 管家台
                  ├─ faceD  → DoorFront        D 就近
                  └─ faceF  → DashboardFace    F 仪表
```

### 关键事实

| 事实 | 依据 |
|---|---|
| `TabView` 已不存在 | 全文件搜索无 `TabView {` |
| `environmentObject` 只有一个注入点 | 全文件仅第 14 行 |
| `mainTabsChrome` 只剩 `DoorRoot()` | 第 963–964 行 |
| `DoorPrism` 三面都挂真实组件 | DoorRoot 第 65–74 行 |

`mainTabsChrome` 是历史遗留命名（曾装 TabView），现在里面就是 `DoorRoot`。
**没有改名**，因为它是 21 道闸门里若干处检查的锚点，改名要连带改闸门。

---

## 二、三个域的落地

| 面 | 组件 | 内容 |
|---|---|---|
| B 管家台 | `ManagerFace` | 底部液态玻璃 5 组：台账/设备/成员/安全/备份外观 |
| D 就近 | `DoorFront` → `XGateDoor` | 07 竖条门 + 刃锁体，真实比例，点锁放大 |
| F 仪表 | `DashboardFace` | 顶部液态玻璃双段：这把锁 / 这些人 |

---

## 三、D 域六轮修复记录

这些全是"看不到真机"导致的错误，靠数值复算逐个抓出：

| # | 问题 | 修法 | 性质 |
|---|---|---|---|
| 1 | 呼吸动画从未发生 | `drag` → `turn`（动画驱动） | **功能** |
| 2 | 门溢出屏幕 33pt | `min(byWidth, byHeight)` | 布局 |
| 3 | 锁被横向拉伸 5 倍 | `diameter` → `size: CGSize` | **几何** |
| 4 | 热区把锁撑成正方形 | `frame(minWidth:)` → `overlay` | 布局 |
| 5 | 遮罩跟着锁一起放大 | `background` → `ZStack` 顶层 | **功能** |
| 6 | 冗余裁剪 | 删 `.clipped()` | 性能 |

### 其中最严重的两条

**① 呼吸动画从未发生**

`drag` 只在手指按住时非零，松手归零；`step()` 完全不动 `drag`。
所以 `breathScale` 恒为 1.0000。

这和 R3 那轮用户说"为什么我看到没任何变化"是同一类问题：
HTML 原型用 `t`（动画时间）驱动，Swift 里换成了 `drag`，但 `drag` 不是动画时间。

**② 遮罩跟着锁放大 → "点其他位置归位"根本点不到**

`.background` 挂在 `.scaleEffect(3.2)` 之后，遮罩尺寸 = 锁 × 3.2。
用户明确要求的功能用不了。

---

## 四、数值验证（脚本复算，非目测）

### 三棱柱呼吸

| drag/turn | 角度 | 缩放 |
|---|---|---|
| 0 | 面正对 | 1.0000 |
| 0.5 | 棱正对 | **0.8000** |
| 1 | 下一面正对 | 1.0000 |

四条切换路径（D→F / F→B / D→B / B→F）起点终点模 360° 全部同向。

### D 域尺寸

| 机型 | 门 | 锁 | 锁宽高比 |
|---|---|---|---|
| iPhone SE | 250×547pt | 18.0×90.0pt | 1:5.00 |
| iPhone 15 | 334×732pt | 19.1×95.5pt | 1:5.00 |
| 15 Pro Max | 371×812pt | 21.2×105.9pt | 1:5.00 |
| iPad mini | 463×1013pt | 26.4×132.1pt | 1:5.00 |

### 3.2× 放大

| 机型 | 放大后锁宽 | 占屏宽 | 占屏高 |
|---|---|---|---|
| iPhone SE | 58pt | 15% | 43% |
| iPhone 15 | 61pt | 16% | 36% |
| 15 Pro Max | 68pt | 16% | 36% |

---

## 五、RealityKit API 验证状态

累加式探针 `RealityAPIProbe.swift`，5 个区块：

| 区块 | 内容 | 结论 |
|---|---|---|
| 1 | RealityView 与几何生成器 | run #417/#420 SUCCESS |
| 2 | MeshDescriptor 手搓多边形 | run #439 SUCCESS |
| 3 | SimpleMaterial 真实能力 | run #442 FAILURE → 结论 |
| 4 | 实体层级与变换 | run #458（XLockBlade 在用） |
| 5 | typealias vs .self | run #442 FAILURE → 结论 |

**累计：✓ 9 条 / ✗ 5 条 / 待验证 0 条。**

### 确认不支持的（保留注释作为证据）

- `SimpleMaterial.emissiveColor` —— 不存在
- `MeshResource.generateCylinder(radialSegments:)` —— 无段数参数
- `RealityViewContent` 显式类型标注 —— 不在公开作用域，必须让编译器推断
- 不能 `let G = X.self` —— 拿不到嵌套类型，必须 `typealias`

---

## 六、M5 形态评估结论

详见 `docs/redesign/M5-SHAPE-AUDIT.md`。

要点：**"52 页独立构思" ≠ "52 页全部重写"**。

用 git 基线 `f7d8c57` 核对证明：
`ScrollView + XPanel + xScrollLift` 在本次重构**开始前就存在**，
是本仓既有约定（30 个文件用 XPanel，只有 2 个用 List）。

| 类别 | 数量 | 处理 |
|---|---|---|
| A. 形态雷同且该改 | 5 页 | ✅ 重做（五种不同形态） |
| B. 形态本就合适 | 22 页 | ❌ 不动 |
| C. 畸形结构 | 3 处 Form | ✅ 全仓清零 |
| D. 新增页面 | 3 页 | ✅ M3/M4 做的 |

**差点犯的错**：原计划把 `AddLockPage` 改成步骤条，
核查发现它已有 `spine`（三步圆点 + 三态着色 + checkmark + 脉冲 + reduceMotion 降级），
比我要做的更完整。

---

## 七、本地闸门

23 道本地 / 40 道 CI。

新增 1 道：`tools/declcheck.js` —— 属性包装器死变量检测。
由来：我用 `splice` 替换视图代码时删掉了三个 `@AppStorage` 声明，引用还在，
`swiftcheck`（括号）和 `swiftlint`（臆造符号）都没发现。

**另两个尝试失败并被删除的闸门**（记录教训）：
- `refscheck.js` 未声明标识符 → 误报 11 处（`if let` 绑定、闭包参数）
- `enumcase.js` enum case 归属 → 误报 13 处（同文件多 enum 无法判断）

规律：**文本级检查能做对，语义检查需要类型系统 → 交给 CI 编译器。**

---

## 八、尚未完成 / 已知限制

### 需要真机确认的

- 3D 锁体的实际观感（材质/光照 —— three.js ACES vs RealityKit PBR 不同）
- 三棱柱的手感（时长、透视强度、边缘拖拽跟手度）
- 液态玻璃在真机上的表现

### 未做的事

- 52 页里的 22 页按评估结论**保持原样**（这是判断，不是遗漏）
- 部分页面（`ExportCenter` 2470 行等大页面）只做了核查，未改形态

### 验证方式说明

本机**无 Swift 编译器、无 Apple 文档访问**。
所有编译验证靠 CI，所有数值验证靠 JS 复算 Swift 的算式。
**渲染观感无法在本机验证。**
