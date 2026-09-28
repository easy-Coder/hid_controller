const std = @import("std");

// Switch full reports use packed 12-bit axes, not the simple HID descriptor.
// Canonical order: south/east/west/north, LB/RB/LT/RT, View/Menu,
// LS/RS click, Home/Capture. Axis Y increases downward for the tester.
pub const State = struct {
    axes: [4]u16,
    buttons: [14]bool,
    hat: u8,
};
fn hatFromBits(bits: u8) u8 {
    return switch (bits & 15) {
        2 => 0,
        6 => 1,
        4 => 2,
        5 => 3,
        1 => 4,
        9 => 5,
        8 => 6,
        10 => 7,
        else => 8,
    };
}
fn pair(bytes: []const u8) [2]u16 {
    return .{ @as(u16, bytes[0]) | (@as(u16, bytes[1] & 15) << 8), @as(u16, bytes[1] >> 4) | (@as(u16, bytes[2]) << 4) };
}
fn little(bytes: []const u8) u16 {
    return @as(u16, bytes[0]) | (@as(u16, bytes[1]) << 8);
}
fn scaled(raw: u16) u16 {
    return @intCast((@as(u32, raw) * 4095 + 32767) / 65535);
}
pub fn decode(bytes: []const u8) ?State {
    if (bytes.len == 0) return null;
    if (bytes[0] == 0x30 or bytes[0] == 0x31 or bytes[0] == 0x21) {
        if (bytes.len < 13) return null;
        const left = pair(bytes[6..9]);
        const right = pair(bytes[9..12]);
        const r = bytes[3];
        const m = bytes[4];
        const l = bytes[5];
        return .{ .axes = .{ left[0], 4095 - left[1], right[0], 4095 - right[1] }, .buttons = .{ r & 4 != 0, r & 8 != 0, r & 1 != 0, r & 2 != 0, l & 64 != 0, r & 64 != 0, l & 128 != 0, r & 128 != 0, m & 1 != 0, m & 2 != 0, m & 8 != 0, m & 4 != 0, m & 16 != 0, m & 32 != 0 }, .hat = hatFromBits(l) };
    }
    if (bytes[0] == 0x3f) {
        if (bytes.len < 12) return null;
        const a = bytes[1];
        const b = bytes[2];
        return .{ .axes = .{ scaled(little(bytes[4..6])), scaled(little(bytes[6..8])), scaled(little(bytes[8..10])), scaled(little(bytes[10..12])) }, .buttons = .{ a & 1 != 0, a & 2 != 0, a & 4 != 0, a & 8 != 0, a & 16 != 0, a & 32 != 0, a & 64 != 0, (a & 128 != 0 or b & 128 != 0), b & 1 != 0, b & 2 != 0, b & 4 != 0, b & 8 != 0, b & 16 != 0, b & 32 != 0 }, .hat = if (bytes[3] < 8) bytes[3] else 8 };
    }
    return null;
}

test "captured Nova Lite full report is neutral buttons and independent sticks" {
    const bytes = [_]u8{ 0x30, 0x83, 0x71, 0, 0x80, 0, 0xf6, 0xe7, 0x78, 0x13, 0xe8, 0x7e, 0x0c };
    const state = decode(&bytes).?;
    try std.testing.expectEqualSlices(u16, &.{ 2038, 2161, 2067, 2065 }, &state.axes);
    for (state.buttons) |pressed| try std.testing.expect(!pressed);
    try std.testing.expectEqual(@as(u8, 8), state.hat);
    var changed = bytes;
    changed[1] = 0xff; // timer must not become buttons
    changed[6] = 0xff;
    changed[7] = 0xef; // only LS X changes
    const next = decode(&changed).?;
    try std.testing.expectEqual(@as(u16, 4095), next.axes[0]);
    try std.testing.expectEqualSlices(u16, state.axes[1..], next.axes[1..]);
    try std.testing.expectEqualSlices(bool, &state.buttons, &next.buttons);
}
test "full report buttons and hats do not alter axes" {
    var bytes = [_]u8{ 0x30, 0, 0, 4, 8, 6, 0, 8, 128, 0, 8, 128, 0 };
    const state = decode(&bytes).?;
    try std.testing.expect(state.buttons[0] and state.buttons[10]);
    try std.testing.expectEqual(@as(u8, 1), state.hat);
    bytes[3] = 0;
    bytes[4] = 0;
    bytes[5] = 0;
    try std.testing.expectEqualSlices(u16, &state.axes, &decode(&bytes).?.axes);
}
test "simple reports, truncated packets, and unknown IDs" {
    const state = decode(&.{ 0x3f, 1, 0, 8, 0, 128, 0, 128, 0, 128, 0, 128 }).?;
    try std.testing.expect(state.buttons[0]);
    try std.testing.expectEqualSlices(u16, &.{ 2048, 2048, 2048, 2048 }, &state.axes);
    try std.testing.expect(decode(&.{ 0x30, 1 }) == null);
    try std.testing.expect(decode(&.{ 0x81, 1, 2 }) == null);
}

test "rolling any one axis cannot move the other three or press buttons" {
    const neutral = [_]u8{ 0x30, 0, 0, 0, 0, 0, 0, 8, 128, 0, 8, 128, 0 };
    const base = decode(&neutral).?;
    for (0..4) |axis| {
        var packet = neutral;
        const offset: usize = if (axis < 2) 6 else 9;
        if (axis % 2 == 0) {
            packet[offset] = 0xff;
            packet[offset + 1] |= 15;
        } else {
            packet[offset + 1] |= 0xf0;
            packet[offset + 2] = 0xff;
        }
        const next = decode(&packet).?;
        for (0..4) |i| {
            if (i == axis) try std.testing.expect(next.axes[i] != base.axes[i]) else try std.testing.expectEqual(base.axes[i], next.axes[i]);
        }
        try std.testing.expectEqualSlices(bool, &base.buttons, &next.buttons);
        try std.testing.expectEqual(base.hat, next.hat);
    }
}
