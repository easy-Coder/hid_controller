#ifndef CONTROLLER_LAB_H
#define CONTROLLER_LAB_H
#include <stdint.h>
// ABI v2. All functions are called from one Dart isolate. Snapshots are copies.
typedef struct {
    uint64_t id;
    uint32_t vendor, product, input_count, reserved;
    char name[128];
    char transport[32];
} HCDevice;
typedef struct {
    uint32_t cookie, page, usage, kind; // kind: 1 button, 2 axis, 3 hat, 4 other
    int64_t value, minimum, maximum;
    uint64_t changes;
    uint64_t presses;
    int64_t seen_minimum, seen_maximum;
} HCInput;
uint32_t hc_abi_version(void);
int32_t hc_start(void);
void hc_stop(void);
uint32_t hc_devices(HCDevice *out, uint32_t capacity);
uint32_t hc_inputs(uint64_t id, HCInput *out, uint32_t capacity);
int32_t hc_map(uint64_t id, uint32_t cookie, int32_t key); // -1 clears; buttons only
void hc_clear_mappings(void);
int32_t hc_enable(int32_t enabled); // fails without Accessibility permission
int32_t hc_accessibility(int32_t prompt);
// 1: observed Nova Lite Xbox USB identity; 0: absent; -1: registry unavailable.
// This is a diagnostic query; it does not open keyboard interfaces.
int32_t hc_usb_mode_hint(void);
int32_t hc_reset_extrema(uint64_t id);
#endif
