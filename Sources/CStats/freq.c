#include "CStats.h"
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <string.h>

// Private IOReport API (libIOReport, in the dyld shared cache), loaded at runtime.
typedef CFDictionaryRef (*CopyChannelsInGroupFn)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
typedef void (*MergeChannelsFn)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
typedef void *(*CreateSubscriptionFn)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
typedef CFDictionaryRef (*CreateSamplesFn)(void *, CFMutableDictionaryRef, CFTypeRef);
typedef CFDictionaryRef (*CreateSamplesDeltaFn)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
typedef CFStringRef (*ChannelStringFn)(CFDictionaryRef);
typedef int32_t (*StateCountFn)(CFDictionaryRef);
typedef CFStringRef (*StateNameFn)(CFDictionaryRef, int32_t);
typedef int64_t (*StateResidencyFn)(CFDictionaryRef, int32_t);
typedef int64_t (*SimpleValueFn)(CFDictionaryRef, int32_t);

static CreateSamplesFn createSamples;
static CreateSamplesDeltaFn createDelta;
static ChannelStringFn getGroup, getSubGroup, getName;
static StateCountFn stateCount;
static StateNameFn stateName;
static StateResidencyFn stateResidency;
static SimpleValueFn simpleValue;
static ChannelStringFn unitLabel;

static void *g_sub = NULL;
static CFMutableDictionaryRef g_subbed = NULL;
static CFDictionaryRef g_prev = NULL;
static int g_state = 0; // 0 = uninitialised, 1 = ready, -1 = unsupported

#define MAX_ENERGY 512
static energy_reading g_energy[MAX_ENERGY];
static int g_energy_count = 0;

int energy_channels(energy_reading *out, int max) {
    int n = g_energy_count < max ? g_energy_count : max;
    memcpy(out, g_energy, sizeof(energy_reading) * n);
    return n;
}

#define MAX_STATES 64
static double g_etable[MAX_STATES], g_ptable[MAX_STATES], g_gtable[MAX_STATES];
static int g_ecount, g_pcount, g_gcount;

/// Reads a DVFS table ("voltage-statesN") from the pmgr node: pairs of (frequency, voltage) as UInt32.
static int read_table(io_registry_entry_t pmgr, const char *key, double *out) {
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFTypeRef data = IORegistryEntryCreateCFProperty(pmgr, k, kCFAllocatorDefault, 0);
    CFRelease(k);
    if (!data) return 0;
    int n = 0;
    if (CFGetTypeID(data) == CFDataGetTypeID()) {
        const uint32_t *v = (const uint32_t *)CFDataGetBytePtr(data);
        CFIndex pairs = CFDataGetLength(data) / 8;
        for (CFIndex i = 0; i < pairs && n < MAX_STATES; i++) {
            double f = v[i * 2];
            if (f <= 0) continue;
            out[n++] = f > 1e8 ? f / 1e6 : f / 1e3; // Hz on M1–M3, kHz on newer chips
        }
    }
    CFRelease(data);
    return n;
}

static void load_tables(void) {
    io_iterator_t it;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"), &it) != KERN_SUCCESS) return;
    io_registry_entry_t e;
    while ((e = IOIteratorNext(it))) {
        io_name_t name;
        if (IORegistryEntryGetName(e, name) == KERN_SUCCESS && strcmp(name, "pmgr") == 0) {
            g_ecount = read_table(e, "voltage-states1-sram", g_etable);
            g_pcount = read_table(e, "voltage-states5-sram", g_ptable);
            g_gcount = read_table(e, "voltage-states9", g_gtable);
        }
        IOObjectRelease(e);
    }
    IOObjectRelease(it);
}

static int init(void) {
    void *h = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW);
    if (!h) return -1;
    CopyChannelsInGroupFn copyChannels = dlsym(h, "IOReportCopyChannelsInGroup");
    MergeChannelsFn merge = dlsym(h, "IOReportMergeChannels");
    CreateSubscriptionFn subscribe = dlsym(h, "IOReportCreateSubscription");
    createSamples = dlsym(h, "IOReportCreateSamples");
    createDelta = dlsym(h, "IOReportCreateSamplesDelta");
    getGroup = dlsym(h, "IOReportChannelGetGroup");
    getSubGroup = dlsym(h, "IOReportChannelGetSubGroup");
    getName = dlsym(h, "IOReportChannelGetChannelName");
    stateCount = dlsym(h, "IOReportStateGetCount");
    stateName = dlsym(h, "IOReportStateGetNameForIndex");
    stateResidency = dlsym(h, "IOReportStateGetResidency");
    simpleValue = dlsym(h, "IOReportSimpleGetIntegerValue");
    unitLabel = dlsym(h, "IOReportChannelGetUnitLabel");
    if (!copyChannels || !merge || !subscribe || !createSamples || !createDelta || !getGroup || !getSubGroup ||
        !getName || !stateCount || !stateName || !stateResidency) return -1;

    load_tables();
    if (g_pcount == 0 && g_gcount == 0) return -1;

    // Subscribe only to the performance-state subgroups; the full groups carry hundreds of channels.
    CFDictionaryRef cpu = copyChannels(CFSTR("CPU Stats"), CFSTR("CPU Complex Performance States"), 0, 0, 0);
    CFDictionaryRef gpu = copyChannels(CFSTR("GPU Stats"), CFSTR("GPU Performance States"), 0, 0, 0);
    if (!cpu || !gpu) return -1;
    merge(cpu, gpu, NULL);
    CFDictionaryRef energy = copyChannels(CFSTR("Energy Model"), NULL, 0, 0, 0);
    if (energy) { merge(cpu, energy, NULL); CFRelease(energy); }
    CFMutableDictionaryRef desired = CFDictionaryCreateMutableCopy(NULL, CFDictionaryGetCount(cpu), cpu);
    CFRelease(cpu);
    CFRelease(gpu);
    g_sub = subscribe(NULL, desired, &g_subbed, 0, NULL);
    CFRelease(desired);
    return g_sub ? 1 : -1;
}

