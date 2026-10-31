# WARNINGS · 编译告警分类与评估

> 数据来源：`origin/ci-log:build.log`（commit `2991cbe`，run `41207309291`，BUILD SUCCEEDED / errors=0）。
> 统计口径：`: warning:` 行，剔除 Xcode 的镜像回显行。
> 结论：**0 error；89 条 warning（1 条项目级 + 88 条源码 warning，与 BUILD-FIX-2 记录的 88 条一致），去重后 84 个唯一位置。**
> `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO` 且语言模式为 Swift 5，所以它们**不阻断构建**；但 `SWIFT_STRICT_CONCURRENCY = complete` 已开，切到 Swift 6 时其中大部分会变成 error（见评估列）。

## 一、按类型汇总

| 类型 | 条数（去重后） | 典型告警 | 风险评估 | 修法 |
|---|---:|---|---|---|
| 并发 / Swift 6 迁移 | 62 | `call to main actor-isolated initializer 'init()' in a synchronous nonisolated context`（43 条，集中在 `App/Shell/Destinations.swift`） | **中**：当前 Swift 5 不阻断；切 Swift 6 会成片变 error。`Destinations.view(for:)` 是非隔离静态函数里构造 @MainActor View，目前只在主线程被调用，不会现场崩 | 给 `Destinations.view(for:)` 标 `@MainActor`；`Router` / `SettingsStore` / `RecordsOverlay` / `RecordsRoute` 标 `@MainActor`；闭包捕获改 `[weak self]` 或 `@Sendable` 安全捕获 |
| 未使用值 / 变量 | 19 | `result of call to 'execOk(_:needToken:retries:)' is unused`（13 条） | **低**：不改变行为；但 `execOk` 的返回值被丢弃说明这些调用点不检查回执码 —— 需逐个确认是“确实不需要”还是漏判 | 确认后改 `_ = try await execOk(...)` 或检查返回值；其余 `let x` 未使用改 `_` |
| Deprecated（iOS 26 API） | 2 | `'main' was deprecated in iOS 26.0`（`CaptureShield.swift` 2 处） | **低**：仅未来 SDK 移除风险；当前功能正常 | 改 `UIScreen.main` → 由 `view.window?.windowScene?.screen` 或 traitCollection 取；短期可保留 |
| 其他（项目级） | 1 | `'UIRequiresFullScreen' has been deprecated starting in iOS 26.0` | **低**：Info.plist 键被忽略，不影响竖屏锁定（`UISupportedInterfaceOrientations` 仍生效） | 从 project.yml/Info.plist 移除该键，或用 `UISupportedInterfaceOrientations` 表达 |

## 二、按文件 Top

| 文件 | 条数 | 主要类型 |
|---|---:|---|
| `App/Shell/Destinations.swift` | 43 | 并发 / Swift 6 迁移 |
| `App/Engine/LockServiceOps.swift` | 7 | 未使用值 / 变量 |
| `App/Design/Components/CaptureShield.swift` | 6 | Deprecated（iOS 26 API） |
| `App/Engine/LockServiceCredentials.swift` | 6 | 未使用值 / 变量 |
| `App/Shell/Router.swift` | 5 | 并发 / Swift 6 迁移 |
| `App/Features/Settings/SettingsParts.swift` | 4 | 并发 / Swift 6 迁移 |
| `App/Features/Records/RecordsModels.swift` | 2 | 并发 / Swift 6 迁移 |
| `App/Design/Components/ScreenAwake.swift` | 2 | 并发 / Swift 6 迁移 |
| `(project)` | 1 | 其他 |
| `App/Engine/AutoOpenKit.swift` | 1 | 未使用值 / 变量 |
| `App/Engine/CredentialOrgBatch.swift` | 1 | 未使用值 / 变量 |
| `App/Engine/CredentialOrgState.swift` | 1 | 并发 / Swift 6 迁移 |
| `App/Engine/FrameRedact.swift` | 1 | 未使用值 / 变量 |
| `App/Design/Components/Ledger.swift` | 1 | 未使用值 / 变量 |
| `App/LockKeeperApp.swift` | 1 | 未使用值 / 变量 |
| `App/Features/Door/SafeModeScreen.swift` | 1 | 未使用值 / 变量 |
| `App/Features/Settings/SettingsModel.swift` | 1 | 并发 / Swift 6 迁移 |

