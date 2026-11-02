# AUDIT-ROUND-318 · 第 318 轮：存储安全四问 —— 全部到位，修一处过期注释

> CI：`7956de4d` build 全绿（errors=0）。

## 1. 钥匙串属性

`SecretStore` 用的是：`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

| 属性 | 含义 |
|---|---|
| `WhenUnlocked` | 锁屏后读不到 |
| **`ThisDeviceOnly`** | **不同步到 iCloud 钥匙串** ✅ |
| 未设 `kSecAttrSynchronizable` | 默认 false ✅ |

## 2. 文件保护等级

| 文件 | 保护 |
|---|---|
| 备份快照（含 skey） | `.completeFileProtection` ✅ |
| **回滚快照（含整库 skey/pins 明文）** | `.completeFileProtection` ✅（代码里 SEC-09/SEC-10 有注释） |
| 诊断日志 | `.completeFileProtectionUntilFirstUserAuthentication`（日志，可接受） |

## 3. 会不会随系统备份出机

| 目录 | `isExcludedFromBackup` |
|---|---|
| `BackupStudio.dir` | ✅ true |
| `BackupStudio.rollbackDir` | ✅ true |
| `DiagLogStore` 所在 Caches | ✅ true（双保险） |

## 4. 口令派生是不是系统实现

`CryptoBox.pbkdf2` 调的是 **CommonCrypto 的 `CCKeyDerivationPBKDF`**（HMAC-SHA256），不是手搓 ✅。

而且对**来自不可信备份信封的迭代次数**做了钳制（`iterMin = 1_000` / `iterMax = 2_000_000`）：
旧写法 `UInt32(iterations)` 遇到负数或超大值会 trap —— 那是一个「远端可触发的 DoS」。

## 5. 本轮唯一改动：一处过期注释

`LockService.swift:80` 写着「全仓无 `isExcludedFromBackup` → 随系统备份出机」——
而上面第 3 节表明这条**已经修好了**。注释留着会让人以为日志还在出机。已就地更正并注明「修复前的状态」。

## 6. 方法论

**存储安全只要问四个问题，每个都有明确的正确答案 —— 逐条对，比通读实现快得多。**

| 问 | 正确答案 |
|---|---|
| 钥匙串属性 | `…ThisDeviceOnly`（不同步） |
| 文件保护 | 含密钥的 → `.completeFileProtection` |
| 会不会随备份出机 | `isExcludedFromBackup = true` |
| 密钥派生 | 系统实现 + 参数钳制 |

判据：**安全审计先从这四问开始 —— 它们覆盖「静态数据」这一整面，且每条都能一眼判对错。**