static int is_idle_state(CFStringRef name) {
    return CFStringFind(name, CFSTR("IDLE"), 0).location != kCFNotFound ||
           CFStringFind(name, CFSTR("OFF"), 0).location != kCFNotFound ||
           CFStringFind(name, CFSTR("DOWN"), 0).location != kCFNotFound;
}

/// Residency-weighted frequency across the channel's active states, mapped onto the DVFS table.
static void summarise(CFDictionaryRef ch, const double *table, int tableCount, freq_reading *r) {
    int n = stateCount(ch);
    double active[MAX_STATES];
    int activeCount = 0;
    double total = 0;
    for (int i = 0; i < n; i++) {
        double res = (double)stateResidency(ch, i);
        total += res;
        CFStringRef name = stateName(ch, i);
        if (name && !is_idle_state(name) && activeCount < MAX_STATES) active[activeCount++] = res;
    }
    int offset = tableCount > activeCount ? tableCount - activeCount : 0;
    double weighted = 0, activeTotal = 0;
    for (int i = 0; i < activeCount && i + offset < tableCount; i++) {
        weighted += active[i] * table[i + offset];
        activeTotal += active[i];
    }
    r->max_mhz = tableCount > 0 ? table[tableCount - 1] : 0;
    r->active = total > 0 ? activeTotal / total : 0;
    r->mhz = activeTotal > 0 ? weighted / activeTotal : 0;
}

/// Energy of an "Energy Model" channel in joules, using its unit label (mJ, uJ, nJ).
static double channel_joules(CFDictionaryRef ch) {
    if (!simpleValue) return 0;
    double v = (double)simpleValue(ch, 0);
    CFStringRef unit = unitLabel ? unitLabel(ch) : NULL;
    if (!unit) return v;
    if (CFStringCompare(unit, CFSTR("mJ"), 0) == kCFCompareEqualTo) return v / 1e3;
    if (CFStringCompare(unit, CFSTR("uJ"), 0) == kCFCompareEqualTo) return v / 1e6;
    if (CFStringCompare(unit, CFSTR("nJ"), 0) == kCFCompareEqualTo) return v / 1e9;
    return v;
}

int freq_sample(freq_reading *out, int max, double *cpu_joules, double *gpu_joules) {
    *cpu_joules = -1;
    *gpu_joules = -1;
    if (g_state == 0) g_state = init();
    if (g_state != 1) return 0;

    CFDictionaryRef cur = createSamples(g_sub, g_subbed, NULL);
    if (!cur) return 0;
    if (!g_prev) { g_prev = cur; return 0; }
    CFDictionaryRef delta = createDelta(g_prev, cur, NULL);
    CFRelease(g_prev);
    g_prev = cur;
    if (!delta) return 0;

    int count = 0;
    g_energy_count = 0;
    CFArrayRef channels = CFDictionaryGetValue(delta, CFSTR("IOReportChannels"));
    for (CFIndex i = 0; channels && i < CFArrayGetCount(channels) && count < max; i++) {
        CFDictionaryRef ch = CFArrayGetValueAtIndex(channels, i);
        CFStringRef group = getGroup(ch), sub = getSubGroup(ch), name = getName(ch);
        if (!group || !name) continue;
        if (!sub) sub = CFSTR("");
        if (CFEqual(group, CFSTR("Energy Model"))) {
            if (g_energy_count < MAX_ENERGY) {
                energy_reading *e = &g_energy[g_energy_count++];
                CFStringGetCString(name, e->name, sizeof(e->name), kCFStringEncodingUTF8);
                e->joules = channel_joules(ch);
            }
            if (CFEqual(name, CFSTR("CPU Energy"))) *cpu_joules = (*cpu_joules < 0 ? 0 : *cpu_joules) + channel_joules(ch);
            else if (CFEqual(name, CFSTR("GPU Energy"))) *gpu_joules = (*gpu_joules < 0 ? 0 : *gpu_joules) + channel_joules(ch);
            continue;
        }
        freq_reading r;
        memset(&r, 0, sizeof(r));
        CFStringGetCString(name, r.name, sizeof(r.name), kCFStringEncodingUTF8);

        if (CFEqual(group, CFSTR("CPU Stats")) && CFEqual(sub, CFSTR("CPU Complex Performance States"))) {
            // Cluster channels are ECPU/PCPU/PCPU1 (or *ACC* on newer chips); skip the *CPM channels.
            if (strstr(r.name, "CPM") != NULL || (strstr(r.name, "CPU") == NULL && strstr(r.name, "ACC") == NULL)) continue;
            int eff = r.name[0] == 'E' || strstr(r.name, "EACC") != NULL;
            int perf = r.name[0] == 'P' || strstr(r.name, "PACC") != NULL;
            if (!eff && !perf) continue;
            r.kind = eff ? 0 : 1;
            summarise(ch, eff ? g_etable : g_ptable, eff ? g_ecount : g_pcount, &r);
            out[count++] = r;
        } else if (CFEqual(group, CFSTR("GPU Stats")) && CFEqual(sub, CFSTR("GPU Performance States")) &&
                   CFEqual(name, CFSTR("GPUPH"))) {
            r.kind = 2;
            strcpy(r.name, "GPU");
            summarise(ch, g_gtable, g_gcount, &r);
            out[count++] = r;
        }
    }
    CFRelease(delta);
    return count;
}
