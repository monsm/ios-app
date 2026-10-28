package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import android.content.Context;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/* JADX INFO: loaded from: classes.dex */
public class GateWayConnector extends BleLockConnector {
    private static Map<String, GateWayConnector> ConnectorPool = new HashMap();

    private GateWayConnector(Context ctx, String mac) {
        super(ctx, mac);
        BleLockConnector.RX_SERVICE_UUID = UUID.fromString("0000fe90-0000-1000-8000-00805f9b34fb");
        BleLockConnector.RX_CHAR_UUID = UUID.fromString("0000fe92-0000-1000-8000-00805f9b34fb");
        BleLockConnector.TX_CHAR_UUID = UUID.fromString("0000fe91-0000-1000-8000-00805f9b34fb");
        BleLockConnector.CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    }

    public static GateWayConnector create(Context ctx, String mac) {
        if (ConnectorPool.containsKey(mac)) {
            return ConnectorPool.get(mac);
        }
        GateWayConnector retVal = new GateWayConnector(ctx, mac);
        ConnectorPool.put(mac, retVal);
        return retVal;
    }
}
