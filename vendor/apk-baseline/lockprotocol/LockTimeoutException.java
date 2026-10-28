package cn.zelkova.ZKurlcsPlugin.lockprotocol;

/* JADX INFO: loaded from: classes.dex */
public class LockTimeoutException extends LockException {
    public LockTimeoutException(String detailMessage) {
        super(detailMessage);
    }

    public LockTimeoutException(String detailMessage, Throwable throwable) {
        super(detailMessage, throwable);
    }
}
