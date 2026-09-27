#include "CStats.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_INDEX 8
#define SMC_CMD_READ_KEYINFO 9

typedef struct { char major; char minor; char build; char reserved[1]; UInt16 release; } SMCVersion;
typedef struct { UInt16 version; UInt16 length; UInt32 cpuPLimit; UInt32 gpuPLimit; UInt32 memPLimit; } SMCPLimitData;
typedef struct { UInt32 dataSize; UInt32 dataType; char dataAttributes; } SMCKeyInfo;
typedef struct {
    UInt32 key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfo keyInfo;
    char result;
    char status;
    char data8;
    UInt32 data32;
    unsigned char bytes[32];
} SMCParam;

static io_connect_t g_conn = 0;

#define CACHE_SIZE 512
static UInt32 g_cache_keys[CACHE_SIZE];
static SMCKeyInfo g_cache_info[CACHE_SIZE];
static int g_cache_count = 0;

static UInt32 key_from_string(const char *s) {
    return ((UInt32)(unsigned char)s[0] << 24) | ((UInt32)(unsigned char)s[1] << 16) |
           ((UInt32)(unsigned char)s[2] << 8) | (UInt32)(unsigned char)s[3];
}

static void key_to_string(UInt32 k, char *out) {
    out[0] = (char)(k >> 24); out[1] = (char)(k >> 16); out[2] = (char)(k >> 8); out[3] = (char)k; out[4] = 0;
}

int smc_open(void) {
    if (g_conn) return 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &g_conn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) { g_conn = 0; return -1; }
    return 0;
}

void smc_close(void) {
    if (g_conn) { IOServiceClose(g_conn); g_conn = 0; }
}

static int smc_call(SMCParam *input, SMCParam *output) {
    size_t outSize = sizeof(SMCParam);
    kern_return_t kr = IOConnectCallStructMethod(g_conn, KERNEL_INDEX_SMC, input, sizeof(SMCParam), output, &outSize);
    return (kr == KERN_SUCCESS && output->result == 0) ? 0 : -1;
}

static int get_key_info(UInt32 key, SMCKeyInfo *info) {
    for (int i = 0; i < g_cache_count; i++) {
        if (g_cache_keys[i] == key) { *info = g_cache_info[i]; return 0; }
    }
    SMCParam input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.data8 = SMC_CMD_READ_KEYINFO;
    if (smc_call(&input, &output) != 0) return -1;
    *info = output.keyInfo;
    if (g_cache_count < CACHE_SIZE) {
        g_cache_keys[g_cache_count] = key;
        g_cache_info[g_cache_count] = output.keyInfo;
        g_cache_count++;
    }
    return 0;
}

static int read_raw(const char *keystr, char *type, UInt32 *size, unsigned char *bytes) {
    if (!keystr || strlen(keystr) != 4) return -1;
    if (!g_conn && smc_open() != 0) return -1;
    UInt32 key = key_from_string(keystr);
    SMCKeyInfo info;
    if (get_key_info(key, &info) != 0) return -1;
    SMCParam input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.keyInfo.dataSize = info.dataSize;
    input.data8 = SMC_CMD_READ_BYTES;
    if (smc_call(&input, &output) != 0) return -1;
    memcpy(bytes, output.bytes, 32);
    key_to_string(info.dataType, type);
    *size = info.dataSize;
    return 0;
}

int smc_read_value(const char *key, double *value) {
    char type[5];
    UInt32 size = 0;
    unsigned char b[32];
    if (read_raw(key, type, &size, b) != 0) return -1;

    if (strcmp(type, "flt ") == 0 && size == 4) {
        float f; memcpy(&f, b, 4); *value = f; return 0;
    }
    if (strcmp(type, "sp78") == 0 && size == 2) {
        int16_t v = (int16_t)((b[0] << 8) | b[1]); *value = v / 256.0; return 0;
    }
    if (strcmp(type, "fpe2") == 0 && size == 2) {
        *value = ((b[0] << 8) | b[1]) / 4.0; return 0;
    }
    if (strcmp(type, "fp88") == 0 && size == 2) {
        *value = ((b[0] << 8) | b[1]) / 256.0; return 0;
    }
    if (strcmp(type, "ui8 ") == 0 && size >= 1) { *value = b[0]; return 0; }
    if (strcmp(type, "ui16") == 0 && size == 2) { *value = (b[0] << 8) | b[1]; return 0; }
    if (strcmp(type, "ui32") == 0 && size == 4) {
        *value = (double)(((UInt32)b[0] << 24) | ((UInt32)b[1] << 16) | ((UInt32)b[2] << 8) | b[3]); return 0;
    }
    if (strcmp(type, "ioft") == 0 && size == 8) {
        uint64_t v; memcpy(&v, b, 8); *value = v / 65536.0; return 0;
    }
    return -1;
}

int smc_key_type(const char *keystr, char *type) {
    if (!keystr || strlen(keystr) != 4) return -1;
    if (!g_conn && smc_open() != 0) return -1;
    SMCKeyInfo info;
    if (get_key_info(key_from_string(keystr), &info) != 0) return -1;
    key_to_string(info.dataType, type);
    return 0;
}

int smc_key_count(void) {
    double v = 0;
    if (smc_read_value("#KEY", &v) != 0) return -1;
    return (int)v;
}

int smc_key_at(int index, char *key) {
    if (!g_conn && smc_open() != 0) return -1;
    SMCParam input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.data8 = SMC_CMD_READ_INDEX;
    input.data32 = (UInt32)index;
    if (smc_call(&input, &output) != 0) return -1;
    key_to_string(output.key, key);
    return 0;
}
