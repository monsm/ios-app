# 本地备份文件列表 —— 从缺口到实现

> 2026-10-21。这份文档记录一个**代码自己承诺了、但六轮都没实现**的功能，
> 以及最终怎么补上的。

## 缺口证据（发现时）

`App/UI/BackupStudio.swift` 原第 310 行：

```swift
// ================= 本地备份文件 (434/436/454/511) =================


// ================= 导出向导 (407-413) =================
struct ExportWizardView: View {
```

章节标题下面**只有两个空行**。该文件里只有 3 个 struct：
`BackupStudioView` / `ExportWizardView` / `RestoreWizardView`。

但代码在多处引用它：

| 位置 | 原文 |
|---|---|
| `BackupStudio.swift:57` | 「每份旧备份自己的参数在**「本地备份文件」列表**逐文件标注」 |
| `BackupStudio.swift:757` | 「已写入**本地备份文件列表**」 |
| `BackupStudio.swift:195` | 「只清理本 App 生成的备份文件 (文件名以「锁管家_」开头那族)」 |

## 更深一层：连数据层都是断的

不只是视图没写，**数据管线也断在半路**：

| 组件 | 状态 |
|---|---|
| `BackupStudio.dir` | ✅ 有 |
| `BackupStudio.filePrefix` / `isOurBackup(_:)` / `volumeSet` / `dateInName` | ✅ 有 |
| `pruneLocal(keep:)` | ✅ **已经在枚举这个目录** |
| `AlgoNote` 枚举 | ⚠️ **声明了，全仓零调用** |
| `jsonStr` / `jsonNum` | ⚠️ **写了，全仓零调用** |
| `localFiles()` / 列表视图 | ❌ **不存在** |

所以「435 逐文件算法标注」写了一半：**读参数的工具齐了，没人用、没处显示**。

## 实现（本轮）

### 1. 先写探针（本仓纪律）

`App/UI/RealityAPIProbe.swift` 新增**区块 7**：

```swift
enum ProbeBlock7_FileEnumeration {
    static func probe() throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        // ...
        let files = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey,
                                        .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles])
        // url.resourceValues(forKeys:) ...
    }
}
```

**CI run `39588049606` = SUCCESS** → 这套 API 全部成立。

### 2. 数据层（`BackupStudioKit.swift`）

```swift
static func algoNote(for url: URL) -> AlgoNote     // 只读文件头 8KB，不解密
struct LocalBackupFile: Identifiable               // name/url/bytes/createdAt/modifiedAt/algo
static func localFiles() -> [LocalBackupFile]      // 枚举 + 过滤 + 排序
@discardableResult
static func deleteLocalFile(_ name: String) -> Bool // 只删自家名字族
```

`algoNote` 终于让 `AlgoNote` / `jsonStr` / `jsonNum` 有了调用方。

### 3. 视图（`BackupStudio.swift` 原章节注释处）

```swift
struct LocalBackupFilesSection: View {
    // 每行: 文件名 · 大小 · 时间 · 算法参数 · 删除按钮
}
```

挂在 `BackupStudioView` 的 `cadenceCard` 之后。

## 三个实现细节

### `jsonStr` 的 marker 要带值的开引号

```swift
jsonStr(head, "\"alg\":\"")   // ✓ 正确
jsonStr(head, "\"alg\"")       // ✗ 会把开引号当结束位置，返回空串
```

因为它找到 marker 后取「下一个 `"` 之前的内容」。

### 日期不用 DateFormatter

闸门要求 `DateFormatter` 必须钉 `en_US_POSIX`。这里直接走
`WeekCal.gregorian.dateComponents` 手工拼，历法来源唯一也不需要 locale。

### 嵌套 struct 里用外层 static 要限定名

```swift
struct LocalBackupFile {
    var shortName: String {
        let p = BackupStudio.filePrefix    // ✓ 限定名
        // let p = filePrefix               // ⚠ 不可靠
    }
}
```

## 闸门拦下的一处

`swiftlint` 的「疑似臆造符号」把 `FileHandle` 报了 —— 它是 Foundation 类型，
但全仓只此一处、不在前缀白名单里。已加白并注明理由
（`FileHandle.read(upToCount:)` 是唯一只读文件头、不把整份备份读进内存的做法）。

## 仍未验证的

- **真机**：文件枚举在真实沙盒里的行为、删除后列表刷新、空目录空态
- **算法参数读取**：需要一份真实的加密信封文件才能确认 `alg`/`kdf`/`iter` 的 JSON 键名
