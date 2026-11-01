# AUDIT-ROUND-231 · 第 231 轮：放弃一个低精度扫描 + 三项核对

> CI：`3b231a8` build 全绿（`project=yes / swift_files=150`）；`8cf6a28` / `2222064` 排队中。

## 1. 放弃：「参数全未使用」扫描

写了一个扫「函数参数一个都没用到」的脚本，命中 **136 处** —— 全部是**假阳性**。

原因：本仓大量函数是**单行函数体**：

```swift
static func alertKey(_ mac: String, _ kind: String, _ key: Int) -> String { "kf_calert_\(mac)_\(kind)_\(key)" }
```

而我的解析器按「从 `{` 到匹配 `}`」取函数体、再丢掉第一行 —— 单行函数体整行被丢掉，于是"参数全未使用"。

**按本仓纪律：低精度扫描不追噪声，直接放弃。**（同批放弃过的还有：死类型 66 候选、只读 `kf_` 键 55、
成员逐一初始化顺序 839/915、裸 `guard…else{return}` 170、`return` 后代码 130、重复修饰符 3/4。）

留此记录，免得下一轮又写一遍。

## 2. 核对：`settingsBinding` 是否真的写回

`BackupScreen` / `SettingsParts` 用 `settingsBinding(\.encryptBackup)` 这类绑定 —— 若是本地 `@State`，开关就不持久。

```swift
Binding(get: { SettingsStore.shared[keyPath: keyPath] },
        set: { SettingsStore.shared[keyPath: keyPath] = $0 })
```

✅ 读写都走 `SettingsStore.shared`，落盘由各属性的 setter 负责（Round 192 已核过 52 个键配对）。

## 3. 核对：`8cf6a28` 的新调用类型正确（CI 未到，先静态过一遍）

| 表达式 | 类型 |
|---|---|
| `item.pwd?.alias` | `LedgerPwd?` → `Int?` ✅ |
| `item.fp?.batch` | `LedgerFp?` → `Int?` ✅ |
| `CredentialOrg.purgeDerivedState(mac:pwdAlias:fpBatch:)` | 签名一致 ✅ |

## 4. 方法论

**「扫描器报了多少条」不是价值，**「报出来的每一条经得起人看」才是**。**

| 指标 | 意义 |
|---|---|
| 命中 136 条 | 看起来"硕果累累" |
| 逐条看后 0 条成立 | **实际价值为 0，还消耗了一轮** |

判据：**写扫描器前先问"它的假阳性会从哪来"；跑完先抽 3 条人工核，不成立就立刻放弃，不要试图调参救它。**
