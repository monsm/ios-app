# AUDIT-ROUND-62 · 第六十二轮：预演摘要放错了位置，粘贴入口收不到

> CI：`45bcf85` 已验证；`42a1951` / `d3217ef` 待回执。本轮本地提交。

## 1. 上一轮我把摘要算在了"读文件"那一刻

`readBackupFile(url)` 里解析并填 `importPreviewNote` —— 这只覆盖**从文件选**这一条入口。
而主备份页还有第二条入口：**从剪贴板粘贴**（`UIPasteboard` → `importText`），
完全不经过 `readBackupFile`。

于是粘贴过来的备份，确认对话框里**没有预演摘要** —— 用户仍然看不到"会写进多少/会跳过几把锁"。

## 2. 修法：挪到"点恢复、弹确认之前"

那一处是**唯一同时覆盖两条入口**的位置（此时 `importText` 已有内容、对话框还没弹出）：

```
importChecksumMismatch = (BackupStudio.checksumState(importText) == .mismatch)
importPreviewNote = BackupScreen.previewNote(text: importText, password: importPassword)
showRestoreConfirm = true
```

并把摘要逻辑抽成 `private static func previewNote(text:password:)`，删掉读文件那一份 ——
**两处算同一件事**迟早会不一致。

## 3. 方法论（第三次同一类错误）

| 轮次 | 我漏掉的入口 |
|---|---|
| ROUND-58 | 预演只统计包里声明数，不等于实际写入 |
| ROUND-59 | 只改了工作室页，主备份页没改 |
| ROUND-60 | 主路径只报新增/覆盖，跳过数丢了 |
| **本轮** | **主备份页内部还有"粘贴"这条入口** |

四次都是"我修了想到的那一条，而不是列出全部"。

所以这条判据要升级成**动作**而不只是提醒：**在写任何"给用户看的提示"之前，
先把这个页面的所有输入入口列出来（文件/粘贴/分享接收/深链），逐个确认**。
这次我确实是先 grep 了 `TextField` 与 `showImporter` 才发现第二条入口的。
