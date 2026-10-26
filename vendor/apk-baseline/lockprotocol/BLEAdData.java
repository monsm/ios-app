package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import android.util.Log;
import com.xiaomi.mipush.sdk.MiPushClient;
import java.io.UnsupportedEncodingException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/* JADX INFO: loaded from: classes.dex */
public class BLEAdData {
    private static final byte ADV_TYPE = -2;
    private List<AdStruct> mAdDataList = new ArrayList();
    private String mId;

    private class AdStruct {
        public byte[] adData;
        public byte adType;
        public byte length;

        private AdStruct() {
        }

        public String toString() {
            return "[" + ((int) this.length) + MiPushClient.ACCEPT_TIME_SEPARATOR + String.format("0x%02x", Byte.valueOf(this.adType)) + "]" + BitConverter.toHexString(this.adData);
        }
    }

    public static BLEAdData parse(String id, byte[] scanRecord) {
        byte length;
        BLEAdData bleAdData = new BLEAdData();
        bleAdData.mId = id;
        ByteBuffer buffer = ByteBuffer.wrap(scanRecord).order(ByteOrder.LITTLE_ENDIAN);
        while (buffer.remaining() > 2 && (length = buffer.get()) != 0) {
            byte adType = buffer.get();
            byte[] adData = new byte[length - 1];
            buffer.get(adData, 0, length - 1);
            if (adData.length > 2 && BitConverter.toHexString(adData, "").substring(0, 4).equals("98ed") && adData[2] >= 12) {
                Log.d("vvvvcccc", BitConverter.toHexString(adData));
                bleAdData.add(length, ADV_TYPE, adData);
            } else {
                bleAdData.add(length, adType, adData);
            }
        }
        return bleAdData;
    }

    public int getManuId() {
        byte[] mData = getManufacturerData();
        if (mData == null) {
            return 0;
        }
        try {
            byte[] manuId = Arrays.copyOfRange(mData, 0, 2);
            return manuId[0];
        } catch (Exception ex) {
            ex.printStackTrace();
            return 0;
        }
    }

    public byte[] getMac() {
        byte[] mData = getAdvData();
        if (mData == null) {
            return null;
        }
        return Arrays.copyOfRange(mData, 6, 12);
    }

    public String getMacHexText() {
        byte[] mac = getMac();
        return mac == null ? "" : BitConverter.toHexString(mac, "");
    }

    public String getMacText() {
        byte[] mac = getMac();
        return mac == null ? "" : BitConverter.convertMacAdd(mac);
    }

    public int getPid() {
        byte[] mData = getAdvData();
        if (mData == null) {
            return 0;
        }
        byte[] pdata = Arrays.copyOfRange(mData, 4, 6);
        return BitConverter.toInt16(pdata, 0);
    }

    private AdStruct add(byte length, byte adType, byte[] adData) {
        AdStruct ad = new AdStruct();
        ad.length = length;
        ad.adType = adType;
        ad.adData = adData;
        this.mAdDataList.add(ad);
        return ad;
    }

    public AdStruct[] getADList() {
        return (AdStruct[]) this.mAdDataList.toArray(new AdStruct[0]);
    }

    public String getId() {
        return this.mId;
    }

    public byte[] getManufacturerData() {
        byte[] mData = getData((byte) -1);
        Log.d("ZK-ManuFac", BitConverter.toHexString(mData));
        return mData;
    }

    public byte[] getAdvData() {
        byte[] mData = getData(ADV_TYPE);
        return mData;
    }

    public String byteToBit(byte b) {
        return "" + ((int) ((byte) ((b >> 7) & 1))) + ((int) ((byte) ((b >> 6) & 1))) + ((int) ((byte) ((b >> 5) & 1))) + ((int) ((byte) ((b >> 4) & 1))) + ((int) ((byte) ((b >> 3) & 1))) + ((int) ((byte) ((b >> 2) & 1))) + ((int) ((byte) ((b >> 1) & 1))) + ((int) ((byte) ((b >> 0) & 1)));
    }

    private byte getFrameCtrl() {
        byte[] advData = getAdvData();
        if (advData == null) {
            return (byte) 0;
        }
        return advData[2];
    }

    public int getResetStatus() {
        byte b = getFrameCtrl();
        int result = (b >> 0) & 1;
        return result;
    }

    public int getContainNotify() {
        byte b = getFrameCtrl();
        int result = (b >> 1) & 1;
        return result;
    }

    public int getContainPid() {
        byte b = getFrameCtrl();
        int result = (b >> 2) & 1;
        return result;
    }

    public int getContainMac() {
        byte b = getFrameCtrl();
        int result = (b >> 3) & 1;
        return result;
    }

    public int getDfuState() {
        byte b = getFrameCtrl();
        int result = (b >> 5) & 1;
        return result;
    }

    public String getNetStateText() {
        byte[] mData = getManufacturerData();
        byte netState = 0;
        if (mData != null) {
            netState = mData[9];
        }
        return byteToBit(netState);
    }

    private int getHeight4(byte data) {
        int height = (data & 240) >> 4;
        return height;
    }

    private int getLow4(byte data) {
        int low = data & 15;
        return low;
    }

    public String getDeviceName() {
        String deviceName = "";
        byte[] dName = getData((byte) 8);
        if (dName != null) {
            try {
                deviceName = new String(dName, "utf-8");
            } catch (UnsupportedEncodingException e) {
                e.printStackTrace();
            }
        }
        byte[] dName2 = getData((byte) 9);
        if (dName2 != null) {
            try {
                return new String(dName2, "utf-8");
            } catch (UnsupportedEncodingException e2) {
                e2.printStackTrace();
                return deviceName;
            }
        }
        return deviceName;
    }

    private byte[] getData(byte type) {
        byte[] result = null;
        for (AdStruct cur : this.mAdDataList) {
            if (cur.adType == type) {
                if (result == null) {
                    result = cur.adData;
                } else {
                    Log.w(getClass().getSimpleName(), "发现了重复的AdType:" + ((int) type));
                }
            }
        }
        return result;
    }
}
