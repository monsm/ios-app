# AUDIT-ROUND-155 · 第一百五十五轮：删成员不清手机钥匙

> CI：`b0ca56e` 已验证绿（golden 也绿）；`4fd7b89` / `f81185d` 待回执。本轮本地提交。

## 1. 缺陷：`removeMember` 清了六族，漏了第七族

`Store.removeMember` 已经清得很仔细：

| 族 | 清了吗 |
|---|---|
| 台账归属（`owner`） | ✅ |
| 认领映射（`kf_mclaim_`） | ✅（注释写明"否则永远无法重新认领"） |
| 档案扩展/徽章/生日 | ✅ |
| 值班周表（`kf_duty_week`） | ✅（注释写明上一版误按 key 过滤恒不命中） |
| **手机钥匙（`kf_mkey_` 的 `memberID`）** | ❌ **漏了** |

`MobileKey` 有 `memberID` 字段（第 19 行），删成员后这些钥匙成为孤儿：

```swift
var memberID: String      // 归属成员
```

## 2. 后果

| 层 | 后果 |
|---|---|
| 列表 | 手机钥匙页显示一条**归属不存在的**钥匙 |
| 钥匙串 | `mkey.<mac>.pin.<id>` / `.ekey.<id>` 副本仍在（可读的开门口令） |
| 备份 | 随 `kf_mkey_` 一起导出，孤儿继续传播 |

## 3. 修法

```swift
for kc in keychains() {
    let raw = store.get([MobileKey].self, "kf_mkey_" + kc.mac) ?? []
    let keep = raw.filter { $0.memberID != id }
    if keep.count != raw.count {
        for k in raw where k.memberID == id {
            SecretStore.remove("mkey." + kc.mac + ".pin." + k.id)
            SecretStore.remove("mkey." + kc.mac + ".ekey." + k.id)
        }
        store.setCodable("kf_mkey_" + kc.mac, keep)
    }
}
```

## 4. 边界说明（写进注释了）

这里**只清本机记录**，锁端那张钥匙是否真的吊销要走 `MobileKeyService.revoke`（需要 BLE）。
而删成员是本地操作 —— 这与本仓"解除归属但保留凭证"的既有取舍一致
（`MemberDetailScreen:402` 的注释就是这么写的）。

## 5. 方法论

**"清理函数"是最容易漏一族的地方 —— 因为它是手写枚举，不是数据结构驱动。**

本段在清理上踩过的坑（全部是"漏一族"）：

| 轮次 | 漏的那一族 |
|---|---|
| 27 | 台账口令的钥匙串副本 |
| 47 | 回收站 / 版本快照副本 |
| 87 | 手机钥匙的 pin/ekey 副本（**删设备**时） |
| **155** | **手机钥匙的 plist 条目（删成员时）** |

注意 87 与 155 是**同一族数据、两条不同路径**：

| 路径 | 该清什么 | 修于 |
|---|---|---|
| 删设备 | `kf_mkey_` 键 + 钥匙串副本 | 87 |
| **删成员** | **`kf_mkey_` 里匹配 `memberID` 的条目** | **155** |

**判据**：清理函数改完后，去问「**这个函数删的那个实体，还被哪些表引用**」——
成员被 `owner` / `memberID` / `whoId` / 值班表引用，每个都要看一遍。
