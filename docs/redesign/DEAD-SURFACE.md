# 不可达的 API 面 —— 「假机制」清单

> 工具：[tools/deadfuncs.js](tools/deadfuncs.js)、[tools/statewrites.js](tools/statewrites.js)
> 记录时间：2026-10-22。这是**已知未完成**，不是待办清单里的猜测。

## 为什么要专门记这个

这几轮发现的最难缠的一类问题不是崩溃、不是报错，而是**代码看起来很努力但从不执行**：

- 它不违反任何闸门
- 它读起来完全正常
- 它甚至会互相引用，形成"看起来有功能"的闭环
- 唯一的症状是：**某个功能在界面上无法使用**

读代码很难发现，因为"它看起来对"。所以做了两个机器检查：

| 工具 | 查什么 |
|---|---|
| `tools/statewrites.js` | 声明了但从不被写入的 `@State` |
| `tools/deadfuncs.js` | 声明了但从不被调用的函数 |

## 当前结果

- `@State` 从不写入：**0 个**（已清零）
- `App/Core` + `App/Services` 里零调用函数：**183 个 / 1112 个声明**

## 已确认的几个「完整但够不着」的功能簇

> **2026-10-22 更新：星标与归档已接通。**
> 根因查明：`KeysPage.keyRow` **完全没有行级交互**（无点击、无滑动、无 NavigationLink），
> 凭证列表是纯只读展示 —— 所以 CredentialOrg 里那整套写入 API 都没有入口。
> 已在行上补长按菜单（置顶 / 归档 / 删除）与对应无障碍动作。
> 零调用函数由 183 降至 181，正好少掉 `toggleStar` 与 `setArchived`。

### 1. 凭证星标（原状：整块不可达）

```
toggleStar ─┬─> setStar
            └─> isStarred
```

三者互相引用，**外部零调用**。所以界面上没有任何地方能打星。
这不是"星标做得简陋"，是**星标根本没有入口**。

### 2. 凭证归档（原状：读侧铺满、写侧缺失）—— 现已接通

| | 状态 |
|---|---|
| `isArchived` 过滤 | **15 处**，散落在 CredentialOrg 与 QuickPool |
| `setArchived` 写入 | **零调用** |

归档集合恒为空 → 那 15 处过滤全部是空操作。
（已在 `CredentialOrg.setArchived` 上写明，避免后来者以为功能可用。）

### 3. 停用便签（内部自循环）

`markDisabled` / `DisableMark` / `disReasonKey` 只在 `CredentialOrg` 内部互相引用。
界面上「停用」的实际实现是**删除并入回收站**（`MemberCenterView:1402` → `DB.delPwd`），
与这套"停用便签"不是同一条路径。

## 堆积最多的文件

| 文件 | 零调用函数 |
|---|---|
| `App/Core/CredentialOrg.swift` | **42** |
| `App/Core/RecordSearch.swift` | 19 |
| `App/Core/StatsKit.swift` | 14 |
| `App/Core/Store.swift` | 13 |
| `App/Services/BackupStudioKit.swift` | 12 |

### 4. 夜间免打扰时段（可读可写，但改不了）

| 项 | 状态 |
|---|---|
| `nightFrom` / `nightTo` 读 | **活的** —— `StatsKit` 用它判定「深夜开门」 |
| `holidayExtendOn` 读 | **活的** —— 节假日自动延长结束时刻 |
| `setNightFrom` / `setNightTo` / `setHolidayExtend` | **零调用**，全仓无对应界面 |

所以这套配置永远停在默认 **22:00–06:00**。功能完整，用户改不了。
对夜班用户来说「深夜」不是 22 点 —— 这是真实缺口，不是洁癖。
已在这三个 setter 上写明接通方式。

### 5. `outOfWindow`（临时码越窗检测）—— 判定不可靠，**故意不接**

它遍历所有临时码，只要日志时间落在**任意一个**码的有效期外就标记。
但日志本身不说明用的是哪个码 —— 所以 A 码的有效使用会被 B 码的窗口判成越窗。
误报率高。**接进告警会造成狼来了效应，让用户忽略真告警。**
宁可不用，也不要一个会叫错的警报。

## 六、工具新增：自动找「有读无写」

`tools/deadfuncs.js` 现在会额外报一类最危险的死函数：

> **读侧在用、写侧零调用** —— 界面上有这个值，但用户改不了。

判据：零调用的 `setXxx` / `toggleXxx` / `markXxx` / `removeXxx` / `clearXxx` / `deleteXxx`，
去配对同名的读侧 `isXxx` / `hasXxx` / `getXxx` / `xxx`。读侧存在且被调用过 → 报出来。

