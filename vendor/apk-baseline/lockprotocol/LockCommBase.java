package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import android.util.Log;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.ArrayDeque;
import java.util.Arrays;

/* JADX INFO: loaded from: classes.dex */
public abstract class LockCommBase {
    private static final int HEAD_LEN = 8;
    private static final String TAG = "ZKLockCommBase";
    private static final byte headMark = -121;
    private static final byte reserve = 0;
    private static final byte version = 16;
    private int sequId = 0;
    protected final KLVListContainer mKLVList = new KLVListContainer();

    public abstract byte getCmdId();

    public abstract String getCmdName();

    public abstract boolean needSessionToken();

    private static boolean hasWholeBody(byte[] buffer) {
        byte[] head = Arrays.copyOf(buffer, 8);
        if (head[0] != -121) {
            Log.e("LockCommBase", "无效的Comm协议头内容");
            throw new LockFormatException("无效的Comm协议头内容");
        }
        int payloadLen = BitConverter.toUInt16(buffer, 2);
        Log.i(TAG, "缓存长度：" + buffer.length + "；payloadLen：" + payloadLen + "；协议包长度：" + (payloadLen + 8));
        return buffer.length >= payloadLen + 8;
    }

    public static LockCommResponse parse(ArrayDeque<Byte> value) {
        byte[] buffer = BitConverter.toPrimitive((Byte[]) value.toArray(new Byte[0]));
        Log.d(TAG, BitConverter.toHexString(buffer));
        if (!hasWholeBody(buffer)) {
            return null;
        }
        int packageLen = BitConverter.toUInt16(buffer, 2) + 8;
        byte[] buffer2 = new byte[packageLen];
        for (int i = 0; i < packageLen; i++) {
            buffer2[i] = value.pop().byteValue();
        }
        Log.i(TAG, "缓存消耗后长度：" + value.size());
        Log.d("ZK-buffer", BitConverter.toHexString(buffer2));
        try {
            ByteArrayInputStream inStream = new ByteArrayInputStream(buffer2);
            LittleEndianInputStream input = new LittleEndianInputStream(inStream);
            byte tempByte = input.readByte();
            if (tempByte != -121) {
                String msg = "无效的Comm协议头内容:" + ((int) tempByte);
                Log.e(TAG, msg);
                throw new LockFormatException(msg);
            }
            input.readByte();
            int payloadLen = input.readUnsignedShort();
            byte cmdId = input.readByte();
            input.readByte();
            input.readByte();
            input.readByte();
            byte[] klvBuffer = new byte[payloadLen];
            input.read(klvBuffer);
            KLVListContainer klvList = KLVListContainer.parse(klvBuffer);
            LockCommResponse response = LockCommResponseMapper.create(cmdId);
            response.setCmdId(cmdId);
            response.setKLVList(klvList);
            return response;
        } catch (IOException e) {
            e.printStackTrace();
            throw new LockFormatException("解析Comm时异常:" + e.getMessage(), e);
        }
    }

    private boolean getErrFlag() {
        return false;
    }

    private boolean getAckFlag() {
        return false;
    }

    public byte[] getBytes() {
        return getBytes(null);
    }

    public byte[] getBytes(byte[] ssToken) {
        if (needSessionToken() && (ssToken == null || ssToken.length <= 0)) {
            throw new LockException("未给命令提供ssToken,cmdId:[" + ((int) getCmdId()) + "]" + getCmdName());
        }
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        LittleEndianOutputStream out = new LittleEndianOutputStream(baos);
        try {
            if (needSessionToken()) {
                this.mKLVList.add((byte) -18, ssToken);
            }
            out.writeByte(-121);
            int temp = 0 | 256;
            out.writeByte(temp | 0);
            out.writeShort(this.mKLVList.getBytes().length);
            out.writeByte(getCmdId());
            out.write(new byte[3]);
            out.write(this.mKLVList.getBytes());
            return baos.toByteArray();
        } catch (IOException e) {
            e.printStackTrace();
            throw new LockException("序列化Comm时异常:" + e.getMessage(), e);
        }
    }

    void setSequId(int value) {
        this.sequId = value;
    }

    void setKLVList(KLVListContainer value) {
        if (value == null) {
            throw new NullPointerException();
        }
        this.mKLVList.clear();
        this.mKLVList.addAll(value);
    }

    protected KLVListContainer getKLVList() {
        return this.mKLVList;
    }

    public String toString() {
        return "[" + ((int) getCmdId()) + "]" + getCmdName();
    }
}
