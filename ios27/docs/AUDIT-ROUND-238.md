# AUDIT-ROUND-238 · 第 238 轮：把 `owner` 的两种口径收干净（投影侧）

> CI：**`1d40003` build 全绿**（电量统一编译通过）；`ac0e3ed` 排队中。

## 1. 上一轮留下的最后一处

Round 237 修了台账 `owner` 的写入侧与三处计数，但**投影侧还有一处**：

`AppModel.reloadKeys` 的手机钥匙分支写的是 `owner: k.memberName`（名字），
而同一个 `KeyItem.owner` 在密码/指纹分支里存的是 `p.owner` / `f.owner`（**成员 id**）。

| 分支 | `KeyItem.owner` |
|---|---|
| 密码 / 指纹 | **成员 id** |
| **手机钥匙** | **成员名** ❌ |

## 2. 修法

`owner: k.memberID.isEmpty ? k.memberName : k.memberID` —— 优先 id；
旧手机钥匙记录可能没有 `memberID`，那时回落名字（读侧 `ownerName` 已有名字回退，所以仍能显示）。

## 3. `owner` 归一化到此收口

| 层 | 状态 |
|---|---|
| 台账写入（`addPassword`） | ✅ 237：统一成 id |
| 台账读取（`ownerName`） | ✅ 237：id 优先、名字回退（兼容旧数据） |
| 计数（`MemberCard.keyCount` + 两处 `KeysOwnerRow`） | ✅ 237：两种口径都认 |
| **投影（`KeyItem.owner`）** | ✅ **本轮** |

## 4. 方法论

**修完「写入侧 + 读取侧」不等于修完 —— 中间还有「投影层」。**

| 层 | 例子 |
|---|---|
| 存储 | `LedgerPwd.owner` |
| 投影 | `KeyItem.owner` / `MemberCard` |
| 展示 | `ownerName(_:)` |

三层的口径必须一起定，否则修好两层、第三层还在混 —— 而**表现**会变成「某些地方对了、某些地方还不对」，
比全都错更难定位。

判据：**处理一个「字段口径」问题时，先列出这个字段流经的三层（存储 / 投影 / 展示），逐层确认。**
