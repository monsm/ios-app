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

## 十、`DiagKit` 有数据，没有任何界面（2026-10-22）

`App/Core/DiagKit.swift` 有完整的诊断数据采集。**全仓 UI 里零消费**。

后果连锁出两处假承诺：

| 位置 | 原来写的 | 实际 |
|---|---|---|
| 自检横幅按钮 | 「去诊断」+ `pendingSettingsFocus = "diag"` | 没有任何诊断页 |
| 自检 toast | 「详见「设置-诊断」」 | 那个页面不存在 |

**修复**（本轮）：

- `backup` 这条是真的，接上了：`ManagerFace.consumePendingFocus()` 把落点名翻译成 `path = [.backup]`
- `diag` 这条没有落点，**不再承诺**：按钮改为「打开设置」（它本来就只是打开管理面板），toast 去掉页面指向

### 未解决：诊断数据仍然是采集了不显示

`DiagKit` 值得单独做一屏，但那是**新功能**，不是修缺陷。
在此之前，界面上不应该有任何地方暗示"有诊断页可看" —— 这一轮已经清掉了两处。

## 处理原则

**不批量删除。** 理由：

1. 本机没有 Swift 编译器，删错一处就是一次 CI 红
2. 其中有真实但尚未接 UI 的 API（如归档），删掉会丢失意图
3. 有些可能通过 KeyPath / 协议 / 反射间接使用，静态扫描看不到

所以采取**标注而非删除**：在关键处写清"这个功能目前够不着"，
并在这里集中记录。要接通时按记录补 UI，要清理时按记录删，两边都有依据。

---

# 追加：实现完整但零调用的 API 清单（2026-10-22）

扫了全仓 `static func`：**79 个实现超过 5 行、但调用方为零**。

它们不是半成品 —— 是**成品放在仓库里，没有出口**。
共同特征：**注释比代码更完整**。作者想清楚了为什么、怎么写，就是没做最后一步"接上界面"。

## 本轮接上的一个

### `CredentialOrg.expiringSoonCount`

```swift
/// 930 凭证 Tab 角标: 近 7 日内到期的条数。
/// 与 363 月历格、dueSoonPwds 同源同一把尺 (expiryDate)，不另算第二套。
static func expiringSoonCount(macs: [String], within days: Int = 7) -> Int
```

它原本是**凭证 Tab 的角标**。而 Tab 栏在单控制台重构时删掉了 ——
函数还在，数就没有去处了。

已接到门厅的「关键提示」：

| 优先级 | 提示 |
|---|---|
| 1 | 有 N 条告警还没处理 → 安全中心 |
| 2 | 门锁电量 N%，该换电池了 → 设备管理 |
| 3 | **有 N 项钥匙将在 7 天内到期 → 钥匙列表** |

到期放最低优先级是对的：告警和低电更紧急。

## 剩下 78 个的处置原则

不打算一次全接 —— 那会把 79 个功能塞进界面，是另一种灾难。判据：

| 该接 | 不该接 |
|---|---|
| 信息**用户需要**，只是缺一个展示位置 | 为已删界面设计的（Tab 角标、圆盘尺寸、刃锁间距）|
| 能接上一个**已有的**提示/入口 | 需要新造一整屏才能用 |
| 零调用是因为重构丢了出口 | 零调用是因为设计被否决过（如 `outOfWindow`）|

下一轮继续按这个判据挑，一次接一个。

## 本轮再接两个（第 83 轮）

| 函数 | 行数 | 原状态 | 新位置 |
|---|---|---|---|
| `DataHealth.gapDays` | 17 | 处理 451 空洞日期检测，零调用 | 诊断页「数据健康」：日志有 N 天没有记录 |
| `BatteryCare.bigDropDays` | 25 | 处理 1040 单日掉电观察，零调用 | 设备页「明细」：单日掉电 >20% 的最近三天 |

两个都满足判据：**信息用户需要，只是缺一个展示位置**，而位置本来就有。

### 接的时候守住的两条注释纪律

- `gapDays` 只报**两侧都有数据**的内部空洞 —— 所以"刚装上还没记录"不会被报成问题
- `bigDropDays` 只对"当天至少读到过两次电量"的日子成立，且**只用真实两个点相减，不拟合不外推**
  —— 所以界面上写的是「单日掉电 >20%」，不是「电池健康」之类的结论

**这两条注释是原作者写的。我接界面时原样守住了它们** —— 一个函数被冷落两年，
它注释里那些"不做什么"的约定仍然是有效的。

## 76 个的归类与处置（第 84 轮）

