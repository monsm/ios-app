# AUDIT-ROUND-157 · 第一百五十七轮：给 ROUND-155 的修复补测试，并修掉它的一个健壮性缺口

> CI：`4fd7b89` 已验证绿（build + golden）；`f81185d` / `3eb61f4` / `04f045e` 待回执。本轮本地提交。

## 1. 先修我自己那版修复的一个缺口

ROUND-155 的实现遍历的是 `keychains()`：

```swift
for kc in keychains() {          // ← kf_mkey_<mac> 可能存在于没有 keychain 的 mac
    ...
}
```

而 `kf_mkey_<mac>` 这个键**可能在没有对应钥匙串时仍然存在**（例如钥匙串已删、mkey 残留）。
那种情况下遍历 `keychains()` 会漏掉。

改成遍历**存储键**：

```swift
for key in store.keys() where key.hasPrefix("kf_mkey_") {
    let mac = String(key.dropFirst("kf_mkey_".count))
    ...
}
```

这与 `removeDevice` 里"按前缀整族清"是同一思路 —— **按数据在存储里的实际存在方式遍历**，
而不是按"它应该依附于谁"遍历。

## 2. 补测试

```swift
func testRemoveMemberDropsTheirMobileKeys() {
    let mac = "aabbccddee11"
    guard let m = DB.addMember("测试成员-\(mac)") else { XCTFail(); return }
    MobileKeyService.save(mac, [
        MobileKey(id: "mk-owned", memberID: m.id, memberName: m.name),
        MobileKey(id: "mk-other", memberID: "someone-else", memberName: "别人"),
    ])
    XCTAssertEqual(MobileKeyService.rawList(mac).count, 2, "前置：两把钥匙都写进去了")

    DB.removeMember(m.id)

    XCTAssertEqual(MobileKeyService.rawList(mac).map(\.id), ["mk-other"],
                   "只应删掉属于被删成员的那把，别人的必须留着")
}
```

## 3. 为什么这条用例能在 CI 上真跑

关键的取舍：**用空 `pin` / `ekey`**。

```swift
// MobileKeyService.save
for i in safe.indices {
    if !keys[i].pin.isEmpty, SecretStore.set(...) { ... }    // ← 空串则完全跳过
    if !keys[i].ekey.isEmpty, SecretStore.set(...) { ... }
}
```

`save` 只在 pin/ekey **非空**时才碰 Keychain。所以：

| 用例 | 依赖钥匙串权限？ |
|---|---|
| `testMobileKeyPurgeRemovesSecretCopies`（ROUND-87） | **是** ⇒ `XCTSkipUnless(keychainAvailable)` |
| **`testRemoveMemberDropsTheirMobileKeys`（本轮）** | **否** ⇒ 在未签名宿主上也能真跑 |

两者互补：**前者测"副本有没有清"，后者测"条目有没有清"**，而后者不依赖环境。

## 4. 断言设计

第二把钥匙（`memberID: "someone-else"`）是**反向对照**：如果实现写成"清空整表"，
这条会红。只断言"被删成员那把没了"是不够的 —— **必须同时证明"别人的还在"**。

## 5. 方法论

**"修完补测试"时要问：这条测试在 CI 上会不会被 skip？**

本仓既有测试有 2 条 `XCTSkipUnless(keychainAvailable)` —— 那是必要的（未签名宿主没权限），
但也意味着**它们在 CI 上不产生保护**。新加的测试应当优先选择"不依赖环境"的写法：

| 依赖 | 能否避免 |
|---|---|
| 钥匙串 | **能**（用空 pin/ekey，只测 plist 条目） |
| BLE | 不能（那部分靠金标夹具） |
| 时间 | 能（传显式 `now`） |

