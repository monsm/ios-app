# BUILD-FIX-2 · CI 可读性 / callsig2 静态闸门 / 审计 C 列交付项

> 快照：2026-10-31 21:40 +08:00，`HEAD = d2f9bde`（工作树干净）。
> 本机限制：Windows，无 xcodebuild。真编译只能在 CI 上跑；本报告把「CI 到底报了什么」当作第一等事实来处理。

## 结论（先看这段）

1. **CI 结果能读到，但不是走 HTTP。** `github.com` 与 `api.github.com` 在本机被解析到非公网地址，`web_fetch` 直接拒绝（原文 `URL hostname "github.com" resolves to a non-public IP address`）。可读路径是 git：CI 会把 `build.log` / `errors.txt` / `meta.txt` 推到一个孤儿分支 `ci-log`，`git fetch origin` 之后就能 `git show origin/ci-log:errors.txt` 读原文。
2. **用这条路径拿到了最近一次真编译**（run `41205021986`，commit `c2d9562`）：4 条 error、2 个根因，全部在 `App/Features/Shared/V7Extras.swift`。`f8020cc` 已把它修掉；本轮新增的闸门在**修前的 c2d9562 上精确复现了这 2 条**（行号 150/417 与 CI 一致），在修后的树上 0 条。
3. **新增第 16 道闸门 `Gates/callsig2.js`**：1030 个 func、264 个构造签名、2068 处调用点，判 7 类（标签/个数/构造签名/@MainActor 隔离/let 赋值/无标签 tuple 成员/类型成员）。注入 5 类真编译错自测 **5/5 命中**。
4. **审计 C 列三项落地**：构建号可注入（`CFBundleVersion` 走构建设置）、3 个显式 `import`、删掉没有消费方的相机键、蓝牙文案与 WebDAV 的实际能力对齐。
5. 推送：`f8020cc..d2f9bde`，第 1 次尝试即成功（流程里仍保留最多 4 次重试）。

---

## 一、CI 结果可读性（第一件事的答案）

### 1.1 两条 URL 都不可达（与委派方的现象一致）

| URL | 结果 | 原文 |
|---|---|---|
| `https://github.com/monsm/ios-app/actions/workflows/ios27.yml` | 拒绝 | `URL hostname "github.com" resolves to a non-public IP address` |
| `https://api.github.com/repos/monsm/ios-app/actions/runs?per_page=5` | 拒绝 | `URL hostname "api.github.com" resolves to a non-public IP address` |

这是**取数层**的拒绝（域名解析到非公网地址），不是 403/404，重试无意义。

### 1.2 替代路径：`ci-log` 分支（`c2d9562` 引入）

```text
$ git fetch origin --quiet
$ git show origin/ci-log:meta.txt
commit=c2d95629170d8eac1c43deeb8d68be70e2347d46
run=41205021986
job=build
errors=7
```

`errors.txt` 原文（`errors=7` 是含缩进续行的行数，去重后 4 条）：

```text
App/Features/Shared/V7Extras.swift:136:67: error: generic parameter 'each Content' could not be inferred
App/Features/Shared/V7Extras.swift:150:34: error: type 'V.List' has no member 'searchRow'
App/Features/Shared/V7Extras.swift:412:35: error: generic parameter 'each Content' could not be inferred
App/Features/Shared/V7Extras.swift:417:34: error: type 'V.List' has no member 'searchRow'
```

判读：**2 个根因，不是 4 个**。`VFieldRow.body`（136）与 `VBusyRow.body`（412）里，同一个表达式链末端 `.frame(minHeight: V.List.searchRow)` 失败后，外层 `HStack` 的 content pack 就推不出来（`each Content`），于是每个 body 各多报一条级联错误。修掉 `searchRow`，两条 `each Content` 一起消失 —— 这也解释了为什么 `f8020cc` 只改了两行却关掉了 4 条 annotation。

### 1.3 再上一轮：两轮合计 9 条

web 不可达时，从本机残留的已保存 annotation（`D:\aapk\.tmp-audit-c\ann_*.json`、`runs_*.json`）读到的历史：

| run | commit | 结果 | 条数 | 错误类 |
|---|---|---|---:|---|
| 41201710690 | 1f87607 | failure | 5 | `StatusSnapshot` 无成员 ×2、`collectAll()` 隔离、`doorName` 参数标签、`Int`→`UInt32` |
| 41203581478 | 23f46bb | failure | 4 | tuple `.after`、`cascadeBinMember` 隔离、`VReading(size:)`、`GatewayRow` let 赋值 |
| 41205021986 | c2d9562 | failure | 4（2 根因） | `V.List.searchRow` ×2 + 级联 `each Content` ×2 |