按「用户会在什么时候需要它」分类：

| 类别 | 例子 | 处置 |
|---|---|---|
| **应该自动跑** | `migrateSecretsToKeychain` / `recordTap` / `pinToFront` | 接进操作流程，不给按钮 |
| **缺编辑能力** | `setPwdNote` / `setFpNote` / `renameFp` / `rePwd` | 接进已有右键菜单 |
| **缺展示位** | `gapDays` / `bigDropDays` / `expiringSoonCount` | 接到已有区块（已做 3 个）|
| **需要新屏** | `batchExtend` / `batchTransfer` / `smartSet` | 暂不接 —— 会显著增加界面复杂度 |
| **被撤功能** | `outOfWindow` / `confirmDestructiveTyped` | 保留但不接 |

### 本轮修的两个

#### 1. `DB.migrateSecretsToKeychain` —— 明文密钥可能一直没搬进 Keychain

```swift
/// 2026-10-14 一次性迁移: 把旧 plist 里明文的 skey/bkey/ekey 搬进系统 Keychain,
/// 并从 plist 抹掉。幂等 (没有明文字段时不动), **启动时调一次**。
```

它全仓零调用。后果：只要本机还留着旧格式的明文密钥，
它们就会一直躺在 UserDefaults 里（可被备份提取），永远不会进 Keychain。

实现本身很谨慎 —— **只有 Keychain 里确实有值才抹掉明文**，
避免"首次解锁前的后台启动"写失败 + 抹明文 = 永久丢密钥。
已原样接进 `onLaunch()` 的第一行。

#### 2. 凭证备注**创建后改不了**

创建时能写（AddKeyPage 与工坊都有备注框），创建之后没有入口 ——
`DB.setPwdNote` / `DB.setFpNote` 写好了零调用。打错一个字只能删了重建。

已接到钥匙页右键菜单「编辑备注」，用单行输入弹窗（改一个字段不该做一整屏）。

### 第 85 轮：`hydrateMacOrders` —— 不是缺陷，是每次冷启动白付一个来回

我原本怀疑它是"重启后 MAC 顺序丢失"的缺陷。查完发现**自愈路径确实存在**：

```swift
// LockService.exec(): 命令因字节序失败时换序重试，井把正确顺序落盘
let used = ZKProtocol.macOrder(curMac)
ZKProtocol.setMacOrder(curMac, other)   // 换一种再试
DB.setMacOrder(curMac, other)           // 记住
```

所以**正确性没问题**。但代价是真的：协议层的字节序在**内存**里，冷启动后回到默认 `.display`；
已配对的锁要等第一条命令失败一次，探针才会纠正它。而冷启动后的第一条命令**往往就是开锁**。

`hydrateMacOrders` 就是把落盘的顺序提前灌进协议层（纯读，无写），
它零调用 → 这个优化一直没生效。已接进 `onLaunch()`。

**这一类要分清：**

| 零调用意味着 | 例子 | 该不该接 |
|---|---|---|
| 功能缺失 | `setPwdNote`（备注改不了）| 接 |
| 安全漏洞 | `migrateSecretsToKeychain` | 接 |
| **只是少了优化** | `hydrateMacOrders` | 接，但不紧急 |
| 被撤功能 | `outOfWindow` | 不接 |

**接之前必须查清楚是哪种** —— 把"少了优化"当成"功能缺失"去大改，就是制造风险。

### 第 86 轮：批量的先不接，先接一个"设密码时会看见"的

#### 不接：`batchExtend` / `batchTransfer` / `smartSet`

三个都是批量操作。查了钥匙页：**没有多选态**（只有单选行与分段控件，
`batchDisable` 虽然名字叫 batch，实际每次只传一条）。

要用它们得先做一整套多选 UI（进入选择态、勾选、操作条、日期选择器），
那是新屏级改动。而判据是：**需要新造一整屏才能用的，暂不接**。

家庭门锁场景里凭证通常十来条 —— 批量编辑是"顺手的便利"，不是"缺了不行"。
记在这里，不装作遗漏。

#### 接上：`StudioTools.pwdStrength`

```swift
/// 8 密码强度条: 全同位 / 顺子 / 短 → 弱 (本地推断)
static func pwdStrength(_ v: String) -> (score: Int, hint: String)
```

零调用。而它针对的正是**家里设门锁密码最常见的两种错误**：
全同数字（111111）与顺子（123456）—— 也是试错者最先试的两种。

