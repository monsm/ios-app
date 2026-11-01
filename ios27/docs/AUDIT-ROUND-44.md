# AUDIT-ROUND-44 · 第四十四轮：换机后成员的「备注 / 关怀文案 / 归档标记」全丢

> CI：`59384b6` 已验证（errors=0、build_ok=1）；本轮本地提交，**不推送**（攒批）。

## 1. 缺陷：备份带得走成员，带不走成员的档案

`Member` 只有六个字段：`id / name / relation / phone / color / at`。
而成员的其它资料全在 `kf_member_ext`（`MemberExt`）：

> 角色（main/member/guest）· 备注名 · 关怀文案 · 访客欢迎语 · 分组标签 ·
> 归档标记 · 代管标记 · 紧急管理员 · 常用锁 · 紧急联系人

备份包里 **没有** 这一族（`Globals` 里没有对应字段），恢复流程也不写回。
结果：

> 换机迁移后，成员名单还在、凭证归属还在，
> 但每个人的备注、关怀文案、归档状态**全部变成默认值**，而且界面不会提示"这些丢了"。

而被归档的成员会因为 `archived = false` **重新出现在名单里** —— 这是用户能直接看见的错误。

## 2. 修法（向后兼容，不动 schema 版本）

1. `MemberExt` 加 `Equatable`（只用于"是否仍是全默认档案"的判断）；
2. `BackupBundle.Globals` 新增 `var memberExt: [String: MemberExt]? = nil`
   —— 可选 + 默认 nil，旧包解码为 nil，新包给旧版本读也只是忽略未知键；
3. 导出：`memberExt: MemberHub.allExt().isEmpty ? nil : MemberHub.allExt()`；
4. 恢复：`importMemberExt(_:remap:)` 用同一张 id 重映射写回，
   **只在目标成员仍是全默认档案时写** —— 这样二次恢复同一个包不会覆盖用户此后改过的内容。

## 3. 待验证

本轮改动只过了形状闸门；`Globals` 成员构造、`Equatable` 合成、`MemberHub.ext/saveExt` 调用
都要等 CI 编译确认。**在回执前不声称通过。**

## 4. 方法论

**"备份恢复了成员"这句话里的"成员"到底指什么，要按字段核。**
本仓把成员资料拆成两处（`kf_members` 基础档 + `kf_member_ext` 扩展档），
备份只收前者 —— 这种"同一实体拆两处存储"的架构，最容易在迁移路径上漏掉一半。

判据：**每加一个 `kf_<实体>_ext` 之类的旁挂表，都要同时问"它进不进备份、恢复时怎么 remap"。**