前两轮 5 + 4 = **9 条**，与「连着两轮报 9 条真错」吻合；第三轮是本轮新拿到的。

---

## 二、callsig2 判什么（第二件事）

`ios27/Gates/callsig2.js`，已接入 `Gates/allgates.js`（15 → 16 道）。

### 2.1 数据来源

对 `App/**/*.swift`（148 个文件）做三件事：

1. **遮罩**：注释换空格；字符串内容换 `~`（不是空格 —— 否则 `cached("yyyy-MM-dd")` 这种「一个位置实参」会被当成零个实参）。
2. **结构**：括号/花括号配对；`statements()` 按顶层换行与 `;` 切语句（同一行的 `struct A { var x: Int; var y: Int }` 也要拆开）。
3. **建表**：类型声明（含**嵌套作用域**，键是 `Outer.Inner`）、func 签名、构造签名（显式 init + struct 成员逐一初始化器）、成员表（存储/计算属性、enum case、方法、嵌套类型）、extension 成员（合并进基类型）。

### 2.2 七条判据

| 规则 | 判什么 | 等级 |
|---|---|---|
| **R1** | 调用点标签与声明不符：多参数 / 缺参数 / 标签位置错 / 缺标签 | 红 |
| **R2** | 构造调用（struct 成员逐一初始化器 / 显式 init）的标签与个数 | 红 |
| **R3** | **显式** `@MainActor` 的成员在非 MainActor 同步上下文被直接调用 | 红 |
| **R4** | `值.let属性 = …`（let 存储属性被赋值） | 红 |
| **R5** | 无标签 tuple 返回值用 `.成员` 访问（`.after` 那一类） | 红 |
| **R6** | `类型名.成员` 不存在，**支持成员链** `V.List.searchRow` | 红 |
| **R7** | 局部变量成员不存在（只在「同一函数体里有唯一类型标注」时才判） | 提示 |

### 2.3 关键：Swift 的实参匹配是**按标签**，不是按位置

```swift
static func cached(_ format: String, timeZone: TimeZone? = nil, locale: String = "en_US_POSIX") -> DateFormatter
cached("yyyy-MM-dd", timeZone: TimeZone(identifier: "UTC"))   // 合法：跳过有默认值的 locale
```

所以判据是**游标式匹配**：具名实参从当前位置往后找同名参数，被跳过的中间参数必须都有默认值；位置实参按顺序消费；尾随闭包绑定最后一个参数。
第一版按位置逐项比对，一次误报 502 条 —— 规则搞错的代价比不判还大。

### 2.4 R3 的边界（这条最容易判过火）

- 只认**显式** `@MainActor`（写在 func/类型声明前）。
- 不认「`struct X: View` 隐含 MainActor」：`View` 是 `@MainActor @preconcurrency` 协议，Swift 5 语言模式下违例只降级为**告警**；CI 的三次真错也都只出在**显式标注**的方法上（`collectAll()`、`cascadeBinMember`）。把 View 体系也当隔离源，会一次性误报 22 条 `Shell/Destinations.swift`（那是全仓最正常的 `static func view(_:) -> some View`）。

---

## 三、先证明它不是 no-op（自测 + 回放）

静态闸门最危险的状态是「全绿但其实什么都没判」（旧的 `callsig.js` 现在就输出 `检查 0 处具名调用`）。所以做了两步验证：

### 3.1 注入自测：5 类真编译错 5/5 命中

在临时树 `App/__selftest.swift` 里注入（不进仓库）：

| 注入 | CI 对应错误类 | 闸门输出 |
|---|---|---|
| `VReading(value: "x", unit: nil, size: 12)` | `extra argument 'size' in call` | `多出参数 "size:"（声明参数：value, unit, font, tint, animated）` ✅ |
| `VReading("x")` | `missing argument label 'value:' in call` | `第 1 个实参缺标签，声明要求 "value:"` ✅ |
| `@MainActor func f()` + 非隔离同步调用 | `main actor-isolated … in a sync nonisolated context` | `… 是 @MainActor，调用方 … 是同步 nonisolated 上下文` ✅ |
| `var r: VReading; r.value = "x"`（value 是 let） | `cannot assign to property: 'value' is a 'let' constant` | `r.value 被赋值，但 VReading.value 声明为 let` ✅ |
| `VReading.noSuchStaticMember` | `value of type 'V' has no member …` | `VReading.noSuchStaticMember —— VReading 没有成员 noSuchStaticMember` ✅ |

