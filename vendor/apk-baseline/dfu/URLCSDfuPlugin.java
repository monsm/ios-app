package com.plugin.urlcsDfuPlugin;

import android.util.Log;
import com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuProgressListener;
import com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuServiceListenerHelper;
import com.taobao.accs.common.Constants;
import org.android.agoo.common.AgooConstants;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/* JADX INFO: loaded from: classes.dex */
public class URLCSDfuPlugin extends CordovaPlugin {
    private final String TAG = "ZK-Dfu";
    DfuProgressListener mDfuProgressListener = new DfuProgressListener() { // from class: com.plugin.urlcsDfuPlugin.URLCSDfuPlugin.1
        @Override // com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuProgressListener
        public void onDeviceConnecting(String deviceAddress) {
            Log.d("ZK-Dfu", "升级服务开始与硬件设备连接.");
            URLCSDfuPlugin.this.sendExeResult("state", 0, "升级服务开始与硬件设备连接.");
        }

        @Override // com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuProgressListener
        public void onDeviceConnected(String deviceAddress) {
            Log.d("ZK-Dfu", "升级服务连接成功.");
            URLCSDfuPlugin.this.sendExeResult("state", -1, "升级服务连接成功.");
        }

        @Override // com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuProgressListener
        public void onDfuProcessStarting(String deviceAddress) {
            Log.d("ZK-Dfu", "升级进程启动.");
            URLCSDfuPlugin.this.sendExeResult("state", 1, "升级进程启动.");
        }

        @Override // com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuProgressListener
        public void onDfuProcessStarted(String deviceAddress) {
            Log.d("ZK-Dfu", "DFU进程启动和要发送的字节" + deviceAddress);
            URLCSDfuPlugin.this.sendExeResult("state", -1, "DFU进程启动和要发送的字节");
        }

        @Override // com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuProgressListener
        public void onEnablingDfuMode(String deviceAddress) {
            Log.d("ZK-Dfu", "硬件设备切换到升级模式.");
            URLCSDfuPlugin.this.sendExeResult("state", 2, "硬件设备切换到升级模式.");
        }

        @Override // com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuProgressListener
        public void onProgressChanged(String deviceAddress, int percent, float speed, float avgSpeed, int currentPart, int partsTotal) {
            URLCSDfuPlugin.this.sendExeResult("progress", -1, percent + "");
        }

        @Override // com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuProgressListener
        public void onFirmwareValidating(String deviceAddress) {
            Log.d("ZK-Dfu", "硬件设备正在验证新固件！");
            URLCSDfuPlugin.this.sendExeResult("state", 4, "硬件设备正在验证新固件！");
        }

        @Override // com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuProgressListener
        public void onDeviceDisconnecting(String deviceAddress) {
            Log.d("ZK-Dfu", "服务开始断开设备连接！");
            URLCSDfuPlugin.this.sendExeResult("state", 5, "服务开始断开设备连接！");
        }

        @Override // com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuProgressListener
        public void onDeviceDisconnected(String deviceAddress) {
            Log.d("ZK-Dfu", "硬件设备已重置！");
            URLCSDfuPlugin.this.sendExeResult("state", -1, "硬件设备已重置！");
        }

        @Override // com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuProgressListener
        public void onDfuCompleted(String deviceAddress) {
            Log.d("ZK-Dfu", "升级成功！");
            URLCSDfuPlugin.this.sendExeResult("state", 6, "升级成功！");
            DfuServiceListenerHelper.unregisterProgressListener(URLCSDfuPlugin.this.cordova.getActivity(), URLCSDfuPlugin.this.mDfuProgressListener);
        }

        @Override // com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuProgressListener
        public void onDfuAborted(String deviceAddress) {
            Log.d("ZK-Dfu", "升级进程已中止");
            URLCSDfuPlugin.this.sendExeResult("state", 7, "升级进程已中止！");
        }

        @Override // com.plugin.urlcsDfuPlugin.no.nordicsemi.android.dfu.DfuProgressListener
        public void onError(String deviceAddress, int error, int errorType, String message) {
            Log.d("ZK-Dfu", "升级发生错误:" + message);
            URLCSDfuPlugin.this.sendExeResult("error", error, "升级发生错误:" + message);
        }
    };

    @Override // org.apache.cordova.CordovaPlugin
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        Log.d("ZK-action", action);
        if (!action.equals("startDfu")) {
            return false;
        }
        JSONObject dataObj = args.getJSONObject(0);
        startDfu(dataObj, callbackContext);
        return true;
    }

    private void startDfu(JSONObject dataObj, CallbackContext callbackContext) {
        Log.d("ZK-启动", "进入DFU插件");
        ZKBleBlock zkBleBlock = new ZKBleBlock(dataObj, this.cordova.getActivity(), callbackContext);
        BleDfu bleDfu = BleDfu.getInstance(zkBleBlock);
        bleDfu.doScan();
        DfuServiceListenerHelper.registerProgressListener(this.cordova.getActivity(), this.mDfuProgressListener);
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void sendExeResult(String type, int code, String value) {
        JSONObject data = new JSONObject();
        try {
            JSONObject vObj = new JSONObject();
            if (type.equals("state")) {
                vObj.put("state", code);
                vObj.put(Constants.SHARED_MESSAGE_ID_FILE, value);
                data.put("state", vObj);
            } else if (type.equals("error")) {
                vObj.put(Constants.KEY_ERROR_CODE, code);
                vObj.put(Constants.SHARED_MESSAGE_ID_FILE, value);
                data.put("error", vObj);
            } else {
                vObj.put("progress", value);
                data.put("progress", vObj);
            }
            data.put(AgooConstants.MESSAGE_TYPE, type);
            Log.d("ZK-Dfu", data.toString());
        } catch (JSONException je) {
            je.printStackTrace();
        }
        PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, data);
        pluginResult.setKeepCallback(true);
        ZKBleBlock.callbackContext.sendPluginResult(pluginResult);
    }
}
