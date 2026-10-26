# APK 协议基线对照（apkshadow）

> 本文记录「Swift 实现 ↔ 厂商原版 APK」的协议对齐结论。
> **权威来源只有两个**：`apk_raw/assets/www/build/main.js`（H5 业务层）与
> `jzzns22561_out/.../lockprotocol/LockCommBase.java`（Java 生产链）。
> **不用 `vendor/app/**`** —— 那是本仓自己的移植稿，拿它证明"一致"是循环论证。

## 为什么需要这一支

仓库原有 `tools/cmdsshadow.js` 的基线是 `fixtures/golden.json`，而 `tools/golden.js` 从
`vendor/app` 生成。也就是说：**旧闸门只能证明 Swift 与移植稿一致，不能证明与原版 APK 一致**。
`tools/apkshadow.js` 直接读原版 APK 的 `main.js` 与 Java 生产链，逐项断言。

已在 CI 里与 `cmdsshadow.js` 并列：

```
- name: 'APK 基线协议对照 (… )'
  run: node tools/apkshadow.js
```

## 帧格式（Java 生产链是最终依据）

`LockCommBase.java:86-112` 的 `getBytes(byte[] ssToken)`：

```java
out.writeByte(-121);                       // 0x87 头标记
int temp = 0 | 256;  out.writeByte(temp);  // 低位 0x00（版本/保留）
out.writeShort(mKLVList.getBytes().length); // 长度：2 字节小端
out.writeByte(getCmdId());                 // 命令号
out.write(new byte[3]);                    // 3 × 0x00
out.write(mKLVList.getBytes());            // KLV 体
```

即 `87 00 <len16 LE> <cmd> 00 00 00 <KLV…>`，与 Swift `ZKProtocol.buildFrame(_:_:ssToken:header:)`
的 `header == 8` 分支逐字节同构。

## 令牌注入键 = 0xEE（不是 F0）

这是本次对照里最容易搞错的一处，记下来免得后人再走一遍：

- `main.js` 的枚举里有 **`ZKCCOMM_SESSIONTOKENKEY="F0"`**，但**全库零使用点**——是个死常量。
- 真正的注入写在 `LockCommBase.java:98`：

  ```java
  this.mKLVList.add((byte) -18, ssToken);   // (byte)-18 = 0xEE
  ```

- Swift `ZKProtocol.injectToken` 用的正是 `buildKLV(0xEE, tokenHex)` ⇒ **对齐原版**。
- 另有一条 `needSessionToken() && (ssToken == null || length <= 0)` 时**直接抛错**的纪律，
  Swift 侧对应 `execOk` 的 fail-closed 处理（拿不到 rc 不报成功）。

## KLV 编码

`main.js` 的 `it.getData()`：

```js
var l = (this.value.length / 2).toString(16).toUpperCase();
l = En.toSmallByteOrder(l, 1);        // key + len(1B) + value
return this.key + l + this.value;
```

- 长度是 **1 字节**，`toSmallByteOrder` 在超长时按 1 字节截断 ⇒ **KLV 单值上限 255B**
- `toSmallByteOrder` 是**逐字节全反转**（不是按字节对交换）：
  `toSmallByteOrder('aabbccddeeff', 3) === 'ffeeddccbbaa'`
- 输出大写；Swift `hexPair` 输出小写，但 `buildFrame` 末尾统一 `.uppercased()` ⇒ 字节一致

## EKey 包络（0x88）

`main.js` 的 `kt.getBytes()`：

```
88 + "00"(Version) + 反转 TargetMAC(6B) + TrackId(4B LE) + ValidFrom(4B LE) + ValidTo(4B LE) + Cmd(1B)
```

总长 **21 字节 = 42 hex**。Swift `ZKProtocol.buildEkey` 的字段序与之一致：
`"8800" + reversePairs(mac) + u32leHex(trackId) + u32leHex(validFrom) + u32leHex(vt) + hexPair(cmd)`。

> 注意：这里的 `reversePairs` 是**逐字节全反转**，所以 `aabbccddeeff` → `ffeeddccbbaa`，
> 不是 `eeffccddaabb`。0x88 包络里的 MAC 字节序有 display/raw 两种口径，
> 由 `kf_macorder_<mac>` 真机裁定，默认 `.display` = 原版语义。

## 命令体（本轮新写的三条已逐项核对）

| 命令 | APK 体结构 | Swift | 结果 |
|---|---|---|---|
| `08` SYNCPINS | `addCount(1B) + delCount(1B) + addPins + delPins`，pin 为 4B LE；`null` 时 count 保持 `"00"` | `hexPair(addPins.count) + hexPair(delPins.count) + addPins.joined() + delPins.joined()` | ✅ |
| `22` enableDFUstate | param 单字节，包络键 `0x02` | 同 | ✅ |
| `25` setDefence | `control(1B) + start(4B LE) + end(4B LE)`，包络键 `0x01` | 同 | ✅ |
| `41` Key_Chain_WriteEKey | **明文帧**（免令牌） | `buildFrame(0x41, …)`，未走 `wrapFrame` | ✅ |

pin 编码的关键前提：Swift `KeyGen.genPin()` 直接产出**4 字节小端 hex**
（`HexKit.hex([b[3], b[2], b[1], b[0]])`），所以 `addPins.joined()` 与 APK 的
`toSmallByteOrder(pin.toString(16), 4)` 等价——**不是**把十进制字符串直接拼进去。
`delPinSentinel = "ffffffff"` 对应 APK 的 `4294967295`。

## 协议时间

`main.js` 的 `getProtocolTimeSecond`：

```js
var n = new Date('2010-01-01 00:00:00').getTime() / 1000;  // 本地解释，无 Z
return Math.floor(t/1000) - Math.floor(n);
```

Swift `ZKProtocol.epochMs` 用 `DateComponents(year:2010, month:1, day:1)` + `TimeZone.current`，
同口径。这一条容易在 UTC runner 上出假差异，所以 `apkshadow.js` 与 `golden.js` 都钉了
`Asia/Shanghai`。

## 边界（本对照**不能**证明的）

1. **AES 密文本身**：`AESKit` 走 CommonCrypto，node 侧只能证明"输入相同"，不能证明 iOS 的
   `CCCrypt` 分支与 JS 的 CryptoJS 逐位一致——那要真机跑一次 04/05 看锁是否 rc=0。
2. **锁端是否认这些字节**：所有断言都是"源码算法 ↔ APK 算法"，不覆盖固件实现差异。
3. **DFU 传输层**（`App/Services/DFUKit.swift`）：Nordic Secure 的 PRN 流控与 Legacy 的
   start packet 结构来自 Nordic 规范与 APK 插件的状态码，**没有真机验证过**。
4. `main.js` 是单行压缩文件，所有证据只能给字符偏移（`@<offset>`），拿不到行号。