挂在 AddKeyPage 的提示行：密码一变成"可用"，就改说它弱不弱，并改用警示色
（否则"全部同数字"会显示成通过色，等于在鼓励它）。

---

---

# 附：零调用函数处置总表

判据：`static func` + 零调用 + 实现 > 5 行，共 **72 个**。

| 处置 | 数量 | 说明 |
|---|---|---|
| **缺编辑能力** | 6 | **真缺口**：setter 写好了但界面没有入口 —— 用户改不了 |
| **应自动跑** | 25 | 本该在操作流程里自动执行，不该做成按钮 |
| **缺展示位** | 27 | 信息有用，只缺一个显示位置（**不是缺陷，是欠一笔债**） |
| **需要新屏** | 4 | 要新造一整屏或多选态，风险大于收益 —— **这是结论，不是待办** |
| **仪式需求** | 6 | 需要特定场景（节气/问候/焦点序列）才触发 |
| **协议底层** | 3 | 协议层探测/加解密工具，由上层封装调用 |
| **不接（误报多）** | 1 | 判定逻辑不可靠，接了会制造假警报 |

## 先说怎么用这张表

- **不要**从上往下挨个接。先问：用户会在什么时候需要它？
- 「需要新屏」是**已判定不值得做**的结论，不是待办清单。
- 「缺编辑能力」是**真缺口**，优先级最高。
- 「应自动跑」需要找到那个操作流程，把调用塞进去，而不是给用户一个按钮。
- 表是活的：接一个就把它移到下面「已接上的」。

## 缺编辑能力（6）

| 函数 | 文件 | 行数 |
|---|---|---|
| `rePwd` | Store.swift | 5 |
| `setFpAlarm` | Store.swift | 5 |

> **`rePwd` 与 `setFpAlarm` 明确不接：**
>
> · `rePwd` 只改本地台账的 `pwd` 字段，**不写锁**。接了会造出一条"本地显示新密码、锁里还是旧的"的骗人记录。
>   真要换密码必须走"锁端删旧 + 写新"的完整流程（工坊已有）。
> · `setFpAlarm` 只影响比对标签与备份导出里的"预警指纹/普通"，**不配置锁端防拆**。
>   接上去会让人以为开了一个安全开关，实际只是个标签 —— 正是本会话一直在清理的那种假开关。
| `setMemberBadge` | Milestones.swift | 5 |
| `setMemberBirthday` | Milestones.swift | 5 |

## 应自动跑（25）

| 函数 | 文件 | 行数 |
|---|---|---|
| `canTailgate` | PidMap.swift | 5 |
| `diff` | CredentialOrg.swift | 26 |
| `digitDiff` | CredentialOrg.swift | 10 |
| `exportPackage` | CredentialOrg.swift | 12 |
| `lastApplyAt` | CredentialOrg.swift | 5 |
| `markDisabled` | CredentialOrg.swift | 12 |
| `markPinSeen` | BackupStudioKit.swift | 5 |
| `markRecordsViewed` | Milestones.swift | 12 |
| `namingTemplate` | CredentialOrg.swift | 11 |
| `noteMigTxnDone` | BackupStudioKit.swift | 6 |
| `observed` | FirmwareHistory.swift | 7 |
| `pendingMigrationTxn` | BackupStudioKit.swift | 5 |
| `pinToFront` | LockStats.swift | 8 |
| `prefixConflict` | CredentialOrg.swift | 5 |
| `purgeNow` | CredentialOrg.swift | 5 |
| `pushSearchHistory` | CredentialOrg.swift | 5 |
| `recordOrganize` | Milestones.swift | 13 |
| `recordTap` | QuickPool.swift | 9 |
| `reordered` | LockStats.swift | 11 |
| `repeatTarget` | QuickPool.swift | 15 |
| `rescueCode` | AuditChain.swift | 6 |
| `scheduleAlerts` | CredentialOrg.swift | 33 |
| `setSelected` | QuickPool.swift | 8 |
| `tier` | BatteryCare.swift | 11 |
| `writeRoster` | ExportCenter.swift | 11 |

## 缺展示位（27）

