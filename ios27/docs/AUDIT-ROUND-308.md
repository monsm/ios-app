# AUDIT-ROUND-308 · 第 308 轮：把 `RESERVED.md` 的数字与行号逐条核了一遍

> CI：`344acda` build 全绿（errors=0）。

## 1. 清单 ↔ 代码标记：8/8 一致 ✅

| RESERVED 条目 | 代码标记 |
|---|---|
| #1 `markDisabled` | `CredentialOrg.swift:246` ✅ |
| #2 `disableMark` | `CredentialOrgState.swift:249` ✅ |
| #10 `TimeWord.word` | `RecordSearch.swift:187` ✅ |
| #11 `sameTypeCount` | `RecordSearchBuild.swift:109` ✅ |
| #12 `context` | `RecordSearchBuild.swift:117` ✅ |
| #14 `recentUseCount` | `CredentialOrg.swift:314` ✅ |
| #17 `overlapWindows` | `CredentialOrg.swift:416` ✅ |
| `kf_week_start` | `WeekCal.swift:36` ✅ |

`node Gates/reserved.js` → **清单与源码标记一致** ✅。

## 2. 具体数字抽查

| 声明 | 实测 | 结论 |
|---|---|---|
| `strictBytes(_:)` 在 `ZKProtocol.swift` **7 处** | 7 | ✅ |
| `weakReason` 在 `KeyCreateParts.swift:192` | 192 | ✅ 精确 |
| `batchPrefixNote` 在 `CredentialStudioScreen.swift:491` | **502** | ❌ 差 11 行 |
| `recentExcerpts` 在 `MemberOpsScreen.swift:282` | **281** | ❌ 差 1 行 |

## 3. 修法：不留精度，留锚点

按第 307 轮刚立的判据（易漂的引用要标明时效），把这两处改成**文件名 + 搜索锚点**：

    | `batchPrefixNote(...)` | `CredentialStudioScreen.swift`（搜 batchPrefixNote 即得，原写 :491 实为 :502） |

**为什么不是改成 `:502`**：下一个人再拆一行就又错了。锚点（符号名）比行号稳定得多。

## 4. 方法论

**「活文档」里的行号是一个必然过期的字段 —— 而文档的读者要靠它定位代码。**

| 引用形式 | 半年后还在吗 |
|---|---|
| `File.swift:491` | 大概不在 |
| **`File.swift`（搜 `symbol`）** | **在** ✅ |

判据：**在会持续编辑的文档里，用「符号名」定位、用「行号」只做当下的旁证 —— 反过来写，文档就会说假话。**
