# AUDIT-ROUND-197 · 第 197 轮：**CI 红了**（我上一轮写错），并把这类错误变成闸门

## 1. 红的是什么

`940f4fa`（第 194 轮的单飞修复）CI 回执：

```
build_ok=0  archive_ok=0
App/Engine/LockServiceLink.swift:46:17: error: extensions must not contain stored properties
```

**我把 `private var connecting: (mac:task:)` 写进了 `extension LockService { … }`。**
Swift 不允许扩展里有存储属性 —— 这是硬约束，我本该知道。

更糟的是：**本地 22 道闸门全绿**。也就是说这条错误在本地完全不可见，只能靠 CI 真编译器。

## 2. 修复

把属性移到 `LockService.swift` 的**类体**里（`rawTrace` 旁边），并改成 internal ——
因为 `LockServiceLink.swift` 是另一个文件里的扩展，`private` 跨文件不可见。

`b49eebd` 已推送。

## 3. 把这类错误变成闸门

`Gates/swiftcheck.js` 新增一条规则：**`extension` 里不许声明实例存储属性**。

```js
const PROP = /^\s*(?:private|…)?\s*(?:var|let)\s+\w+\s*(?::[^={]+|=…)$/
if (atBodyLevel && PROP.test(s)) → FAIL
```

### 写了三版才对（过程本身值得记）

| 版本 | 结果 | 原因 |
|---|---|---|
| v1：自己数花括号判块范围 | **误报 256 处** | 字符串/注释里的括号把深度带偏 |
| v2：改用"剥壳后的行 + 行首深度" | **误报 5 处** | 把函数体内的局部 `let x = …` 当成存储属性 |
| v3：只在**直接体内**（父深度+1）判 | 又发现 5 处 | 那是 `static let` —— **扩展里静态存储属性是合法的** |
| v4：排除 `static` | ✅ **0 误报** | |

### 双向验证

往 `extension LockService {` 里临时塞 `private var __probeStored: Int = 0`：

```
App/Engine/LockServiceLink.swift:6  extension 里声明了存储属性 —— Swift 不允许
swiftcheck: FAIL — 1 处不平衡
```

移除后 22/22 全绿。

## 4. 方法论

**"本地闸门全绿"不等于"能编译" —— 这次是第 3 次证明。**

| 本地闸门能抓 | 本地闸门抓不到 |
|---|---|
| 括号/引号不平衡 | 类型错误、访问控制、扩展存储属性 |
| 已知模式的字符串扫描 | **任何没被写成规则的语言约束** |

所以每踩一次"CI 才发现的错"，正确的反应不是"下次小心"，
而是**问一句"这个约束能不能写成规则"** —— 能，就写；不能，才靠小心。

本轮这条能写，已写。

## 5. 顺带

这也解释了为什么第 194 轮之后 CI 一直停在 `940f4fa` 不动：
**红 build 会让后续所有提交都排不上**（`43397b1` / `720e56d` 从未被编译过）。
所以这次修复不只是修一个错，是把整条流水线解锁。
