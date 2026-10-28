package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Arrays;

/* JADX INFO: loaded from: classes.dex */
class KLVContainer {
    private int mKey;
    private byte[] mVal;

    public String toString() {
        String result = "[" + Integer.toHexString(this.mKey);
        return ((result + "." + Integer.toString(this.mVal.length)) + "." + Arrays.toString(this.mVal)) + "]";
    }

    public KLVContainer(int key, byte[] val) {
        this.mKey = 0;
        this.mVal = null;
        this.mKey = key;
        this.mVal = val;
    }

    public int getKey() {
        return this.mKey;
    }

    public byte[] getVal() {
        return this.mVal;
    }

    public byte[] getBytes() {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        LittleEndianOutputStream out = new LittleEndianOutputStream(baos);
        try {
            out.writeByte(this.mKey);
            out.writeByte(this.mVal.length);
            out.write(this.mVal);
            return baos.toByteArray();
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }
}
