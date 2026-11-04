# AUDIT-ROUND-89 · 第八十九轮：CI 抓到我上一轮引入的隔离错误

> CI：`fd07a75` **判红**（`errors=2`、`build_ok=0`）：
>
> ```
> App/Engine/StoreKeychain.swift:221:26: error: call to main actor-isolated static method
>   'purgeSecretsForDevice' in a synchronous nonisolated context [#ActorIsolatedCall]
> ```

## 1. 我错在哪

`MobileKeyService` 整体标了 `@MainActor`，而我新加的 `purgeSecretsForDevice` 被
`Store.removeDevice`（**nonisolated**）调用 —— 上下文不匹配。

而且第一版改法还埋了第二处同类错误：我把它标成 `nonisolated`，但函数体里调用了
`rawList` / `pinAccount` / `ekeyAccount`，**它们三个也都在同一个 `@MainActor` 枚举里**。

## 2. 修法

1. 标 `nonisolated`（与 `BackupStudio.purgeLocalArtifacts` 同一处置 —— 仓里已有先例）；
2. **不再调用任何被隔离的成员**：直接读存储取 id 列表、直接拼账户名：

```swift
let raw = DB.store.get([MobileKey].self, "kf_mkey_" + mac) ?? []
for k in raw {
    SecretStore.remove("mkey." + mac + ".pin." + k.id)
    SecretStore.remove("mkey." + mac + ".ekey." + k.id)
}
```

（少掉"回填密钥"那一步无所谓 —— 反正马上要删；且已核对账户名格式与 `pinAccount`/`ekeyAccount`
逐字一致。）

## 3. 这次与本段其它 CI 判红的对比

| 轮次 | CI 错误 | 性质 |
|---|---|---|
| 54 | 实参顺序（`argument must precede`） | 语法级、编译器的强项 |
| **89** | **actor 隔离** | **同上：编译器一抓就准，本地 20 道形状闸门看不见** |

两次都是"我写的代码在形状上完全正确，只有编译器能判"。这印证了段内一直坚持的做法：
**本地闸门全绿 ≠ 能编译；每个 Swift 改动都要等 CI 回执再声称通过。**

## 4. 方法论

**给一个函数加 `nonisolated` 之前，先看它**调用了什么**。**

`nonisolated` 只解决"入口"的隔离，函数体内部每一次对被隔离成员的访问都会各报一次错。
判据：**标 `nonisolated` 时，把函数体里所有 `self.` / 同类型静态成员调用逐个过一遍**；
要么它们也 `nonisolated`，要么就地下沉（如本轮直接读存储）。
