#include "CStats.h"

// Private IOKit HID event-system API (exported by IOKit.framework). Declared with
// opaque pointer types so they never collide with the public HID headers.
extern void *IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(void *client, CFDictionaryRef matching);
extern CFArrayRef IOHIDEventSystemClientCopyServices(void *client);
extern CFTypeRef IOHIDServiceClientCopyProperty(void *service, CFStringRef key);
extern void *IOHIDServiceClientCopyEvent(void *service, int64_t type, int32_t options, int64_t timestamp);
extern double IOHIDEventGetFloatValue(void *event, int32_t field);

#define kHIDEventTypeTemperature 15
#define HIDEventFieldBase(type) ((type) << 16)

static void *g_client = NULL;

CFArrayRef hid_copy_temperature_sensors(void) {
    if (!g_client) {
        g_client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!g_client) return NULL;
        int page = 0xff00, usage = 5;
        CFNumberRef pageNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
        CFNumberRef usageNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
        const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
        const void *vals[] = { pageNum, usageNum };
        CFDictionaryRef matching = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 2,
                                                      &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        IOHIDEventSystemClientSetMatching(g_client, matching);
        CFRelease(matching);
        CFRelease(pageNum);
        CFRelease(usageNum);
    }

    CFArrayRef services = IOHIDEventSystemClientCopyServices(g_client);
    if (!services) return NULL;

    CFMutableArrayRef result = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    CFIndex count = CFArrayGetCount(services);
    for (CFIndex i = 0; i < count; i++) {
        void *service = (void *)CFArrayGetValueAtIndex(services, i);
        CFTypeRef name = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        void *event = IOHIDServiceClientCopyEvent(service, kHIDEventTypeTemperature, 0, 0);
        if (name && CFGetTypeID(name) == CFStringGetTypeID() && event) {
            double value = IOHIDEventGetFloatValue(event, HIDEventFieldBase(kHIDEventTypeTemperature));
            if (value > 0 && value < 150) {
                CFNumberRef num = CFNumberCreate(kCFAllocatorDefault, kCFNumberDoubleType, &value);
                const void *keys[] = { CFSTR("name"), CFSTR("value") };
                const void *vals[] = { name, num };
                CFDictionaryRef entry = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 2,
                                                           &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                CFArrayAppendValue(result, entry);
                CFRelease(entry);
                CFRelease(num);
            }
        }
        if (event) CFRelease((CFTypeRef)event);
        if (name) CFRelease(name);
    }
    CFRelease(services);
    return result;
}
