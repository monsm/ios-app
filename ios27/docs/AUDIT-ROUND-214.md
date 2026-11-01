# AUDIT-ROUND-214 · 第 214 轮：备份删除「失败也报已删除」+ 四类单位/语义核对

> CI：`02457cb`（文档纠错）已验证绿；`e834943` 排队中。

## 1. 缺陷：`try?` 吞掉删除结果

```swift
private func deleteFile(_ file: BackupFile) {
    try? FileManager.default.removeItem(at: …)   // ← 成功失败都不看
    reloadFiles()
    outcome = "已删除 \(file.name)"              // ← 无条件报成功
}
```

删除失败（文件被占用 / 目录只读 / 权限）时：

| 界面 | 实际 |
|---|---|
| 「已删除 backup-xxx.json」 | 文件还在；`reloadFiles()` 之后**又出现在列表里** |

用户会以为「删了又自己回来了」—— 而真正原因是**从来没删掉**。

### 修法

`do/catch` 按真实结果报；`pruneFiles` 同理，并统计失败份数。

## 2. 本轮另外四类「审过、正确」

| 检查 | 结果 |
|---|---|
| `isSuspended` 的秒/毫秒混用 | ✅ `Double(t)/1000 > now`（t 是毫秒、now 是秒）；`setSuspendUntil` 传的确实是毫秒 |
| `rc=26` 语义 | ✅ `rcMsg[26] = "门锁被撬"` —— 防拆挂起 24h 的依据正确 |
| 备份列表排序 | ✅ `.sorted { $0.date > $1.date }` 降序（最新在前）⇒ `dropFirst(keep)` 保留最新 N 份，不会误删新备份 |
| `PrivacyInfo.xcprivacy` 覆盖 | ✅ 用了 UserDefaults（CA92.1）与 `contentModificationDate`（C617.1），两者都已申报；全仓无 `systemUptime` / 磁盘容量等其它 required-reason API |
| 五个页面的路由初始消费 | ✅ `HouseholdScreen` 有 `.onAppear(perform: consume)`（上轮我 grep `consume()` 漏了方法引用形式，本轮补核） |

## 3. 方法论

**`try?` 是「我不关心结果」的声明 —— 但凡后面还要给人一个结论，就不能用它。**

| 写法 | 什么时候可以 |
|---|---|
| `try?` | 结果**真的**不影响任何后续判断（如 best-effort 缓存清理，且不报告） |
| `do/catch` | 任何"要给用户一个说法"的路径 |

本轮的错法是典型：**删了之后还要说「已删除」** —— 那这个调用就不可能"不关心结果"。
判据：**看到 `try?` 后面跟着一句"已…"文案，就是 bug。**
