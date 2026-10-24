# 无对应 HTML 的界面汇总

> 目标要求：「审核标准是与之匹配的 html，**若无对应的 html，可以先汇总，后续再处理**」。
>
> 本文件 = 当前**没有可对照 HTML 原型**的全部界面（iOS + Android）。
> 后续要么补 HTML 原型，要么确认「不需要原型」（系统控件/一次性流程）。

---

## A. iOS —— 确实没有对应 HTML（需要补原型）

| # | 界面 | 文件 | 说明 | 建议 |
|---|---|---|---|---|
| A1 | 告警中心 | `AlarmsPage.swift` | 告警列表 + 类型筛选 + 处置 | 补一页（图2 语言）|
| A2 | 恢复备份 | `BackupPage.swift` | 选中备份文件后的恢复确认屏 | 补一页（危险操作卡）|
| A3 | 恢复向导 | `BackupStudio.swift` | 分区勾选 + 冲突策略 | 补一页（同 81 的向导语言）|
| A4 | 备份与云盘 | `BackupView.swift` | 云盘账号 + WebDAV 导出 | 补一页 |
| A5 | 保养历史 | `CareViews.swift` | 保养流水列表 | 补一页 |
| A6 | 导入 otpauth | `CredentialStudio.swift` | 粘贴 URI / 扫码导入 | 补一页 |
| A7 | 扫一扫 | `CredentialStudio.swift` | 通用扫码（系统相机）| N/A（系统控件）|
| A8 | 扫码核对 | `ReportVerifyView.swift` | 扫描回执校验 | 补一页 |
| A9 | 家庭设置 | `MemberCenterView.swift` | 家庭级开关（非单成员）| 补一页 |
| A10 | 本机保护 | `SecurityPage.swift` | 安全页内的子分组 | 可并入 40-security |

---

## B. iOS —— 有 HTML 但标题不同（不算缺失，只是用词差异）

| 界面 | 对应 HTML | 备注 |
|---|---|---|
| 同步时间 | 25-synctime「校准时间」| 见 DEVIATIONS A4 |
| 智能网关 | 23-gateway「网关配网」| 见 DEVIATIONS A3 |
| 门锁管理 | 20-locks「我的门锁」| 见 DEVIATIONS A2 |
| 凭证详情 | 13-key-detail「密码详情」| 见 DEVIATIONS A9 |
| 审计流水 | 44-audit「安全审计」| 见 DEVIATIONS A6 |
| 导出与分享 | 48-export「导出中心」| 见 DEVIATIONS A7 |
| 建档向导 | 31-member-wizard「添加成员」| — |
| 这台锁 | 03-devices「设备」| — |

---

## C. Android —— 没有对应 HTML（需要补原型）

| # | 界面 | 实现位置 | 说明 | 建议 |
|---|---|---|---|---|
| C1 | **AirTag 全屏层** | `MainActivity.KfApp` | 靠近时全屏雷达：3D 视差 + 朝向箭头 + 提示音 + 手动收起 | **补一页**（这是 Android 端最有辨识度的一屏，却没有原型）|
| C2 | **蓝牙权限/故障态** | `MainActivity` | 缺权限时整屏提示 + 去系统设置 | 可并入 80-states 的组件级规范 |
| C3 | 解绑确认框 | `MainActivity` | 单卡确认 + 后果说明 | 已有 05-rebind 原型，但**结构不同**（原型是双卡新旧对照）|

---

## D. Android —— 有原型但实现方式不同（有意）

| 界面 | 对应 HTML | 现状 | 判定 |
|---|---|---|---|
| 扫码添加门锁 | 02-scan（自绘取景框）| 用 **Google Code Scanner** 系统扫码器 | 有意：系统扫码免相机权限、无需自绘取景框；UI 不可控但更稳 |

---

## E. 统计

| 平台 | 界面总数 | 有 HTML 可对照 | 无 HTML（本文档 A/C 节）|
|---|---|---|---|
| iOS | 51 | 33 | **10**（A 节）+ 8 用词差异 |
| Android | 6 | 5 | **3**（C 节，含 1 个结构性差异）|

---

## 后续处理顺序（建议）

1. **C1 AirTag 全屏层** —— Android 端最独特的一屏，没有原型等于没法审
2. **A1 告警中心** —— iOS 高频入口（首页待处理告警要跳这里），却没有原型
3. A2/A3 备份恢复两个向导 —— 危险操作，值得有原型对齐文案
4. 其余按使用频率排