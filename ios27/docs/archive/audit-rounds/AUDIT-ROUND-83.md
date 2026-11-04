# AUDIT-ROUND-83 · 第八十三轮：配网链的「已中止」分支永远不会触发

> CI：`e150d03`（安全披露）已验证；`816aa3f` / `efc94c8` 刚推送。本轮本地提交。

## 1. 缺陷：依赖 `Task.isCancelled`，却从不 cancel

`AddLockScreen.runChain` 里有两处中止判定：

```swift
if Task.isCancelled { rollback("已中止：配网没有跑完，锁未被改动。"); return }
```

分别覆盖「正常返回后」与「抛错后」。也就是说：**只要任务被 cancel，用户会得到一句诚实的收尾**。

但全仓搜索 `pairTask`：只有 `rollback()` 里会 cancel —— 而 `rollback` 本身就是"链已经结束"时调的。
页面消失时**没有任何 cancel**：

```
grep onDisappear  ->  该文件只有一处 .task { await scan() }，没有 onDisappear
```

所以用户中途退出页面：配网链**继续跑下去**（它会真的写锁端密钥槽 —— cmd23→05→08×4→21→03），
而那两句"已中止"永远不会执行。更讽刺的是界面上的确认文案写着：

> 配网会生成本机密钥并写入门锁密钥槽，App 内无法撤销。**请让手机贴近门锁，中途不要离开这一页。**

—— 提醒了用户别走，却没准备"走了怎么办"。

## 2. 修法

```swift
.onDisappear {
    guard pairTask != nil else { return }
    pairTask?.cancel()
    pairTask = nil
}
```

`runChain` 已有的两处 `isCancelled` 判定随即生效，会走 `rollback("已中止…")` 收尾。

## 3. 同类核查（这次是好的）

全仓共 3 个存储的 `Task` 状态：

| 变量 | 生命周期 |
|---|---|
| `CaptureShield.flashTask` | `onDisappear` cancel ✅ |
| `DoorScreen.holdTask` | `onDisappear` + 三处 cancel ✅ |
| **`AddLockScreen.pairTask`** | **只在 rollback 里 cancel ← 本轮修复** |

三个里两个是对的 —— 又是一个"同族里只有一处漏了"的例子（第 N 次）。

## 4. 方法论

**`Task.isCancelled` 是一个"等待别人触发"的判据：没有 cancel 调用点，它就永远是 false。**

判据：**看到 `Task.isCancelled` / `Task.checkCancellation()`，就去搜同一任务变量的 `.cancel()`**；
搜不到就等于**那段中止逻辑是死代码** —— 而且它看起来写得很完整，最容易被当成"已处理"。
