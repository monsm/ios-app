# AUDIT-ROUND-75 · 第七十五轮：备份整表写入缺取值白名单

> CI：`2dae705` 已验证；`cdb0615` / `1452c0d` 刚推送。本轮本地提交。

## 1. 缺陷：`setDispositions` 原样收下任意结论

`RecordOverlay.setDispositions` 只供备份恢复用（整表写入），而它收到的 `verdict` **来自外部包**：

```swift
for (k, verdict) in table {
    m[k] = RecordSearch.Disposition(at: 0, verdict: verdict)   // ← 不校验
}
```

而 `Disposition.verdict` 的注释列了五种合法值（已处理 / 误报 / 已处置 / 测试 / 已人工检查），
实现里只有 `RecordDetailScreen` 会写「已处置」。

后果：

1. 界面把 `overlay.disposed.count`（**键数**）显示成「已处置 N 条」——
   构造一个包就能让统计数字虚高；
2. CSV / xlsx 导出会把任意文本当"处置结论"带出去。

## 2. 对照：同一族里 `setNotes` 是**做了**校验的

```swift
// setNotes（早已正确）
let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
if !t.isEmpty { m[k] = String(t.prefix(60)) }
```

也就是说同一份文件里，**两张整表写入的纪律不一致** —— 而它们的输入都是"外部备份包"。

## 3. 修法

- 提一个 `static let verdicts: Set<String>`（合法结论的唯一一份，含注释说明实际只写「已处置」）；
- `setDispositions` 里 trim + 白名单，不在表内就 `continue`（丢掉该条，不整表失败）。

## 4. 新增测试

`testDispositionRestoreRejectsUnknownVerdicts`：喂 `["a": "已处置", "b": "随便写的", "c": "误报"]`，
断言只剩 2 条、`b` 不存在。

## 5. 方法论

**"同一族里有一处做了校验"是最有用的线索。**

我不是先想到"这里该有白名单"，而是看到 `setNotes` 有 trim+截断、
顺手问了一句"同族的 `setDispositions` 呢" —— 于是发现它什么都不做。

这已经是本仓反复出现的模式：**同一类数据的两三条路径，纪律不一致**
（前几轮：写路径误用展示层读取器、旁挂表有的进备份有的没进、
`ownerName` 五个调用点四个兜底一个不兜底）。

所以这条判据值得当成固定动作：**看到一处做了校验/兜底/守卫，立刻去查同族的其它处。**
