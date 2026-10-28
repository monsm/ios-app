package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import android.util.Log;

/* JADX INFO: loaded from: classes.dex */
class LockCommResponseMapper {
    LockCommResponseMapper() {
    }

    public static LockCommResponse create(short cmdId) {
        Log.d("ZKCMDID", ((int) cmdId) + "--");
        switch (cmdId) {
            case 1:
                LockCommResponse retVal = new LockCommSessionTokenResponse();
                return retVal;
            default:
                Log.w("LockCommResponseMapper", "未找到指定的Response类，使用通用类，cmdId：" + String.format("0x%02x", Short.valueOf(cmdId)));
                LockCommResponse retVal2 = new LockCommDataResponse();
                return retVal2;
        }
    }
}