### 3.2 回放真失败 commit：`c2d9562`

```text
$ git worktree add --detach .tmp-wt c2d9562
$ node Gates/callsig2.js          # 用本轮的闸门跑修前的树
callsig2: FAIL — 2 处高置信度问题
  Features/Shared/V7Extras.swift:150  V.List.searchRow —— V.List 没有成员 searchRow
  Features/Shared/V7Extras.swift:417  V.List.searchRow —— V.List 没有成员 searchRow
```

**行号 150/417 与 CI 的 annotation 完全一致。** 在修后的当前树上：

```text
$ node Gates/callsig2.js
callsig2: 148 个文件，1030 个 func，264 个构造签名，检查 2068 处调用
callsig2: OK — 标签/参数个数/@MainActor 隔离/let 赋值/tuple 成员/静态成员全部通过
```

---

## 四、开发过程中消掉的 11 个误报（这才是闸门的工程量）

每一条都是「闸门判错了」而不是「代码错了」。不修掉它们，闸门要么误红要么被关掉。

| # | 现象 | 原因 | 修法 |
|---|---|---|---|
| 1 | 502 条参数顺序错 | 按位置比对标签，忽略了「跳过的参数有默认值」 | 游标式标签匹配（§2.3） |
| 2 | `cached(…)` / `enumVal(…)` 报「缺参数」 | 字符串遮罩成空格后，唯一的位置实参变成空串被丢弃 | 字符串内容遮成 `~` |
| 3 | `AutoCal` / `BkEvent` 报「多出参数」 | 一行写完的 `struct A { var x: Int; var y: Int }` 只读到第一个成员 | `statements()` 按 `;` 与换行切语句 |
| 4 | `Locked(CheckedContinuation<Void, Error>?)` 报「多出位置实参」 | 泛型实参里的逗号被当成分隔符 | `splitTop` 增加尖括号深度 |
| 5 | 被扩展类型的成员全部判错 | `extension X` 先被读到，占住了 `X` 的槽位，真实声明没覆盖 | 非 extension 声明覆盖 extension 桩 |
| 6 | `Candidate(id:name:pid:…)` 误报 | 两个文件各有一个 `Candidate`，按简单名索引互相覆盖 | 类型键限定为 `Outer.Inner` |
| 7 | `MemberMergeSheet(primary:)` / `CredBinSheet(mac:)` 报缺参数 | 把 `@State private var x: String?` 当成必填 | 属性包装器不参与必填（依据：`AddLockScreen()` 在编译通过的 e45c804 上就有 4 个 `@State` 可选属性） |
| 8 | `Gateway(mac:)` 报「多出参数 mac:」 | `extension Gateway { init?(fromDict:) }` 被当成压制了成员逐一初始化器 | 扩展里的 init **不**压制；同类型内声明的 init 才压制 |
| 9 | 22 条 `Shell/Destinations.swift` 隔离违规 | 把「`struct X: View`」当成构造器也是 @MainActor | 只认显式 `@MainActor`（§2.4） |
| 10 | `raw.contains` 误报 `PidMap` 没有成员 | 三元表达式 `? raw : PidMap.productName(…)` 里的冒号被当成类型标注 | 标注只认声明位，且类型名后必须紧跟 `,` `)` `=` 或空白 |
| 11 | **`V.List.searchRow` 完全没报**（真 bug 漏检） | 成员访问正则只取两个标识符，`V.List.searchRow` 的第二段被吃掉 | 改成成员链，沿嵌套类型逐段解析 |

第 11 条正好就是 CI 这次报的错 —— 这个闸门是拿真实的失败 commit 校准出来的，不是凭空写的。

---

## 五、本轮改了什么

| 文件 | 改动 | 为什么 |
|---|---|---|
| `ios27/Gates/callsig2.js` | **新增** | 第二件事的主体；7 条判据 + 自测校准 |
| `ios27/Gates/allgates.js` | 接入 `callsig2` | 15 → 16 道，CI 的 gates job 会自动跑 |
| `.github/workflows/ios27.yml` | `CURRENT_PROJECT_VERSION` 传给 build 与 archive；生成后自检 `CFBundleVersion`；job 名 11 → 16 道 | C-03 |
| `ios27/project.yml` | `CFBundleVersion: $(CURRENT_PROJECT_VERSION)` + `CURRENT_PROJECT_VERSION: "1"`；删 `NSCameraUsageDescription`；蓝牙文案改写 | C-03 / C-08 |
| `ios27/App/Engine/AppLock.swift` | `+import Combine` | C-07（`ObservableObject`/`@Published` 不该靠 SwiftUI 隐式再导出） |
| `ios27/App/Design/Tokens.swift` | `+import UIKit` | C-07（`UIColor`） |
| `ios27/App/Engine/FrameRedact.swift` | `+import Foundation` | C-07（`String.range(of:)`；原先一个 import 都没有） |

