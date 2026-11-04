# AUDIT-ROUND-234 · 第 234 轮：WebDAV 路径含空格/中文时上传失败，报错还指错方向

> CI：`2222064` build 全绿；`d7bf690` / `bd0f594` / `238f2cc` 排队中。

## 1. 缺陷

```swift
let target = base.hasSuffix("/") ? base + path : base + "/" + path
guard let url = URL(string: normalized(target)) else { throw …"WebDAV 远端地址不是合法 URL" }
```

**字符串拼接 → `URL(string:)`。** 而 `URL(string:)` 遇到**空格或中文**会返回 `nil`。

| 用户输入 | 结果 |
|---|---|
| `zklock-backup.json`（默认） | ✅ |
| `我的备份/锁管家.json` | ❌ 「不是合法 URL」 |
| `backup 2026-11-01.json` | ❌ 同上 |

**而用户看着地址是对的** —— 报错指向"地址不合法"，实际原因是"路径没做百分号编码"。

## 2. 修法

改用 `URLComponents`：`path` 接受未转义字符串，取 `.url` 时自动百分号编码。

```swift
guard var comps = URLComponents(string: normalized(base)) else { throw … }
let basePath = comps.path.hasSuffix("/") ? comps.path : comps.path + "/"
let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
comps.path = basePath + cleanPath
guard let url = comps.url else { throw … }
```

边界已核：base 无路径（`https://host`）时 `comps.path` 为空 ⇒ `basePath = "/"` ✅；
`path` 以 `/` 开头时去重，避免 `//` ✅。

## 3. 顺带核对（2 项）

| 检查 | 结论 |
|---|---|
| WebDAV 是否强制 https | ✅ SEC-20：`http://` 除 localhost/127.0.0.1 外一律改写为 `https://` |
| WebDAV 密码存哪 | ✅ `SecretStore`（钥匙串）；只有账号名进 UserDefaults（低敏） |

## 4. 方法论

**「地址不合法」这个报错，要区分是"地址写错了"还是"我们拼错了"。**

| 拼 URL 的方式 | 什么时候坏 |
|---|---|
| 字符串 `+` 再 `URL(string:)` | **任何含空格/中文/`#`/`?` 的段** |
| **`URLComponents.path`** | 不会（自动编码） |

判据：**只要 URL 的某一段来自用户输入，就必须走 `URLComponents` 或 `addingPercentEncoding`，
不能用字符串拼接。** 前者让系统替你决定转义，后者要你自己记住每一种特殊字符。
