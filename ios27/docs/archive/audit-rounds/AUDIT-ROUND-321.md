# AUDIT-ROUND-321 · 第 321 轮：**保存一把锁，会把其它锁全部抹掉**（损坏时）

> CI：`8ff51157` build 全绿（errors=0）。

## 1. 缺陷

`StoreKeychain.saveKeychain` 的写入块：

    keychainWriteLock.withLock { _ in
        var map = store.getDict("kf_keychains")     // 解码失败时返回 [:]
        map[normalizeMac(kc.mac)] = kc.toDict()
        store.set("kf_keychains", map)              // ← 写回「只有这一把锁」的整表
    }

**没有 `isDictCorrupt` 守卫。** 而 `getDict` 在解码失败时（`Store.swift:47-48`）：

| 行为 | 结果 |
|---|---|
| 记进 `corruptKeys` | ✅ |
| **返回 `[:]`** | ← 于是上面写回的就是空表 + 这一把 |

⇒ 一次「无关的保存」（改个备注、重命名）就会让**其它所有锁从本机消失** ——
密钥还在 Keychain 里，但 plist 里没有它们的条目，界面再也列不出来、也开不了门。

## 2. 更糟的是：注释说这件事已经修好了

`Store.swift:41-44` 原文：

> 现在失败时返回带**哨兵键**的字典，调用方（`saveKeychain`）见哨兵即放弃写入。

**这句话是假的，三层都不成立**：

| 声称 | 事实 |
|---|---|
| 返回带哨兵键的字典 | ❌ 返回的是 `[:]` |
| 调用方见哨兵 | ❌ 全仓没有任何哨兵常量 |
| 放弃写入 | ❌ `saveKeychain` 从来没查过任何东西 |

而 `migrateSecretsToKeychain` 是**真的**做了防护的（第一行 `if store.isDictCorrupt("kf_keychains") { return }`）——
所以这个洞一直躲在「同一文件里另一处做对了」的阴影下。

## 3. 修法

| 位置 | 改动 |
|---|---|
| `saveKeychain` | 写入前 `guard !store.isDictCorrupt("kf_keychains") else { 记遥测; return }` |
| `Store.getDict` 注释 | 改成真实机制：解码失败 → 记 `corruptKeys` → 调用方用 `isDictCorrupt(k)` 判断 |

取舍：**这次保存不生效** vs **抹掉别人的锁** —— 前者可重试，后者不可逆。

## 4. 方法论

**「文档里描述了一个不存在的机制」比「没有文档」更危险 —— 它会让下一个人跳过验证。**

| 情形 | 后来者反应 |
|---|---|
| 没有防护 | 会去加 |
| **注释说「已有哨兵键防护」** | **信了，跳过** —— 而防护根本不存在 |

判据：**注释里凡出现具体机制名（哨兵键 / 标记位 / 计数器），都必须能在代码里 grep 到同名实现；grep 不到，就当成不存在。**
