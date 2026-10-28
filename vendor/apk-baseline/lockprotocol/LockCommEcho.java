package cn.zelkova.ZKurlcsPlugin.lockprotocol;

/* JADX INFO: loaded from: classes.dex */
public class LockCommEcho extends LockCommBase {
    public static final byte CMD_ID = 18;

    public LockCommEcho(String msg) {
        this.mKLVList.add((byte) 1, msg);
    }

    public LockCommEcho(byte[] value) {
        this.mKLVList.add((byte) 1, value);
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public byte getCmdId() {
        return (byte) 18;
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public String getCmdName() {
        return "Echo Req&Resp";
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public boolean needSessionToken() {
        return true;
    }
}
