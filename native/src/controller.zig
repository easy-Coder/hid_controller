const std = @import("std");
const KeyState = @import("key_state.zig").KeyState;
const switch_report = @import("switch_report.zig");
const c = @cImport({
    @cInclude("controller.h");
    @cInclude("pthread.h");
    @cInclude("IOKit/hid/IOHIDManager.h");
    @cInclude("IOKit/IOKitLib.h");
    @cInclude("ApplicationServices/ApplicationServices.h");
});

const Slot = struct {
    device: c.IOHIDDeviceRef = null,
    info: c.HCDevice = std.mem.zeroes(c.HCDevice),
    inputs: [128]c.HCInput = std.mem.zeroes([128]c.HCInput),
    keys: [128]i32 = @splat(-1),
    pressed: [128]bool = @splat(false),
};
var slots: [16]Slot = @splat(.{});
var mutex: c.pthread_mutex_t = undefined;
var condition: c.pthread_cond_t = undefined;
var thread: c.pthread_t = undefined;
var initialized = false;
var running = false;
var ready = false;
var stopping = false;
var status: i32 = 0;
var loop: c.CFRunLoopRef = null;
var enabled = false;
var key_state: KeyState = .{};

fn lock() void {
    _ = c.pthread_mutex_lock(&mutex);
}
fn unlock() void {
    _ = c.pthread_mutex_unlock(&mutex);
}