**这个模式已经造成过两个整块不可达的功能**（应用锁、门锁解绑），所以值得自动化。

### 当前报出的 9 对（已逐个判断）

| 写函数 | 读侧 | 判断 |
|---|---|---|
| `Store.clearFailEvents` | `failEvents` | **真缺口** —— 开门失败事件会一直累积，清不掉 |
| `CredentialOrg.setEarlyExpireMin` | `earlyExpireMin` | **真缺口** —— 「提前多久提醒过期」写死默认值 |
| `CredentialOrg.setSeq` | `seq` | **真缺口** —— 排序序号读得到设不了 |
| `RecordSearch.setNote` | `note` | **真缺口** —— 事件备注读得到写不了 |
| `CredentialOrg.saveAlert` | `alert` | 待判断 |
| `CredentialOrg.saveSmartLists` | `smartLists` | 待判断（智能列表面板没有）|
| `CredentialOrg.saveDraft` | `draft` | 假阳性 —— `draft()` 只有声明，读侧也是死的 |
| `CredentialOrg.pushSearchHistory` / `removeSearchHistory` | `searchHistory` | 自闭环 —— 只被自己读，整块死码（与 EventsPage 用的 `RecordSearch.pushHistory` 是两套）|

**工具只负责指出候选，判断仍要人做。** 上表就是"工具输出 ≠ 结论"的例子：
9 条里 4 条真缺口、1 条假阳性、2 条自闭环、2 条待判断。

### 6. 锁端设置：一半能改、一半连读都读不到

| 设置 | 状态字段 | 写函数 | 结论 |
|---|---|---|---|
| 验证方式（A单验/B双验）| `verifyMode` | `setValidationMode` | ✅ **已可用**（SettingsView 有按钮 + 回读校验）|
| **静音** | `soundVolumn`（同 cmd18 同一字节）| `setSilent` | ✅ **本轮接通**（开关 + 回读校验）|
| 广播模式 | `broadcastMode` | 无 | 只读展示 |
| 临时密码 / ZOTP | `tempPwdMode`（securityLevel bit2）| `setZotp` | ⚠ 不接：cmd19 的字节语义与这个状态位**是否同一概念无法确认** |
| 自动落锁时间 | **无** | `setAutoLock` | ⚠ 不接：连"当前值"都读不到，写盲等于让用户按一个看不见的旋钮 |
| 防拆报警 | 疑似 `securityLevel` | `setDefence`（3 个参数）| ⚠ 不接：同上，且需要起止时段配置 |

**判断依据**：能双向确认的才接。状态读不回来的设置，接上去只能给用户一个
"我改了但不知道改成什么"的界面 —— 那比没有更糟。

## 七、孤立页面（定义完整、全仓零引用）

用「剔除注释后统计类名出现次数」扫了 87 个 View struct。

| 页面 | 行数 | 状态 |
|---|---|---|
| **EventsPage** | 620+ | ✅ **本轮已接通**（MePage → 事件记录）。它带着按天时间线、查询引擎、命名筛选视图、最近搜索、事件备注、失败记录清除、从门锁同步 —— 但一直没有任何入口 |
| DevicePage | 435 | 三域合并后设备域已并入 HomeConsole，本页与 HomeConsole 的信息重叠，**暂不接**（其中「锁内容量」是 HomeConsole 没有的，若以后需要可单独接）|
| DeviceHomeView | 230 | 同上 |

**教训**：重写版做好了却没接到导航上，用户看到的还是旧版。

### 可达性全扫（tools/reach.js）

从 `RootView` 做 BFS，边按「名字提及」建（宁高估可达）。
**修完 EventsPage / DevicePage 后：88 个 View 中 87 个可达**，
唯一不可达的是 `XLockBlade`（只被 API 探针引用，刻意保留）。

**所以「52 页重写都没接进去」这个猜测是错的 —— 只有 2 个。**

但这个工具本身修了四次才可信：

| 版本 | 问题 | 后果 |
|---|---|---|
| 1 | 只认 `Name(`，不认尾随闭包 `Name { }` | 8 个正常视图被误判孤立 |
| 2 | 只从 View struct 收集边 | QuickPool 的 switch、ImageRenderer 载体里的实例化全漏 |
| 3 | 同名 body 覆盖而非拼接 | `extension RootView` 顶掉真 body，可达集只剩 1 |
| 4 | 只认实例化 | 命名空间 enum 永不 new，`AlarmCenterView` 误判孤立 |

