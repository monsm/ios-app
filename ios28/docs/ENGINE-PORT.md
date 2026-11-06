# Engine 移植记录

来源：`ios27/App/Engine/`（上一版已经过金标差分与真机验证的协议层）。

## 原则

协议、密码学、存储、BLE 是**字节级验证过**的资产。重写等于把"不要 BUG"的保证丢掉。
界面层则 100% 新写，不复用任何上一版的设计系统。

## 照搬（协议 / 密码学 / 存储 / BLE 未改）

`App/Engine/` 下 69 个文件，逐字节复制。动了三处**纯开发工具 / 死代码**：

| 位置 | 为什么动 |
|---|---|
| `FullPageCapture.swift`（整文件删） | CI 截图脚手架，只在 `-kfFullPage` 启动参数下可达；且引用旧设计令牌 `V8.C.bg` |
| `SeedImporter.swift`（整文件删） | CI 种子导入，只在 `-kfSeed` 启动参数下可达 |
| `MemberHub.sortedForPicker(...)`（函数删） | 签名引用上一版的界面类型 `KeyItem`，本版没有这个类型；函数全仓零调用 |

## 本版对 Engine 的第四处改动：一个真缺陷

| 位置 | 改了什么 | 为什么 |
|---|---|---|
| `AppLock.verify(_:)` | 失败时补写单调时钟那一份冷却；成功时把它一起清掉 | 见下 |

`AppLock` 在 2026-11-03 引入了「墙钟 + 单调时钟」双记，用来防「把系统时间往前拨就绕过冷却」。
但这份双记只写进了 `recordFailure()`（二次开锁口令那条路），**门禁页真正用的 `verify()` 没有写**：

- `cooldownRemaining()` 取两者较大者，而单调那一档恒为 0 ⇒ 从门禁页输错密码建立的冷却
  只存在于墙钟里，改时间即可绕过。4 位数字码只有 1 万种，冷却正是把它从「几秒穷举」
  拖成「不可行」的那道闸。
- 成功解锁只清了墙钟。若先前 `recordFailure()` 记下的单调窗口还在走，
  下一次 `verify()` 会在验密码之前就返回 `.cooling` —— 用户看到「刚解锁过却又要等」。
  这与该文件 2026-11-01 修过的刷脸解锁缺陷是同一类。

改动只是补齐 `recordFailure()` 已有的那两行写/清，**不涉及协议、不涉及数据格式**。
`ios27` 里的同一份代码有同样的缺陷（两版 `AppLock.swift` 逐字节相同）。

## 为编译而补的七个符号

Engine 反向引用了若干上一版属于界面层的类型。这一版在 `App/Core/`（`Tone` 在 `App/Design/`）里按**同名同签名**重新实现，因此 Engine 源码一行都不用改：

| 符号 | Engine 里的用途 | 本版实现 |
|---|---|---|
| `SettingsStore.shared.notifyChanged()` | 备份恢复写入外观偏好后通知界面 | `App/Core/SettingsStore.swift`（`@Observable`，`revision` 计数） |
| `LinkSenseModel.savedRSSI/level/levelWord` | `Reading` 的信号口径出口 | `App/Core/LinkSense.swift`（RSSI 四档、预热、回连阶梯） |
| `RecordCSV.field(_:)` | `StatsKit` 的周报 CSV 转义 | `App/Core/RecordCSV.swift`（防公式注入 + 引号转义） |
| `Tone` | `Reading.Value.tone` 的语义色 | `App/Design/Tone.swift`（neutral / ok / attention / critical） |
| `CredStarStore` | 备份导出星标、彻底删除时摘掉星标 | `App/Core/CredentialStores.swift`（键 `kf_cstar_ui_<mac>`，与 Engine 同名同键） |
| `CredBinStore` | 删设备时清回收站留在 Keychain 的副本 | 同上（本版无回收站 ⇒ 诚实的空实现） |
| `CredHistoryStore` | 删设备时清版本快照留在 Keychain 的副本 | 同上（本版无版本历史 ⇒ 诚实的空实现） |

星标的 ID 口径与 Engine 一致：`pwd:<alias>` / `fp:<batch>`，所以 Engine 在
`CredentialOrg.purgeDerivedState` 里删密码/指纹时会顺手摘掉同一颗星。

## 本版新增的界面层基础设施（Engine 不感知）

| 文件 | 作用 | 为什么需要它 |
|---|---|---|
| `App/Core/ScreenAwake.swift` | 「开门时保持亮屏」的总闸 | 接管 `UIApplication.isIdleTimerDisabled`；离开门口那页就交还给系统，回前台补一次（系统在进后台时复位过） |
| `App/Core/Haptics.swift` | 触感反馈的总闸 | 用户在「外观 · 手感」里关掉后，全 App 不再震动。**触感只在结果上给**（按下 / 成功 / 失败），不在中间相位上给 —— 挂相位会连着震四五下 |
| `App/Core/SettingsStore.swift`（改写） | 偏好改成**存储属性**镜像 | `@Observable` 只给存储属性建观察边；从 UserDefaults 现读的计算属性改了也没人知道，界面要等下一次重画才认 —— 于是「改了设置回到上一页还是旧样子」。Engine 需要的 `notifyChanged()` 形态保持不变 |

## 已知但未修的问题（保持与来源一致）

- `Keychain.trackid` 生成后没有参与 ekey 签发。
- 布防没有回读校验。
- 回滚点只写不读；明文 `skey` 在其中（靠文件保护）。
- 固件包没有签名校验，只有 CRC 与尺寸。

这些都在 `docs/BACKEND.md §6` 里如实记录。**改它们不属于"重做界面"，需要单独的协议/安全评审。**
