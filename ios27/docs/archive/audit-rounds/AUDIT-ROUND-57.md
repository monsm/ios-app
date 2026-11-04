# AUDIT-ROUND-57 · 第五十七轮：`3864e54` 转绿，并给新字段补上回归保护

> CI：`3864e54` **已验证通过** —— `errors=0`、`build_ok=1`、`archive_ok=1`。
> 也就是说备份 schema / canonical 那批改动**真的能编译**了。

## 1. 顺便澄清一个误读风险

`ci-test` 上 `8d2c96b` 的 `test_ok=0`、`test_failed=2` 看起来像"测试挂了"。
读 `test.log` 才看清：那 2 个失败是**同一批编译错误**：

```
BackupKit.swift:186: error: argument 'alerts' must precede argument 'recFlags'
Testing cancelled because the build failed.
```

**金标 job 里 `test_failed` 也可能是"构建挂了"而不是"断言挂了"。**
以后看到非零必须去读 `test.log`，不能只看计数。

## 2. 新字段没有回归保护

`BackupRoundTripTests` 覆盖了 canonical 稳定性、凭证往返、归属丢弃、合并不删、冲突裁决、
校验和确认、非法 skey —— 但**没有一条**断言"成员档案 / 提醒档位出现在导出文本里"。

这很危险，因为这两族的失败方式是**静默的**：字段在、类型对、编译过，
只是 canonical 白名单没 emit ⇒ 导出文本里没有 ⇒ 换机全丢，且不报错。

## 3. 新增 `testNewFamiliesReachTheExportedText`

判据不看"结构体有没有这个字段"，而看 **`BackupCanonical.exportText` 的输出里有没有它**：

- 设 `globals.memberExt = ["m1": 备注名"小张" / role "guest" / archived true]`，
  断言导出文本含 `memberExt`、`小张`、`guest`；
- 设 `Device.Meta.alerts = ["pwd:1": h2]`，断言导出文本含 `alerts`。

## 4. 写测试时踩到同一个坑（正好印证上一轮的结论）

我第一版写成 `BackupBundle.Globals()` —— 但 `Globals` **没有无参 init**，
成员逐一构造要求**传齐所有字段且顺序正确**。改成"先建后赋值"，
并显式写全参（顺序按声明序）。

这正是上一轮放弃 `memberorder` 闸门时说的那件事：**这类错编译器会拦，测试代码也会被它拦。**
我这次是靠"想起上一轮的教训"避开的，而不是靠闸门。