## 三、逐条明细（去重后 84 个唯一位置）

### 其他（1）

- `(project):0` — 'UIRequiresFullScreen' has been deprecated starting in iOS 26.0 and will be ignored in a future release. See the UIRequiresFullScreen documentation for more details. (in target 'LockKeeper' from project 'LockKeeper')

### 未使用值 / 变量（19）

- `App/Engine/AutoOpenKit.swift:419` — result of 'try?' is unused [#NoUsage]
- `App/Engine/CredentialOrgBatch.swift:57` — initialization of immutable value 'batchId' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]
- `App/Engine/FrameRedact.swift:30` — initialization of immutable value 'payloadBytes' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]
- `App/Design/Components/Ledger.swift:111` — initialization of immutable value 'cal' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]
- `App/LockKeeperApp.swift:182` — immutable value 'remaining' was never used; consider replacing with '_' or removing it [#NoUsage]
- `App/Engine/LockServiceCredentials.swift:56` — result of call to 'execOk(_:needToken:retries:)' is unused [#NoUsage]
- `App/Engine/LockServiceCredentials.swift:69` — result of call to 'execOk(_:needToken:retries:)' is unused [#NoUsage]
- `App/Engine/LockServiceCredentials.swift:87` — result of call to 'execOk(_:needToken:retries:)' is unused [#NoUsage]
- `App/Engine/LockServiceCredentials.swift:95` — result of call to 'execOk(_:needToken:retries:)' is unused [#NoUsage]
- `App/Engine/LockServiceCredentials.swift:207` — result of call to 'execOk(_:needToken:retries:)' is unused [#NoUsage]
- `App/Engine/LockServiceCredentials.swift:213` — result of call to 'execOk(_:needToken:retries:)' is unused [#NoUsage]
- `App/Engine/LockServiceOps.swift:104` — result of call to 'execOk(_:needToken:retries:)' is unused [#NoUsage]
- `App/Engine/LockServiceOps.swift:127` — result of call to 'execOk(_:needToken:retries:)' is unused [#NoUsage]
- `App/Engine/LockServiceOps.swift:134` — result of call to 'execOk(_:needToken:retries:)' is unused [#NoUsage]
- `App/Engine/LockServiceOps.swift:139` — result of call to 'execOk(_:needToken:retries:)' is unused [#NoUsage]
- `App/Engine/LockServiceOps.swift:144` — result of call to 'execOk(_:needToken:retries:)' is unused [#NoUsage]
- `App/Engine/LockServiceOps.swift:155` — result of call to 'execOk(_:needToken:retries:)' is unused [#NoUsage]
- `App/Engine/LockServiceOps.swift:167` — result of call to 'execOk(_:needToken:retries:)' is unused [#NoUsage]
- `App/Features/Door/SafeModeScreen.swift:104` — value 'st' was defined but never used; consider replacing with boolean test [#NoUsage]

### Deprecated（iOS 26 API）（2）

- `App/Design/Components/CaptureShield.swift:10` — 'main' was deprecated in iOS 26.0: Use a UIScreen instance found through context instead (i.e, view.window.windowScene.screen), or for properties like UIScreen.scale with trait equivalents, use a traitCollection found through context. [#Dep
- `App/Design/Components/CaptureShield.swift:20` — 'main' was deprecated in iOS 26.0: Use a UIScreen instance found through context instead (i.e, view.window.windowScene.screen), or for properties like UIScreen.scale with trait equivalents, use a traitCollection found through context. [#Dep

### 并发 / Swift 6 迁移（62）

- `App/Design/Components/CaptureShield.swift:10` — main actor-isolated default value in a nonisolated context; this is an error in the Swift 6 language mode
- `App/Design/Components/CaptureShield.swift:20` — capture of 'self' with non-Sendable type 'CaptureWatcher?' in a '@Sendable' closure [#SendableClosureCaptures]
- `App/Design/Components/CaptureShield.swift:20` — main actor-isolated property 'isCaptured' can not be referenced from a Sendable closure
- `App/Design/Components/CaptureShield.swift:20` — main actor-isolated class property 'main' can not be referenced from a Sendable closure
- `App/Engine/CredentialOrgState.swift:61` — converting non-Sendable function value to '@MainActor @Sendable @convention(block) () -> Void' may introduce data races
- `App/Shell/Destinations.swift:11` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:12` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:13` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:14` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:15` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:17` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:18` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:19` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:20` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:21` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:22` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:23` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:24` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:25` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:26` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:27` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:28` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:29` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:30` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:33` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:34` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:35` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:36` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:37` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:38` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:39` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:41` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:42` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:43` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:44` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:46` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:47` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:48` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:49` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:51` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:52` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:53` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:54` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:55` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:56` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:57` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:58` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Shell/Destinations.swift:59` — call to main actor-isolated initializer 'init()' in a synchronous nonisolated context [#ActorIsolatedCall]
- `App/Features/Records/RecordsModels.swift:170` — static property 'shared' is not concurrency-safe because non-'Sendable' type 'RecordsOverlay' may have shared mutable state; this is an error in the Swift 6 language mode [#MutableGlobalVariable]
- `App/Features/Records/RecordsModels.swift:330` — static property 'shared' is not concurrency-safe because non-'Sendable' type 'RecordsRoute' may have shared mutable state; this is an error in the Swift 6 language mode [#MutableGlobalVariable]
- `App/Shell/Router.swift:232` — capture of 'self' with non-Sendable type 'Router' in a '@Sendable' closure [#SendableClosureCaptures]
- `App/Shell/Router.swift:233` — capture of 'self' with non-Sendable type 'Router' in a '@Sendable' closure [#SendableClosureCaptures]
- `App/Shell/Router.swift:234` — capture of 'self' with non-Sendable type 'Router' in a '@Sendable' closure [#SendableClosureCaptures]
- `App/Shell/Router.swift:235` — capture of 'self' with non-Sendable type 'Router' in a '@Sendable' closure [#SendableClosureCaptures]
- `App/Shell/Router.swift:236` — capture of 'self' with non-Sendable type 'Router' in a '@Sendable' closure [#SendableClosureCaptures]
- `App/Design/Components/ScreenAwake.swift:11` — main actor-isolated property 'isIdleTimerDisabled' can not be mutated from a nonisolated context
- `App/Design/Components/ScreenAwake.swift:11` — main actor-isolated class property 'shared' can not be mutated from a nonisolated context
- `App/Features/Settings/SettingsModel.swift:154` — static property 'shared' is not concurrency-safe because non-'Sendable' type 'SettingsStore' may have shared mutable state; this is an error in the Swift 6 language mode [#MutableGlobalVariable]
- `App/Features/Settings/SettingsParts.swift:322` — capture of 'keyPath' with non-Sendable type 'ReferenceWritableKeyPath<SettingsStore, Value>' in a '@Sendable' closure [#SendableClosureCaptures]
- `App/Features/Settings/SettingsParts.swift:323` — capture of 'keyPath' with non-Sendable type 'ReferenceWritableKeyPath<SettingsStore, Value>' in a '@Sendable' closure [#SendableClosureCaptures]
- `App/Features/Settings/SettingsParts.swift:330` — main actor-isolated property 'trialGuard' can not be referenced from a Sendable closure
- `App/Features/Settings/SettingsParts.swift:332` — main actor-isolated property 'trialGuard' can not be mutated from a Sendable closure

## 四、评估与建议

1. **不要求清零**：本轮目标是把「88 条 warning」从一句模糊数字变成可核对的分类账；当前构建 0 error，warning 不阻断发布。
2. **优先级最高的是一类**：并发/Swift 6 迁移中的 43 条 `main actor-isolated initializer` 集中在 `Destinations.swift`。这是「给 `view(for:)` 标 `@MainActor`」一次就能消掉 43 条的低风险改动；但它会牵动 `Router` 的调用点，建议单独一轮做并跑 CI。
3. **第二优先是 13 条 `execOk` 返回值未使用**：需确认不是漏判回执码（本仓历史上出现过「不看 rc 就报成功」的缺陷，见 LockServiceCredentials 的 0A alias 注释）。若确认不需要，改成 `_ =` 只是消除噪声；若需要，是功能缺陷。
4. **不建议**为清零而加 `@preconcurrency` / `nonisolated(unsafe)` 掩盖并发告警 —— 那会把 Swift 6 迁移的雷留到更晚。
5. 完整原始日志：`origin/ci-log:build.log`（随每次 CI 更新）。
