const std = @import("std");

pub const KeyState = struct {
    held: [128]u32 = @splat(0),

    // Returns a key-down/up transition only when the shared key state changes.
    pub fn change(self: *KeyState, key: usize, pressed: *bool, down: bool) ?bool {
        if (pressed.* == down) return null;
        pressed.* = down;
        if (down) {
            self.held[key] += 1;
            return if (self.held[key] == 1) true else null;
        }
        if (self.held[key] > 0) self.held[key] -= 1;
        return if (self.held[key] == 0) false else null;
    }
};

test "shared key stays down until both buttons release; repeats are ignored" {
    var state: KeyState = .{};
    var first = false;
    var second = false;
    try std.testing.expectEqual(@as(?bool, true), state.change(49, &first, true));
    try std.testing.expectEqual(@as(?bool, null), state.change(49, &first, true));
    try std.testing.expectEqual(@as(?bool, null), state.change(49, &second, true));
    try std.testing.expectEqual(@as(?bool, null), state.change(49, &first, false));
    try std.testing.expectEqual(@as(?bool, false), state.change(49, &second, false));
    try std.testing.expectEqual(@as(u32, 0), state.held[49]);
}
test "releasing twice does not duplicate key-up or underflow" {
    var state: KeyState = .{};
    var pressed = false;
    _ = state.change(0, &pressed, true);
    try std.testing.expectEqual(@as(?bool, false), state.change(0, &pressed, false));
    try std.testing.expectEqual(@as(?bool, null), state.change(0, &pressed, false));
    try std.testing.expectEqual(@as(u32, 0), state.held[0]);
}