**方向很重要**：宁可高估可达（漏掉一个孤立页），也不要低估（误报一堆孤立页）。
后者会让我去"修"本来正常的导航。

## 八、破坏性动作的分级（审计结果：体系是好的）

审查了全 App 的"危险操作是否与后果匹配"，结论是**这套体系设计得不错**，且有明确的四档递进：

| 档 | 手段 | 用在哪 |
|---|---|---|
| 1 | `confirmDestructive`：取消 + 红色按钮 + **具体后果** | 删除钥匙/记录/网关/导入备份（10 处）|
| 2 | 双选项 + 后果逐条解释 | 删除成员（"只移除档案" vs "连锁端一起收回"，还写明"指纹一旦在锁端删掉无法远程补录"）|
| 3 | 长按 2 秒 + 就地提示 | 清空回收站 |
| 4 | 勾选「我理解不可恢复」+ 输应用锁密码 | 彻底销毁 |

**关键点**：每档都写了"后果"，不是只说"确定吗"。
例如「删除后若不再配网将无法找回」、「TA 仍能开门」——这些是**可核对的后果预告**。

### 一处死代码：`confirmDestructiveTyped`

`Alerts.swift` 里有一个更严的确认：**必须逐字键入指定词**，并把连带删除数量写进正文。**全仓零调用。**

但这不是缺口 —— 最该用它的「彻底销毁」实现的是**更强的方案**：
勾选 + **输应用锁密码验证**（`SecurityPolicy.sudoRequired`）。密码比"键入一个词"更难蒙混。

所以它属于"被更强方案替代的死代码"，不是"没接上的能力"。
**保留**（未来若出现"无密码可验但仍需强确认"的场景会用到），但如果一直不用，可以删。

## 九、`@Published` 里"写了没人读"的跳转意图（2026-10-22）

扫了全部 81 个 `@Published`，按「声明 / 写入 / 读取」三类计数。
	extbf{34 个从未被读}。其中 `pending*` 这一组最危险：

它们看起来是「解锁后要去哪儿」的意图载体，实际上 `applyPendingRoute()` **只消费两个**：

```swift
func applyPendingRoute() {
    if let m = pendingMac, appUnlocked && !decoyMode { pendingMac = nil; select(m) }
    guard let r = pendingRoute else { return }
    pendingRoute = nil
    if appUnlocked && !decoyMode { requestRoute(r) }
}
```

``pendingRecordsFilter / pendingJumpLock / pendingCredNav / pendingCredPanel /
pendingCare / pendingSettingsFocus`` 等：**写了，没人读**。
三域合并成单一控制台之后，导航改走 `managerGroup` / `requestRoute`，
这一批是旧 Router 的残留 —— 设了等于没设。

### 已删（只有声明，零读零写，删除零风险）

`onboardingFinished`、`pendingCredSelect`、`pendingRecordsMember`、
`pendingMemberAdd`、`pendingRecordKey`、`pendingRecordsDay`、
`pendingFlashKey`、`pendingSearch`、`pendingAddDevice`（9 个）

### 保留但标记（有写入、零读取）

`pendingRecordsFilter`、`pendingJumpLock`、`pendingCredNav`、`pendingCredNavMac`、
`pendingCredPanel`、`pendingCare`、`pendingSettingsFocus`、`showGuestGate`、
`showGate`、`homeMoment`、`failStreak`、`retryAttempt`、`revalidating`、
`connectSource`、`lastReceipt`、`lastError`、`dongleState`、`gatewayState` 等。

**这些暂不删**，因为它们是"某处设了意图、界面还没接"的半成品，
而不是纯粹的噪声；删掉会丢失"这里本来想做什么"的信息。
但如果一直不接，它们和死代码没有区别。

### 这类问题比 `@State` 更隐蔽

`@State` 是局部的，不读就是本页没反应。
`@Published` 是跨视图共享的**真相**——它声明在那里，读代码的人会以为
"设置了它，别处就会响应"。结果是：设置了，哪儿都不响。

## 处理原则

**不批量删除。** 理由：

1. 本机没有 Swift 编译器，删错一处就是一次 CI 红
2. 其中有真实但尚未接 UI 的 API（如归档），删掉会丢失意图
3. 有些可能通过 KeyPath / 协议 / 反射间接使用，静态扫描看不到

所以采取**标注而非删除**：在关键处写清"这个功能目前够不着"，
并在这里集中记录。要接通时按记录补 UI，要清理时按记录删，两边都有依据。
