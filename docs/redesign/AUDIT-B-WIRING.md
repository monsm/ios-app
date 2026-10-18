# AUDIT-B · 门面接线点核查（PART1 §9「照抄既有调用」逐条对账）

> 取证方式：`grep -n` + 定点行段读取；未通读大文件。所有行号为当前工作树实测。
> 结论先行：**§9 共 8 行 —— 实测正确 2 行（:255 手势档位、:257 玻璃）；需改写 5 行（:254/:256/:258/:259/:260）；:261 是"新写"无事实错误。另 §1:26 / §8:246 / §12:329 各有一处符号或方向错误。** 逐条见下。

---

## 1. 开锁调用链（最要命的一条）

**结论：`UnlockDial` 里没有任何 `LockService` 调用。** 它是纯视图，按到底只调一个闭包。

| 环节 | 真实符号与签名 | 文件:行号 |
|---|---|---|
| 圆盘按钮回调（唯一出口） | `var action: () -> Void` —— 注释原话「手势确认 / VO 直开 → AppState.requestUnlock」 | UnlockDial.swift:323 |
| 长按计时 | `private func beginHold()`；`holdTask = Task { @MainActor in … }`，每 16ms 推进 `holdProgress`，`p >= 1` 时调 `fire()` | UnlockDial.swift:833-852（fire 调用在 :850） |
| 按下完成 | `private func fire()`：`guard !isBusy, bleReady, !firedThisTouch`(865) → 129 暂缓分支(868-877) → `firedThisTouch = true`(879) → `stopHold()`(880) → **`action()`(:886)** | UnlockDial.swift:864-887 |
| 其它 action 触发点 | `:493`（无障碍/VO 直开）、`:778`（上滑确认） | UnlockDial.swift:493,778 |
| action 实参（设备页） | `action: { dialAction() }`；`private func dialAction()` | DeviceHomeView.swift:1250 / 1357 |
| action 实参（专注页） | `action: { app.requestUnlock() }` | DeviceHomeView.swift:2476 |
| **正确照抄点** | `func requestUnlock()`（296 只读闸 491 · 244 去重 1.2s 508 · 250 二次开锁闸 514 · → `startUnlock()` 518） | LockKeeperApp.swift:488-519 |
| 真正下发 | `try await lock.ensureConnected(mac: kc.mac)` → `let rc = try await lock.unlock(mac: kc.mac, pinDec: chosenPin(kc))` | LockKeeperApp.swift:594,599 |
| 服务层入口 | `func unlock(mac: String? = nil, pinDec: String? = nil) async throws -> Int`（内部发 cmd04，返回 rc：0 成功 / 22 双验） | LockService.swift:447-461 |

**❌ 必须修正**：§9 写「现有 `LockService` 的解锁入口（`UnlockDial` 里既有调用点，照抄参数）」—— 照抄不到，`UnlockDial` 只调 `action()`。
新门面**不许直接调 `LockService.shared.unlock(…)`**：那会绕过 296 只读 / 244 去重 / 250 二次开锁三道闸（LockKeeperApp.swift:489-517 注释明确说「这几条侧门全汇到这一个入口」）。接线一律走 `app.requestUnlock()`。

## 2. 开锁失败 rc 文案

| 项 | 真实符号 | 文件:行号 |
|---|---|---|
| 人话直读（推荐） | `StatusParser.rcFriendly(_ rc: Int) -> String`（= `rcHint` ?? `rcMessage`） | StatusParser.swift:181 |
| 「该怎么办」层 | `StatusParser.rcHint(_ rc: Int) -> String?` | StatusParser.swift:166 |
| 「是什么」层 | `StatusParser.rcMessage(_ rc: Int) -> String`；表 `static let rcMsg: [Int: String]` | StatusParser.swift:162 / 154 |
| 实际消费 | `lastMsg = StatusParser.rcFriendly(rc)`（84 人话直读）→ `unlockState = .failed(lastMsg)` | LockKeeperApp.swift:613 → :636 |

