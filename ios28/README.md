# 阈 / Threshold · iOS

> 一个完全离线的门锁客户端。协议层照搬已验证实现；**界面、交互、信息架构全部重写**。

```
ios27（上一版）                 ios28（这一版）
  冷石墨 + 黄铜 + 仪器面板        陶土纸 + 日光 + 一扇窗
  V7/V8 两套设计系统并行         一套 DAYLIGHT 令牌 + 一套组件语法
  25 页 + 11 sheet               21 个 Dest + 3 个 Tab 根 + 4 个 sheet
  43 条路由                      21 条路由，3 Tab + 设置独立栈
```

---

## 这是什么

- **离线**：没有服务器、没有账号。蓝牙直连门锁。
- **真实**：开锁、写密码、录指纹、读日志、校时、布防、配网关、刷固件，全部走真协议。
- **诚实**：镜头只在门锁真的回执后才走满；失败停在断点并给出原因。
- **重新设计**：不是换皮。设计语言、组件库、导航、页面、动效都是新的（`Gates/lineage.js` 机器证明旧设计符号零残留）。

---

## 快速开始

```bash
cd ios28

# 1. 静态闸门（本机可跑，不需要 Mac）
npm install
node Gates/allgates.js

# 2. 视觉验收台（HTML → Edge headless 截图）
node DesignLab/run.js
#    → DesignLab/out/index.html
#    → DesignLab/shots/*.png（浅色 + 深色）

# 3. 真编译（需要 macOS + Xcode 27；或推到 GitHub 走 CI）
xcodegen generate
xcodebuild build -project Threshold.xcodeproj -scheme Threshold \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

**签名**：`project.yml` 里是 `CODE_SIGN_STYLE: Automatic`，没有写死 Team。
在 Xcode 里选一次自己的 Team 即可；CI 全程 `CODE_SIGNING_ALLOWED=NO`。

**安装**：未签名 IPA 需要用自己的 Apple ID 签一次（Sideloadly / AltStore / Xcode）。

---

## 文档

| 文件 | 内容 |
|---|---|
| [docs/BACKEND.md](docs/BACKEND.md) | **后台实际功能点**：协议事实、43 项能力、数据存在哪、安全边界 |
| [docs/DESIGN.md](docs/DESIGN.md) | DAYLIGHT 设计语言：概念、令牌、组件、信息架构、页面清单 |
| [docs/ENGINE-PORT.md](docs/ENGINE-PORT.md) | Engine 移植记录：照搬了什么、改了哪两处、为什么 |

---

## 结构

```
ios28/
├── App/
│   ├── ThresholdApp.swift        入口：门禁 / Shell / 三个 Tab
│   ├── Core/                     投影层：AppModel、Router、成员/凭证/记录的视图模型
│   ├── Design/                   DAYLIGHT：令牌、日光场、组件、控件
│   ├── Features/                 Today / Access / Log / Settings / Shared
│   └── Engine/                   协议 / 密码学 / 存储 / BLE（照搬，已验证）
├── Gates/                        6 道静态闸门
├── DesignLab/                    令牌 → CSS → Edge 截图
├── Tools/                        令牌生成、图标生成
└── docs/
```

---

## 6 道机器闸门

| 闸门 | 判什么 |
|---|---|
| `swiftparse` | 真 Swift 语法树（tree-sitter）的 ERROR / MISSING |
| `tokensync` | `Tokens.swift` / `tokens.css` 与 `tokens.json` 完全一致 |
| `tokens` | 页面层没有颜色 / 字号字面量 |
| `lineage` | 与上一版 V7/V8 设计系统彻底切割（旧符号零残留） |
| `destmap` | `Dest` 台账 ↔ 实现一一对应 |
| `contrast` | 明暗两套文字色的 WCAG 对比度 |

---

## 诚实的边界

| 项 | 状态 |
|---|---|
| 静态闸门 | ✅ 全绿（6 道） |
| 视觉验收台 | ✅ 7 屏 × 明暗两套已渲染 |
| 真编译 | ✅ 通过（CI：`build_ok=1` `archive_ok=1` `errors=0`，iOS 27 SDK，未签名 IPA 已打包） |
| 真机手感 | ❌ 未验（镜头按压、触觉、真实材质折射） |
| 动态字体极端值 | ⚠️ 已按令牌缩放，AX5 仍要看真机 |
| 横屏 / iPad | ❌ 只支持竖屏 iPhone |
| 单元测试 | ❌ 本版没有（`Tests/` 空）。上一版的 8 个测试文件没有随界面重写一起搬过来 —— `xcodebuild test` 在这台自托管 runner 上**永远跑不完**（见 `ios27.yml` 的说明），硬接进 CI 会堵死整条队列 |

**这份 README 不会用"已完成"掩盖上面几项没做到的验证。**

