# 已知缺口：本地备份文件列表（未实现）

> 2026-10-21 逐页适配时发现。这是一个**代码自己承诺了、但没有实现**的功能。

## 证据

`App/UI/BackupStudio.swift:310-313`：

```swift
// ================= 本地备份文件 (434/436/454/511) =================


// ================= 导出向导 (407-413) =================
struct ExportWizardView: View {
```

章节标题下面**只有两个空行**。该文件里只有 3 个 struct：
`BackupStudioView`(10) / `ExportWizardView`(314) / `RestoreWizardView`(765)。
「本地备份文件」对应的视图不存在。

## 但代码在多处引用了它

| 位置 | 原文 |
|---|---|
| `BackupStudio.swift:57` | 「每份旧备份自己的参数在**「本地备份文件」列表**逐文件标注」 |
| `BackupStudio.swift:757` | 「已写入**本地备份文件列表** — 传到新机后用「换机迁移」任一通道导入」 |
| `BackupStudio.swift:195` | 「只清理本 App 生成的备份文件 (文件名以「锁管家_」开头那族)」 |

## 为什么没实现

数据源本身也没建。`BackupStudio` 有：

- `fileName(vol:)` / `incrementalFileName()` —— 名字能生成
- `filePrefix = "锁管家_"` —— 前缀有
- `lastExportMs` / `lastExportBytes` / `sizeText(_:)` —— 只有**最后一次**的尺寸

**缺的是**：枚举导出目录（Documents 下）里现有文件、读每个文件的创建时间/大小/口令参数。

## 影响

用户导出多份备份后，App 里看不到历史文件列表，只能去「文件」App 里自己翻。
「每份旧备份自己的参数」这句承诺也无处兑现。

## 建议实现路径（未做）

1. 在 `BackupStudio` 加 `static func localFiles() -> [LocalBackupFile]`
   - 枚举 `FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)`
   - 只收 `filePrefix` 开头的
   - 返回 name / createdAt / bytes / 口令参数（口令参数需写在文件名或伴随文件里）
2. 实现 `LocalFilesSection: View`，挂在 `BackupStudioView` 的 `cadenceCard` 之后
3. 每行显示：文件名 · 大小 · 相对时间 · 参数徽章；左滑删除

## 为什么这次没直接做

- 需要新的文件系统枚举 API，本机**没有 Swift 编译器**，只能靠 CI 试错；
- 而这一条是**新功能**，不是「已有数据缺呈现」的内容适配 ——
  其余 30 页的适配都是把已经算好的数据接到界面上，风险低得多。

如果要做，应当单独一轮，并且先在 `RealityAPIProbe.swift` 里加探针验证
`FileManager.contentsOfDirectory` 与 `URLResourceValues` 的用法。
