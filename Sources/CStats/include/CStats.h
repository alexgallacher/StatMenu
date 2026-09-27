#ifndef CSTATS_H
#define CSTATS_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

// Apple System Management Controller (fans, power, temperatures).
int smc_open(void);
void smc_close(void);
/// Reads a numeric SMC key and decodes it into a double. Returns 0 on success.
int smc_read_value(const char *key, double *value);
/// Writes the 4-char data type of `key` into `type` (5 bytes incl. NUL). Returns 0 on success.
int smc_key_type(const char *key, char *type);
/// Number of keys exposed by the SMC, or -1.
int smc_key_count(void);
/// Writes the key at `index` into `key` (5 bytes incl. NUL). Returns 0 on success.
int smc_key_at(int index, char *key);

/// Apple Silicon temperature sensors exposed through the HID event system.
/// Returns an array of dictionaries: { "name": CFString, "value": CFNumber (°C) }.
CFArrayRef hid_copy_temperature_sensors(void) CF_RETURNS_RETAINED;

/// Average clock of a CPU cluster or the GPU over the last sampling interval (Apple Silicon only).
typedef struct {
    char name[16];      // IOReport channel, e.g. "ECPU", "PCPU1", "GPU"
    int kind;           // 0 = efficiency CPU, 1 = performance CPU, 2 = GPU
    double mhz;         // residency-weighted average while active
    double max_mhz;     // top of the DVFS table
    double active;      // fraction of the interval spent in an active state
} freq_reading;

/// Returns the number of readings written (0 on the first call or when unsupported).
/// Also reports the CPU and GPU energy (joules) consumed since the previous call; -1 when unavailable.
int freq_sample(freq_reading *out, int max, double *cpu_joules, double *gpu_joules);

/// One "Energy Model" channel from the last `freq_sample` interval.
typedef struct {
    char name[32];
    double joules;
} energy_reading;

/// Copies the per-channel energy from the most recent `freq_sample` call. Returns the count.
int energy_channels(energy_reading *out, int max);

#endif