fn cfString(value: [*:0]const u8) c.CFStringRef {
    return c.CFStringCreateWithCString(null, value, c.kCFStringEncodingUTF8);
}
fn numberProperty(device: c.IOHIDDeviceRef, name: [*:0]const u8) u32 {
    const key = cfString(name);
    defer c.CFRelease(key);
    const value = c.IOHIDDeviceGetProperty(device, key) orelse return 0;
    if (c.CFGetTypeID(value) != c.CFNumberGetTypeID()) return 0;
    var result: i32 = 0;
    _ = c.CFNumberGetValue(@ptrCast(value), c.kCFNumberSInt32Type, &result);
    return @bitCast(result);
}
fn stringProperty(device: c.IOHIDDeviceRef, name: [*:0]const u8, out: []u8) void {
    const key = cfString(name);
    defer c.CFRelease(key);
    const value = c.IOHIDDeviceGetProperty(device, key) orelse return;
    if (c.CFGetTypeID(value) == c.CFStringGetTypeID()) {
        _ = c.CFStringGetCString(@ptrCast(value), out.ptr, @intCast(out.len), c.kCFStringEncodingUTF8);
    }
}
fn postKey(key: usize, down: bool) void {
    const event = c.CGEventCreateKeyboardEvent(null, @intCast(key), down);
    if (event) |e| {
        c.CGEventPost(c.kCGHIDEventTap, e);
        c.CFRelease(e);
    }
}
fn press(slot: *Slot, index: usize, down: bool) void {
    const key = slot.keys[index];
    if (key < 0 or key >= 128) return;
    const k: usize = @intCast(key);
    if (key_state.change(k, &slot.pressed[index], down)) |transition| postKey(k, transition);
}
fn releaseAll() void {
    for (&slots) |*slot| {
        for (0..slot.info.input_count) |i| press(slot, i, false);
    }
}
fn switchDevice(slot: *const Slot) bool {
    return slot.info.vendor == 0x057e and slot.info.product == 0x2009;
}
fn canonicalSwitch(slot: *Slot) void {
    slot.info.input_count = 19;
    for (0..19) |i| {
        const axis = i < 4;
        const button = i >= 4 and i < 18;
        const value: i64 = if (axis) 2048 else if (button) 0 else 8;
        slot.inputs[i] = .{
            .cookie = @as(u32, 0x53570000) + @as(u32, @intCast(i)),
            .page = if (button) 9 else 1,
            .usage = if (axis) ([_]u32{ 0x30, 0x31, 0x32, 0x35 })[i] else if (button) @intCast(i - 3) else 0x39,
            .kind = if (axis) 2 else if (button) 1 else 3,
            .value = value,
            .minimum = 0,
            .maximum = if (axis) 4095 else if (button) 1 else 7,
            .changes = 0,
            .presses = 0,
            .seen_minimum = value,
            .seen_maximum = value,
        };
    }
}
fn update(slot: *Slot, index: usize, value: i64) void {
    const item = &slot.inputs[index];
    if (item.value != value) item.changes +%= 1;
    if (item.kind == 1 and item.value == 0 and value != 0) item.presses +%= 1;
    item.value = value;
    item.seen_minimum = @min(item.seen_minimum, value);
    item.seen_maximum = @max(item.seen_maximum, value);
    if (enabled and item.kind == 1) press(slot, index, value != 0);
}
fn report(_: ?*anyopaque, result: c.IOReturn, sender: ?*anyopaque, _: c.IOHIDReportType, _: u32, data: [*c]u8, length: c.CFIndex) callconv(.c) void {
    if (result != 0 or sender == null or data == null or length <= 0) return;
    const device: c.IOHIDDeviceRef = @ptrCast(sender);
    lock();
    defer unlock();
    for (&slots) |*slot| {
        if (slot.device != device or !switchDevice(slot)) continue;
        const bytes = data[0..@intCast(length)];
        const state = switch_report.decode(bytes) orelse return;
        slot.info.reserved = bytes[0];
        for (state.axes, 0..) |value, i| update(slot, i, value);
        for (state.buttons, 4..) |pressed, i| update(slot, i, if (pressed) 1 else 0);
        update(slot, 18, state.hat);
        return;
    }
}
fn matched(_: ?*anyopaque, result: c.IOReturn, _: ?*anyopaque, device: c.IOHIDDeviceRef) callconv(.c) void {
    if (result != 0 or device == null) return;
    lock();
    defer unlock();
    for (slots) |slot| {
        if (slot.device == device) return;
    }
    for (&slots) |*slot| {
        if (slot.device != null) continue;
        slot.* = .{};
        slot.device = device;
        _ = c.IORegistryEntryGetRegistryEntryID(c.IOHIDDeviceGetService(device), &slot.info.id);
        slot.info.vendor = numberProperty(device, "VendorID");
        slot.info.product = numberProperty(device, "ProductID");
        stringProperty(device, "Product", &slot.info.name);
        stringProperty(device, "Transport", &slot.info.transport);
        if (switchDevice(slot)) {
            canonicalSwitch(slot);
            return;
        }
        const elements = c.IOHIDDeviceCopyMatchingElements(device, null, 0) orelse return;
        defer c.CFRelease(elements);
        const count: usize = @intCast(c.CFArrayGetCount(elements));
        for (0..count) |i| {
            if (slot.info.input_count >= slot.inputs.len) break;
            const element: c.IOHIDElementRef = @ptrCast(@constCast(c.CFArrayGetValueAtIndex(elements, @intCast(i))));
            const kind = c.IOHIDElementGetType(element);
            if (kind < c.kIOHIDElementTypeInput_Misc or kind > c.kIOHIDElementTypeInput_ScanCodes) continue;
            const page = c.IOHIDElementGetUsagePage(element);
            const usage = c.IOHIDElementGetUsage(element);
            const j = slot.info.input_count;
            slot.inputs[j] = .{
                .cookie = c.IOHIDElementGetCookie(element),
                .page = page,
                .usage = usage,
                .kind = if (page == 9) 1 else if (page == 1 and usage == 0x39) 3 else if (page == 1 and usage >= 0x30 and usage <= 0x38) 2 else 4,
                .value = 0,
                .minimum = c.IOHIDElementGetLogicalMin(element),
                .maximum = c.IOHIDElementGetLogicalMax(element),
                .changes = 0,
                .presses = 0,
                .seen_minimum = 0,
                .seen_maximum = 0,
            };
            var value: c.IOHIDValueRef = null;
            if (c.IOHIDDeviceGetValue(device, element, &value) == 0 and value != null) slot.inputs[j].value = c.IOHIDValueGetIntegerValue(value);
            slot.inputs[j].seen_minimum = slot.inputs[j].value;
            slot.inputs[j].seen_maximum = slot.inputs[j].value;
            slot.info.input_count += 1;
        }
        return;
    }
}
fn removed(_: ?*anyopaque, _: c.IOReturn, _: ?*anyopaque, device: c.IOHIDDeviceRef) callconv(.c) void {
    lock();
    defer unlock();
    for (&slots) |*slot| {
        if (slot.device == device) {
            for (0..slot.info.input_count) |i| press(slot, i, false);
            slot.* = .{};
        }
    }
}
fn input(_: ?*anyopaque, result: c.IOReturn, _: ?*anyopaque, value: c.IOHIDValueRef) callconv(.c) void {
    if (result != 0 or value == null) return;
    const element = c.IOHIDValueGetElement(value);
    const device = c.IOHIDElementGetDevice(element);
    const cookie = c.IOHIDElementGetCookie(element);
    const v = c.IOHIDValueGetIntegerValue(value);
    lock();
    defer unlock();
    for (&slots) |*slot| {
        if (slot.device != device or switchDevice(slot)) continue;
        for (slot.inputs[0..slot.info.input_count], 0..) |*item, i| {
            if (item.cookie != cookie) continue;
            update(slot, i, v);
            return;
        }
    }
}
fn run(_: ?*anyopaque) callconv(.c) ?*anyopaque {
    const manager = c.IOHIDManagerCreate(null, 0);
    var dictionaries: [3]c.CFMutableDictionaryRef = undefined;
    const pageKey = cfString("DeviceUsagePage");
    const usageKey = cfString("DeviceUsage");
    defer c.CFRelease(pageKey);
    defer c.CFRelease(usageKey);
    for (&dictionaries, [_]i32{ 4, 5, 8 }) |*dict, usage| {
        dict.* = c.CFDictionaryCreateMutable(null, 0, &c.kCFTypeDictionaryKeyCallBacks, &c.kCFTypeDictionaryValueCallBacks);
        var page: i32 = 1;
        var use = usage;
        const p = c.CFNumberCreate(null, c.kCFNumberSInt32Type, &page);
        const u = c.CFNumberCreate(null, c.kCFNumberSInt32Type, &use);
        c.CFDictionarySetValue(dict.*, pageKey, p);
        c.CFDictionarySetValue(dict.*, usageKey, u);
        c.CFRelease(p);
        c.CFRelease(u);
    }
    const matches = c.CFArrayCreate(null, @ptrCast(&dictionaries), 3, &c.kCFTypeArrayCallBacks);
    c.IOHIDManagerSetDeviceMatchingMultiple(manager, matches);
    c.CFRelease(matches);
    for (dictionaries) |dict| c.CFRelease(dict);
    c.IOHIDManagerRegisterDeviceMatchingCallback(manager, matched, null);
    c.IOHIDManagerRegisterDeviceRemovalCallback(manager, removed, null);
    c.IOHIDManagerRegisterInputValueCallback(manager, input, null);
    c.IOHIDManagerRegisterInputReportCallback(manager, report, null);
    const workerLoop = c.CFRunLoopGetCurrent();
    c.IOHIDManagerScheduleWithRunLoop(manager, workerLoop, c.kCFRunLoopDefaultMode);
    const opened = c.IOHIDManagerOpen(manager, 0);
    lock();
    loop = workerLoop;
    status = opened;
    ready = true;
    _ = c.pthread_cond_signal(&condition);
    unlock();
    if (opened == 0) {
        while (true) {
            lock();
            const shouldStop = stopping;
            unlock();
            if (shouldStop) break;
            _ = c.CFRunLoopRunInMode(c.kCFRunLoopDefaultMode, 0.05, 0);
        }
    }
    lock();
    releaseAll();
    enabled = false;
    loop = null;
    slots = @splat(.{});
    unlock();
    c.IOHIDManagerUnscheduleFromRunLoop(manager, workerLoop, c.kCFRunLoopDefaultMode);
    _ = c.IOHIDManagerClose(manager, 0);
    c.CFRelease(manager);
    return null;
}