**⚠ 修正**：§9 只写「`StatusParser` 的 rc 文案表」——表是数据，门面要的是**函数**；写清 `rcFriendly(rc)`。

## 3. 连接状态（已连接 / 未连接 / 连接中）

| 项 | 真实符号 | 文件:行号 |
|---|---|---|
| 三态枚举 | `enum LinkState: Equatable { case ready, connecting, down }`，`.name` 给中文（已连接/握手中/未连接） | LinkSenseKit.swift:13-14 / 15-20 |
| 数据源 | `LinkSense.shared.linkState`，类型 `LinkState`；`LinkSense` 是 `final class … ObservableObject` + `static let shared` | LinkSenseKit.swift:28-29 / 68 |
| 口径（本次关键） | `ready` 判据 = `lockSvc.connectedMAC == app.currentMac`（注释原话「连着的必须是当前这把」） | LinkSenseKit.swift:67-73 |
| 圆盘现在收的 | 布尔 `connected:`/`bleReady:`（传 `bleOn`/`btReady`）+ `rssi: LinkSense.rssiFor(app.currentMac)` | DeviceHomeView.swift:1244-1245,1249 |

**❌ 修正**：`linkState` 是**计算属性、不是 `@Published`**；视图要跟随刷新必须 `@ObservedObject var sense = LinkSense.shared`（RootView:1048 就是这个写法）。别自己判 `LockService.shared.connectedMAC` 造第二套口径。

## 4. 电量

| 项 | 真实符号 | 文件:行号 |
|---|---|---|
| **推荐（单点）** | `BatteryCare.faceText(BatteryCare.facePct(mac, live: app.status?.powerLevel ?? -1))` | DeviceHomeView.swift:2473 |
| 计算属性 | `BatteryCare.facePct(_ mac: String, live: Int) -> Int`；`static func faceText(_ p: Int) -> String` | BatteryCare.swift:162 / 165 |
| 实时值 | `app.status?.powerLevel`（`@Published var status: LockStatus?`；字段 `powerLevel: Int = -1`，-1 = 未知） | LockKeeperApp.swift:64 · StatusParser.swift:11 |
| 快照兜底 | `DB.readStatus(mac)?.powerLevel ?? -1`，已在 `displayPct` 内处理 | BatteryCare.swift:109 |
| 设备页包装（可直接抄） | `private func batteryText(for kc: Keychain) -> String` / `batteryPct(for:)` | DeviceHomeView.swift:2299-2301 / 2294-2297 |

**⚠**：门面别直接读 `app.status`，会漏掉「本机缓存读数 vs 实时读数」那套溯源（BatteryCare.swift:99-109 有解释）。

## 5. 上次开锁时间

**结论：本机没有「上次开锁时刻」的持久键。** `grep kf_open|lastOpen|kf_unlock_last` 无存储命中。

| 可得来源 | 符号 | 文件:行号 | 性质 |
|---|---|---|---|
| 内存（private） | `private var lastUnlockSuccessAt: Date?`（250 判定用，成功时写入） | LockKeeperApp.swift:378 / :953 | **private，外部读不到** |
| 可持久读 | `LockUsage.lastOpenAt: String`（最近一次开门，由日志缓存推出） | LockStats.swift:269（推导 325-326） | 需 `LockStats.usage()` 全量 map（LockStats.swift:309） |
| 底层表 | `DB.readLogs(mac)` ← `kf_logcache_<mac>` | Store.swift:677 / 661 | 单锁日志，≤~300 条 |

**❌**：门面若要显示「上次开锁」，**不许自造键名**；用 `LockStats.usage()` 里的 `lastOpenAt`（空串 = 未记录），或明确申报「新增键」并走 `tools/keydead.js` 台账。

## 6. 触觉

