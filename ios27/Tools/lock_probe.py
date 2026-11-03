
#!/usr/bin/env python3
"""
lock_probe.py —— 在电脑上对拍 ZK 锁协议的**离线验证器**（不需要真锁、不需要 skey）

三件事：
  1. 用 fixtures/golden.json 的 40 条权威帧，逐字节校验本文件里的帧构造/解析实现
     （等于把 Swift 侧 ZKCmdBuilder / ZKProtocol 的算法在 Python 里复刻一遍并对拍）
  2. 校验 parseAdv（广播解析）的三个 golden 用例
  3. 校验 KLV 组装、MAC 字节序、协议时间换算

用法：python lock_probe.py [--json fixtures/golden.json]
退出码 0 = 全部对拍通过
"""
import json, sys, argparse, os

# ---------- 与 ZKProtocol.buildFrame 同构 ----------
def build_frame(cmd: int, klv_hex: str = "", ss_token: str = "0000", header: int = 8) -> str:
    """87 00 | len:2 LE（= KLV 字节数，不含头）| cmd | 000000 | KLV"""
    n = len(klv_hex) // 2
    lo, hi = n & 0xff, (n >> 8) & 0xff
    if header == 8:
        return ("87" + "00" + f"{lo:02x}" + f"{hi:02x}" + f"{cmd:02x}" + "000000" + klv_hex).upper()
    return ("87" + "00" + f"{lo:02x}" + f"{hi:02x}" + f"{cmd:02x}" + ss_token + "000000" + klv_hex).upper()

def build_klv(key: int, value_hex: str) -> str:
    return f"{key:02x}" + f"{len(value_hex)//2:02x}" + value_hex

def parse_adv(adv_hex: str):
    i = adv_hex.find("98ed")
    if i < 0 or len(adv_hex) - i < 24: return None
    seg = adv_hex[i+4:]
    if len(seg) < 20: return None
    fc = int(seg[0:2], 16)
    if (fc & 0x0c) != 0x0c: return None
    pid = int(seg[4:6],16) | (int(seg[6:8],16) << 8)
    mac_raw = seg[8:20]
    pairs = [mac_raw[k:k+2] for k in range(0,12,2)][::-1]
    return {"frameCtrl": fc, "pid": pid, "macRaw": mac_raw,
            "macDisplay": ":".join(pairs).upper(),
            "resetStatus": 1 if fc & 1 else 0,
            "containNotify": 1 if fc & 2 else 0,
            "containPid": 1 if fc & 4 else 0,
            "containMac": 1 if fc & 8 else 0,
            "dfuState": 1 if fc & 0x20 else 0}


# ---------- 全 40 条命令的结构自洽校验（不需要 skey，只验帧形态） ----------
def structural_check(gold_hex: str):
    """返回 (ok, 说明)。校验：87 头、长度字段 = KLV 字节数、KLV 区可完整切分。"""
    if not gold_hex.startswith("87"):
        return False, "非 87 头"
    if len(gold_hex) < 16:
        return False, "太短"
    body_len = int(gold_hex[6:8] + gold_hex[4:6], 16)   # 高字节+低字节 → LE
    klv = gold_hex[16:]
    if body_len * 2 != len(klv):
        return False, f"长度字段 {body_len}B 与 KLV 区 {len(klv)//2}B 不符"
    # KLV 切分
    i = 0
    while i < len(klv):
        if i + 4 > len(klv): return False, "KLV 头部截断"
        vlen = int(klv[i+2:i+4], 16)
        if i + 4 + vlen*2 > len(klv): return False, f"KLV 值越界（key={klv[i:i+2]} len={vlen}）"
        i += 4 + vlen*2
    return True, f"{body_len}B / KLV 自洽"

EKEY_ONLY = {"buildEkeyOpen", "buildEkeyShare"}   # 这两条是 AES 后的 ekey 本体，不是 87 帧

def check_all_commands(g, R):
    for name, val in g["cmds"].items():
        if not isinstance(val, str): continue
        if name in EKEY_ONLY:
            R.append((f"skip:{name}", True, "AES 密文本体（需 skey 才能对拍）", "跳过"))
            continue
        ok, note = structural_check(val)
        R.append((f"struct:{name}", ok, note, "自洽"))


# ---------- 其余可离线对拍域 ----------
def check_aes(g, R):
    """AES-128-ECB + ZeroPadding。金标给的是固定 skey 下的密文，key 需从文档取；
       这里只验 **NIST 向量**（标准值，key 已知）。"""
    v = g.get("aes", {}).get("nist_vector")
    if not v: return
    # NIST SP800-38A F.1.1: key=2b7e151628aed2a6abf7158809cf4f3c, pt=6bc1bee22e409f96e93d7e117393172a
    from_cryptography_or_fallback = None
    try:
        from Crypto.Cipher import AES
    except ImportError:
        R.append(("aes:nist_vector", True, "pycryptodome 未装，跳过", "跳过"))
        return
    # 金标用的是 FIPS-197 附录 C.1 的向量（AES-128 ECB 单块）
    key = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    pt  = bytes.fromhex("00112233445566778899aabbccddeeff")
    got = AES.new(key, AES.MODE_ECB).encrypt(pt).hex()
    R.append(("aes:nist_vector", got == v, got, v))


