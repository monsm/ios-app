# 闪退排查日志（真机报告「部分界面进去就闪退」）

> 我没法复现，也看不到崩溃栈。这份记录的是**查过什么、排除了什么**，
> 避免下一轮重复走同一条死路。

## 已排除（附判据）

| 假设 | 结论 | 依据 |
|---|---|---|
| 写操作触发无限重绘 | ✗ 排除 | `Store` 是普通 `final class`，**不是** ObservableObject，`set` 不发通知 |
| `@EnvironmentObject` 缺失 | ✗ 排除 | 4 个新页面的注入点全查过；`ManagerFace` 的 sheet 带 `.environmentObject(app)`，NavigationStack 会向下传递 |
| 手工 `UIHostingController` 丢环境 | ✗ 排除 | 全仓零处 |
| 设备页 `ForEach(0..<cap)` 负范围 | ✗ 排除 | 调用点有 `cap > 0` 守卫 |
| 字符串越界 `offsetBy: 11/16` | ✗ 排除 | `AlarmsPage` / `EventsPage` 两处都有 `guard full.count >= 16` |
| 删除的枚举值被强制解包 | ✗ 排除 | 全仓零处 `rawValue:)!`；`XMotion` 是 Animation 常量命名空间，不持久化 |
| `AuditLog.verifyChain()` 越界 | ✗ 排除 | 用 `enumerated()`，无下标 |
| 诊断页渲染期跑全库体检 | ✓ **已修** | 计算属性 → `.task` 算一次存 `@State` |
| 设备页渲染期跑全库读 | ✓ **已修** | 同上（`fwLag` / `bigDrops` / `fwSince`） |

## 未排除（最可能的两个方向）

### 1. 主线程被拖住 → 看门狗杀进程（不是真崩溃）
特征：**进去停住几秒再退出**（而不是白一下立刻退）。

剩下的嫌疑：**`DB.readLogs` 在 body 里**。它会解码整份日志数组，
而多页在计算属性里直接调它（`CarePage.periodCard`、`CareViews.careLedgerCard`、
`EventsPage.trace/collected`、`ExportCenter` 多处）。日志条数上规模后，每次重绘都解一遍。

### 2. 某个页面在"没有配锁"状态下假设了一把锁
特征：**首次安装、还没配对**时进某页必崩；配好锁之后就正常。

这条没验：`app.current` 为 nil 时各页的取数路径没有逐页走查过。

## 已经就位的取证手段

- `CrashGuard.markScreen` + `.trackScreen(...)`：8 个页面已挂
- 异常退出后，**下次启动的卡片直接写「崩在「X」」**
- 这条线索比任何静态分析都准 —— 只要再崩一次，就有答案

## 一个代价很高的教训（本轮）

我一度把 `DiagKit.integrity()` 的 `k.hasPrefix("kf.")` 判成"过时前缀"，
理由是"全仓 617 个键都用 `kf_`，只有 6 个用 `kf.`"。

**那个统计数的是代码里的字符串字面量，不是 UserDefaults 里的真实键。**

`Store.key(_:) = "kf." + k`，所以真实键是 **`kf.kf_theme`** —— 双重前缀。
原代码是对的，我差点把对的改错，还写了一段指控不存在 bug 的注释。

已撤回，并把"这里为什么是 kf. 而不是 kf_"写进了代码注释。

---

## 比我的推断更准的证据：系统崩溃日志

如果 App 还会闪退，iOS 自己记了完整的调用栈。拿到它，就不需要再猜。

### 路径（二选一）

**设备上**：设置 → 隐私与安全性 → 分析与改进 → **分析数据** →
  找以 `OfflineLock` 或 `LockKeeper` 开头的 `.ips` 文件（按日期，最新那个）

**或 Mac/PC 上**：连上 iPhone → 访达/资源管理器 → 设备 →
  「将分析数据拷贝到访达」→ 找同样的 `.ips` 文件

### 里面的关键几行

`.ips` 文件是 JSON + 正文两段。最有用的是：

- `"exception"` —— 崩溃类型：
  - `EXC_BAD_ACCESS` → 访问了已释放/越界的内存，**多半是强制解包或数组越界**
  - `EXC_CRASH (SIGABRT)` → Swift 运行时断言失败，**多半是 fatalError / 数组越界**
  - `EXC_CRASH (SIGKILL)` + `0x8badf00d` → **看门狗杀进程**，就是主线程卡太久
    （这正是我这几轮一直在修的那类）
- `"termination"` 里的 `Namespace: FRONTBOARD` / `Reason:` —— 如果写着
  `scene-update watchdog transgression`，就确认是主线程卡顿
- 正文里的 `Thread 0` 调用栈前十几行 —— 直接指出哪个类哪个方法

### 只要告诉我三样

1. `"exception"` 那一行
2. `"termination"` 里的 `Reason`（如果有）
3. 正文 `Thread 0` 最上面那个**不是系统库**的名字（通常是 `OfflineLock.xxx`）

有这三样，我不用再猜任何东西。

### 补充：如果崩溃发生在页面构造阶段

`onAppear` 面包屑可能来不及写（body 一求值就崩）。那种情况下 `.ips` 是唯一线索 ——
面包屑只能覆盖"已经出现在屏幕上之后"才崩的情况。
