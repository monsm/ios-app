package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import android.bluetooth.BluetoothAdapter;
import org.apache.cordova.CallbackContext;

/* JADX INFO: loaded from: classes.dex */
public class BleState {
    public static boolean isBleEnable(CallbackContext callbackContext) {
        BluetoothAdapter blueadapter = BluetoothAdapter.getDefaultAdapter();
        if (blueadapter == null) {
            callbackContext.error("手机没有蓝牙模块");
        }
        return blueadapter.isEnabled();
    }
}
