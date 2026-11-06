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

## 本版对 Engine 的第五处改动：空壳的两处残余

| 位置 | 改了什么 | 为什么 |
|---|---|---|
| `DB.otpStatus(_:)` | 加 `if isDecoy { return nil }` | 读路径原先不判空壳 |
| `AppLock.swift` 的 `DecoyCopy` | 整段删除（零调用） | 它生成的两句话会印在屏幕上 |

`otpStatus` 不判空壳的后果：锁上**真开过**动态密码时，空壳里的「动态密码」页会完整可用 ——
周期、序号、失效时刻全从真实数据读，点一下就能算出一串此刻真能开门、还会推进真实
`otpIdx_` 的数字。凭证页在空壳里是空的，这一页却把同一把锁的开锁凭证摆出来。
`ios27` 的 `AUDIT-FINAL.md` 把「空壳下动态码要不要拦」列在"需要你拍板"的第①条 ——
这一版替它做了决定：**空壳里不给动态码**。备份导出在空壳里本来就被拒，所以这个过滤
不影响备份（`BackupKit` 那处读法只在导出时走到）。

`DecoyCopy` 的两句模板是「空壳模式下不 <动作> —— 先退出空壳再来」。这一版只剩两处调用
（登记钥匙串 / 把 ekey 写进钥匙串），都印在设置页的消息行上 —— 而空壳的全部意义是
让胁迫者看不出这台手机在空壳里，把「空壳模式」四个字印在屏幕上等于当面翻底牌。
两处已改成与其它写入拒绝同一句中性话（「暂时无法……，请稍后再试。」），函数零调用后删除。

写路径侧的同类守卫（手机钥匙签发/吊销、`setZotp`）落在 `AppModel`，不属于 Engine 改动。

## 本版对 Engine 的第六处改动：删成员不该删手机钥匙

| 位置 | 改了什么 | 为什么 |
|---|---|---|
| `DB.removeMember(_:)` | 名下手机钥匙改为「把 `memberID` 置空」，不再整条删除 + 清 Keychain 副本 | 见下 |

原实现把 `kf_mkey_<mac>` 里 `memberID` 指向该成员的条目整个 `filter` 掉，并删除
Keychain 里的 `pin`/`ekey` 副本。但**锁端那张钥匙没有被吊销** —— 删成员是本机操作，
不走 BLE。于是：一枚此刻仍然能开门的手机钥匙从列表里消失，从此既看不到、也无法吊销；
而删除确认上写着「名下的凭证会变成未归属」。

这与同一函数对密码/指纹的取舍（解除归属、保留凭证）相反，也与 `MemberMergeKit`
合并成员时「改判，不删除」的纪律相反。现在统一为：只把 `memberID` 置空，
`memberName` 原样保留（它本来就是刻意冗余，成员删除后仍显示这把钥匙原来是谁的）。
记录还在 ⇒ 钥匙还在列表里 ⇒ 随时可以吊销。

## 本版对 Engine 的第七处改动：自动开门的两句承诺

| 位置 | 改了什么 | 为什么 |
|---|---|---|
| `AutoOpenKit.faceFresh(...)` | 严格档增加 30 秒上界 | 界面写着「刷一次，之后 30 秒内有效」 |
| `AutoOpenKit.makeContext(...)` | 「上次开门」取内存与持久值的较大者 | 界面写着「距离上次开门超过 6 秒」 |
| `AutoOpenKit.onForeground(...)` | 空壳里直接返回 | 刷脸提示与审计条目都是真实副作用/使用痕迹 |

`faceFresh` 原先只要求 `lastFace >= strictSince`，**没有上界**：上一次前台刷的脸可以被无限期复用，
与设置页「之后 30 秒内有效」不符。现在超过 30 秒的确认一律不算数；`pendingPrompt`（提示进行中）
仍然直接判负 —— 2026-10-31 的 SEC-04 修复不受影响。

冷却原先只认自动开门的 `dispatch`，手动开锁不写时间戳：手动开完立刻走开再靠近，
2 秒后就能被自动开门。现在 `AppModel.unlock` 成功时也会写
`kf_autoopen_lastdispatch_<mac>`（界面层调用，不改协议），`makeContext` 取两者较大值 ——
两条开锁路径共用同一个「上次开门」口径。

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