| 档 | 真实调用形式 | 文件:行号 |
|---|---|---|
| 过程（light） | `DS.Haptics.tick.impactOccurred()` | DesignSystem.swift:256 |
| 动作（medium） | `DS.Haptics.trigger.impactOccurred()` | DesignSystem.swift:257 |
| 结果 | `UINotificationFeedbackGenerator().notificationOccurred(.success/.warning/.error)` | LockKeeperApp.swift:959 / 607 / 638 |
| **第四种（§9 漏了）** | SwiftUI 原生 `.sensoryFeedback(…)` | LockKeeperApp.swift:1401 · UnlockDial.swift:597,607 · DeviceHomeView.swift:246,727 |

**❌ 修正**：§9 写「**全 App 只允许这三档**」与事实不符 —— `.sensoryFeedback` 已在 3 个文件 5 处使用（`.sensoryFeedback(.selection, trigger:)` / `.sensoryFeedback(trigger:) { old, new in … }`）。
**⚠ 编译级坑**：`enum Haptics` 带 `@MainActor`（DesignSystem.swift:254），`tick`/`trigger` 是 `static let` 生成器实例；在非主 actor 上下文（如 `ButtonStyle.makeBody`）调用会编译错。门面的触觉调用必须留在视图/主 actor 里。

## 7. 动效降级档位：新文件**读不到** `DS.Motion.tier`

| 事实 | 证据 |
|---|---|
| `DS.Motion.tier` 是 `private static var tier: String` | DesignSystem.swift:286 |
| 公开的是**成品令牌**（各自内部 switch tier）：`summon`/`fling`/`quick`/`standard`/`soft`/`exit` | DesignSystem.swift:299 / 308 / 315 / 322 / 329 / 336 |
| 档位原始值可读（不含降级） | `DB.store.getString("kf_motion")`，白名单 `calm/standard/lively` | DesignSystem.swift:291-292 |
| 降级的两个额外输入 | `AXFlags.reduceMotionSnapshot`(285) · `BatteryCare.appLowBattery`(290) | DesignSystem.swift:285,290 |
| `kf_motion` 写入点 | `applyAppearance { DB.store.set("kf_motion", key) }` | LockKeeperApp.swift:735 |

**结论**：新文件**没有任何公开入口**读到"已含 reduceMotion 与低电量"的档位。两条合规做法：
① 新增 `DS.Motion.doorSwing` 令牌（私有 `tier` 仍可读，因为**同文件内**）—— 落点：`enum DS → enum Motion {`（DesignSystem.swift:106 → 280）内、`exit` 之后、`}`(:343) 之前，即 **DesignSystem.swift:342 附近**；
② 门面若要自己判档，必须**同样**读 `AXFlags.reduceMotionSnapshot` + `BatteryCare.appLowBattery` + `kf_motion` 三处并保持同优先级（286-290），否则等于把降级规则实现第二遍（295-296 注释明令禁止）。

**❌ §12 的方向写反了**：`doorSwing` 「从 `tokens.json` 生成」不成立 —— `ios-app/tools/layout-replica/tokens.json` 是 `build.js:81` 从 DesignSystem 反向导出的**产物**；`design-system/` 目录与 `tools/gen-tokens.js` 在本仓**不存在**（只在 PART0/DECISIONS/MASTER-PLAN 里被规划）。

## 8. 根容器接 ZStack：具体改法

位置：`rootGroup`（LockKeeperApp.swift:1311-1324），最内层现有 `Group`(:1312)。§12「`rootGroup`（现有 Group，`:1312`）」**正确**。

**改前**（1311-1324，原样）：
```swift
@ViewBuilder
private var rootGroup: some View {
    Group {
        if !Onboarding.allDone && !app.onboardingFinished {
            OnboardingView(onExit: { app.onboardingFinished = true })
                .environmentObject(app)
        } else {
            mainTabsChrome
        }
    }
}
```

