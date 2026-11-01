# AUDIT-ROUND-174 · 第 174 轮：台账是手动的（但没说）+ 手动开锁总失败的真因

## 1. 台账：**不是自动获取**，而且"上次读取时间"算了却从不显示

### 事实（代码链路）

```
RecordsScreen.onAppear  →  reload() + consume()
   reload() 只读**本机缓存**（DB.readLogs / RecordsSource.load），不碰蓝牙

唯一真读锁内日志的路径：
RecordsScreen.read()  →  app.readLogs()  →  cmd16 翻页（最多 20 页 × 5 条）→ DB.writeLogs + kf_logsync_
```

所以：**台账要靠手点才会从锁里拉**。

### 手动入口是有的，但用户找不到

| 位置 | 形态 | 可见性 |
|---|---|---|
| `RecordsScreen:436` | 检索卡右上角一排小字：`告警类型 · 工作室 · 导出 · 读取` | **在的，但只是 13pt 蓝字之一** |
| `RecordsScreen:647` | 空态卡里的 `VActionButton("读取锁内日志")` | 只在**一条记录都没有**时出现 |

也就是说：**有记录之后，那排小字是唯一入口**，很容易被当成"标题旁的链接"而不是"刷新"。

### 缺陷：`readAt` 有值但从未显示

```swift
@State private var readAt: Int64?          // 28 行：声明
readAt = synced                             // 756 行：赋值（RecordsSource.lastSync）
// 全文再无 readAt —— 从未显示
```

后果：用户既不知道记录要手动读、也不知道上次读到什么时候，
自然会觉得"怎么没有刷新按钮"。

**修法**：在检索卡标题行下面加一行状态：

```swift
Text(readAt.map { "上次读取 · " + TimeFormat.ago($0) } ?? "还没读取过锁内日志")
```

这样"要不要再读一次"变成一眼能判断的事，而不是靠记忆。

## 2. 手动开锁总失败：**用户选的 PIN 被完全忽略**

### 病因

```swift
// LockServiceOps.unlock（旧）
if !kc.ekey.isEmpty {
    cred = kc.ekey          // ← pinDec 被完全忽略
} else {
    let pin = pinDec ?? kc.pins.first
    cred = buildEkeyOpen(skey, mac, pin)
}
```

配网后 `kc.ekey` **基本都非空**，于是：

| 后果 | 说明 |
|---|---|
| ①「锁档案 · 开锁 PIN」形同虚设 | 用户选第 N 枚，实际用的仍是配网那枚 |
| ② **一旦配网 ekey 失效，每次开锁都失败且无法自救** | 换 PIN / 换管理员 / 锁被重刷 / rc=6「已绑定其他设备」——这些都让那枚 ekey 永久不可用；而本机**没有任何路径能现签一枚新的** |

`rc=1/11`（解密失败）、`rc=2`（无效的PIN码）、`rc=6`（已绑定其他设备）
都是**确定性**失败 —— 不换凭证就永远是同一个结果，正好对应"总是失败"。

### 修法（两层）

**① 显式选了 PIN 就现签**（"选它"的意义就在于此）：

```swift
let chosen = (pinDec ?? "").trimmingCharacters(in: .whitespaces)
if !chosen.isEmpty { cred = signed(chosen) }
else if !kc.ekey.isEmpty { cred = kc.ekey }
else if let first = kc.pins.first(where: { !$0.isEmpty }) { cred = signed(first) }
```

默认路径不变（没选 PIN 仍用配网 ekey），只在**用户明确选择**时才改变行为。

**② 凭证被拒时自愈重试一次**：

```swift
let credentialRejected = [1, 2, 6, 11].contains(r.rc)
if credentialRejected, let pin = kc.pins.first(where: { !$0.isEmpty }) {
    r = try await exec(ZKCmdBuilder.cmd04Open(signed(pin), klv01Hex: "0000"), retries: 1)
}
```

只对**凭证类**错误码（1/2/6/11）回落 —— 锁忙(25)、布防(27)、反锁(21)、时间偏差(3/9/13)
都不是"凭证坏了"，对它们重试只会更糟，所以**不**回落。

## 3. 方法论

**"总是失败"要当成一条线索：找那个"每次都会走到"的分支。**

| 失败形态 | 指向 |
|---|---|
| 偶尔失败 | 信号 / 超时 / 锁忙 |
| **总是失败** | **某个确定性条件恒成立**（本轮：`kc.ekey` 非空 ⇒ 永远用同一枚失效凭证） |

找法：把失败路径上的每个 `if` 都当成"恒真/恒假"来问一遍。
本轮就是 `if !kc.ekey.isEmpty` 恒真 ⇒ 后面的"用 PIN 现签"永远不执行。

另一条（与上一段同源）：**算了的值要显示出来。**
`readAt` 被赋值却从不渲染，等于系统内部知道"上次读是三天前"、而用户永远不知道。
