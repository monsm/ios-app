# AUDIT-ROUND-20 · 第二十轮：空壳模式漏了通知面

> CI：`80f6993` 已验证全绿（build errors=0、金标 test_ok=1、0 失败）；本轮提交待回执

## 1. 缺陷：进了空壳，通知中心还在念真实名字

SEC-03 修的是"空壳模式下数据层返回空集"。但**通知面没管**：

- `c6.alert.<mac>.p<alias>.<档位>` —— 凭证到期提醒，正文带凭证名；
- `c6.batt.<mac>.l<level>` —— 低电提醒，正文是「<锁名>」只剩 N%。

用户用胁迫码进入空壳后，界面是空的，可**通知中心里还躺着这些文案**，
而且已排的提醒到点还会弹。等于当着胁迫者的面把「前门密码」「<锁名>」念出来 ——
这正是空壳模式要防的事。

## 2. 修法

新增 `CredentialOrg.cancelAllForDecoy()`：

- 走**同一条串行队列**（与排程/取消共用），不会与正在进行的排程交错；
- 用 `c6.` 前缀整族识别（`isOwnNotification`），两个生产者的文案都带名字，都要清；
- `removePendingNotificationRequests` + `removeAllDeliveredNotifications` —— 
  已送达的那批留着一样泄露；
- **幂等守卫**：`reload` 频繁调用，只在"这次真的进入空壳"时清一次，退出时复位。

调用点在 `AppModel.reload` 的 `DB.setDecoy(decoyMode)` 之后（与 SEC-03 同一处），
退出空壳走 else 分支复位守卫。

## 3. 新增断言

`testOwnNotificationIDsAreRecognisable`：真实标识形状（含 `c6.batt.*`）都必须被识别，
非本 App 前缀不许误杀。

## 4. 方法论

**"数据层已隔离"不等于"这个模式已经隔离"。** 一个 App 的信息出口至少有四条：
界面、存储、**通知**、剪贴板。SEC-03 只覆盖了前两条；这一轮补的是第三条。
（第四条剪贴板在更早的轮次已由 `privacy` 闸门第 1 条判据守住。）

检查清单可以固定下来：**每加一个"隐藏/受限模式"，都要把四条出口逐一问一遍。**
