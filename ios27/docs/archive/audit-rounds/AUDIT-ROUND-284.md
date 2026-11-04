# AUDIT-ROUND-284 · 第 284 轮：死函数里藏着一条**本该生效却没接上**的规则

> CI：`f87993a` build 全绿；`68c0bf7` / `402f8e6` / `ad7da11` / `4edf420` 排队中。

## 1. 发现

`MobileKeyService.validityLabel` 全仓**零调用**（含 Tests）—— 手机钥匙的列表其实在凭证页，
走 `KeyItem.expiresAt` + `KeysState`，根本不用它。

但它里面有一条规则：

    if k.forever || k.validTo.hasPrefix("2118") { return "永久有效" }
    // 注释：与 APK page-delblekey 同判据

**这条「2118 即永久」的判据，从没被真正的消费点用上。**

## 2. 后果

`AppModel.reloadKeys` 的投影只判 `k.forever`：

    expiresAt: k.forever ? nil : Self.epochMillis(k.validTo)

于是从**厂商 App / 旧备份**导入的手机钥匙（`forever == false` 但 `validTo = "2118-01-01 …"`）：

| 应该显示 | 实际显示 |
|---|---|
| 永久 | **约 33000 天后到期** |

## 3. 修法

| 动作 | 说明 |
|---|---|
| 把规则搬到投影层 | `expiresAt: (k.forever || k.validTo.hasPrefix("2118")) ? nil : …` |
| 删掉死函数 | 原地留注记说明规则去了哪 |

## 4. 方法论

**删死代码前，先读它「想做什么」—— 死函数里的规则，常常是**本该生效却没接上**的业务约定。**

| 死代码类型 | 处置 |
|---|---|
| 纯冗余（与别处重复） | 直接删 |
| **编码了一条别处没有的判据** | **先把判据搬到消费点，再删**（本轮） |
| `【保留未接】` 且有接线点 | 保留 + 写清接线动作 |

判据：**删之前问一句「它算的那件事，别处算对了吗」—— 没算对，这就是一个还没发作的 bug。**
