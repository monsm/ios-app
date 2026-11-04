# AUDIT-ROUND-115 · 第一百一十五轮：一个 0 字节的 Swift 文件

> CI：`526d101` 全绿（`errors=0`、`build_ok=1`、`archive_ok=1`、`warnings=0`）；`21f2e74` 待回执。

## 1. 怎么找到的：按「从未在报告里出现」筛文件

用脚本比对 `App/` 下 148 个 `.swift` 与全部 `AUDIT-*.md` 的正文，找出**从未被任何报告提到**的文件：

```
总文件: 148   从未出现: 27
```

这 27 个里有几个我确实改过（`BatteryCare` / `TimeFormat` / `LockStats` / `RecordSearchBuild`），
说明它们是"被顺带改动"而非"被专门审过"。逐个看体量时，发现一个异常：

```
HintOnce.swift        0 行
```

## 2. 缺陷：`App/Engine/HintOnce.swift` 是 **0 字节**

```powershell
Get-ChildItem ... HintOnce.swift -> bytes=0
```

核查三件事：

| 检查 | 结果 |
|---|---|
| 全仓引用 `HintOnce` | **0 处** |
| `project.yml` 是否显式列出 | 否 —— 但它用 `sources: - path: App` **目录通配**，所以会被编进工程 |
| `git log` 历史 | 只有首次提交 `d6107a9`，**自那以后一直是空文件** |

所以它从诞生起就是个空壳：**编进工程、什么都不产出、零引用、没人会发现**。已删除。

## 3. 加闸门（`swiftcheck.js`）

```js
const body = src.replace(/\/\/.*$/gm, "").replace(/\s+/g, "");
if (body.length < 20) {
  console.log(`  ${rel}  空或近空的 Swift 文件（去掉注释与空白后仅 ${body.length} 字符）`);
  bad++;
}
```

双向验证：新建 `_EmptyProbe.swift`（0 字节）→

```
App/Engine/_EmptyProbe.swift  空或近空的 Swift 文件（去掉注释与空白后仅 0 字符）—— 删掉它，或补上内容
swiftcheck: FAIL — 1 处不平衡
```

删掉探针 → `allgates: 全部 21 道闸门通过`。

## 4. 顺带同步了文档里的闸门输出

文件数 148 → 147，而 `README.md` / `COMPLETION.md` 的示例输出块里 24 行全部写着 148 及旧数字。
用脚本**直接取 `allgates` 的真实输出**替换同名行（不是手改）—— 这样以后不会因为"我记得改了哪几个"而漏。

历史报告（`AUDIT-*.md`、`FIX-REPORT.md`、`SWEEP-REPORT.md` 等）**不动** —— 它们是当时的快照。

## 5. 方法论

**"从未在报告里出现"是一个可机械计算的覆盖指标，而且它真的指向了东西。**

| 指标 | 能回答的问题 |
|---|---|
| 闸门全绿 | 已知形状没问题 |
| **文件 × 报告正文的差集** | **哪些文件从未被专门看过** |

27 个"从未出现"的文件里，大部分是我顺带改过的（所以间接被读过），
而 `HintOnce.swift` 是唯一一个**顺带也碰不到的**（因为它是空的）。

这条指标值得保留：**下次做地毯审计，先跑这个差集。**
