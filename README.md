# 离线锁管家 for iOS (全原生 SwiftUI)

智能锁离线管理端 — 对厂商原版 APK 的协议级 iOS 全原生移植。
针对最新 iOS 26 SDK 编译，**最低部署版本 iOS 26.5**，通过 GitHub Actions 云编译，本地无需 Mac。

界面按 iOS 26 平台原生设计语言实现：液态玻璃（Liquid Glass）、声明式 `Tab` 导航、
系统 `ContentUnavailableView` 空态、系统触觉反馈与符号动效。设计令牌集中在
`App/Core/DesignSystem.swift`（间距 4/8 节奏、圆角、44pt 触达、图标尺寸、动效时长、
明暗自适应语义色），页面不各自写死颜色与尺寸。

## 架构

```
App/Core/     协议与业务核心 (Swift 重写, 与已验证的 JS 核心做差分测试)
  HexKit        十六进制/字节工具
  AESKit        AES-128-ECB + ZeroPadding (CommonCrypto)
  ZKProtocol    0x87 帧 / KLV / 0x88 EKey 包络 / 令牌注入 / 三头型解析 / 粘包重组 / 广播解析
  ZKCmdBuilder  全部 40 条命令构造器 (01..25/30/31/32/35/38/41/43/44)
  ZOTP          临时密码 (冻结时钟差分验证)
  KeyGen        配网密钥族 (SecRandomCopyBytes CSPRNG)
  StatusParser  03 状态 / 16 日志解析 + rc 文案表
  PidMap        型号矩阵与能力开关 (布防/尾随/清密码/升级)
  Store         本地存储 (kf_* 键与小程序互通)
App/Services
  BLEService    CoreBluetooth: 扫描/连接/服务发现/20B 分片写/notify
  LockService   会话令牌生命周期 / 命令执行 / rc=3 自愈 / 配网编排 (23→05→01→08×4→21→03)
  HardwareService 蓝牙钥匙串 (cmd 41/43/44) + 网关 (cmd 30/31/35/38)
  DFUKit        ZIP 解析 + 原生 inflate + Nordic DFU (Secure FE59 / Legacy 1530) + cmd22 编排
  Attribution   开门归属推断 (R1 临时码窗口 / R2 唯一凭证+实时背书)
  BackupKit     全量备份包 + PBKDF2/AES-CBC/HMAC 信封 + 坚果云 WebDAV
App/UI        SwiftUI: 设备 / 凭证 / 记录 / 设置 4 Tab + 13 个功能页
Tests         XCTest 差分回归 — 与 fixtures/golden.json 逐字节断言
tools         golden.js — 用已验证的 JS 核心生成差分金标
vendor/app    已验证的 JS 业务核心 (仅用于生成金标, 不参与 App 构建)
```

## 为什么可信 (不要BUG)

协议、密码学、解析的每个原语都有**字节级差分测试**：
`tools/golden.js` 用经过 25 套 Node 测试验证的 JS 核心生成 40 条命令帧、
AES 向量（含 NIST）、状态/日志解析、广播解析、ZOTP（冻结时钟）、网关/钥匙串应答解析、
真实固件包解析等金标；CI 在 iOS 模拟器上跑 XCTest 逐字节断言 Swift 输出一致。
任何偏差都会在合并前失败。

## 云编译 (GitHub Actions)

推送到 GitHub 后自动构建 (macOS runner + 最新 Xcode):

```bash
git init && git add -A && git commit -m "feat: iOS native port"
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

构建流水线 (`.github/workflows/ios.yml`):
1. Node 重生成差分金标
2. `xcodegen generate` 生成 Xcode 工程
3. **XCTest 差分回归** (模拟器) — 测试不过即失败
4. 模拟器 Release 构建
5. 真机未签名 IPA (`CODE_SIGNING_ALLOWED=NO`)
6. 上传构建产物 (Actions → Artifacts → `OfflineLock-build`)

## 安装到手机

未签名 IPA 需要自签 (免费 Apple ID 即可):
- **AltStore / SideStore**: 手机与电脑装 AltServer, 用 Apple ID 侧载 `OfflineLock-unsigned.ipa`
- **Sideloadly**: 拖入 IPA + Apple ID 自动签名安装
- **Xcode** (如有 Mac): 打开 `xcodegen generate` 生成的工程直接跑真机

首次使用: 设置 → 蓝牙权限允许 → 添加设备 (先在门锁上做键盘重置)。

## 同步小程序侧业务改动

`vendor/app/` 是已验证 JS 核心的**冻结快照**（只保留 golden.js 依赖闭包内的 21 个文件）。
小程序侧 (`../miniprogram-app`) 协议/业务有改动时：把对应 .js 覆盖进 vendor/app 同路径，
然后 `node tools/golden.js` 重新生成金标——若 Swift 与 JS 行为出现分歧，差分测试会当场失败，
此时以 JS（真机验证过）为准修正 Swift。
