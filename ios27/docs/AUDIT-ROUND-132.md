# AUDIT-ROUND-132 · 第一百三十二轮：一处重复修饰符，以及一次假阳性

> CI：**`49db24a` 已验证**（`build_ok=1`）—— 这是带第 22 道闸门 `memberfill` 的提交，
> 而 `build` 依赖 `gates`，所以**新闸门在 CI 的 ubuntu 上跑通了**。
> `cab0218` / `78d2e0d` 待回执。本轮本地提交。

## 1. 缺陷：`KeysShortcutRow` 写了两次 `accessibilityHidden`

```swift
Image(systemName: symbol)
    .accessibilityHidden(true)   // ← 第一次（位置也怪：夹在 Image 与 .font 之间）
    .font(V.F.icon18)
    .foregroundStyle(V.C.text2)
    .frame(width: V.Icon.xl, alignment: .leading)
    .accessibilityHidden(true)   // ← 第二次
```

同一修饰符写两遍：**行为无变化**（幂等），但说明作者改的时候没注意已有。
已合并为一处，并把注释挪到正确位置。

## 2. 我的扫描脚本报了 3 处 `.buttonStyle(.plain)` —— 全是假阳性

```
LockPortfolioScreen.swift:101 重复 .buttonStyle(.plain)
CredentialStudioScreen.swift:348 重复
RecordsStudioScreen.swift:152 重复
```

逐个看，全是**相邻的两个不同 Button**，各有一个 `.buttonStyle(.plain)`：

```swift
Button { groupFilter = "" } label: { VTag(...) }
.buttonStyle(.plain)
ForEach(groups) { g in
    Button { groupFilter = g } label: { VTag(...) }
    .buttonStyle(.plain)      // ← 这是另一个 Button 的
}
```

**我的窗口是"6 行内出现 2 次就算重复"** —— 而两个 Button 相邻时必然满足。

## 3. 为什么没做成闸门

按本段原则（**假红多的判据不做**）：

| 判据想法 | 假红率 | 结论 |
|---|---|---|
| "6 行内同一修饰符出现 2 次" | 3/4 是假红 | ❌ 不做 |
| "同一 `Image`/`Text` 的修饰符链上重复" | 需要解析链边界 | 成本高，暂不做 |

这类缺陷（重复修饰符）**行为无影响**，只是整洁问题 —— 不值得为它做一条会持续误报的闸门。

## 4. 方法论

**"我写的检测脚本报出的东西"同样是线索，不是证据** —— 与 `RESERVED.md` 那次误判同源。

本段已第三次撞到这个：

| 轮次 | 工具输出 | 真相 |
|---|---|---|
| 121 | 脚本说 5 个键"有读无写" | 1 个是假阳性（写入经常量中转） |
| 130 | 想让闸门自己数规则条数 | 数出 11 而实际 21（格式不统一） |
| **132** | 脚本报 3 处重复修饰符 | **3 处全是假阳性** |

判据：**任何自动扫描的输出都要逐条看现场**；能一口气判掉 3 条假阳性的，只有"打开文件看那几行"。
