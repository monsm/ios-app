package cn.zelkova.ZKurlcsPlugin.lockprotocol;

/* JADX INFO: loaded from: classes.dex */
public class LockCommResponse extends LockCommBase {
    private byte mCmdId;

    LockCommResponse() {
    }

    void setCmdId(byte value) {
        this.mCmdId = value;
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public byte getCmdId() {
        return this.mCmdId;
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public String getCmdName() {
        return "CommonResp";
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public boolean needSessionToken() {
        return false;
    }
}
