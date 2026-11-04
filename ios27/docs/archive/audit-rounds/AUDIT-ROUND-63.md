# AUDIT-ROUND-63 · 第六十三轮：归档成员，点完什么都不说

> CI：`d3217ef` 已验证（errors=0、build_ok=1）；`70cf56d` / `b00ad23` 刚推送。本轮本地提交。

## 1. 缺陷：有后果的动作没有回执

`MemberDetailScreen.toggleArchive()`：

```
internal func toggleArchive() {
    app.members[i] = m.hh(archived: !m.archived)
    roster.mirrorArchived(m.id, !m.archived)
}
```

三行，**没有任何反馈**。而归档的后果不小：

- 成员数变少（统计不含已归档）；
- 名单里看不到他（要专门去「归档」页找）；
- 但名下凭证与历史仍在。

用户点一下工具栏图标，界面只是"图标变了个形状" —— 既不知道自己做了什么，
也不知道怎么回去（HIG feedback：有后果的动作必须给回执）。

## 2. 修法

按全仓一致的做法加 toast：

```
AppToast.shared.show(next ? "已归档 · 历史仍在，记录页仍能筛到 TA" : "已恢复为在册成员", tone: .ok)
```

文案刻意说清"历史仍在"，因为这是用户最容易担心的一点。

（先核对了 `AppToast.show(_:tone:)` 的签名与 `ToastTone` 的取值，没有凭印象写。）

## 3. 顺带确认的事

归档是**真落库**的（`mirrorArchived` → `MemberHub.ext` → `saveExt`），不是只改界面投影 ——
这点在上一轮修备份时已经确认过（`kf_member_ext` 现已进备份，所以归档状态也能跟着换机走）。

## 4. 方法论

**"静默成功"和"静默失败"在用户眼里是同一件事。**
这条动作本身是对的、也真的写进去了，但因为没有回执，用户无法区分它和"点了没反应"。

判据：**任何改变"用户能看到多少东西"的动作（归档/隐藏/筛选/折叠），都必须给回执**，
因为它改的是可见性，而可见性变化本身是看不见的。
