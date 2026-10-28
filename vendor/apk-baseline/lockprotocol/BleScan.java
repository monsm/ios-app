package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.os.Handler;
import android.os.Message;
import android.util.Log;
import org.apache.cordova.PluginResult;
import org.json.JSONObject;

/* JADX INFO: loaded from: classes.dex */
public class BleScan {
    private static BleScan instance = null;
    ZKBleBlock zkBleBlock;
    private BluetoothAdapter.LeScanCallback leScanCallback = new MyLeScanCallback();
    private Handler handler = new Handler() { // from class: cn.zelkova.ZKurlcsPlugin.lockprotocol.BleScan.2
        @Override // android.os.Handler
        public void handleMessage(Message msg) {
            super.handleMessage(msg);
            int i = msg.what;
        }
    };
    private BluetoothAdapter blAdp = BluetoothAdapter.getDefaultAdapter();

    public static BleScan getInstance(ZKBleBlock zkBleBlock) {
        if (instance == null) {
            synchronized (BleScan.class) {
                if (instance == null) {
                    instance = new BleScan(zkBleBlock);
                }
            }
        }
        return instance;
    }

    public ZKBleBlock getZkBleBlock() {
        return this.zkBleBlock;
    }

    public void setZkBleBlock(ZKBleBlock zkBleBlock) {
        this.zkBleBlock = zkBleBlock;
    }

    public BleScan(ZKBleBlock zkBleBlock) {
        this.zkBleBlock = zkBleBlock;
    }

    private class MyLeScanCallback implements BluetoothAdapter.LeScanCallback {
        private MyLeScanCallback() {
        }

        @Override // android.bluetooth.BluetoothAdapter.LeScanCallback
        public void onLeScan(BluetoothDevice device, int rssi, byte[] scanRecord) {
            try {
                String deviceName = device.getName();
                if (deviceName != null) {
                    BLEAdData curAdData = BLEAdData.parse(device.getAddress(), scanRecord);
                    JSONObject data = new JSONObject();
                    data.put("mac", device.getAddress().replace(":", "").toLowerCase());
                    data.put("name", device.getName());
                    data.put("identifier", device.getAddress());
                    data.put("pid", curAdData.getPid());
                    data.put("resetStatus", curAdData.getResetStatus());
                    data.put("containNotify", curAdData.getContainNotify());
                    data.put("containPid", curAdData.getContainPid());
                    data.put("containMac", curAdData.getContainMac());
                    data.put("dfuState", curAdData.getDfuState());
                    data.put("rssi", rssi);
                    Log.d("ZK-Scan", data.toString());
                    PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, data);
                    pluginResult.setKeepCallback(BleScan.this.zkBleBlock.keep);
                    BleScan.this.zkBleBlock.callbackContext.sendPluginResult(pluginResult);
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    public void doScan() {
        try {
            this.blAdp.startLeScan(this.leScanCallback);
            this.handler.postDelayed(new Runnable() { // from class: cn.zelkova.ZKurlcsPlugin.lockprotocol.BleScan.1
                @Override // java.lang.Runnable
                public void run() {
                    BleScan.this.blAdp.stopLeScan(BleScan.this.leScanCallback);
                }
            }, 10000L);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public void stopScan() {
        this.blAdp.stopLeScan(this.leScanCallback);
    }
}