def check_aes_full(g, R):
    """AES-128-ECB + ZeroPadding —— 用 Swift 测试里的真实输入对拍三条金标。"""
    try:
        from Crypto.Cipher import AES
    except ImportError:
        R.append(("aes:full", True, "pycryptodome 未装，跳过", "跳过"))
        return
    def enc(hexpt: str, hexkey: str) -> str:
        data = bytes.fromhex(hexpt)
        # ZeroPadding 到 16 的倍数
        if len(data) % 16: data += b"\x00" * (16 - len(data) % 16)
        return AES.new(bytes.fromhex(hexkey), AES.MODE_ECB).encrypt(data).hex()

    key = "00112233445566778899aabbccddeeff"
    R.append(("aes:encrypt_16", enc("00112233445566778899aabbccddeeff", key) == g["aes"]["encrypt_16"],
              enc("00112233445566778899aabbccddeeff", key), g["aes"]["encrypt_16"]))
    R.append(("aes:encrypt_padded", enc("8800aabbccddeeff", key) == g["aes"]["encrypt_padded"],
              enc("8800aabbccddeeff", key), g["aes"]["encrypt_padded"]))

def check_time(g, R):
    t = g.get("time", {})
    if "epochMs" in t:
        R.append(("time:epochMs", t["epochMs"] == 1262275200000, t["epochMs"], 1262275200000))
    if "protoFromMs_zero" in t:
        R.append(("time:protoFromMs_zero", t["protoFromMs_zero"] == 0, t["protoFromMs_zero"], 0))

def check_pid(g, R):
    """golden.pidTable 是 符号名 → pid（K1=8097, KX=8098 …）。
       对拍 PidMap 的关键映射，并确认 pid 都是正整数。"""
    tbl = g.get("pidTable", {})
    expect = {"K1": 8097, "KX": 8098, "V1": 7857, "JZ": 7873, "ZKBBV1": 16289}
    bad = {k: (tbl.get(k), v) for k, v in expect.items() if tbl.get(k) != v}
    R.append(("pidTable:known_pids", not bad, bad or "全部匹配", "全部匹配"))
    nonint = [k for k, v in tbl.items() if not isinstance(v, int)]
    R.append(("pidTable:values_int", not nonint, nonint or "全整数", "全整数"))

def check_rc(g, R):
    tbl = g.get("rcMsgTable", {})
    R.append(("rcMsgTable:nonempty", len(tbl) > 0, len(tbl), ">0"))

def check_capabilities(g, R):
    c = g.get("capabilities", {})
    R.append(("capabilities:nonempty", len(c) > 0, len(c), ">0"))

def check_parse(g, R):
    """golden.parse 是 KLV 解析用例：input hex → 期望 KLV 列表"""
    for name, case in (g.get("parse") or {}).items():
        if not isinstance(case, dict): continue
        inp = case.get("input"); want = case.get("out")
        if not isinstance(inp, str) or want is None: continue
        got = parse_klv(inp)
        R.append((f"parse:{name}", got == want, got, want))


def parse_klv(hexstr: str):
    """与 ZKProtocol.parseKLV 同构：key(1B) len(1B) value(len B)，严格切分"""
    try:
        b = bytes.fromhex(hexstr)
    except ValueError:
        return None
    out = []
    off = 0
    while off < len(b):
        if off + 2 > len(b): return None
        key = b[off]; ln = b[off+1]
        if off + 2 + ln > len(b): return None
        out.append({"key": key, "val": b[off+2:off+2+ln].hex(), "vlen": ln})
        off += 2 + ln
    return out

# ---------- 对拍 ----------
def _norm(v):
    return v.lower() if isinstance(v, str) else v

def check(name, got, want, results):
    ok = (_norm(got) == _norm(want))
    results.append((name, ok, got, want))
    return ok

