package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import android.util.Log;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/* JADX INFO: loaded from: classes.dex */
public class LockCommData extends LockCommBase {
    public static byte CMD_ID;
    private JSONObject mData;

    public LockCommData(JSONObject data) {
        byte[] value;
        this.mData = data;
        try {
            Log.d("ZK-data", data.toString());
            CMD_ID = BitConverter.fromHexString(this.mData.getString("commandId"))[0];
            JSONArray kvs = this.mData.getJSONArray("kvs");
            for (int i = 0; i < kvs.length(); i++) {
                JSONObject jsonObj = kvs.getJSONObject(i);
                byte[] key = BitConverter.fromHexString(jsonObj.getString("key"));
                if (jsonObj.getString("value").equals("")) {
                    value = new byte[0];
                } else {
                    value = BitConverter.fromHexString(jsonObj.getString("value"));
                }
                this.mKLVList.add(key[0], value);
            }
        } catch (JSONException e) {
            e.printStackTrace();
        }
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public byte getCmdId() {
        return CMD_ID;
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public String getCmdName() {
        return "Data Req&Resp";
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public boolean needSessionToken() {
        try {
            return this.mData.getBoolean("needToken");
        } catch (JSONException e) {
            e.printStackTrace();
            return false;
        }
    }
}
