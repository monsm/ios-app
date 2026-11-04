# AUDIT-ROUND-210 · 第 210 轮：批量移交报「已移交 N 项」—— 而 N 是选中数不是实际数

> CI：`a5450a7`（日志翻页方向）已验证绿；`5c5b184` / `f924a73` 排队中。

## 1. 缺陷

`CredentialStudioScreen.applyTransfer()`：

```swift
for alias in selectedPwds { DB.setPwdOwner(studioMac, alias, transferOwner) }
for batch in selectedFps  { DB.setFpOwner(studioMac, batch, transferOwner) }
studioOutcome = "已移交 \(selectedPwds.count + selectedFps.count) 项"
```

而 `DB.setPwdOwner` / `setFpOwner` 是：

```swift
for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].owner = owner }
saveLedger(mac, l)          // ← 找不到也照样写回（内容没变）
```

**返回 Void，找不到就静默跳过。** 于是：

| 选中 | 台账里真实存在 | 界面显示 | 实际 |
|---|---|---|---|
| 5 | 2 | **已移交 5 项** | 只改了 2 条，另外 3 条的归属还是空的 |

这与 D-58（`batchDisable` 静默跳过）**同一个族** —— 那轮修了 disable，**移交这条漏了**。

## 2. 修法

```swift
@discardableResult
static func setPwdOwner(...) -> Bool {
    var hit = false
    for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].owner = owner; hit = true }
    if hit { saveLedger(mac, l) }      // 没改到就不写（省一次整表重写）
    return hit
}
```

`applyTransfer` 改为按实际计数，并把找不到的编号如实列出：`已移交 ok 项；本机找不到 M 项（…）`，且置 `studioOutcomeBad`。

## 3. 顺带确认（本轮另外 4 项「审过、正确」）

| 疑点 | 结论 |
|---|---|
| `batchExtend` 是否真的逐条下发 0B | ✅ 逐条 `setPasswordExpiry`，且两类失败分开报（台账找不到 / 下发失败） |
| 「锁端凭证不会自动删除」是否真的标注 | ✅ `CredentialStudioScreen:341` 与 `MemberOpsScreen:70` 两处都在 |
| 纯图标按钮有无无障碍标签 | ✅ 全仓仅 2 处疑似，核对后一处有 `accessibilityHidden(true)`、一处是 `SharePreview` 缩略图（不可聚焦） |
| 小尺寸固定高度是否会裁字 | ✅ 全仓只有 1 处 7×7 装饰圆点 |

## 4. 方法论

**同一族的 bug，修一处时必须把「同形状的兄弟」全部找出来 —— D-58 只修了 disable，移交活了一年。**

判据：**修完一个「静默跳过」的 bug 后，把所有「遍历 + 调 save/set + 返回 Void」的组合再 grep 一遍** —— 它们全是同一个模子刻出来的。