export fn hc_abi_version() u32 {
    return 2;
}
export fn hc_start() i32 {
    if (!initialized) {
        _ = c.pthread_mutex_init(&mutex, null);
        _ = c.pthread_cond_init(&condition, null);
        initialized = true;
    }
    if (running) {
        // A Flutter hot restart must never inherit active keyboard output.
        hc_clear_mappings();
        return status;
    }
    ready = false;
    stopping = false;
    const result = c.pthread_create(&thread, null, run, null);
    if (result != 0) return result;
    running = true;
    lock();
    while (!ready) {
        _ = c.pthread_cond_wait(&condition, &mutex);
    }
    const resultStatus = status;
    unlock();
    return resultStatus;
}
export fn hc_stop() void {
    if (!running) return;
    lock();
    stopping = true;
    if (loop != null) {
        c.CFRunLoopStop(loop);
        c.CFRunLoopWakeUp(loop);
    }
    unlock();
    _ = c.pthread_join(thread, null);
    running = false;
}
export fn hc_devices(out: [*]c.HCDevice, capacity: u32) u32 {
    lock();
    defer unlock();
    var count: u32 = 0;
    for (slots) |slot| {
        if (slot.device == null or count >= capacity) continue;
        out[count] = slot.info;
        count += 1;
    }
    return count;
}
export fn hc_inputs(id: u64, out: [*]c.HCInput, capacity: u32) u32 {
    lock();
    defer unlock();
    for (slots) |slot| {
        if (slot.device == null or slot.info.id != id) continue;
        const count = @min(slot.info.input_count, capacity);
        @memcpy(out[0..count], slot.inputs[0..count]);
        return count;
    }
    return 0;
}
export fn hc_reset_extrema(id: u64) i32 {
    lock();
    defer unlock();
    for (&slots) |*slot| {
        if (slot.device == null or slot.info.id != id) continue;
        for (slot.inputs[0..slot.info.input_count]) |*item| {
            item.seen_minimum = item.value;
            item.seen_maximum = item.value;
        }
        return 0;
    }
    return -1;
}
export fn hc_map(id: u64, cookie: u32, key: i32) i32 {
    if (key < -1 or key >= 128) return -1;
    lock();
    defer unlock();
    for (&slots) |*slot| {
        if (slot.device == null or slot.info.id != id) continue;
        for (slot.inputs[0..slot.info.input_count], 0..) |item, i| {
            if (item.cookie != cookie or item.kind != 1) continue;
            press(slot, i, false);
            slot.keys[i] = key;
            return 0;
        }
    }
    return -2;
}
export fn hc_clear_mappings() void {
    lock();
    defer unlock();
    releaseAll();
    enabled = false;
    for (&slots) |*slot| {
        slot.keys = @splat(-1);
    }
}
export fn hc_enable(want: i32) i32 {
    lock();
    defer unlock();
    releaseAll();
    enabled = want != 0 and c.AXIsProcessTrusted() != 0;
    return if (enabled or want == 0) 0 else -1;
}
export fn hc_accessibility(prompt: i32) i32 {
    if (prompt == 0) return if (c.AXIsProcessTrusted() != 0) 1 else 0;
    const options = c.CFDictionaryCreateMutable(null, 0, &c.kCFTypeDictionaryKeyCallBacks, &c.kCFTypeDictionaryValueCallBacks);
    defer c.CFRelease(options);
    c.CFDictionarySetValue(options, c.kAXTrustedCheckOptionPrompt, c.kCFBooleanTrue);
    return if (c.AXIsProcessTrustedWithOptions(options) != 0) 1 else 0;
}

