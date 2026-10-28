package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import android.util.Log;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;

/* JADX INFO: loaded from: classes.dex */
public class LockCommSessionTokenResponse extends LockCommResponse {
    public static final byte CMD_ID = 1;
    public static final String TAG = "LockCommSessionToken";
    private Date expireDate;

    public enum SafetyTypeEnum {
        Clear,
        Token
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommResponse, cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    public String getCmdName() {
        return "ssTokenResp";
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.LockCommBase
    void setKLVList(KLVListContainer klvList) {
        super.setKLVList(klvList);
        Calendar now = Calendar.getInstance();
        now.add(13, getEffectSnd());
        this.expireDate = now.getTime();
        DateFormat sdFormat = SimpleDateFormat.getTimeInstance();
        String msg = "加密形式:" + getSafetyType();
        Log.i(TAG, (((msg + "; Token:" + BitConverter.toHexString(getToken())) + "; 有效秒数:" + getEffectSnd()) + "; 过期时间:" + sdFormat.format(getExpire())) + "; 当前时间:" + sdFormat.format(Calendar.getInstance().getTime()));
    }

    public boolean isExpire() {
        DateFormat sdFormat = SimpleDateFormat.getTimeInstance();
        Calendar now = Calendar.getInstance();
        now.add(13, 2);
        Log.i("LockCommSessionToken.ex", sdFormat.format(now.getTime()));
        Log.i("LockCommSessionToken.ex", sdFormat.format(getExpire()));
        return now.getTime().getTime() > getExpire().getTime();
    }

    public Date getExpire() {
        return this.expireDate;
    }

    public int getEffectSnd() {
        KLVContainer klv = this.mKLVList.getKLV(3);
        Log.d("Zk-token", BitConverter.toHexString(klv.getVal()));
        int retVal = BitConverter.toUInt16(klv.getVal(), 0);
        return retVal;
    }

    public byte[] getToken() {
        KLVContainer klv = this.mKLVList.getKLV(2);
        byte[] retVal = klv.getVal();
        return retVal;
    }

    public SafetyTypeEnum getSafetyType() {
        KLVContainer klv = this.mKLVList.getKLV(1);
        int retVal = klv.getVal()[0] & 3;
        return retVal == 2 ? SafetyTypeEnum.Token : SafetyTypeEnum.Clear;
    }
}
