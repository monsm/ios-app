package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import java.util.Calendar;

/* JADX INFO: loaded from: classes.dex */
public class ProfileProvider {
    private static ProfileProvider pp = null;

    protected ProfileProvider() {
    }

    public static ProfileProvider getIns() {
        if (pp == null) {
            pp = new ProfileProvider();
        }
        return pp;
    }

    public static void setProvider(ProfileProvider provider) {
        pp = provider;
    }

    public int getTraceId() {
        return (int) Calendar.getInstance().getTimeInMillis();
    }

    public byte[] getSecurityKey(String macAddress) {
        return new byte[]{48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48};
    }

    byte[] getSecurityKey(byte[] macAddress) {
        return getSecurityKey(BitConverter.convertMacAdd(macAddress));
    }
}