**改后**（≤20 行，只动 else 分支）：
```swift
@ViewBuilder
private var rootGroup: some View {
    Group {
        if !Onboarding.allDone && !app.onboardingFinished {
            OnboardingView(onExit: { app.onboardingFinished = true })
                .environmentObject(app)
        } else {
            ZStack {                        // 本轮新增：门面在底，主界面在顶
                LockFaceView()              // 层级 1（新）
                mainTabsChrome              // 层级 2（原样，其内部一行不改）
                    .opacity(faceOpen ? 1 : 0)
                    .allowsHitTesting(faceOpen)
                    .accessibilityHidden(!faceOpen)
            }
        }
    }
}
```

- **不会**触发 type-check 超时：`rootGroup`/`rootCore`/`rootChrome` 三个 `@ViewBuilder` 本就是为此拆出来的（:1309/:1326/:1355 注释），`body` 只有一行 `rootChrome`（:1305-1307）。但**门面相位编排不要内联进 rootGroup**，放进 `LockFaceView.body`（同仓先例：:1466 / :1505 / :1529 都是"内联即超时"）。
- **❌ §1 层级图里的「3. Sheets / fullScreenCovers ← 现有 CoverRegistry」是幻觉符号**：全仓 `grep CoverRegistry` = **0 命中**（唯一命中是 PART1:26 自己）。现有 cover 挂在：`mainTabs` 的 `.fullScreenCover{showGuestGate}`(:1246-1249) 与 `.sheet{showAmbientList}`(:1252-1255)、`mainTabsChrome` 的 `.modifier(MomentLayer())`(:1270) —— 它们都在 `mainTabsChrome` 之内，随层级 2 一起被门盖住，**不需要也不能新造 CoverRegistry**。
- **⚠ §1 说「靠 opacity/scale 显隐，不许用 if 插入/移除主界面」—— 正确且必须保留**（:1313 的 `if` 只切引导/主界面，与门无关）。

## 9. 锁体直径：`DS.Metric.dial` 新文件**可以**直接读

| 事实 | 证据 |
|---|---|
| `enum DS {` —— 顶层，**无 `private`** | DesignSystem.swift:106 |
| `enum Metric {` —— 嵌套 internal | DesignSystem.swift:152 |
| `static var dial: CGFloat` —— `static`（var，非 private），读 `kf_dial_size` 160/176/200，越界回落 176 | DesignSystem.swift:153-156 |

**结论**：`App/Core/LockFaceStyle.swift` 与 `enum DS` 同 module ⇒ **`DS.Metric.dial` 可直接读**，§2 第 48 行的映射（160→220 / 176→240 / 200→272，再 `min(…, screenW*0.68)`）可以照写。
**⚠ 反向提醒**：同层级的 `DS.Motion.tier` 是 `private`（:286）就读不到 —— **可见性不能靠"看它像不像 public"推断，两者在同一文件里却一公一私**。

## 10. 皮肤持久化：`LockProfile` **不存在**

| 事实 | 证据 |
|---|---|
| ❌ 全仓无 `LockProfile` 类型；只有视图 `LockProfileView` | Sheets.swift:1289（视图）· Destination.swift:53 `case lockProfile = "LockProfileView"` |
| ✅ 真实 per-lock 元数据 | `struct LockMeta: Codable` | LockStats.swift:16 |
| 读 | `LockArchive.meta(_ mac: String) -> LockMeta` → `DB.get(LockMeta.self, "kf_lockmeta_" + mac) ?? LockMeta()` | LockStats.swift:67-68 |
| 写 | `LockArchive.save(_ mac: String, _ m: LockMeta)` | LockStats.swift:70 |
| 现有字段 | `note / symbol / colorKey / place / batteryModel / batteryChangedAt / verifiedAt / lastConnectedAt / grp` | LockStats.swift:17-25 |

