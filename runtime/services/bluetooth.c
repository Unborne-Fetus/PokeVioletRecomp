// The application's BLE interfaces with no nearby Switch BLE peripherals. SDL supplies host controllers separately.
// Protocol: https://switchbrew.org/wiki/BTM_services and /wiki/Bluetooth_Driver_services.
// In particular, GetCore must return an object and event acquisition returns both a true bool and a real handle;
// an empty successful response makes Violet abort inside InitializeBtmUserInterface.
#include <string.h>
#include "../hle.h"
#include "../ipc.h"

static uint32_t ble_events[6];  // scan, connection, pairing, service discovery, MTU, low-level BLE event
static pthread_mutex_t ble_event_lock = PTHREAD_MUTEX_INITIALIZER;
RT_ON_RESET(bluetooth_reset) { memset(ble_events, 0, sizeof ble_events); }

static uint32_t ble_event(unsigned index) {
    pthread_mutex_lock(&ble_event_lock);
    if (!ble_events[index]) {
        uint32_t writable;
        kernel_create_event_pair(&writable, &ble_events[index]);
    }
    uint32_t handle = ble_events[index];
    pthread_mutex_unlock(&ble_event_lock);
    return handle;
}

static void empty_list(IpcReq *req, IpcResp *resp) {
    IpcBuf *buffer = out_buf(req, 0);
    if (buffer && buffer->addr && buffer->size) memset((void *)(uintptr_t)buffer->addr, 0, buffer->size);
    OUT(uint8_t, 0) = 0;
    resp_size(resp, 1);
}

static void btm_user_core(Service *s, IpcReq *req, IpcResp *resp) {
    (void)s;
    int event = -1;
    switch (req->cmd) {
    case 0: event = 0; break;   // AcquireBleScanEvent
    case 1: {  // GetBleScanFilterParameter(u16): the Switch's built-in Nintendo scan filter, not a device result.
        uint16_t id = IN(uint16_t, 0);
        if (id != 1 && id != 0xFFFF) { resp->result = 0xF601; break; }
        // BleAdvertisePacketParameter: Nintendo company ID (0x0553), followed by the six-byte filter.
        static const uint8_t general[6] = {0x00, 0x01, 0x00, 0x00, 0x01, 0x00};
        static const uint8_t special[6] = {0xAD, 0xDE, 0x00, 0xEF, 0xBE, 0x00};
        OUT(uint16_t, 0) = 0x0553;
        memcpy(resp->data + 2, id == 1 ? general : special, 6);
        resp_size(resp, 8);
        break;
    }
    case 17: event = 1; break;  // AcquireBleConnectionEvent
    case 21: event = 2; break;  // AcquireBlePairingEvent
    case 26: event = 3; break;  // AcquireBleServiceDiscoveryEvent
    case 33: event = 4; break;  // AcquireBleMtuConfigEvent
    case 3: case 4: case 6: case 7: case 8: case 9:  // start/stop the three scan modes: no devices to discover
    case 19: case 23: case 24: case 36: case 37:     // disconnect/unpair/data-path registration
        break;
    case 5: case 10: case 20: case 25: case 27: case 29: case 31: case 32:
        empty_list(req, resp);
        break;
    default:
        LOG("[btm] unsupported IBtmUserCore cmd %u\n", req->cmd);
        resp->result = 0xF601;  // unsupported operation; do not fabricate a successful device transaction
        break;
    }
    if (event >= 0) {
        OUT(uint8_t, 0) = 1;
        resp_size(resp, 1);
        resp->copy_handles[resp->ncopy++] = ble_event((unsigned)event);
        LOG("[btm] acquired BLE event %d (no nearby devices)\n", event);
    }
}

SERVICE("btm:u", btm_user) {
    (void)s;
    if (req->cmd == 0) ipc_return_object(resp, service_new("IBtmUserCore", btm_user_core, NULL));
    else { LOG("[btm] unsupported IBtmUser cmd %u\n", req->cmd); resp->result = 0xF601; }
}

SERVICE("bt", bluetooth_user) {
    (void)s;
    if (req->cmd == 9) {  // RegisterBleEvent: no event is signalled until a real device transaction occurs
        resp->copy_handles[resp->ncopy++] = ble_event(5);
    } else {
        LOG("[bt] unsupported IBluetoothUser cmd %u\n", req->cmd);
        resp->result = 0xF601;
    }
}
