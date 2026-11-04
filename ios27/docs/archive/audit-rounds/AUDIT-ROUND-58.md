# AUDIT-ROUND-58 · 第五十八轮：预演说"8 条密码"，恢复只回来 3 条

> CI：`3864e54` 已验证；`0d35a93` / `85e9480` 待回执。本轮本地提交。

## 1. 缺陷：预演报的是"包里声明了多少"，恢复报的是"实际写进多少"

`Preview.pwdCount` 的计算是：

```
for d in m.devices { p += d.ledger?.pwds.count ?? 0 }
```

—— 即"包里**声明**了多少条"。

而恢复路径里 SEC-08 会**整把锁跳过**：

```
guard HexKit.bytes(d.mac).count == 6, CryptoBox.isHex(d.kc.skey, len: 32) else {
    BleTelemetry.recordEvent("备份里有非法 skey，已跳过该锁")
    mskip += 1; continue
}
let badPins = d.kc.pins.filter { !CryptoBox.isHex($0, len: 8) }
guard badPins.isEmpty else { ... mskip += 1; continue }
```

所以用户可能看到「凭证：8 密码 · 1 指纹」，点确认后只回来 3 条 —— 会以为**备份坏了**。
实际是包里那把锁的密钥格式非法，被有意拒写（这条设计是对的，缺的是"提前告知"）。

## 2. 修法

- `Preview` 新增 `skippedLocks: Int`（默认 0）；
- `parsePreview` 里用与恢复**同一套判据**算它（非法 mac / 非法 skey / 非法 pin）；
- 预演页多一行「将被跳过：N 把（密钥格式非法，SEC-08 拒绝写入）」，仅在 N>0 时显示。

判据共用是关键：**预演与恢复必须用同一套拒绝规则**，否则两个数字永远对不上。

## 3. 方法论

**"预览"若只统计包里的内容，就必然与实际执行结果不一致。**
预览的正确口径是「**这次操作会做什么**」，而不是「输入里有什么」。

判据：任何预览/预估界面，都要问一句「它统计的是输入还是效果」；
两者不同时，必须以效果为准，或把差额显式说出来。
