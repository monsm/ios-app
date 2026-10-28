package cn.zelkova.ZKurlcsPlugin.lockprotocol;

/* JADX INFO: loaded from: classes.dex */
public class LockCommSessionToken extends LockCommBase {
    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public byte getCmdId() {
        return (byte) 1;
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public String getCmdName() {
        return "sessionToken";
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public boolean needSessionToken() {
        return false;
    }
}