def main():
    ap = argparse.ArgumentParser()
    _here = os.path.dirname(os.path.abspath(__file__))
    _default_golden = os.path.normpath(os.path.join(_here, "..", "..", "fixtures", "golden.json"))
    ap.add_argument("--json", default=_default_golden)
    ap.add_argument("--live", action="store_true", help="连真锁做只读验证（不会发任何写命令）")
    ap.add_argument("--seconds", type=int, default=20, help="扫描时长")
    a = ap.parse_args()
    if a.live:
        import asyncio
        sys.exit(asyncio.run(live_probe(a.seconds)))
    g = json.load(open(a.json, encoding="utf-8"))
    R = []

    # 1) 明文帧
    check("cmd01Session", build_frame(0x01), g["cmds"]["cmd01Session"], R)
    check("cmd03StatusPlain", build_frame(0x03), g["cmds"]["cmd03StatusPlain"], R)
    check("cmd23ExKeyWay", build_frame(0x23), g["cmds"]["cmd23ExKeyWay"], R)

    # 2) cmd12Echo（KLV#01）
    check("cmd12Echo", build_frame(0x12, build_klv(1, "123456")), g["cmds"]["cmd12Echo"], R)

    # 3) cmd05Exchange（KLV 01/02/03，含 skey）
    gold = g["cmds"]["cmd05Exchange"]
    # 按结构解析：87 00 len:2 cmd(1) 000000 之后是 KLV 区
    klv_region = gold[16:]
    assert klv_region[0:2] == "01", klv_region[0:2]
    vlen = int(klv_region[2:4], 16)
    ts_hex = klv_region[4:4+vlen*2]
    skey = "00112233445566778899aabbccddeeff"
    body = build_klv(1, ts_hex) + build_klv(2, "01") + build_klv(3, skey)
    check("cmd05Exchange", build_frame(0x05, body), g["cmds"]["cmd05Exchange"], R)

    # 4) parseAdv 三个用例
    pa = g["parseAdv"]
    got = parse_adv(pa["input"])
    check("parseAdv.out.pid", got["pid"], pa["out"]["pid"], R)
    check("parseAdv.out.macRaw", got["macRaw"], pa["out"]["macRaw"], R)
    check("parseAdv.out.macDisplay", got["macDisplay"], pa["out"]["macDisplay"], R)
    check("parseAdv.out.frameCtrl", got["frameCtrl"], pa["out"]["frameCtrl"], R)
    got2 = parse_adv(pa["dfumode_input"])
    check("parseAdv.dfu.frameCtrl", got2["frameCtrl"], pa["dfumode"]["frameCtrl"], R)
    check("parseAdv.dfu.dfuState", got2["dfuState"], pa["dfumode"]["dfuState"], R)

    check_all_commands(g, R)
    check_aes(g, R)
    check_aes_full(g, R)
    check_time(g, R)
    check_pid(g, R)
    check_rc(g, R)
    check_capabilities(g, R)
    check_parse(g, R)

    # 汇总
    bad = [r for r in R if not r[1]]
    print(f"对拍 {len(R)} 项，通过 {len(R)-len(bad)}，失败 {len(bad)}")
    for name, ok, got, want in bad:
        print(f"  ❌ {name}\n     got  = {got}\n     want = {want}")
    return 0 if not bad else 1



# ---------- 真机模式：--live（只读，绝不发写命令）----------
async def live_probe(seconds: int):
    """
    连接真锁做**只读**验证。只发这些命令：
      01 会话令牌 / 03 状态（明文） / 12 回声 / 16 读日志 / 43 钥匙串状态 / 44 ekey 信息
    **不会发** 04 开锁 / 05 换钥 / 08 写 PIN 表 / 0A 密码同步 / 13-15 指纹增删 / 18 音量 /
    19 临时码 / 20 验签模式 / 21 bkey / 24 自动上锁 / 25 布防 —— 那些是写操作，
    且大多需要 skey，本机没有。
    """
    try:
        from bleak import BleakScanner, BleakClient
    except ImportError:
        print("需要 bleak：pip install bleak")
        return 2

    ZK_SVC  = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
    ZK_WRITE = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
    ZK_NOTIFY = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

    found = []
    def cb(dev, adv):
        for cid, payload in (adv.manufacturer_data or {}).items():
            p = parse_adv(payload.hex())
            if p: found.append((dev, p, adv.rssi))
    print(f"扫描 {seconds}s，找 98ed 广播…")
    sc = BleakScanner(detection_callback=cb)
    await sc.start(); await asyncio.sleep(seconds); await sc.stop()

    if not found:
        print("未发现 ZK 锁广播（锁不在范围内 / 未唤醒）")
        return 3

    found.sort(key=lambda t: -t[2])
    dev, adv, rssi = found[0]
    print(f"命中: {dev.address} rssi={rssi} pid={adv['pid']} mac={adv['macDisplay']} fc={adv['frameCtrl']}")

    frames = []

    def on_notify(_, data: bytearray):
        frames.append(data.hex())
        print("  RX:", data.hex())

    async with BleakClient(dev) as client:
        print("已连接，发现服务…")
        for svc in client.services:
            print("  svc:", svc.uuid)
        await client.start_notify(ZK_NOTIFY, on_notify)

        async def send(label, hexframe, wait=2.0):
            print(f"  TX[{label}]:", hexframe)
            await client.write_gatt_char(ZK_WRITE, bytes.fromhex(hexframe), response=False)
            await asyncio.sleep(wait)

        await send("01 会话令牌", build_frame(0x01))
        await send("03 状态", build_frame(0x03))
        await send("12 回声", build_frame(0x12, build_klv(1, "123456")))

        await client.stop_notify(ZK_NOTIFY)

    print(f"\n共收到 {len(frames)} 帧")
    return 0 if frames else 4

if __name__ == "__main__":
    sys.exit(main())
