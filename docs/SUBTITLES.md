# 页内副标题基线（40 页全覆盖）

> 每页顶部 = 导航栏标题 + 页内大标题（30 Bold/-0.4）+ 本表副标题（16/textSub）。
> 与 HTML 的 navbar + .h1 + .sub 三层同构。
> 改副标题时的规则：**不写数字**（HTML 里的 mock 数字不能搬，App 的数字是活的，
> 由读数卡承担）；只写「这页是干什么的/怎么用」的说明句。

| 页 | 副标题 | 来源 |
|---|---|---|
| 保养历史 | 每次保养都记在这里，不做云同步 | CareViews |
| 备份工作室 | 数据只存在这台 iPhone | BackupStudio |
| 备份与恢复 | 数据只在这台 iPhone · 全程离线加密 | BackupPage |
| 备份与云盘 | 本机备份 · 云盘账号只存这一台 | BackupView |
| 本机保护 | 现在安全吗 · 有没有事 · 有哪些功能 | SecurityPage |
| 本机设置 | 这台手机上的保护与数据 | MePage |
| 成员 | 谁能开门 · 各自的授权来源 | MembersPage |
| 导出与分享 | 生成过程纯本地，不经过任何网络 | ExportCenter |
| 导入 otpauth | 从验证器 App 搬到本机台账 | CredentialStudio |
| 动态 | 这把锁今天发生了什么 | FeedPage |
| 防窥与遮蔽 | 口令与码值在本机怎么藏 | SecurityCenterView |
| 分享给安卓 | 这把锁的开锁二维码 | ShareToAndroidView |
| 固件升级 | 升级前请完成全部检查项 | FirmwarePage |
| 关怀提醒 | 生日与纪念日的本地提醒 | CareRemindersView |
| 归档成员 | 归档不删数据，名下钥匙转成「未分配」 | MemberCenterView |
| 换电指引 | 上次换电：还没有换电记录 | CareViews |
| 回收站 | 删掉的钥匙在这里，可以恢复 | CredentialBinView |
| 建档向导 | 给这位成员起个名字，之后全家都用它称呼 | MemberCenterView |
| 蓝牙钥匙串 | 随身开门的实体钥匙串 | DonglesPage |
| 录入指纹 | 每枚指纹都对应锁里的一个槽位 | AddFingerPage |
| 凭证详情 | 这一条凭证的码值与使用记录 | KeysPage |
| 认领还没分配的钥匙 | 把无主记录归到人 | MemberCenterView |
| 审计流水 | 谁在什么时候做了什么 | SecurityCenterView |
| 锁档案 | 这台锁的名字 / 符号 / 配色 | LockProfilePage |
| 锁体保养 | 五项清单 · 还没保养过 | CareViews |
| 添加密码 | 写入门锁 · 会占用密码库存 | AddKeyPage |
| 同步时间 | 锁钟偏差 · 写入手机时间 | DeviceHomeView |
| 退出处置向导 | 逐条处置：保留 / 移交 / 停用 | MemberCenterView |
| 外观工作室 | 正文始终是正文的颜色，不会因此变得看不清 | AppearancePage |
| 维护与保养 | 机械件也该有保养记录 | CarePage |
| 销毁与应急 | 不可逆操作 · 需要二次确认 | SecurityCenterView |
| 钥匙工坊 | 密码 / 临时码 / 指纹 / OTP | StudioPage |
| 钥匙管理 | 密码 / 指纹 / 临时码的台账 | KeysPage |
| 应用锁 | 打开 App 前先验一次口令 | AppLockSetupView |
| 这台锁 | 这把锁的身份与实时状态 | DevicePage |
| 诊断与自检 | 进入时算一次，动作后重算 | DiagnosticsPage |
| 智能网关 | 把门锁接到家里网络 | GatewayPage |
| 重复合并 | 选一位作为主档案，另一位并入 | MemberCenterView |
| App 图标 | 轻点任意一款立即生效 | IconPicker |
| OTP 与口令 | 锁端 ZOTP · 独立 TOTP · 静态备份码 | CredentialStudio |

---

## 覆盖统计

- XScreen 页总数：40
- 有副标题：40（**100%**）
- 重复副标题：0
- 跨文件同名页：0

来源列说明：HTML = 从 tools/proto 对应页的 .sub 搬运（无数字）；功能 = 我按「这页是干什么的」补写。