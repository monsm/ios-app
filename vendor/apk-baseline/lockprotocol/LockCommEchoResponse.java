package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import java.io.UnsupportedEncodingException;

/* JADX INFO: loaded from: classes.dex */
public class LockCommEchoResponse extends LockCommResponse {
    public static final byte CMD_ID = 18;

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommResponse, cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public String getCmdName() {
        return "echoResp";
    }

    public String getMsg() {
        KLVContainer klv = this.mKLVList.getKLV(1);
        try {
            String result = new String(klv.getVal(), "utf-8");
            return result;
        } catch (UnsupportedEncodingException e) {
            e.printStackTrace();
            throw new RuntimeException(e);
        }
    }
}
