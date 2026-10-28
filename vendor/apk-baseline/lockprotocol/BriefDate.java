package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;

/* JADX INFO: loaded from: classes.dex */
public class BriefDate {
    public static final String BASE_DATE_TIME = "2010-01-01 00:00:00";
    public static final String DATE_FORMAT = "yyyy-MM-dd HH:mm:ss";
    private final Date theDate;

    public static Date getBaseTime() {
        SimpleDateFormat sdFormat = new SimpleDateFormat(DATE_FORMAT);
        try {
            Date theBaseDate = sdFormat.parse(BASE_DATE_TIME);
            return theBaseDate;
        } catch (ParseException e) {
            e.printStackTrace();
            return null;
        }
    }

    private BriefDate(Date val) {
        if (getBaseTime().getTime() > val.getTime()) {
            SimpleDateFormat sdFormat = new SimpleDateFormat(DATE_FORMAT);
            throw new IllegalArgumentException("应大于协议基准日期:" + sdFormat.format(val));
        }
        long theTime = val.getTime() / 1000;
        this.theDate = new Date(theTime * 1000);
    }

    public static BriefDate fromNature(Date val) {
        return new BriefDate(val);
    }

    public static BriefDate fromProtocol(byte[] val) {
        long theDateSnd = BitConverter.toUInt32(val, 0);
        return fromProtocol(theDateSnd);
    }

    public static BriefDate fromProtocol(long dateSnd) {
        if (dateSnd < 0) {
            throw new IllegalArgumentException("不能小于0");
        }
        Calendar cld = Calendar.getInstance();
        cld.setTimeInMillis(getBaseTime().getTime() + (1000 * dateSnd));
        return new BriefDate(cld.getTime());
    }

    public Date toNature() {
        return this.theDate;
    }

    public byte[] toProtocolByte() {
        int diffSnd = (int) toProtocol();
        byte[] retVal = BitConverter.getBytes(diffSnd);
        return retVal;
    }

    public long toProtocol() {
        long diffMS = this.theDate.getTime() - getBaseTime().getTime();
        long diffSnd = diffMS / 1000;
        return diffSnd;
    }

    public String toString() {
        SimpleDateFormat sdFormat = new SimpleDateFormat(DATE_FORMAT);
        String retVal = sdFormat.format(this.theDate);
        return retVal;
    }
}
