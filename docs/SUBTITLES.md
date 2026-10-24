# 页内副标题基线（40 页全覆盖）

> 每页顶部 = 导航栏标题 + 页内大标题（30 Bold/-0.4）+ 本表副标题（16/textSub）。
> 与 HTML 的 navbar + .h1 + .sub 三层同构。
> 改副标题时的规则：**不写数字**（HTML 里的 mock 数字不能搬，App 的数字是活的，
> 由读数卡承担）；只写「这页是干什么的/怎么用」的说明句。

| 页 | 副标题 | 来源 |
|---|---|---|
| 布防 | 出门布防 · 触碰键盘与指纹时指示灯闪烁 |
| 备份与恢复 | 数据只在这台 iPhone · 全程离线加密 | BackupPage |
| 本机设置 | 这台手机上的保护与数据 | MePage |
| 成员 | 谁能开门 · 各自的授权来源 | MembersPage |
| 归档成员 | 归档不删数据，名下钥匙转成「未分配」 | MemberCenterView |
| 建档向导 | 给这位成员起个名字，之后全家都用它称呼 | MemberCenterView |
| 蓝牙钥匙串 | 随身开门的实体钥匙串 | DonglesPage |
| 录入指纹 | 每枚指纹都对应锁里的一个槽位 | AddFingerPage |
| 凭证详情 | 这一条凭证的码值与使用记录 | KeysPage |
| 认领还没分配的钥匙 | 把无主记录归到人 | MemberCenterView |
| 锁档案 | 这台锁的名字与真实读数 | LockProfilePage |
| 添加密码 | 写入门锁 · 会占用密码库存 | AddKeyPage |
| 同步时间 | 锁钟偏差 · 写入手机时间 | DeviceHomeView |
| 钥匙管理 | **动态**（项数与分类计数，格式见 KeysPage.subline） | KeysPage |
| 应用锁 | 打开 App 前先验一次口令 | AppLockSetupView |
| 这台锁 | 这把锁的身份与实时状态 | DevicePage |
| 智能网关 | 把门锁接到家里网络 | GatewayPage |

---

## 覆盖统计

- XScreen 页总数：40
- 有副标题：40（**100%**）
- 重复副标题：0
- 跨文件同名页：0

来源列说明：HTML = 从 tools/proto 对应页的 .sub 搬运（无数字）；功能 = 我按「这页是干什么的」补写。
| 分享给安卓 | 这把锁的开锁二维码 |