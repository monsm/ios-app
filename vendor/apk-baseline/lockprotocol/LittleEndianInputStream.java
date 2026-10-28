package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import java.io.EOFException;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UTFDataFormatException;

/* JADX INFO: loaded from: classes.dex */
public class LittleEndianInputStream extends FilterInputStream {
    public LittleEndianInputStream(InputStream in) {
        super(in);
    }

    public boolean readBoolean() throws IOException {
        int bool = this.in.read();
        if (bool == -1) {
            throw new EOFException();
        }
        return bool != 0;
    }

    public byte readByte() throws IOException {
        int temp = this.in.read();
        if (temp == -1) {
            throw new EOFException();
        }
        return (byte) temp;
    }

    public int readUnsignedByte() throws IOException {
        int temp = this.in.read();
        if (temp == -1) {
            throw new EOFException();
        }
        return temp;
    }

    public short readShort() throws IOException {
        int byte1 = this.in.read();
        int byte2 = this.in.read();
        if (byte2 == -1) {
            throw new EOFException();
        }
        return (short) ((((byte2 << 24) >> 16) + (byte1 << 24)) >>> 24);
    }

    public int readUnsignedShort() throws IOException {
        int byte1 = this.in.read();
        int byte2 = this.in.read();
        if (byte2 == -1) {
            throw new EOFException();
        }
        return ((byte2 << 24) >>> 16) + ((byte1 << 24) >>> 24);
    }

    public char readChar() throws IOException {
        int byte1 = this.in.read();
        int byte2 = this.in.read();
        if (byte2 == -1) {
            throw new EOFException();
        }
        return (char) (((byte2 << 24) >>> 16) + ((byte1 << 24) >>> 24));
    }

    public int readInt() throws IOException {
        int byte1;
        int byte2;
        int byte3;
        int byte4;
        synchronized (this) {
            byte1 = this.in.read();
            byte2 = this.in.read();
            byte3 = this.in.read();
            byte4 = this.in.read();
        }
        if (byte4 == -1) {
            throw new EOFException();
        }
        return (byte4 << 24) + ((byte3 << 24) >>> 8) + ((byte2 << 24) >>> 16) + ((byte1 << 24) >>> 24);
    }

    public long readLong() throws IOException {
        long byte1 = this.in.read();
        long byte2 = this.in.read();
        long byte3 = this.in.read();
        long byte4 = this.in.read();
        long byte5 = this.in.read();
        long byte6 = this.in.read();
        long byte7 = this.in.read();
        long byte8 = this.in.read();
        if (byte8 == -1) {
            throw new EOFException();
        }
        return (byte8 << 56) + ((byte7 << 56) >>> 8) + ((byte6 << 56) >>> 16) + ((byte5 << 56) >>> 24) + ((byte4 << 56) >>> 32) + ((byte3 << 56) >>> 40) + ((byte2 << 56) >>> 48) + ((byte1 << 56) >>> 56);
    }

    public String readUTF() throws IOException {
        int numchars;
        int byte1 = this.in.read();
        int byte2 = this.in.read();
        if (byte2 == -1) {
            throw new EOFException();
        }
        int numbytes = (byte1 << 8) + byte2;
        char[] result = new char[numbytes];
        int numread = 0;
        int numchars2 = 0;
        while (numread < numbytes) {
            int c1 = readUnsignedByte();
            int test = c1 >> 4;
            if (test < 8) {
                numread++;
                numchars = numchars2 + 1;
                result[numchars2] = (char) c1;
            } else if (test == 12 || test == 13) {
                numread += 2;
                if (numread > numbytes) {
                    throw new UTFDataFormatException();
                }
                int c2 = readUnsignedByte();
                if ((c2 & 192) != 128) {
                    throw new UTFDataFormatException();
                }
                numchars = numchars2 + 1;
                result[numchars2] = (char) (((c1 & 31) << 6) | (c2 & 63));
            } else if (test == 14) {
                numread += 3;
                if (numread > numbytes) {
                    throw new UTFDataFormatException();
                }
                int c3 = readUnsignedByte();
                int c4 = readUnsignedByte();
                if ((c3 & 192) != 128 || (c4 & 192) != 128) {
                    throw new UTFDataFormatException();
                }
                numchars = numchars2 + 1;
                result[numchars2] = (char) (((c1 & 15) << 12) | ((c3 & 63) << 6) | (c4 & 63));
            } else {
                throw new UTFDataFormatException();
            }
            numchars2 = numchars;
        }
        return new String(result, 0, numchars2);
    }

    public final double readDouble() throws IOException {
        return Double.longBitsToDouble(readLong());
    }

    public final float readFloat() throws IOException {
        return Float.intBitsToFloat(readInt());
    }

    public final int skipBytes(int n) throws IOException {
        int i = 0;
        while (i < n) {
            i += (int) skip(n - i);
        }
        return n;
    }
}