fn registryNumber(service: c.io_service_t, name: [*:0]const u8) i32 {
    const key = cfString(name);
    defer c.CFRelease(key);
    const value = c.IORegistryEntryCreateCFProperty(service, key, null, 0) orelse return -1;
    defer c.CFRelease(value);
    if (c.CFGetTypeID(value) != c.CFNumberGetTypeID()) return -1;
    var result: i32 = -1;
    _ = c.CFNumberGetValue(@ptrCast(value), c.kCFNumberSInt32Type, &result);
    return result;
}

export fn hc_usb_mode_hint() i32 {
    // The observed Xbox persona has a keyboard and vendor-specific interface,
    // but no standard gamepad descriptor. Probe USB metadata, never its keys.
    const matches = c.IOServiceMatching("IOUSBHostDevice") orelse return -1;
    var iterator: c.io_iterator_t = 0;
    if (c.IOServiceGetMatchingServices(c.kIOMainPortDefault, matches, &iterator) != 0) return -1;
    defer _ = c.IOObjectRelease(iterator);
    while (true) {
        const service = c.IOIteratorNext(iterator);
        if (service == 0) return 0;
        const found = registryNumber(service, "idVendor") == 0x3537 and
            registryNumber(service, "idProduct") == 0x1040;
        _ = c.IOObjectRelease(service);
        if (found) return 1;
    }
}
