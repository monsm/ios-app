# AUDIT-ROUND-192 · 第 192 轮：四类「会崩 / 会静默错」的数值与状态模式 —— 全部干净

> CI：`ea66e90` 已验证绿；`82f65a3` / `08b4475` 待回执。

## 1. 本轮扫的四类

| # | 模式 | 为什么危险 | 命中 |
|---|---|---|---|
| A | `Int(Double)` 且值可能 NaN/∞ | Swift 里 `Int(nan)` 是 **trap（崩溃）**，不是返回 nil | **0** |
| B | `String(format:)` 的 `%d` 配 `Double` 实参 | C 变参类型不匹配 ⇒ **输出错误的数字**，且不报错 | **0** |
| C | `ForEach(id: \.self)` 元素可能重复 | SwiftUI 视图身份错乱（上一轮修了 `parsedTags`） | 已清 |
| D | `SettingsStore` 属性的 get 与 set 用了不同的键 | 设置**永远存不下**，且看不出来 | **0** |

## 2. A 类的 6 处除法转换，逐个判

| 位置 | 判据 | 结论 |
|---|---|---|
| `CredentialOrg:400` | `max(0, …) / 86400` | ✅ 非负、除数为常量 |
| `BatteryProfileScreen:112` | `(last.t - first.t) / 86_400_000` | ✅ 有限值 |
| `DeviceInfoScreen:178` | 同上 | ✅ |
| `DeviceInfoScreen:275` | `max(0, Int(nowMs - since.at) / 86_400_000)` | ✅ 先转 Int 再整除，且 `max(0,…)` |
| `DoorScreen:728` | `max(1, Int((Double(battery) / 0.68 / 30).rounded()))` | ✅ 上面有 `guard battery >= 0 else { return "未知" }` —— **不会给未知电量编估计** |
| `SyncTimeScreen:73` | `Int((now - lockAt) / 1000)` | ✅ 整数相除 |

## 3. D 类为什么值得单独查

`SettingsStore` 的属性都是 get/set 成对的，get 与 set 各自写一个 `kf_` 键名。

**只要两个键名差一个字符，这个设置就永远存不下来** —— 界面切了、看着生效了，
重启后彻底回到默认，而且整个过程不报任何错。

52 个属性逐个解析 get/set 块里的 `kf_` 字面量并求交集 —— **全部一致** ✅。

## 4. 方法论

**有些 bug 不报错、不崩、也不"看起来错" —— 只能靠"问一个具体的问题"抓出来。**

| 类别 | 怎么发现 |
|---|---|
| 会崩的（`Int(nan)`） | 列出所有"从 Double 转 Int"并逐个问"它可能是 NaN 吗" |
| 会输出错数字的（`%d` 配 Double） | 按格式串的类型与实参类型对照 |
| 会静默不生效的（get/set 键不同） | **按"同一语义的两处字面量是否相同"对照** |

第三类最值得记：它不是"某处写错了"，而是**"两处必须同时对"**。
这类问题没有局部证据 —— 必须把两处并排看。
