# AUDIT-ROUND-165 · 第 165 轮：接上 **iOS 27 原生拖拽排序**（`reorderable()`）

> CI：`0d161ea` 已验证绿；`fa300ff` / `ad34f48` 待回执。本轮本地提交。

## 1. 这条 API 是"iOS 27 专属"的典型

`swiftui-pro` 的 `references/views.md` 里有一节 **Reordering and swipe actions**：

> The following requires **iOS 27+** and is unavailable on tvOS.
> Enable drag reordering with `reorderable()` on the `ForEach` and `reorderContainer(for:)` on
> its enclosing container. … This works in lists, lazy stacks and grids, **ordinary stacks**, and custom layouts.
> Earlier versions require `List` with `onMove()` or **a custom drag implementation**.

本仓的「模块排序与显隐」正是"a custom drag implementation" —— 而且连拖拽都没有，
只有两个「上移 / 下移」按钮：三个槽要挪到对面得点两次。

## 2. 改法

**（a）新增 `App/Engine/ReorderSupport.swift`**

`reorderable()` 只把"从哪挪到哪"交给你，**不替你改数据**（Apple 示例明确要求调用方应用
`ReorderDifference`）。要点写在注释里：

```swift
let relocated = sources.compactMap { sourceID in items.first { $0.id == sourceID } }
let sourceIDs = Set(sources)
items.removeAll { sourceIDs.contains($0.id) }
```

> `sources` 是**用户选中的顺序**，不是它们在集合里的当前顺序 ——
> 直接按集合顺序插，多选拖动时顺序会反。

**（b）`ModuleOrderSheet` 接上**

```swift
ForEach(order) { slot in ... }
.reorderable()
...
.reorderContainer(for: DevSlot.self) { change in
    change.apply(to: &order)
    DevLayout.setOrder(order)
}
```

`DevSlot` 已经是 `Identifiable`（`id: String = rawValue`），不需要额外改造。

## 3. **上移/下移按钮保留**

| 交互 | 适合谁 |
|---|---|
| **原生拖拽**（本轮新增） | 一般用户；自带拖起动画、自动滚动、系统一致的朗读 |
| **上移/下移按钮**（保留） | 运动障碍、单手持机、VoiceOver 逐项操作 |

**原生拖拽是新增一条路，不是替换掉那条。** 删掉按钮会让一部分人反而更难用。

## 4. 顺带修了类型闸门的两类假红

接新类型时 `types` 闸门报了 5 处，全部是**闸门自身的问题**：

| 报的"不存在类型" | 实际是什么 | 处置 |
|---|---|---|
| `ReorderDifference` | iOS 27 新 SDK 类型 | 加进 `sdk-types.txt` |
| `ReorderableSingleCollectionIdentifier` | 同上 | 同上 |
| `RangeReplaceableCollection` | Swift 标准库协议（白名单一直缺） | 加进 `sdk-types.txt` |
| `CollectionID` / `ItemID` | **泛型参数**，写在 `where` 子句里 | **改闸门判据** |

闸门原来只从 `<T` 和 `<T:` 收集泛型参数名，漏掉了 `where` 子句里声明的：

```swift
extension ReorderDifference where CollectionID == ReorderableSingleCollectionIdentifier
//                                 ^^^^^^^^^^^^ 这里是泛型参数，不是类型
```

补的判据：**把 `where` 到 `{` 之间的标识符都算已知**（该区间只会出现泛型参数与协议名）。

**为什么不用"把 `CollectionID` 塞进 SDK 白名单"这种省事的做法**：那会把一个项目内的泛型参数名
伪装成"系统类型"，白名单从此混入非 SDK 条目，下一个人看到它会以为真是系统给的。

双向验证：往 `Engine/QuickPool.swift` 注入 `TotallyMissingTypeZzz` → 仍判红；删掉 → 22/22 全绿。

## 5. 方法论

**遇到新 API 被闸门拦住时，先判断"是代码错还是闸门错"。**

| 情况 | 处置 |
|---|---|
| 代码引用了真不存在的类型 | 改代码 |
| **闸门不认识新 SDK 类型** | **加白名单** |
| **闸门不认识语言特性（泛型参数）** | **改判据**，不要加白名单 |

第三行最容易做错 —— 加白名单能让它立刻变绿，但会把"闸门能力不足"伪装成"代码没问题"。
