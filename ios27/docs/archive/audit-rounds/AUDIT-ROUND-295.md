# AUDIT-ROUND-295 · 第 295 轮：新增闸门 —— 手写 `CodingKeys` 必须覆盖全部存储属性

> CI：`1337b60` build 全绿（errors=0）。

## 1. 来源：一个真实历史 bug

`BackupBundle.Globals.Appearance` 的 `CodingKeys` 曾经只列了 9 个字段 ——
**没列出的字段被 Codable 完全忽略**，于是 `motion` / `heroTex` / `plain` / `heroStats`
与全部无障碍字段「既不编码也不解码」：备份包里从来没有它们，恢复时也永远读不到。

现有回归测试 `testAppearanceCodableRoundTripKeepsAllFields` 只断言
「**它显式设置的那批字段**」能往返 —— 新增字段忘记加进 `CodingKeys` 时它抓不到。
所以需要一个**静态**规则。

## 2. 规则

    对每个 `enum CodingKeys: String, CodingKey`：
      · 收集它的全部 case 名
      · 回溯找到宿主类型声明
      · 宿主类型体内「缩进 = 宿主+4 且行内没有 `{`」的 var/let 必须都在 case 里

## 3. 第一版是错的（36 处假阳性）

本仓多数 `CodingKeys` 写在**同一行**：

    enum CodingKeys: String, CodingKey { case alias, from, to, temp, at, pwd, owner, note }

而我第一版从**下一行**开始扫 case ⇒ 单行写法全被误判。
修正为先处理本行 `{` 之后、`}` 之前的部分，再决定是否跨行续扫。**改完 0 假阳性。**

## 4. 双向验证（本仓纪律）

| 方向 | 结果 |
|---|---|
| 现状 | ✅ 0 命中（158 个文件的 CodingKeys 目前都是全的） |
| **注入缺陷**：把 `Appearance.CodingKeys` 里的 `motion` 摘掉 | ✅ 报 `motion 没有出现在 CodingKeys 里 —— 该字段既不编码也不解码` |
| 恢复 | ✅ 全绿，22/22 通过 |

## 5. 方法论

**「运行时断言」只能覆盖它设置过的那批值；「静态规则」才能覆盖未来的新增。**

| 防线 | 能抓到 |
|---|---|
| 回归测试（显式设置字段） | ✅ 那批字段的往返 |
| **静态闸门（结构对结构）** | ✅ **任何新增字段忘记登记** |

判据：**同一个坑出过一次、而回归测试只覆盖了一部分时，就把它写成闸门 —— 测试管行为，闸门管结构。**
