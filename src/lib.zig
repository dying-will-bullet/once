const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

pub fn OnceCell(comptime T: type) type {
    if (builtin.single_threaded) {
        return @import("./singlethread.zig").OnceCell(T);
    } else {
        return @import("./multithread.zig").OnceCell(T);
    }
}

pub fn Lazy(comptime T: type, comptime f: fn () T) type {
    if (builtin.single_threaded) {
        return @import("./singlethread.zig").Lazy(T, f);
    } else {
        return @import("./multithread.zig").Lazy(T, f);
    }
}

test {
    // Import All files
    _ = @import("./singlethread.zig");
    _ = @import("./multithread.zig");

    std.testing.refAllDecls(@This());
}