**加字段的正确三步（缺一步就是本仓反复出现过的那种"界面看不出异常却整本档案变空"）**：
1. 属性 + 默认值：`var skin: String = "wood"`（LockStats.swift:25 之后）；
2. `private enum CodingKeys: String, CodingKey` 加 `case skin`（现表在 :33-35）；
3. `init(from d: Decoder)` 内加 `skin = try c.decodeIfPresent(String.self, forKey: .skin) ?? "wood"`（现写法 :44-54 同款）。
**不许只加属性**：LockStats.swift:27-31 注释已写明「合成 Codable 对有默认值的属性**同样要求键存在**」，老数据会 `keyNotFound` → `DB.get` 返 nil → 昵称/色标/备注/换电日期全变默认值。
另：本类型**没有**自定义 `encode(to:)`（`grep 'func encode(to'` = 0 命中）⇒ 编码走合成，加 case 即可，无需同步改编码。

---

## PART1 必须修正的条目（按严重度）

| # | 位置 | 原文 | 改成 |
|---|---|---|---|
| 1 | §9 行 254 | 「`LockService` 的解锁入口（`UnlockDial` 里既有调用点，照抄参数）」 | 「调 `app.requestUnlock()`（LockKeeperApp.swift:488）；`UnlockDial` 只调 `action: () -> Void`(:323→:886)，**里面没有 LockService 调用**。禁止直连 `LockService.shared.unlock`（绕过 296/244/250 三道闸）；服务层入口签名 `func unlock(mac: String? = nil, pinDec: String? = nil) async throws -> Int`（LockService.swift:447）」 |
| 2 | §9 行 256 | 「降级判据 `DS.Motion.tier`（已含 reduceMotion 与低电量）」 | 「`tier` 是 **private**（DesignSystem.swift:286），新文件读不到。要么新增 `DS.Motion.doorSwing`（落点 :342 附近），要么读三处同源（`AXFlags.reduceMotionSnapshot` / `BatteryCare.appLowBattery` / `kf_motion`）」 |
| 3 | §12 行 329 | 「新增令牌（含 `doorSwing`）从 `tokens.json` 生成」 | 方向反了：`tokens.json` 是 `tools/layout-replica/build.js:81` 从 DesignSystem **导出**的产物；`design-system/tokens.json` + `tools/gen-tokens.js` **尚不存在**（属 L0 未动工） |
| 4 | §1 行 26 | 「3. Sheets / fullScreenCovers ← 现有 CoverRegistry」 | 删掉该符号：全仓 0 命中。改为「现有 cover 挂在 mainTabs(:1246/:1252) 与 mainTabsChrome(:1270)，随 mainTabsChrome 一起被门盖住」 |
| 5 | §8 行 246 | 「皮肤来源：`LockProfile.skin`（新增字段）」 | 「`LockArchive.meta(mac).skin`：给 `struct LockMeta: Codable`（LockStats.swift:16）加字段，**三步齐改**（属性 / CodingKeys / decodeIfPresent），否则老档案整本变空」 |
| 6 | §9 行 258 | 「全 App 只允许这三档」 | 补第四种：`.sensoryFeedback(…)`（LockKeeperApp.swift:1401、UnlockDial.swift:597/607、DeviceHomeView.swift:246/727）；并注明 `DS.Haptics` 带 `@MainActor`(:254) |
| 7 | §9 行 259 | 「失败文案：`StatusParser` 的 rc 文案表」 | 给函数：`StatusParser.rcFriendly(rc)`（StatusParser.swift:181，= rcHint(166) ?? rcMessage(162)），消费点 LockKeeperApp.swift:613 |
| 8 | §9 行 260 | 「门禁/深链 `requestRoute`/`pendingRoute`/`pendingMac` —— `LockKeeperApp.swift:133-181`」 | 入口应从 **:124**(`handleDeepLink`) 起；`requestRoute`:168 · `requestTab`:179 · `applyPendingRoute`:144 |

**已核对正确、不要改**：§9 行 257 `axGlass(_:)` / `axGlassCircle()` / `axGlassCapsule()` = AccessibilityKit.swift:388/393/400（实测一致）；行 255 `UnlockPrefs.mode/tapDirect/gestureHint` = UnlockDial.swift:7/12/17（枚举 5-24）；§2 行 48 `DS.Metric.dial` 可见性（见 §9）；§12 行 330 `rootGroup`(Group,:1312) 定位。
