# AUDIT-ROUND-303 · 第 303 轮：协议层（构造 / 夹具 / 解析）三项证据

> CI：`3672131` build 全绿；`56b8155` / `1897666` / `344acda` 排队中。

## 1. 命令构造器的 golden 覆盖（集合差）

| 集合 | 数量 |
|---|---|
| `ZKCmdBuilder` 的 `static func` | 38 |
| 在 `Tests/` 中被提及 | 33 |
| 未被提及 | 5 —— `u16leHex` / `protoSecU32` / `protoSecOrNil` / `protoSecRawOrNil` / `pinToLEOrNil` |

那 5 个都是**工具函数**，被上面 33 个构造器间接调用；构造器字节被钉住 ⇒ 工具函数被间接钉住 ✅。

## 2. 硬件 / DFU 路径确实有夹具（不只是被提到）

| 夹具 | 覆盖的边界 |
|---|---|
| `cmd41WriteEkey` / `cmd41WriteEkey_del` | 写入 **与删除**（空 ekey） |
| `cmd43KeychainStatus_empty` / `_two` | **空表**与两条 mac |
| `cmd44GetEkeyInfo_all` / `_one` | **全量**与单条 |
| `cmd13AddFp` / `cmd14FpConfirm` / `cmd22EnableDfu` | 指纹与 DFU |

边界用例（空表 / 删除 / 全量）都在 —— 这类正是「只测 happy path 会漏」的地方 ✅。

## 3. KLV 解析的越界保护

    while off < b.count {
        guard off + 2 <= b.count else { return nil }        // 头两字节
        let key = Int(b[off]); let len = Int(b[off + 1])
        guard off + 2 + len <= b.count else { return nil }  // 声明长度
        ...
    }

| 场景 | 结果 |
|---|---|
| 帧在「key」处截断 | ✅ 返回 nil |
| 帧声明 len=200 但只有 10 字节 | ✅ 返回 nil |
| 脏字符 hex | ✅ `strictBytes` 先挡掉（SEC-16：宽容版会把噪声读成 0） |

**没有越界下标** ✅。

## 4. 方法论

**「有测试」要问到第三层：① 提到这个函数了吗 ② 有没有钉字节 ③ 边界值有吗。**

| 层次 | 本轮证据 |
|---|---|
| 提到 | 33/38（其余是工具函数） |
| **钉字节** | `built["cmd41WriteEkey"] = …hex` —— 与厂商夹具逐字节比 |
| **边界** | `_del` / `_empty` / `_two` / `_all` / `_one` ✅ |

判据：**核对测试覆盖时，不要停在「名字出现过」—— 要问「它比的是什么、比过哪些边界」。**
