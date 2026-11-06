# Engine 移植记录

来源：`ios27/App/Engine/`（上一版已经过金标差分与真机验证的协议层）。

## 原则

协议、密码学、存储、BLE 是**字节级验证过**的资产。重写等于把"不要 BUG"的保证丢掉。
界面层则 100% 新写，不复用任何上一版的设计系统。

## 照搬（未改一行）

`App/Engine/` 下 69 个文件，逐字节复制。只动了三处**纯开发工具 / 死代码**：

| 位置 | 为什么动 |
|---|---|
| `FullPageCapture.swift`（整文件删） | CI 截图脚手架，只在 `-kfFullPage` 启动参数下可达；且引用旧设计令牌 `V8.C.bg` |
| `SeedImporter.swift`（整文件删） | CI 种子导入，只在 `-kfSeed` 启动参数下可达 |
| `MemberHub.sortedForPicker(...)`（函数删） | 签名引用上一版的界面类型 `KeyItem`，本版没有这个类型；函数全仓零调用 |

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

## 已知但未修的问题（保持与来源一致）

- `Keychain.trackid` 生成后没有参与 ekey 签发。
- 布防没有回读校验。
- 回滚点只写不读；明文 `skey` 在其中（靠文件保护）。
- 固件包没有签名校验，只有 CRC 与尺寸。

这些都在 `docs/BACKEND.md §6` 里如实记录。**改它们不属于"重做界面"，需要单独的协议/安全评审。**
