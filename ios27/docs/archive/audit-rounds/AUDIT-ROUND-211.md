# AUDIT-ROUND-211 · 第 211 轮：「已读取 N 条」里的 N 是**缓存总数**，不是本次读数

> CI：`f924a73`（密码长度）已验证绿；`116b03e` 排队中。

## 1. 缺陷

`RecordsScreen.read()` 成功分支：

```swift
readNote = "已读取 \(entries.count) 条 · \(TimeDisplay.clock(now))"
```

而 `entries` 来自 `reload()`：

```swift
let targets = lockScope == .all ? DB.keychains() : [当前锁]
for kc in targets { merged.append(contentsOf: load.entries) }   // ← 多把锁合并
entries = merged.sorted { $0.at > $1.at }
```

**两个问题叠在一起：**

| 问题 | 后果 |
|---|---|
| `entries.count` 是**合并后的缓存总数** | 这次读到 0 条也会显示「已读取 300 条」 |
| `lockScope == .all` 时还是**多把锁之和** | 只读了 A 锁，却把 B/C 的数也算进去 |

用户拿这个数字判断「读全了吗」，而它是错的。

## 2. 修法

`readLogs()` 的返回值加上**本次实际读到的条数**：

```swift
@discardableResult
func readLogs() async -> (read: Int, remaining: Int?)? { … return (collected.count, remaining) }
```

界面分开说两件事：

```swift
let readCount = fetched?.read ?? 0
let cacheNote = entries.count == readCount ? "" : "（记录页共 \(entries.count) 条）"
readNote = "本次读取 \(readCount) 条" + cacheNote + …
```

**「本次读到多少」与「页面上现在有多少」是两个事实，不该用同一个数字表达。**

## 3. 顺带扫描：24 处「文案里插 .count」

| 类别 | 数量 | 判定 |
|---|---|---|
| 显示已知集合的大小（已选 N 项 / 已签发 N 把 / 内存环 N 帧） | 20 | ✅ 正确 |
| 进度类（已收到 3/5 次） | 2 | ✅ |
| **把"选中数"当"成功数"报告** | 1（上轮修） | ✅ |
| **把"缓存总数"当"本次读数"** | 1（本轮修） | ✅ |

## 4. 方法论

**同一个数字被用来表达两件事，就一定会有一件事是错的。**

| 表达 | 正确来源 |
|------|---------|
| 本次读了 N 条 | `readLogs` 的返回值 |
| 页面上现在有 M 条 | `entries.count` |

判据：**凡是文案里的数字，问一句"它来自哪个变量、那个变量真的是这个意思吗"。**
本轮的错法很典型：变量名（`entries`）看起来像"这次的记录"，实际是"所有缓存"。
