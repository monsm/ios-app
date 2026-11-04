# AUDIT-ROUND-90 · 第九十轮：表格里我又编错了一次标识符（附一次放弃的闸门）

> CI：`fd07a75` 判红已由 `64a3c47` 修（actor 隔离）；本轮本地提交。

## 1. 复核 `64a3c47` 的两处隔离风险（静态）

修完后逐条确认新代码里每个调用点都不会再触发隔离错误：

| 被调 | 隔离 | 从 `nonisolated` 里调安全？ |
|---|---|---|
| `DB.store.get` | `Store` 是 `@unchecked Sendable`，非 `@MainActor` | ✅ |
| `SecretStore.remove` | 普通 enum，非 `@MainActor` | ✅ |
| `rawList` / `pinAccount` / `ekeyAccount` | 在 `@MainActor` 枚举里 | ❌ —— **已改为就地读存储 + 就地拼账户名** |
| `CredBinStore` / `CredHistoryStore` 的 purge | 普通 enum，非 `@MainActor` | ✅（所以 CI 没报它们） |

也就是说 `MobileKeyService` 是**唯一**需要 `nonisolated` 的那个 —— 修复范围正确且完整。

## 2. 表格里又编错一次标识符

上一轮那张「数据族 × 存储位置」表，我写了两处前缀：

| 我写的 | 真实 |
|---|---|
| `keychain.<mac>.skey` | `kc.<mac>.skey` |
| `kc.<mac>.pending.<字段>` | `pair.<mac>.skey` / `.bkey` / `.ekey` / `.pins` |

**两处都是凭印象编的**（都是当场 grep 才发现的）。这已经是本段第三次"写文档时编标识符"
（前两次：ROUND-49 存储键清单、ROUND-73 `weakReason`/`strictBytes`）。

## 3. 试过给这类错加闸门 —— 放弃

想法是：扫注释里形如 `kc.<mac>.xxx` 的前缀，若该前缀在代码里不存在就判红。

**写了四版都没过**，问题全在 JS 里嵌套引号（我的 python 拼接脚本反复把 `"` 吃掉），
最后落成一个语法错的规则。

按本段已定的原则（**半成品规则比没有更糟**，见 ROUND-70 的 `a11y` 回退）——
**回退该规则**，`allgates` 恢复 20/20。

## 4. 但"凭印象编标识符"这件事本身有更低成本的处置

不需要闸门：**写这类表格时，每写一个标识符就当场 grep 一次**。
本轮两处都是这么发现的，成本几乎为零。而闸门版要解决"注释里出现的名字"这种
天然模糊的目标（有的对、有的就是举例），判据本身就难写。

判据更新：**"值不值得做闸门"的判断标准是"判据是否清晰"** ——
`frame(height: V.H.*)`（清晰、已落成规则）值得；"注释里引用的标识符是否存在"（模糊）不值得。
