// Exercise the production BLE handlers, including the object/event contracts the guest SDK checks at startup.
#include "../runtime/hle.h"
#include "../runtime/ipc.h"
#undef SERVICE
#define SERVICE(name, fn) static void fn(Service *s, IpcReq *req, IpcResp *resp)
#undef RT_ON_RESET
#define RT_ON_RESET(fn) static void fn(void)
#include "../runtime/services/bluetooth.c"
#include <assert.h>
#include <stdio.h>

static unsigned created;
static uint32_t handles;
KEvent *kernel_create_event_pair(uint32_t *w, uint32_t *r) {
    static KEvent events[32];
    assert(created < 32);
    *w = ++handles;
    *r = ++handles;
    return &events[created++];
}
Service *service_new(const char *n, ServiceHandler handler, void *state) {
    Service *s = calloc(1, sizeof *s);
    s->name = n; s->handler = handler; s->state = state;
    return s;
}
void ipc_return_object(IpcResp *r, Service *s) { r->objects[r->nobjects++] = s; }

int main(void) {
    IpcReq req = {0};
    IpcResp resp = {0};
    btm_user(NULL, &req, &resp);
    assert(resp.result == 0 && resp.nobjects == 1 && resp.objects[0]->handler);
    Service *core = resp.objects[0];
    const unsigned commands[] = {0,17,21,26,33};
    for (unsigned i = 0; i < 5; i++) {
        req.cmd = commands[i]; memset(&resp, 0, sizeof resp);
        core->handler(core, &req, &resp);
        assert(resp.result == 0 && resp.data_size == 1 && resp.data[0] == 1 && resp.ncopy == 1 && resp.copy_handles[0]);
        uint32_t first = resp.copy_handles[0];
        memset(&resp, 0, sizeof resp); core->handler(core, &req, &resp);
        assert(resp.copy_handles[0] == first);
    }
    assert(created == 5);
    req.cmd = 9; memset(&resp, 0, sizeof resp); bluetooth_user(NULL, &req, &resp);
    assert(resp.ncopy == 1 && resp.copy_handles[0] && !resp.data_size && created == 6);
    uint8_t buffer[64]; memset(buffer, 0xa5, sizeof buffer);
    req = (IpcReq){.cmd=5,.nb=1,.b={{(uintptr_t)buffer,sizeof buffer}}};
    memset(&resp, 0, sizeof resp); core->handler(core, &req, &resp);
    assert(!resp.result && resp.data_size == 1 && !resp.data[0]);
    for (unsigned i = 0; i < sizeof buffer; i++) assert(!buffer[i]);
    req.cmd = 0xffff; memset(&resp, 0, sizeof resp); core->handler(core, &req, &resp);
    assert(resp.result && !resp.nobjects && !resp.ncopy);
    bluetooth_reset(); req.cmd = 0; memset(&resp, 0, sizeof resp); core->handler(core, &req, &resp);
    assert(created == 7 && resp.copy_handles[0] > 12);
    free(core);
    puts("BLE object, event handles, empty scan results, unsupported commands and reboot reset passed");
}
