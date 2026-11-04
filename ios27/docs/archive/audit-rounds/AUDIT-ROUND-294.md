# AUDIT-ROUND-294 · 第 294 轮：权限与设置消费链核对 —— 无缺陷

> CI：`f0d38f8` build 全绿（errors=0）。

## 1. 隐私权限键（缺一个就崩）

| 代码用到 | 需要的 Info.plist 键 | 存在？ |
|---|---|---|
| CoreBluetooth | `NSBluetoothAlwaysUsageDescription` | ✅ |
| 同上（旧键） | `NSBluetoothPeripheralUsageDescription` | ✅ |
| Face ID | `NSFaceIDUsageDescription` | ✅ |
| **WebDAV 访问局域网** | **`NSLocalNetworkUsageDescription`** | ✅ |

再反向核一遍**代码里有没有用别的受限 API**：`AVCapture` / `PhotosPicker` / `CNContactStore` / `CLLocation` —— **全仓零使用** ✅
（文件导入走 `UIDocumentPicker`，不需要键。）

## 2. 通知授权闭环

| 环节 | 结论 |
|---|---|
| 申请授权 | ✅ `QuickActions:28` 启动即 `requestAuthorization([.alert,.sound,.badge])` |
| 设 delegate | ✅ 同一处（否则点击通知无反应） |
| 读取状态并让用户可行动 | ✅ 设置页 `NotifyAuth.label` + 跳系统设置的入口 |
| 授权失败留痕 | ✅ `notifyLog.error("用户未授予通知权限：到期提醒不会送达")` |

（这条以前是**真缺陷**：全仓从未调用 `requestAuthorization`、也没设 delegate —— 注释里留着修复经过。）

## 3. 设置项是否真被消费

| 设置 | 消费点 | 结论 |
|---|---|---|
| 「最近开门条数」`kf_recent_count` | `DoorScreen:1008` `Array(app.entries.prefix(store.recentCount))` | ✅ 真的限制条数 |
| 白名单 | 备份恢复只接受 `[3,5,10]`，与界面芯片一致 | ✅ |

## 4. 两屏同源核对

锁实况页与门页都读 `app.lock` / `app.lastStatus`，并都走 `app.refreshStatus()` ✅ —— 不存在「一屏缓存一屏实时」。

## 5. 方法论

**权限类缺陷的特点是「平时无声、首次调用即崩或永久静默」—— 所以要用「代码用到的 API ↔ plist 键」双向对表。**

| 单向查法 | 漏什么 |
|---|---|
| 只看 plist 有哪些键 | 漏「代码用了但没配」 |
| 只看代码用了什么 | 漏「配了但没用」 |
| **两边都要枚举并求差** | ✅ 两个方向都能发现 |

判据：**权限表要么双向对，要么别对 —— 单向核对只能证明「配过的没白配」，证明不了「用到的都配了」。**
