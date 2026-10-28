package cn.zelkova.ZKurlcsPlugin.lockprotocol;

/* JADX INFO: loaded from: classes.dex */
public class LockException extends RuntimeException {
    public LockException(String detailMessage) {
        super(detailMessage);
    }

    public LockException(String detailMessage, Throwable throwable) {
        super(detailMessage, throwable);
    }
}
