# AUDIT-ROUND-203 · 第 203 轮：**三方对抗对比**（vendor Cordova APK ↔ 老 iOS ↔ ios27）—— 定位 rc=2

> 用户提供：① 倒闭厂商的 APK 反编译产物（`jzzns22561_out`，Cordova + Angular + lockprotocol.js）
> ② 老 iOS 工程（`ios-app/App`，139 文件）③ 现在 `ios27`。
> 用户的判据：**老 iOS 开锁没问题**。

## 1. 三方逐字节对比的结论

| 环节 | vendor（Cordova JS） | 老 iOS | ios27 | 一致？ |
|---|---|---|---|---|
| ekey 信封 | `88` + 版本 + MAC 反序 + TrackId LE + VF LE + VT LE + cmd | 同 | 同 | ✅ 逐字一致 |
| 信封默认窗口 | `2010-01-01` → `2118-01-01` | 同 | 同 | ✅ |
| AES | AES-128 **ECB** + ZeroPadding（CryptoJS） | CommonCrypto 同参 | 同 | ✅ |
| cmd04 帧 | `87 00 len cmd 000000` + KLV01(32B 0) + KLV02(ekey) | 同 | 同 | ✅ |
| cmd08 PIN 写入 | `int → toSmallByteOrder(int.toString(16), 4)`（= LE 4B） | genPin: `hex([b3,b2,b1,b0])`（= LE 4B） | 同 | ✅ |
| 配网批 | 20/批 × 64 枚，批 1 带 del `FFFFFFFF` | 同 | 同 | ✅ |

**协议层三方零差异。** 这排除了"ios27 写错了协议"的全部可能。

## 2. 从 vendor 代码里挖到的**语义**差异（本轮真正收获）

**（a）vendor 的 PIN 是「十进制 int」不是「hex 字符串」**

```js
// vendor 生成
En.generateRandomNumbers(64)              // → 64 个 **int**（0..2^31）
// cmd08 写入: toSmallByteOrder(int.toString(16), 4)   → 4B LE
// 开锁: new $t(parseInt(pin))                          → 又把 int 变回 4B LE
```

```swift
// 本仓（两个 iOS 版本同）
KeyGen.genPin()          // → "0d3f0992" 这类 **8 位 hex 字符串**（已是 LE 字节序的 hex）
// cmd08: addPins.joined()      → 原样发（= 同样的 4B LE）
// pinToLEOrNil: 8 位全 hex → **原样返回**（= 同样的 4B LE）
```

**写入与签名的字节一致 ⇒ 本仓自洽** —— 我用 Python 复刻了 vendor 的 `parseInt` 语义验证：
若把本仓的 PIN 串喂给 vendor 的代码，`parseInt("0d3f0992")` 会**截断成 0**，
`parseInt("104d6ed4")` 会截成 **104** —— vendor 的路径对本仓的锁**必然也全错**。
所以「锁是 vendor App 配的、ios27 来开」不成立 —— **锁一定是 iOS 配的**（两版 iOS 才编码自洽）。

**（b）vendor App 从不做「App 直连开锁」**

`ot.Open`（cmd04）全 JS 只有 **2 处引用**：类定义 + ZOTP 类。所有 `new $t(...)` 都发生在
`shareDevice` / `generateEKey` / `addOtherKeyChain` —— **生成 ekey 后发给服务器，分享给家人**。
vendor 的「手机开门」是：**服务器把 ekey 下发 → 家人 App 现场签 → 直连锁**。

这解释了老 iOS 的能力来源：**老 iOS 把 vendor 的"签 ekey"部分本地化**了（配网时自己生成 skey + 64 PIN，不经服务器）。
ios27 继承了同一套 —— 协议没问题。

## 3. 因此 rc=2 的原因只剩两个，且都在**数据层**

| 假设 | 机制 | 判定办法 |
|---|---|---|---|
| **A. 两版 App 打架** | 老 iOS 和 ios27 各有一份 `kf_keychains`；**谁后配网谁的 skey 生效** —— 锁里只存最后一次 05 的 skey，另一份 App 的所有 PIN 现签全部 rc=2 | 问用户：这把锁**最后一次配网用的是哪个 App**？ |
| **B. 钥匙串被恢复/迁移污染** | 备份恢复把**别的锁**的 PIN 池写进了这把锁的 MAC 下 | 看 `凭证来源` 日志里的「PIN 池 N 枚」与锁端 `pinStock`（cmd03 KLV#22）对不对得上 |

（老 iOS 与 ios27 的协议逐字一致 ⇒ 不存在"新版写错"。）

## 4. 顺带发现（记录，未改）

`keyboardFreeze` / `keyboardErrCount`（cmd03 KLV#06/07）**解析了但零消费** ——
锁端有「连续错 PIN → 键盘冻结」机制，本仓开锁前不查它。在 rc=2 连发场景（上一版 64 连发）下，
**每一条失败都可能加深冻结计数**。下一轮补：开锁前查 freeze、失败后读一次状态把计数暴露给用户。

## 5. 方法论

**"老版本没问题"是最高价值的测试基准 —— 但要先问"它真的走了同一条路吗"。**

三方对比先证明**协议一致**，把嫌疑从"代码写错"压缩到"数据不一致" ——
这正是这次对抗式对比的目的：不是找不同，是**排除整个分支**。

| 对比粒度 | 能排除什么 |
|---|---|
| 函数级（AES/信封/成帧） | 实现错 |
| 语义级（vendor 用 int、本仓用 hex 串） | "看起来不一样但其实等价"的误判 |
| **架构级**（vendor 不直连开门） | **"vendor 能开所以锁是好的"这种想当然** |
