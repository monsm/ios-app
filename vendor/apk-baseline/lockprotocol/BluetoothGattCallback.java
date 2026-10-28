package cn.zelkova.ZKurlcsPlugin.lockprotocol;

import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.util.Log;
import java.util.List;

/* JADX INFO: loaded from: classes.dex */
class BluetoothGattCallback extends android.bluetooth.BluetoothGattCallback {
    public static final String TAG_BLE = "ZkBluetoothGattCallback";
    private WhatHappenCallback sayCallback;
    public Integer rxPackages = 0;
    public Integer txPackages = 0;

    public BluetoothGattCallback(WhatHappenCallback say) {
        this.sayCallback = say;
    }

    @Override // android.bluetooth.BluetoothGattCallback
    public void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic) {
        super.onCharacteristicChanged(gatt, characteristic);
        Integer num = this.rxPackages;
        this.rxPackages = Integer.valueOf(this.rxPackages.intValue() + 1);
        byte[] val = characteristic.getValue();
        showMsg("Characteristic_Changed[Len:" + val.length + ",rxPkg:" + this.rxPackages + "]");
        showMsg("\tUuid:" + characteristic.getUuid());
        showMsg("\tVal:" + BitConverter.toHexString(characteristic.getValue()));
    }

    @Override // android.bluetooth.BluetoothGattCallback
    public void onCharacteristicWrite(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
        super.onCharacteristicWrite(gatt, characteristic, status);
        Integer num = this.txPackages;
        this.txPackages = Integer.valueOf(this.txPackages.intValue() + 1);
        byte[] val = characteristic.getValue();
        showMsg("Characteristic_Write[status:" + status + ",Len:" + val.length + ",txPkg:" + this.txPackages + "]");
        showMsg("\tUuid:" + characteristic.getUuid());
        showMsg("\tVal:" + BitConverter.toHexString(val));
    }

    @Override // android.bluetooth.BluetoothGattCallback
    public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
        super.onConnectionStateChange(gatt, status, newState);
        showMsg("Connection_State_Change[status:" + status + "]");
        showMsg("\tnewState:" + getConnectionStateName(newState));
        showMsg("\tmac:" + gatt.getDevice().getAddress());
        if (newState == 0) {
            this.rxPackages = 0;
            this.txPackages = 0;
        }
        if (status != 0) {
            Log.e(TAG_BLE, "onConnectionStateChange.Status:" + status + ", newState:" + getConnectionStateName(newState));
        }
    }

    @Override // android.bluetooth.BluetoothGattCallback
    public void onDescriptorWrite(BluetoothGatt gatt, BluetoothGattDescriptor descriptor, int status) {
        super.onDescriptorWrite(gatt, descriptor, status);
        showMsg("Descriptor_Write[status:" + status + "]");
        showMsg("\tUuid:" + descriptor.getUuid());
        showMsg("\tVal:" + BitConverter.toHexString(descriptor.getValue()));
    }

    @Override // android.bluetooth.BluetoothGattCallback
    public void onServicesDiscovered(BluetoothGatt gatt, int status) {
        super.onServicesDiscovered(gatt, status);
        showMsg("Services_Discovered[status:" + status + "]");
    }

    private void showMsg(String msg) {
        if (this.sayCallback == null) {
            Log.i(TAG_BLE, msg);
        } else {
            this.sayCallback.letMeKnow(msg);
        }
    }

    public static String getConnectionStateName(int state) {
        String result;
        switch (state) {
            case 0:
                result = "Disconnected";
                break;
            case 1:
            default:
                result = String.valueOf(state);
                break;
            case 2:
                result = "Connected";
                break;
        }
        return "[" + state + "]" + result;
    }

    public static void displayGattServices(BluetoothGatt gatt) {
        List<BluetoothGattService> gattSvcList = gatt.getServices();
        if (gattSvcList != null) {
            for (BluetoothGattService gattService : gattSvcList) {
                Log.i(TAG_BLE, "Svc:" + gattService.getUuid().toString());
                List<BluetoothGattCharacteristic> gattChaList = gattService.getCharacteristics();
                for (BluetoothGattCharacteristic curCha : gattChaList) {
                    Log.i(TAG_BLE, "\t Cha:" + curCha.getUuid().toString());
                    List<BluetoothGattDescriptor> gattDescList = curCha.getDescriptors();
                    for (BluetoothGattDescriptor curDesc : gattDescList) {
                        Log.i(TAG_BLE, "\t\t Desc:" + curDesc.getUuid());
                        Log.i(TAG_BLE, "\t\t\t Val:" + BitConverter.toHexString(curDesc.getValue()));
                        Log.i(TAG_BLE, "\t\t\t Permission:" + curDesc.getPermissions());
                    }
                }
            }
        }
    }
}
