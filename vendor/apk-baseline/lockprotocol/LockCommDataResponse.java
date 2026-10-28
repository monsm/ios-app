package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import org.json.JSONArray;
import org.json.JSONObject;

/* JADX INFO: loaded from: classes.dex */
public class LockCommDataResponse extends LockCommResponse {
    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommResponse, cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public String getCmdName() {
        return "dataResp";
    }

    public JSONObject getMsg() {
        JSONObject jSONObject = new JSONObject();
        JSONArray resultArray = new JSONArray();
        try {
            jSONObject.put("commandId", String.format("%02x", Byte.valueOf(super.getCmdId())));
            for (int i = 0; i < this.mKLVList.size(); i++) {
                KLVContainer klv = this.mKLVList.get(i);
                JSONObject r = new JSONObject();
                r.put("key", klv.getKey());
                r.put("value", BitConverter.toHexString(klv.getVal(), ""));
                resultArray.put(r);
            }
            jSONObject.put("kvs", resultArray);
            return jSONObject;
        } catch (Exception e) {
            e.printStackTrace();
            throw new RuntimeException(e);
        }
    }
}
