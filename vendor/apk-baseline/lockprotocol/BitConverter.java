package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import com.xiaomi.mipush.sdk.MiPushClient;
import java.util.ArrayList;
import java.util.Collections;

/* JADX INFO: loaded from: classes.dex */
public class BitConverter {
    public static int byteToInt(byte b) {
        return b & 255;
    }

    public static short toInt16(byte[] bytes, int offset) {
        short result = (short) (bytes[offset] & 255);
        return (short) (65535 & ((short) (((bytes[offset + 1] & 255) << 8) | result)));
    }

    public static int toUInt16(byte[] bytes, int offset) {
        int result = bytes[offset] & 255;
        return 65535 & (result | ((bytes[offset + 1] & 255) << 8));
    }

    public static int toInt32(byte[] bytes, int offset) {
        int result = bytes[offset] & 255;
        return result | ((bytes[offset + 1] & 255) << 8) | ((bytes[offset + 2] & 255) << 16) | ((bytes[offset + 3] & 255) << 24);
    }

    public static long toUInt32(byte[] bytes, int offset) {
        long result = bytes[offset] & 255;
        return 4294967295L & (result | ((long) ((bytes[offset + 1] & 255) << 8)) | ((long) ((bytes[offset + 2] & 255) << 16)) | ((long) ((bytes[offset + 3] & 255) << 24)));
    }

    public static long toInt64(byte[] bytes, int offset) {
        long result = ((long) bytes[offset]) & 255;
        return (-1) & (result | ((((long) bytes[offset + 1]) & 255) << 8) | ((((long) bytes[offset + 2]) & 255) << 16) | ((((long) bytes[offset + 3]) & 255) << 24) | ((((long) bytes[offset + 4]) & 255) << 32) | ((((long) bytes[offset + 5]) & 255) << 40) | ((((long) bytes[offset + 6]) & 255) << 48) | ((((long) bytes[offset + 7]) & 255) << 56));
    }

    public static byte[] getBytes(short value) {
        byte[] bytes = {(byte) value, (byte) (value >> 8)};
        return bytes;
    }

    public static byte[] getBytes(int value) {
        byte[] bytes = {(byte) value, (byte) (value >> 8), (byte) (value >> 16), (byte) (value >> 24)};
        return bytes;
    }

    public static byte[] getBytes(long value) {
        byte[] bytes = {(byte) value, (byte) (value >> 8), (byte) (value >> 16), (byte) (value >> 24), (byte) (value >> 32), (byte) (value >> 40), (byte) (value >> 48), (byte) (value >> 56)};
        return bytes;
    }

    public static String toHexString(byte[] value) {
        return toHexString(value, MiPushClient.ACCEPT_TIME_SEPARATOR);
    }

    public static String toHexString(byte[] value, String splitter) {
        StringBuilder sb = new StringBuilder();
        for (byte b : value) {
            Byte cur = Byte.valueOf(b);
            String val = String.format("%02x", cur);
            if (sb.length() <= 0) {
                sb.append(val);
            } else {
                sb.append(splitter + val);
            }
        }
        return sb.toString();
    }

    public static byte[] fromHexString(String hexString) {
        if (hexString == null || hexString.equals("")) {
            return null;
        }
        String hexString2 = hexString.toUpperCase();
        int length = hexString2.length() / 2;
        char[] hexChars = hexString2.toCharArray();
        byte[] d = new byte[length];
        for (int i = 0; i < length; i++) {
            int pos = i * 2;
            d[i] = (byte) ((charToByte(hexChars[pos]) << 4) | charToByte(hexChars[pos + 1]));
        }
        return d;
    }

    public static byte[] fromHexString(String hexString, String splitter) {
        return fromHexString(hexString.replace(splitter, ""));
    }

    private static byte charToByte(char c) {
        return (byte) "0123456789ABCDEF".indexOf(c);
    }

    @Deprecated
    public static byte[] hexStringToBytes(String hexString) {
        return fromHexString(hexString);
    }

    public static byte[] toPrimitive(Byte[] value) {
        byte[] result = new byte[value.length];
        for (int i = 0; i < value.length; i++) {
            result[i] = value[i].byteValue();
        }
        return result;
    }

    public static Byte[] toPackaged(byte[] value) {
        Byte[] result = new Byte[value.length];
        for (int i = 0; i < value.length; i++) {
            result[i] = Byte.valueOf(value[i]);
        }
        return result;
    }

    public static String getConnectMacFromSmall(String mac) {
        byte[] macBytes = fromHexString(mac);
        return convertMacAdd(macBytes);
    }

    public static String getConnectMacFromBig(String mac) {
        byte[] macBytes = fromHexString(mac);
        if (macBytes.length > 8) {
            throw new IllegalArgumentException("mac length must be less 8 bytes");
        }
        ArrayList<Byte> temp = new ArrayList<>();
        for (byte b : macBytes) {
            Byte cur = Byte.valueOf(b);
            temp.add(cur);
        }
        while (temp.size() > 6 && temp.get(0).byteValue() == 0) {
            temp.remove(0);
        }
        Byte[] macByte = (Byte[]) temp.toArray(new Byte[0]);
        return toHexString(toPrimitive(macByte), ":");
    }

    public static byte[] convertMacAdd(String mac) {
        byte[] macByte = fromHexString(mac, ":");
        if (macByte.length > 8) {
            throw new IllegalArgumentException("mac length must be less 8 bytes");
        }
        ArrayList<Byte> temp = new ArrayList<>();
        for (byte b : macByte) {
            Byte cur = Byte.valueOf(b);
            temp.add(cur);
        }
        Collections.reverse(temp);
        while (temp.size() < 8) {
            temp.add((byte) 0);
        }
        Byte[] mac8 = (Byte[]) temp.toArray(new Byte[0]);
        return toPrimitive(mac8);
    }

    public static String convertMacAdd(byte[] mac) {
        if (mac.length > 8) {
            throw new IllegalArgumentException("mac length must be less 8 bytes");
        }
        ArrayList<Byte> temp = new ArrayList<>();
        for (byte b : mac) {
            Byte cur = Byte.valueOf(b);
            temp.add(cur);
        }
        Collections.reverse(temp);
        while (temp.size() > 6 && temp.get(0).byteValue() == 0) {
            temp.remove(0);
        }
        Byte[] macByte = (Byte[]) temp.toArray(new Byte[0]);
        return toHexString(toPrimitive(macByte), ":");
    }
}
