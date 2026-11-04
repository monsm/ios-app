# AUDIT-ROUND-182 · 第 182 轮：**「已…失败 N 条」被涂成绿色** —— 颜色由文案前缀决定

> CI：**`a2d143d` 已验证绿**（build_ok=1 errors=0 warnings=0）；`41edf0c` 待回执。

## 1. 缺陷

`CredentialStudioScreen` 用**文案前缀**决定结果行的颜色：

```swift
.foregroundStyle(studioOutcome.hasPrefix("已") ? V.C.rewardGreen : V.C.pink)
```

但本页有三条文案是「以『已』开头、里面含失败计数」：

```swift
studioOutcome = "已延期 \(ok) 条"
//          + "；本机找不到 N 条（编号 …）"
//          + "；下发到锁失败 M 条（本机已改，锁端仍是旧有效期，请重试）"

studioOutcome = "已停用 \(r.done) 项并移入回收站（失败 \(failed) 项）"
```

**它们全被涂成绿色** —— 用户看到一片绿，里面写着「失败 M 条」。

尤其第二条：代码注释（463-467 行）**专门解释过**"两类失败必须分开说，别混成一个数字"，
说明作者非常在意这条信息 —— 结果颜色把这份在意全抹掉了。

## 2. 修法：显式失败标志，不再从文案猜

```swift
@State private var studioOutcomeBad = false
...
.foregroundStyle(studioOutcomeBad ? V.C.pink : V.C.rewardGreen)
```

7 个赋值点逐个置位：

| 站点 | 置位 |
|---|---|
| 「已保存当前台账快照」 | false |
| 「已延期 …」（含两类失败） | `r.failed.count > 0 \|\| remoteFailed > 0` |
| 「已停用 …（失败 M 项）」 | `failedPwds + failedFps > 0` |
| 「已给 N 条加前缀备注」 | false |
| 「已移交 N 项」 | false |
| 「导出失败：没有可导出的凭证」 | true |
| 「已生成凭证包」 | false |

## 3. 全仓同类排查

把「以成功词开头 + 含失败词」的组合全扫一遍，共 4 处：

| 位置 | 判定 |
|---|---|
| `CredentialStudioScreen:497` | **真误色**（本轮已修） |
| `CredentialStudioParts:115`「还原失败：…已被其他凭证占用」 | ✅ 以「还」开头 → 判粉，正确 |
| `BackupStudioScreen:310`「未做备份拷贝 — 已经拒绝…」 | ✅ 以「未」开头 → 判粉，正确 |
| `BackupStudioScreen:429`「未做恢复 — 已经拒绝…」 | ✅ 同上 |

所以只有一处真误色，已修。

## 4. 一个**记录不改**的系统性问题

全仓有 **8 个页面**用同样的写法判结果色：

```
BatteryProfileScreen:130 / DeviceInfoScreen:237 / LockProfileScreen:237 / SafeModeScreen:65
TailgateScreen:54 / CredentialStudioScreen:234 / RecordsScreen:705 / BackupStudioScreen:122,182,261
```

只要文案改一个字（或将来做多语言），颜色就会错 —— 而且**不会报错**。
全面改成显式状态需要给 8 个页面各加一个 `@State`，属独立重构；
本轮只修了**已经出现实际误色**的那一处。记录在案。

## 5. 方法论

**「从文案推断状态」是把展示层当成数据源 —— 它一定会漂。**

| 写法 | 改一个字文案后 |
|---|---|
| `.hasPrefix("已") ? 绿 : 粉` | **静默变色** |
| 显式 `Bool` / 枚举 | 编译期不受影响，行为稳定 |

更隐蔽的是：这种写法让**文案和颜色耦合**，于是"改进文案"（例如把「已停用」改成「停用完成」）
会**顺手改掉颜色**，而改文案的人根本不会想到这一点。

判据：**颜色/图标/排序等"语义衍生量"，必须由数据（Bool/枚举）推出，不能由给用户看的字符串推出。**
