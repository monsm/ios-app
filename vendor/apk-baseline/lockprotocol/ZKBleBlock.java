package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import org.apache.cordova.CallbackContext;

/* JADX INFO: loaded from: classes.dex */
public class ZKBleBlock {
    CallbackContext callbackContext;
    boolean keep;
    int key;

    public ZKBleBlock(boolean keep, int key, CallbackContext callbackContext) {
        this.callbackContext = callbackContext;
        this.keep = keep;
        this.key = key;
    }

    public CallbackContext getCallbackContext() {
        return this.callbackContext;
    }

    public void setCallbackContext(CallbackContext callbackContext) {
        this.callbackContext = callbackContext;
    }

    public boolean isKeep() {
        return this.keep;
    }

    public void setKeep(boolean keep) {
        this.keep = keep;
    }

    public int getKey() {
        return this.key;
    }

    public void setKey(int key) {
        this.key = key;
    }
}
