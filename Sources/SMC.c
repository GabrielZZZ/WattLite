#include "SMC.h"
#include <IOKit/IOKitLib.h>
#include <math.h>
#include <stddef.h>
#include <string.h>

typedef struct {
    uint32_t key;
    uint8_t version[6];
    uint8_t padding[2];
    uint32_t limits[4];
    struct { uint32_t size; uint32_t type; uint8_t attributes; } info;
    uint8_t result;
    uint8_t status;
    uint8_t command;
    uint32_t index;
    uint8_t bytes[32];
} SMCMessage;
_Static_assert(sizeof(SMCMessage) == 80, "SMC ABI size");
_Static_assert(offsetof(SMCMessage, bytes) == 48, "SMC ABI payload offset");

static uint32_t fourcc(const char *key) {
    return (uint32_t)(uint8_t)key[0] << 24 | (uint32_t)(uint8_t)key[1] << 16 |
           (uint32_t)(uint8_t)key[2] << 8 | (uint8_t)key[3];
}

static int call(uint32_t connection, SMCMessage *input, SMCMessage *output) {
    size_t size = sizeof(*output);
    return IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &size) == KERN_SUCCESS &&
           size == sizeof(*output) && output->result == 0;
}

uint32_t smc_open(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;
    io_connect_t connection = 0;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    return result == KERN_SUCCESS ? connection : 0;
}

void smc_close(uint32_t connection) {
    if (connection) IOServiceClose(connection);
}

int smc_key_at(uint32_t connection, uint32_t index, char key[5]) {
    SMCMessage input = {0}, output = {0};
    input.command = 8;
    input.index = index;
    if (!call(connection, &input, &output)) return 0;
    for (int i = 0; i < 4; i++) key[i] = (char)(output.key >> (24 - i * 8));
    key[4] = 0;
    return 1;
}

int smc_read(uint32_t connection, const char *key, double *value) {
    if (!connection || strlen(key) != 4 || !value) return 0;
    SMCMessage input = {0}, output = {0};
    input.key = fourcc(key);
    input.command = 9;
    if (!call(connection, &input, &output)) return 0;
    uint32_t type = output.info.type, size = output.info.size;
    if (size == 0 || size > 32) return 0;
    input.info.size = size;
    input.command = 5;
    memset(&output, 0, sizeof(output));
    if (!call(connection, &input, &output)) return 0;
    if (type == fourcc("flt ") && size == 4) {
        float number;
        memcpy(&number, output.bytes, 4);
        *value = number;
    } else if (type == fourcc("ui32") && size == 4 && strcmp(key, "#KEY") == 0) {
        *value = fourcc((const char *)output.bytes);
    } else {
        return 0;
    }
    return isfinite(*value);
}
