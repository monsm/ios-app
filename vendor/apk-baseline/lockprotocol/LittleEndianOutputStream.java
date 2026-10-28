package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import java.io.FilterOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.io.UTFDataFormatException;

/* JADX INFO: loaded from: classes.dex */
public class LittleEndianOutputStream extends FilterOutputStream {
    protected int written;

    public LittleEndianOutputStream(OutputStream out) {
        super(out);
    }

    @Override // java.io.FilterOutputStream, java.io.OutputStream
    public synchronized void write(int b) throws IOException {
        this.out.write(b);
        this.written++;
    }

    @Override // java.io.FilterOutputStream, java.io.OutputStream
    public synchronized void write(byte[] data, int offset, int length) throws IOException {
        this.out.write(data, offset, length);
        this.written += length;
    }

    public void writeBoolean(boolean b) throws IOException {
        if (!b) {
            write(0);
        } else {
            write(1);
        }
    }

    public void writeByte(int b) throws IOException {
        this.out.write(b);
        this.written++;
    }

    public void writeShort(int s) throws IOException {
        this.out.write(s & 255);
        this.out.write((s >>> 8) & 255);
        this.written += 2;
    }

    public void writeChar(int c) throws IOException {
        this.out.write(c & 255);
        this.out.write((c >>> 8) & 255);
        this.written += 2;
    }

    public void writeInt(int i) throws IOException {
        this.out.write(i & 255);
        this.out.write((i >>> 8) & 255);
        this.out.write((i >>> 16) & 255);
        this.out.write((i >>> 24) & 255);
        this.written += 4;
    }

    public void writeLong(long l) throws IOException {
        this.out.write(((int) l) & 255);
        this.out.write(((int) (l >>> 8)) & 255);
        this.out.write(((int) (l >>> 16)) & 255);
        this.out.write(((int) (l >>> 24)) & 255);
        this.out.write(((int) (l >>> 32)) & 255);
        this.out.write(((int) (l >>> 40)) & 255);
        this.out.write(((int) (l >>> 48)) & 255);
        this.out.write(((int) (l >>> 56)) & 255);
        this.written += 8;
    }

    public final void writeFloat(float f) throws IOException {
        writeInt(Float.floatToIntBits(f));
    }

    public final void writeDouble(double d) throws IOException {
        writeLong(Double.doubleToLongBits(d));
    }

    public void writeBytes(String s) throws IOException {
        byte[] buffer = s.getBytes("utf-8");
        int length = buffer.length;
        for (byte b : buffer) {
            this.out.write(b);
        }
        this.written += length;
    }

    public void writeUTF(String s) throws IOException {
        int numchars = s.length();
        int numbytes = 0;
        for (int i = 0; i < numchars; i++) {
            int c = s.charAt(i);
            if (c < 1 || c > 127) {
                numbytes = c > 2047 ? numbytes + 3 : numbytes + 2;
            } else {
                numbytes++;
            }
        }
        if (numbytes > 65535) {
            throw new UTFDataFormatException();
        }
        this.out.write((numbytes >>> 8) & 255);
        this.out.write(numbytes & 255);
        for (int i2 = 0; i2 < numchars; i2++) {
            int c2 = s.charAt(i2);
            if (c2 >= 1 && c2 <= 127) {
                this.out.write(c2);
            } else if (c2 > 2047) {
                this.out.write(((c2 >> 12) & 15) | 224);
                this.out.write(((c2 >> 6) & 63) | 128);
                this.out.write((c2 & 63) | 128);
                this.written += 2;
            } else {
                this.out.write(((c2 >> 6) & 31) | 192);
                this.out.write((c2 & 63) | 128);
                this.written++;
            }
        }
        this.written += numchars + 2;
    }

    public int size() {
        return this.written;
    }
}
