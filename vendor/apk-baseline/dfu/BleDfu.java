package com.plugin.urlcsDfuPlugin;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.os.Build;
import android.os.Handler;
import android.os.Message;
import android.util.Log;
import cn.zelkova.ZKurlcsPlugin.lockprotocol.BLEAdData;
import com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuServiceInitiator;

/* JADX INFO: loaded from: classes.dex */
public class BleDfu {
    private static final String DEVICE_NAME = "ZkDFU";
    private static final String SERVICE_UUID = "6E401001-B5A3-F393-E0A9-E50E24DCCA0E";
    private static final String WRITE_UUID = "6E401003-B5A3-F393-E0A9-E50E24DCCA0E";
    private static BleDfu instance = null;
    private BluetoothDevice mBluetoothDevice;
    ZKBleBlock zkBleBlock;
    private final String TAG = "ZK-Dfu";
    private BluetoothAdapter.LeScanCallback leScanCallback = new MyLeScanCallback();
    private final int MSG_CONNECT_DFU = 33;
    private Handler handler = new Handler() { // from class: com.plugin.urlcsDfuPlugin.BleDfu.2
        @Override // android.os.Handler
        public void handleMessage(Message msg) {
            super.handleMessage(msg);
            int i = msg.what;
        }
    };
    private BluetoothAdapter blAdp = BluetoothAdapter.getDefaultAdapter();

    public static BleDfu getInstance(ZKBleBlock zkBleBlock) {
        if (instance == null) {
            synchronized (BleDfu.class) {
                if (instance == null) {
                    instance = new BleDfu(zkBleBlock);
                }
            }
        }
        return instance;
    }

    public BleDfu(ZKBleBlock zkBleBlock) {
        this.zkBleBlock = zkBleBlock;
    }

    private class MyLeScanCallback implements BluetoothAdapter.LeScanCallback {
        private MyLeScanCallback() {
        }

        @Override // android.bluetooth.BluetoothAdapter.LeScanCallback
        public void onLeScan(BluetoothDevice device, int rssi, byte[] scanRecord) {
            try {
                if (device.getName() != null) {
                    BLEAdData curAdData = BLEAdData.parse(device.getAddress(), scanRecord);
                    if (curAdData.getPid() == BleDfu.this.zkBleBlock.pid && curAdData.getDfuState() == 1) {
                        StringBuilder sb = new StringBuilder();
                        ZKBleBlock zKBleBlock = BleDfu.this.zkBleBlock;
                        String filePath = sb.append(ZKBleBlock.mContext.getFilesDir().toString()).append("/").append(BleDfu.this.zkBleBlock.fileName).toString();
                        StringBuilder sbAppend = new StringBuilder().append("找到设备:").append(device.getAddress()).append(", filePath:");
                        ZKBleBlock zKBleBlock2 = BleDfu.this.zkBleBlock;
                        Log.d("ZK-Dfu", sbAppend.append(ZKBleBlock.mContext.getFilesDir().toString()).append(", ").append(BleDfu.this.zkBleBlock.fileName).toString());
                        BleDfu.this.stopScan();
                        DfuServiceInitiator zip = new DfuServiceInitiator(device.getAddress()).setDisableNotification(true).setZip(filePath);
                        ZKBleBlock zKBleBlock3 = BleDfu.this.zkBleBlock;
                        zip.start(ZKBleBlock.mContext, DfuService.class);
                    }
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void stopScan() {
        this.blAdp.stopLeScan(this.leScanCallback);
    }

    public void dfu(String macAddress) {
        Log.d("ZK-Dfu", "开始DFU");
        if (Build.VERSION.SDK_INT >= 26) {
            ZKBleBlock zKBleBlock = this.zkBleBlock;
            DfuServiceInitiator.createDfuNotificationChannel(ZKBleBlock.mContext);
        }
        DfuServiceInitiator zip = new DfuServiceInitiator(macAddress).setDisableNotification(true).setZip(this.zkBleBlock.fileName);
        ZKBleBlock zKBleBlock2 = this.zkBleBlock;
        zip.start(ZKBleBlock.mContext, DfuService.class);
    }

    public void doScan() {
        try {
            this.blAdp.startLeScan(this.leScanCallback);
            this.handler.postDelayed(new Runnable() { // from class: com.plugin.urlcsDfuPlugin.BleDfu.1
                @Override // java.lang.Runnable
                public void run() {
                    BleDfu.this.blAdp.stopLeScan(BleDfu.this.leScanCallback);
                }
            }, 10000L);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
