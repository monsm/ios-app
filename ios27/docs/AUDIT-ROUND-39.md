# AUDIT-ROUND-39 · 第三十九轮：生物识别在模型层没有二次校验

> CI：`2d75c19` 已验证（errors=0、build_ok=1）；`c12c91d` 仍未回执（已确认无残留引用）

## 1. 缺陷：入口隐藏 ≠ 能力禁用

`LockKeeperApp` 里，生物识别按钮的可见性由一段**只在 `.onAppear` 算一次**的变量控制：

```
bioAvailable = !DB.hasDuressCode() && DB.store.getBool("kf_bio_unlock", true) && canUseBiometrics()
```

而真正执行解锁的 `AppLock.unlockByBiometric()` **完全不知道「有没有胁迫码」**：

```
func unlockByBiometric() {
    unlocked = true
    decoy = false
}
```

两处问题：

1. **模型层没有守卫** —— 任何新调用点（小组件、深链、以后的自动化）都能绕开 UI 的判断；
2. 调用方**无论模型做了什么**都会置 `app.unlocked = true` —— 即使模型拒绝，界面照样开。
   这正是本仓历史上翻过的那类车（「假门」：代码看着有保护，实际一点也没有）。

## 2. 修法

- `AppLock.unlockByBiometric()` 改成 `@discardableResult -> Bool`，内部 `guard !DB.hasDuressCode() else { return false }`；
- 调用方按返回值决定是否置 `app.unlocked`，失败时给出可理解的文案（「请用本机密码」）。

为什么必须有这条：有胁迫码时刷脸会**直接暴露「这不是伪装模式」** —— 被胁迫者用 Face ID 开门，
胁迫者立刻知道刚才那个空壳是假的。这是胁迫场景里最危险的一种破绽。

## 3. 防复发：privacy 闸门第 19 条

`unlockByBiometric` 函数体内必须出现 `hasDuressCode`。已验证：

```
privacy: FAIL — 1 处回归
  Engine/AppLock.swift:116 — unlockByBiometric 没有在模型层判胁迫码
    → 加 guard !DB.hasDuressCode() else { return false }
```

## 4. 方法论

**「UI 里挡住了」不是安全边界。** 安全判断必须落在**能力所在的那一层**：
模型/服务自己拒绝，而不是「调用方记得不要调」。

判据：**任何 `func` 如果它有安全前提，这个前提必须在这个函数体里再判一次** ——
因为调用方会变，函数不会。
