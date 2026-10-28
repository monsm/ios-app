package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.content.Context;
import android.util.Log;
import com.taobao.accs.common.Constants;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;
import java.util.Timer;
import java.util.TimerTask;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.apache.cordova.PluginResult;
import org.json.JSONException;
import org.json.JSONObject;

/* JADX INFO: loaded from: classes.dex */
public class BleLockConnector implements WhatHappenCallback {
    public static final int MAX_MTU = 20;
    private static final String TAG_BLE = "ZkBleLockConnector";
    private BluetoothAdapter bleLocalAdp;
    private BluetoothManager bleMng;
    private BluetoothDevice bleRemoteDevice;
    private BluetoothGatt bleRemoteGatt;
    private final BleCallbackSignal callbackSignal;
    private ExecutorService cmdExecSvc;
    private Context context;
    private String macAddress;
    private BleGattCallback myBleGattCallback;
    private NoopLeScanCallback noopLeScanCallback;
    private Timer receiveTimer;
    public static UUID RX_SERVICE_UUID = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
    public static UUID RX_CHAR_UUID = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e");
    public static UUID TX_CHAR_UUID = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e");
    public static UUID CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static Date LastDisconnectTime = new Date(0);
    static int IntervalTimeInTwoConnection = 0;

    @Deprecated
    public static int CompatibleBleScanSnd = 15000;
    private static int BLE_TIMEOUT = 8000;
    private static int BLE_Retry_Times = 3;
    private static int Enable_SvcUUID_ScanFilter = 0;
    private static ArrayList<ZKBleBlock> zkBleBlocks = new ArrayList<>();
    private static Map<String, BleLockConnector> ConnectorPool = new HashMap();

    @Deprecated
    public int CompatibleBleScanTimes = 0;
    private boolean selfShowMsg = true;
    private WhatHappenCallback whatHappenCallback = null;
    private IResultCallback resultCallback = null;
    private ArrayDeque<Byte> outputBuffer = new ArrayDeque<>();
    private ArrayDeque<Byte> inputBuffer = new ArrayDeque<>();
    private LockCommSessionTokenResponse ssToken = null;
    private LockCommResponse sendToClient = null;
    private boolean disconnectReq = false;
    private Exception lastException = null;
    ZKBleBlockCallBack zkBleBlockCallBack = new ZKBleBlockCallBack() { // from class: cn.zelkova.ZKurlcsPlugin.lockprotocol.BleLockConnector.1
        @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.ZKBleBlockCallBack
        public void onConnect() {
            Log.d("ZK-BleBlock", "onConnect: " + BleLockConnector.zkBleBlocks.size());
            for (int m = 0; m < BleLockConnector.zkBleBlocks.size(); m++) {
                ZKBleBlock zkBleBlock = (ZKBleBlock) BleLockConnector.zkBleBlocks.get(m);
                PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, "连接成功");
                pluginResult.setKeepCallback(zkBleBlock.keep);
                zkBleBlock.callbackContext.sendPluginResult(pluginResult);
                Log.d("ZK-pluginResult", pluginResult.getMessage());
                zkBleBlock.callbackContext.success("连接成功");
            }
        }