### 5.1 C-03 构建号（XcodeGen 不支持环境变量替换）

XcodeGen 不会展开环境变量，所以走**构建设置引用**而不是字符串替换：

```yaml
# project.yml
settings.base.CURRENT_PROJECT_VERSION: "1"        # 本地回落
info.properties.CFBundleVersion: $(CURRENT_PROJECT_VERSION)
```
```yaml
# ios27.yml
xcodebuild build … CURRENT_PROJECT_VERSION=${{ github.run_number }}
```

xcodebuild 的命令行设置优先于工程设置，Info.plist 里的 `$(…)` 在打包时由构建系统展开 —— 这是 Xcode 的标准做法，比 PlistBuddy 后处理少一个失败点。另外在 `generate` 之后加了一步自检：`App/Info.plist` 里 `CFBundleVersion` 如果不是引用而是写死的 `1`，直接 `::error::` 失败（防止以后有人改回去而注入静默失效）。

### 5.2 C-08 权限与文案

- **删掉 `NSCameraUsageDescription`**：全仓 `AVCapture*` / `UIImagePickerController` / `DataScannerViewController` 消费方为 0；`"camera"` 只作为 SF Symbol 出现在 `CredentialStudioParts.swift:173,202`。声明未使用能力会被 App Store 问询。
- **蓝牙文案**：原文「App 不联网、不上传任何数据」与 `BackupStudioScreen.swift:443,459` 用 `URLSession` 做 WebDAV PROPFIND/PUT 矛盾。改为「门锁通信不经过网络；备份工作室可选连你自建的 WebDAV」—— 既保留“门锁这条链不联网”的真实承诺，也不否认用户自建服务器这条可选路径。

---

## 六、推送

```text
f8020cc..d2f9bde  main -> main
PUSH OK    （第 1 次尝试；脚本保留最多 4 次重试）
```

远端 `main` = `d2f9bdedc4437a8514e9550c4afcc9a9dfdb550d`。

> 说明：`f8020cc` 是并行会话提交的（三处 `import`、`project.yml`、`callsig2` 初版都在这个 commit 里）；`d2f9bde` 是本会话补的 workflow / allgates / callsig2 成员链与一批误报修正。两个 commit 都在远端。

---

## 七、剩余风险（诚实清单）

1. **类型不匹配判不了**（`Int` → `UInt32` 那一类）。没有类型推导，静态做不到，只能靠 CI 一轮。
2. **带闭包实参的调用点整条跳过**（`argText` 里有花括号就放弃） —— SwiftUI 组件调用大量如此。本期覆盖的是 2068 处无闭包调用。
3. **属性包装器不参与必填判定**（§四第 7 条）：用「宁可漏报」换「不误报」，代价是 `@State` 相关的缺参数漏判。
4. **泛型实参推导、协议见证、宏展开、KeyPath、运算符重载** 一律不判。
5. **本地没有编译器**：闸门只能证明「这 7 类没犯」，不能证明「能编译」。真编译仍是唯一硬门槛。
6. **`CFBundleVersion` 的展开值需要一次真 CI 确认**：自检只能证明引用在，不能证明 `$(…)` 展开成了 run_number。装包后可用 `plutil -p Payload/LockKeeper.app/Info.plist` 复核。
7. **`ci-log` 分支是 force-push 的单提交孤儿分支**，故意只留最近一次；代价是每次 CI 都会重写远端一个分支（对历史无副作用，但会出现在分支列表里）。
8. **旧的 `Gates/callsig.js` 仍是 no-op**（`检查 0 处具名调用`）。本轮没有删它（避免 16 道变 15 道引起文档失配），但真正起作用的是 `callsig2`；下一步应当把 `callsig` 退役。

## 附：可复跑命令

```powershell
cd D:\aapk\ios-app\ios27
node Gates/allgates.js                      # 16 道全绿
node Gates/callsig2.js                      # 单跑签名闸门

# 读最近一次真编译的错误（无需 HTTP 出网）
cd D:\aapk\ios-app
git fetch origin --quiet
git show origin/ci-log:meta.txt
git show origin/ci-log:errors.txt
```