| 函数 | 文件 | 行数 |
|---|---|---|
| `compact` | StatsKit.swift | 7 |
| `damageDays` | RecordSearch.swift | 10 |
| `dayDeadlines` | CredentialOrg.swift | 7 |
| `duePins` | BackupStudioKit.swift | 15 |
| `earlyExpiryNote` | CredentialOrg.swift | 8 |
| `fpUseCount30d` | CredentialOrg.swift | 7 |
| `fwLag` | LockStats.swift | 8 |
| `fwSince` | BatteryCare.swift | 7 |
| `inferredLastUseMap` | CredentialOrg.swift | 9 |
| `isAlarm` | RecordSearch.swift | 6 |
| `isIdleLock` | StatsKit.swift | 11 |
| `lastSessionLine` | DiagKit.swift | 11 |
| `listCountdown` | CredentialOrg.swift | 15 |
| `maintenance` | LockStats.swift | 17 |
| `mergedRecentOpens` | RecordSearch.swift | 9 |
| `monthDeadlines` | CredentialOrg.swift | 15 |
| `naturalSentence` | StatsKit.swift | 6 |
| `nextWindow` | ZOTP.swift | 9 |
| `openCountInWindow` | CredentialOrg.swift | 8 |
| `pinDayText` | BackupStudioKit.swift | 7 |
| `pinLabel` | BackupStudioKit.swift | 5 |
| `recentAlarmMacs` | LockStats.swift | 6 |
| `recentUseCount` | CredentialOrg.swift | 19 |
| `recordCard` | ExportCenter.swift | 6 |
| `sampleTimeText` | LockStats.swift | 7 |
| `springFestiveRange` | StatsKit.swift | 17 |
| `usageCount` | CredentialOrg.swift | 8 |

## 需要新屏（4）

| 函数 | 文件 | 行数 |
|---|---|---|
| `batchExtend` | CredentialOrg.swift | 11 |
| `batchPrefixNote` | CredentialOrg.swift | 12 |
| `batchTransfer` | CredentialOrg.swift | 21 |
| `smartSet` | CredentialOrg.swift | 17 |

## 仪式需求（6）

| 函数 | 文件 | 行数 |
|---|---|---|
| `checkInTonight` | Milestones.swift | 9 |
| `launchPhrase` | Milestones.swift | 13 |
| `liveFocusSequence` | AccessibilityKit.swift | 19 |
| `newEntryHaptic` | AccessibilityKit.swift | 9 |
| `solarTermHint` | Milestones.swift | 11 |
| `solarTermToday` | Milestones.swift | 11 |

## 协议底层（3）

| 函数 | 文件 | 行数 |
|---|---|---|
| `buildEkeyShare` | ZKCmdBuilder.swift | 8 |
| `decryptHex` | AESKit.swift | 16 |
| `probeSimplified` | RealityAPIProbe.swift | 9 |

## 不接（误报多）（1）

| 函数 | 文件 | 行数 |
|---|---|---|
| `outOfWindow` | RecordSearch.swift | 21 |

## 已接上的（本会话）

| 函数 | 轮次 | 去处 |
|---|---|---|
| `migrateSecretsToKeychain` | 84 | 启动时把明文密钥迁进 Keychain（**安全漏洞**）|
| `setPwdNote` / `setFpNote` | 84 | 钥匙页右键「编辑备注」|
| `hydrateMacOrders` | 85 | 启动时预热 MAC 字节序（省一次来回）|
| `expiringSoonCount` | 82 | 门厅关键提示「N 项 7 天内到期」|
| `gapDays` | 83 | 诊断页「数据健康」|
| `bigDropDays` | 83 | 设备页「明细」|
| `pwdStrength` | 86 | 设密码时就地提示弱口令 |
| `renameFp` | 88 | 钥匙页右键「改个名字」（锁端无名称字段，纯本机）|
| `renameMember` | 89 | 成员编辑表单补上「称呼」字段（原先 10 个字段唯独没有名字）|

## 一个数字

这 72 个里有 **6 个是真缺口**（用户改不了）、
**27 个是欠一笔展示的债**、**25 个是流程里漏了一次调用**。

剩下 14 个，**已判定不该接**。

### 第 89 轮：成员改名 —— 两处文案承诺了一件做不到的事

成员编辑表单有 **10 个字段**（关系 / 备注名 / 代号 / 紧急联系 / 便签 / 关怀文案 / 欢迎语 / 分组 / 常用锁…），
**唯独没有名字**。而 `DB.renameMember` 写好了、零调用。

于是这两句文案都是空话：

- 「没有同名成员。若只是称呼重复, **请在成员页重命名其一**。」
- 「已按建议命名「x」, **可重命名**」

已把「称呼 (必填)」加进表单，保存时走 `DB.renameMember`（写 `kf_members` 的 name 字段）。
**空输入不覆盖** —— 用户清空一个必填字段不该把称呼抹掉。

顺序也核对过：`MemberHub.saveExt` 写的是扩展表 `extKey`，与主表 `kf_members` 互不覆盖。
