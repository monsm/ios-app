package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import android.util.Log;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.util.ArrayList;

/* JADX INFO: loaded from: classes.dex */
class KLVListContainer extends ArrayList<KLVContainer> {
    private static String TAG = "KLVListContainer";

    public KLVContainer getKLV(int key) {
        for (int i = 0; i < super.size(); i++) {
            KLVContainer klv = (KLVContainer) super.get(i);
            if (klv.getKey() == key) {
                return klv;
            }
        }
        return null;
    }

    public byte getByteVal(int key) {
        return getKLV(key).getVal()[0];
    }

    public short getShortVal(int key) {
        return BitConverter.toInt16(getKLV(key).getVal(), 0);
    }

    public int getUShortVal(int key) {
        return BitConverter.toUInt16(getKLV(key).getVal(), 0);
    }

    public int getIntVal(int key) {
        return BitConverter.toInt32(getKLV(key).getVal(), 0);
    }

    public long getUIntVal(int key) {
        return BitConverter.toUInt32(getKLV(key).getVal(), 0);
    }

    public long getLongVal(int key) {
        return BitConverter.toInt64(getKLV(key).getVal(), 0);
    }

    public byte[] getBytes() {
        ByteArrayOutputStream result = new ByteArrayOutputStream();
        try {
            for (KLVContainer klv : this) {
                result.write(klv.getBytes());
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
        return result.toByteArray();
    }

    @Override // java.util.AbstractCollection
    public String toString() {
        StringBuilder sb = new StringBuilder();
        for (KLVContainer klv : this) {
            sb.append(klv.toString());
        }
        return sb.toString();
    }

    public KLVContainer add(byte key, byte val) {
        KLVContainer klv = new KLVContainer(key, new byte[]{val});
        super.add(klv);
        return klv;
    }

    public KLVContainer add(byte key, byte[] val) {
        KLVContainer klv = new KLVContainer(key, val);
        super.add(klv);
        return klv;
    }

    public KLVContainer add(byte key, String val) {
        try {
            byte[] valByte = val.getBytes("utf-8");
            return add(key, valByte);
        } catch (UnsupportedEncodingException e) {
            throw new RuntimeException(e);
        }
    }

    public static KLVListContainer parse(byte[] value) {
        ByteArrayInputStream bais = new ByteArrayInputStream(value);
        LittleEndianInputStream input = new LittleEndianInputStream(bais);
        KLVListContainer result = new KLVListContainer();
        while (true) {
            try {
                int key = input.readUnsignedByte();
                int len = input.readUnsignedByte();
                byte[] val = new byte[len];
                input.read(val);
                result.add((byte) key, val);
            } catch (IOException e) {
                Log.i(TAG, "正确的通过异常判断了KLV解析完成：" + e.getMessage());
                if (1 == 0) {
                    throw new LockFormatException("KLV未能正确解析所有的内容");
                }
                return result;
            }
        }
    }
}