        @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.ZKBleBlockCallBack
        public void onDisConnect() {
            Log.d("ZK-BleBlock", "onDisConnect: " + BleLockConnector.zkBleBlocks.size());
            for (int n = 0; n < BleLockConnector.zkBleBlocks.size(); n++) {
                ZKBleBlock zkBleBlock = (ZKBleBlock) BleLockConnector.zkBleBlocks.get(n);
                PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, "断开成功" + zkBleBlock.key);
                pluginResult.setKeepCallback(zkBleBlock.keep);
                zkBleBlock.callbackContext.sendPluginResult(pluginResult);
                Log.d("ZK-pluginResult", pluginResult.getMessage());
                zkBleBlock.callbackContext.success("断开成功" + zkBleBlock.key);
            }
        }
    };

    public interface IResultCallback {
        void onConnectionState(String str, ConnectionStateEnum connectionStateEnum, Exception exc);

        void onExecutionResult(String str, Exception exc, LockCommResponse lockCommResponse);
    }

    public enum ConnectionStateEnum {
        Disconnected(0),
        Connected(2);

        private int state;

        ConnectionStateEnum(int val) {
            this.state = val;
        }
    }

    private class BleGattCallback extends BluetoothGattCallback {
        public BleGattCallback(WhatHappenCallback say) {
            super(say);
        }

        @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.BluetoothGattCallback, android.bluetooth.BluetoothGattCallback
        public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
            String disMac;
            super.onConnectionStateChange(gatt, status, newState);
            if (newState != 2) {
                synchronized (BleLockConnector.this.callbackSignal) {
                    disMac = BleLockConnector.this.bleRemoteGatt.getDevice().getAddress();
                    BleLockConnector.this.bleRemoteGatt.close();
                    BleLockConnector.this.bleRemoteGatt = null;
                    BleLockConnector.this.bleRemoteDevice = null;
                    BleLockConnector.this.callbackSignal.notifyAll();
                    BleLockConnector.this.letMeKnow("连接已断开，线程同步notifyAll");
                }
                BleLockConnector.this.letMeKnow("+++++===== closed & cleared:" + disMac + " =====+++++");
                BleLockConnector.this.zkBleBlockCallBack.onDisConnect();
                Date unused = BleLockConnector.LastDisconnectTime = new Date();
                BleLockConnector.this.lastException = null;
                BleLockConnector.this.onConnectionStateCallback(ConnectionStateEnum.Disconnected);
                return;
            }
            BleLockConnector.this.letMeKnow("\tdiscoverServices：" + gatt.discoverServices());
            Log.d(BluetoothGattCallback.TAG_BLE, "连接成功");
        }

        @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.BluetoothGattCallback, android.bluetooth.BluetoothGattCallback
        public void onServicesDiscovered(BluetoothGatt gatt, int status) {
            super.onServicesDiscovered(gatt, status);
            BleLockConnector.this.enableTXNotification();
        }

        @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.BluetoothGattCallback, android.bluetooth.BluetoothGattCallback
        public void onDescriptorWrite(BluetoothGatt gatt, BluetoothGattDescriptor descriptor, int status) {
            super.onDescriptorWrite(gatt, descriptor, status);
            synchronized (BleLockConnector.this.callbackSignal) {
                BleLockConnector.this.callbackSignal.connected = 2;
                BleLockConnector.this.callbackSignal.notifyAll();
                BleLockConnector.this.letMeKnow("连接状态就绪，线程同步notifyAll");
                BleLockConnector.this.zkBleBlockCallBack.onConnect();
            }
        }

        @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.BluetoothGattCallback, android.bluetooth.BluetoothGattCallback
        public void onCharacteristicWrite(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
            super.onCharacteristicWrite(gatt, characteristic, status);
            synchronized (BleLockConnector.this.callbackSignal) {
                BleLockConnector.this.callbackSignal.writeRX = 2;
                BleLockConnector.this.callbackSignal.notifyAll();
            }
        }

        @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.BluetoothGattCallback, android.bluetooth.BluetoothGattCallback
        public void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic) {
            super.onCharacteristicChanged(gatt, characteristic);
            byte[] val = characteristic.getValue();
            Collections.addAll(BleLockConnector.this.inputBuffer, BitConverter.toPackaged(val));
            LockCommResponse result = LockCommBase.parse(BleLockConnector.this.inputBuffer);
            if (result != null) {
                BleLockConnector.this.letMeKnow("解析出一个协议：[" + ((int) result.getCmdId()) + "]" + result.getCmdName());
                if (result.getCmdId() == 1) {
                    synchronized (BleLockConnector.this.callbackSignal) {
                        BleLockConnector.this.ssToken = (LockCommSessionTokenResponse) result;
                        BleLockConnector.this.callbackSignal.sessionToken = 2;
                        BleLockConnector.this.callbackSignal.notifyAll();
                    }
                    return;
                }
                if (BleLockConnector.this.callbackSignal.command == 1) {
                    synchronized (BleLockConnector.this.callbackSignal) {
                        BleLockConnector.this.sendToClient = result;
                        BleLockConnector.this.callbackSignal.command = 2;
                        BleLockConnector.this.callbackSignal.notifyAll();
                    }
                    return;
                }
                BleLockConnector.this.cancelReceiveTimer();
                BleLockConnector.this.onResultCallbackForExecute(result);
            }
        }
    }

    private class NoopLeScanCallback implements BluetoothAdapter.LeScanCallback {
        private NoopLeScanCallback() {
        }

        @Override // android.bluetooth.BluetoothAdapter.LeScanCallback
        public void onLeScan(BluetoothDevice device, int rssi, byte[] scanRecord) {
            if (BleLockConnector.this.macAddress.toLowerCase().equals(device.getAddress().toLowerCase())) {
                BleLockConnector.this.bleRemoteDevice = device;
                synchronized (BleLockConnector.this.callbackSignal) {
                    BleLockConnector.this.callbackSignal.connected = 2;
                    BleLockConnector.this.callbackSignal.notifyAll();
                }
                Log.i(BleLockConnector.TAG_BLE, "found it, stop bleScan, " + device.getAddress());
                return;
            }
            Log.d(BleLockConnector.TAG_BLE, "[" + device.getName() + "]" + device.getAddress());
        }
    }

    private class BleCallbackSignal {
        public static final int Doing = 1;
        public static final int Done = 2;
        public static final int IDLE = 0;
        public int command;
        public int connected;
        public int sessionToken;
        public int writeRX;

        private BleCallbackSignal() {
            this.connected = 0;
            this.writeRX = 0;
            this.sessionToken = 0;
            this.command = 0;
        }
    }

    protected BleLockConnector(Context ctx, String mac) {
        this.macAddress = "";
        this.myBleGattCallback = null;
        this.noopLeScanCallback = new NoopLeScanCallback();
        this.callbackSignal = new BleCallbackSignal();
        this.macAddress = mac;
        this.context = ctx;
        this.bleMng = (BluetoothManager) this.context.getSystemService("bluetooth");
        this.bleLocalAdp = this.bleMng.getAdapter();
        this.myBleGattCallback = new BleGattCallback(null);
    }

    public static void setTimeOut(int snd) {
        BLE_TIMEOUT = snd * 1000;
    }

    public static int getTimeout() {
        return BLE_TIMEOUT / 1000;
    }

    public static int getConnRetryTimes() {
        return BLE_Retry_Times;
    }

    public static void setBLEConnRetryTimes(int val) {
        BLE_Retry_Times = val;
    }

    public static int getEnableSvcUUIDScanFilter() {
        return Enable_SvcUUID_ScanFilter;
    }

    public boolean isConnected() {
        if (this.bleRemoteGatt == null || this.bleRemoteDevice == null) {
            return false;
        }
        int retVal = this.bleMng.getConnectionState(this.bleRemoteDevice, 7);
        return retVal == 2;
    }

    public boolean isSessionTokenExpire() {
        if (this.ssToken == null) {
            return true;
        }
        return this.ssToken.isExpire();
    }

    public void connectAsync() {
        letMeKnow("接到UI连接命令");
        if (isConnected()) {
            letMeKnow("已连，不再执行：" + this.macAddress);
            Log.w(TAG_BLE, "已连，不再执行");
        } else if (this.callbackSignal.connected == 1) {
            letMeKnow("已在Ble连接中...");
            Log.w(TAG_BLE, "已在Ble连接中...");
        } else {
            this.cmdExecSvc = Executors.newSingleThreadExecutor();
            this.cmdExecSvc.execute(new Runnable() { // from class: cn.zelkova.ZKurlcsPlugin.lockprotocol.BleLockConnector.2
                @Override // java.lang.Runnable
                public void run() {
                    try {
                        BleLockConnector.this.doConnect();
                    } catch (Exception ex) {
                        BleLockConnector.this.lastException = ex;
                    }
                    BleLockConnector.this.onConnectionStateCallback(BleLockConnector.this.isConnected() ? ConnectionStateEnum.Connected : ConnectionStateEnum.Disconnected);
                }
            });
        }
    }

    public void connect() {
        letMeKnow("接到UI连接命令");
        if (isConnected()) {
            letMeKnow("已连，不再执行：" + this.macAddress);
            return;
        }
        try {
            doConnect();
        } catch (Exception ex) {
            this.lastException = ex;
        }
        onConnectionStateCallback(isConnected() ? ConnectionStateEnum.Connected : ConnectionStateEnum.Disconnected);
    }

    public void disconnect() {
        if (isConnected()) {
            letMeKnow("接到断开请求");
        } else {
            letMeKnow("接到断开请求，当前已断：" + this.macAddress);
        }
        this.disconnectReq = true;
        this.bleLocalAdp.stopLeScan(this.noopLeScanCallback);
        synchronized (this.callbackSignal) {
            this.callbackSignal.notifyAll();
        }
        if (this.cmdExecSvc != null) {
            this.cmdExecSvc.shutdownNow();
        }
        this.ssToken = null;
        this.inputBuffer.clear();
        this.outputBuffer.clear();
        if (this.bleRemoteGatt != null) {
            synchronized (this.callbackSignal) {
                this.bleRemoteGatt.disconnect();
                letMeKnow("发出断开指令:" + this.macAddress);
                try {
                    this.callbackSignal.wait(1000L);
                    letMeKnow("断开BLE连接，同步信号正常结束");
                } catch (InterruptedException e) {
                    letMeKnow("超时未正常中断BLE连接");
                }
            }
            if (this.bleRemoteGatt != null) {
                Log.w(TAG_BLE, "BluetoothGATT.close again");
                this.bleRemoteGatt.close();
                this.bleRemoteGatt = null;
                this.bleRemoteDevice = null;
                this.lastException = null;
                onConnectionStateCallback(ConnectionStateEnum.Disconnected);
            }
        }
    }

    public void post(final LockCommData data) {
        letMeKnow("接到UI命令");
        this.cmdExecSvc = Executors.newSingleThreadExecutor();
        this.cmdExecSvc.execute(new Runnable() { // from class: cn.zelkova.ZKurlcsPlugin.lockprotocol.BleLockConnector.3
            @Override // java.lang.Runnable
            public void run() {
                try {
                    BleLockConnector.this.doExecute(data);
                    if (!BleLockConnector.this.disconnectReq) {
                        BleLockConnector.this.startReceiveTimer();
                    }
                } catch (Exception ex) {
                    BleLockConnector.this.lastException = ex;
                    BleLockConnector.this.onResultCallbackForExecute(null);
                }
            }
        });
    }

    public LockCommResponse send(LockCommData data) {
        LockCommResponse retVal = null;
        doExecute(data);
        this.callbackSignal.command = 1;
        synchronized (this.callbackSignal) {
            try {
                try {
                    if (this.callbackSignal.command != 2) {
                        this.callbackSignal.wait(BLE_TIMEOUT);
                        if (this.callbackSignal.command == 2) {
                            retVal = this.sendToClient;
                            this.callbackSignal.command = 0;
                            this.sendToClient = null;
                        } else {
                            throw new LockTimeoutException(getErrMsg("1007", "超时未得到返回内容"));
                        }
                    } else {
                        this.callbackSignal.command = 0;
                        this.sendToClient = null;
                    }
                } catch (InterruptedException e) {
                    e.printStackTrace();
                    throw new LockException(getErrMsg("6002", "发送命令时线程中断：" + e.getMessage()), e);
                }
            } catch (Throwable th) {
                this.callbackSignal.command = 0;
                this.sendToClient = null;
                throw th;
            }
        }
        return retVal;
    }

    public static long getIntervalTimeInTwoConnection() {
        return IntervalTimeInTwoConnection;
    }

    public static void setIntervalTimeInTwoConnection(int val) {
        IntervalTimeInTwoConnection = val;
    }

    private static boolean waitInTwoConnection() {
        long diff = new Date().getTime() - LastDisconnectTime.getTime();
        if (diff > IntervalTimeInTwoConnection) {
            return false;
        }
        Log.d(TAG_BLE, "当前时间:" + BriefDate.fromNature(Calendar.getInstance().getTime()).toString() + ",上次断开时间:" + BriefDate.fromNature(LastDisconnectTime).toString());
        try {
            Log.d(TAG_BLE, "需休眠" + (((long) IntervalTimeInTwoConnection) - diff));
            Thread.sleep(((long) IntervalTimeInTwoConnection) - diff);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
        return true;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void doExecute(LockCommData data) {
        byte[] token = new byte[0];
        if (!isConnected()) {
            doConnect();
            onConnectionStateCallback(ConnectionStateEnum.Connected);
        }
        if (!this.disconnectReq) {
            if (data.needSessionToken()) {
                letMeKnow("需要ssToken：[" + ((int) data.getCmdId()) + "]" + data.getCmdName());
                doRefreshSsToken();
                DateFormat df = SimpleDateFormat.getTimeInstance();
                token = this.ssToken.getToken();
                letMeKnow("本次使用的Token：" + BitConverter.toHexString(token) + "; exp:" + df.format(this.ssToken.getExpire()));
            }
            byte[] buffer = data.getBytes(token);
            for (byte b : buffer) {
                this.outputBuffer.add(Byte.valueOf(b));
            }
            writeRXCharacteristic(buffer);
        }
    }

    private void doRefreshSsToken() {
        synchronized (this.callbackSignal) {
            this.callbackSignal.sessionToken = 0;
            LockCommSessionToken st = new LockCommSessionToken();
            Log.d(TAG_BLE, "ssToken-st:" + BitConverter.toHexString(st.getBytes()));
            writeRXCharacteristic(st.getBytes());
            this.callbackSignal.sessionToken = 1;
            try {
                try {
                    this.callbackSignal.wait(BLE_TIMEOUT);
                    if (this.callbackSignal.sessionToken == 2) {
                        letMeKnow("得到了SessionToken");
                        this.callbackSignal.sessionToken = 0;
                    } else {
                        letMeKnow("超时未得到SessionToken");
                        throw new LockTimeoutException(getErrMsg("1006", "获取ssToken超时"));
                    }
                } catch (InterruptedException e) {
                    e.printStackTrace();
                    throw new LockException(getErrMsg("1006", "获取ssToken时线程中断：" + e.getMessage()), e);
                }
            } catch (Throwable th) {
                this.callbackSignal.sessionToken = 0;
                throw th;
            }
        }
    }

    private boolean doCompatibleBleScan() {
        boolean found;
        synchronized (this.callbackSignal) {
            UUID[] svcUUID = getEnableSvcUUIDScanFilter() == 0 ? null : new UUID[]{RX_SERVICE_UUID};
            this.bleLocalAdp.startLeScan(svcUUID, this.noopLeScanCallback);
            letMeKnow("bleScan is doing for " + BLE_TIMEOUT + "ms...");
            this.callbackSignal.connected = 1;
            try {
                try {
                    this.callbackSignal.wait(BLE_TIMEOUT);
                    found = this.callbackSignal.connected == 2;
                    this.callbackSignal.connected = 0;
                    this.bleLocalAdp.stopLeScan(this.noopLeScanCallback);
                } catch (InterruptedException e) {
                    this.callbackSignal.connected = 0;
                    letMeKnow("bleScan not found, timeout");
                    this.bleLocalAdp.stopLeScan(this.noopLeScanCallback);
                    return false;
                }
            } catch (Throwable th) {
                this.bleLocalAdp.stopLeScan(this.noopLeScanCallback);
                throw th;
            }
        }
        return found;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public String getErrMsg(String code, String message) {
        JSONObject errorObj = new JSONObject();
        try {
            errorObj.put(Constants.KEY_HTTP_CODE, code);
            errorObj.put(Constants.SHARED_MESSAGE_ID_FILE, message);
        } catch (JSONException e) {
            e.printStackTrace();
        }
        return errorObj.toString();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void doConnect() {
        waitInTwoConnection();
        int currentRetry = 0;
        this.disconnectReq = false;
        while (!this.disconnectReq) {
            try {
                boolean findDevice = doCompatibleBleScan();
                if (!findDevice) {
                    throw new LockTimeoutException(getErrMsg("2003", "连接超时"));
                }
                doConnectCore();
                return;
            } catch (LockTimeoutException ex) {
                currentRetry++;
                String msg = ("发生异常[" + ex.getMessage() + "]") + "，第" + currentRetry + "/" + BLE_Retry_Times + "次";
                letMeKnow(msg);
                Log.w(TAG_BLE, msg);
                if (this.bleRemoteGatt != null) {
                    this.bleRemoteGatt.close();
                    this.bleRemoteGatt = null;
                    this.bleRemoteDevice = null;
                }
                if (currentRetry >= BLE_Retry_Times) {
                    String msg2 = "重试 " + currentRetry + " 次后仍未成功连接，报连接超时";
                    letMeKnow(msg2);
                    Log.e(TAG_BLE, msg2);
                    throw ex;
                }
            }
        }
    }

    private void doConnectCore() {
        synchronized (this.callbackSignal) {
            if (this.callbackSignal.connected != 0) {
                letMeKnow("当前在执行连接动作，退出：" + this.callbackSignal.connected);
                return;
            }
            this.callbackSignal.connected = 0;
            letMeKnow("开始执行连接到：" + this.macAddress);
            if (this.bleRemoteDevice == null) {
                this.bleRemoteDevice = this.bleLocalAdp.getRemoteDevice(this.macAddress);
                Log.w(TAG_BLE, "连接时初始化bluetoothDevice");
            }
            this.bleRemoteGatt = this.bleRemoteDevice.connectGatt(this.context, false, this.myBleGattCallback);
            letMeKnow("连接命令发送完成");
            this.callbackSignal.connected = 1;
            try {
                try {
                    this.callbackSignal.wait(BLE_TIMEOUT);
                    if (this.callbackSignal.connected != 2) {
                        throw new LockTimeoutException(getErrMsg("2003", "连接超时"));
                    }
                    this.callbackSignal.connected = 0;
                    return;
                } catch (InterruptedException e) {
                    e.printStackTrace();
                    throw new LockException(getErrMsg("6003", "连接时线程中断：" + e.getMessage()), e);
                }
            } catch (Throwable th) {
                this.callbackSignal.connected = 0;
                throw th;
            }
            this.callbackSignal.connected = 0;
            throw th;
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public boolean enableTXNotification() {
        BluetoothGattService gattRxSvc = this.bleRemoteGatt.getService(RX_SERVICE_UUID);
        if (gattRxSvc == null) {
            letMeKnow("\tRx gattSvc not found：" + RX_SERVICE_UUID);
            return false;
        }
        BluetoothGattCharacteristic gattTxChar = gattRxSvc.getCharacteristic(TX_CHAR_UUID);
        if (gattTxChar == null) {
            letMeKnow("\tTx gattChar not found：" + TX_CHAR_UUID);
            return false;
        }
        this.bleRemoteGatt.setCharacteristicNotification(gattTxChar, true);
        BluetoothGattDescriptor descriptor = gattTxChar.getDescriptor(CCCD);
        descriptor.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
        boolean result = this.bleRemoteGatt.writeDescriptor(descriptor);
        letMeKnow("\tenableTXNotification：" + result);
        return result;
    }

    private void writeRXCharacteristic(byte[] val) {
        BluetoothGattService gattRxSvc = this.bleRemoteGatt.getService(RX_SERVICE_UUID);
        if (gattRxSvc == null) {
            letMeKnow("Rx service not found：" + RX_SERVICE_UUID);
            throw new LockException(getErrMsg("6004", "蓝牙底层失败(RxSvcNotFound)"));
        }
        BluetoothGattCharacteristic gattRxChar = gattRxSvc.getCharacteristic(RX_CHAR_UUID);
        if (gattRxChar == null) {
            letMeKnow("Rx characteristic not found：" + RX_CHAR_UUID);
            throw new LockException(getErrMsg("6004", "蓝牙底层失败(RxSvcNotFound)"));
        }
        letMeKnow("******** Begin Tx[Len:" + val.length + "] ********");
        synchronized (this.callbackSignal) {
            int mBufferOffset = 0;
            int idx = 0;
            while (mBufferOffset < val.length) {
                try {
                    this.callbackSignal.writeRX = 0;
                    idx++;
                    int length = Math.min(val.length - mBufferOffset, 20);
                    byte[] data = new byte[length];
                    System.arraycopy(val, mBufferOffset, data, 0, length);
                    gattRxChar.setValue(data);
                    boolean success = this.bleRemoteGatt.writeCharacteristic(gattRxChar);
                    mBufferOffset += length;
                    letMeKnow("[Tx:" + idx + ",status:" + success + "]" + BitConverter.toHexString(data));
                    if (!success) {
                        throw new LockException(getErrMsg("6005", "未成功发送BLE指令"));
                    }
                    this.callbackSignal.writeRX = 1;
                    while (this.callbackSignal.writeRX != 2) {
                        this.callbackSignal.wait(BLE_TIMEOUT);
                        if (this.callbackSignal.writeRX != 2) {
                            letMeKnow("超时未等到Rx写入确认");
                            throw new LockException(getErrMsg("6001", "超时未等到Rx写入确认"));
                        }
                    }
                } catch (InterruptedException e) {
                    e.printStackTrace();
                    throw new LockException(getErrMsg("6002", "发送命令时线程中断：" + e.getMessage()), e);
                }
            }
        }
        letMeKnow("-------- finished Tx --------");
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void onConnectionStateCallback(ConnectionStateEnum state) {
        Log.d("zk-callback", "state---1----: " + state);
        if (this.resultCallback != null) {
            Log.d("zk-callback", "state----2---: " + state);
            try {
                this.resultCallback.onConnectionState(this.macAddress, state, this.lastException);
                this.lastException = null;
            } catch (Exception ex) {
                Log.e(TAG_BLE, "连接回调，客户端发生异常：" + ex.getMessage());
                ex.printStackTrace();
            }
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void onResultCallbackForExecute(LockCommResponse response) {
        if (this.resultCallback != null) {
            try {
                this.resultCallback.onExecutionResult(this.macAddress, this.lastException, response);
                this.lastException = null;
                this.sendToClient = null;
            } catch (Exception ex) {
                Log.e(TAG_BLE, "执行回调，客户端发生异常：" + ex.getMessage());
                ex.printStackTrace();
            }
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void startReceiveTimer() {
        if (this.receiveTimer != null) {
            this.receiveTimer.cancel();
        }
        this.receiveTimer = new Timer("receiveTimer");
        this.receiveTimer.schedule(new TimerTask() { // from class: cn.zelkova.ZKurlcsPlugin.lockprotocol.BleLockConnector.4
            @Override // java.util.TimerTask, java.lang.Runnable
            public void run() {
                BleLockConnector.this.letMeKnow("接收指令超时");
                if (BleLockConnector.this.resultCallback != null) {
                    LockTimeoutException ex = new LockTimeoutException(BleLockConnector.this.getErrMsg("1007", "接收响应内容超时"));
                    BleLockConnector.this.lastException = ex;
                    BleLockConnector.this.onResultCallbackForExecute(null);
                }
            }
        }, BLE_TIMEOUT);
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void cancelReceiveTimer() {
        if (this.receiveTimer != null) {
            this.receiveTimer.cancel();
        }
    }

    public void setResultCallback(IResultCallback callback) {
        this.resultCallback = callback;
    }

    public void setWhatHappend(WhatHappenCallback callback) {
        this.whatHappenCallback = callback;
        this.selfShowMsg = true;
    }

    public void setWhatHappend(boolean innerShowMsg, WhatHappenCallback callback) {
        this.whatHappenCallback = callback;
        this.selfShowMsg = innerShowMsg;
    }

    @Override // cn.zelkova.ZKurlcsPlugin.lockprotocol.WhatHappenCallback
    public void letMeKnow(String msg) {
        if (this.selfShowMsg || this.whatHappenCallback == null) {
            Log.i(TAG_BLE, msg);
        }
        if (this.whatHappenCallback != null) {
            this.whatHappenCallback.letMeKnow(msg);
        }
    }

    public static void addZkBleBlock(ZKBleBlock zkBleBlock) {
        zkBleBlocks.add(zkBleBlock);
        Log.d("ZK-BleBlock", "add: " + zkBleBlocks.size());
    }

    public static BleLockConnector create(Context ctx, String mac) {
        if (ConnectorPool.containsKey(mac)) {
            return ConnectorPool.get(mac);
        }
        BleLockConnector retVal = new BleLockConnector(ctx, mac);
        ConnectorPool.put(mac, retVal);
        return retVal;
    }

    public static BleLockConnector get(String mac) {
        if (ConnectorPool.containsKey(mac)) {
            return ConnectorPool.get(mac);
        }
        return null;
    }

    public static void clear(String mac) {
        if (ConnectorPool.containsKey(mac)) {
            BleLockConnector conn = ConnectorPool.remove(mac);
            conn.disconnect();
            conn.setResultCallback(null);
            conn.setWhatHappend(null);
            Log.i(TAG_BLE, "释放BleLockConnection对象：" + mac);
        }
    }

    public static void clearAll() {
        for (String curMac : ConnectorPool.keySet()) {
            clear(curMac);
        }
    }
}
