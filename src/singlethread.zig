const std = @import("std");
const testing = std.testing;

pub fn Lazy(comptime T: type, comptime f: fn () T) type {
    return struct {
        cell: OnceCell(T),

        const Self = @This();

        pub fn init() Self {
            return Self{ .cell = OnceCell(T).empty() };
        }

        pub fn get(self: *Self) *T {
            return self.cell.getOrInit(f);
        }

        pub fn getConst(self: *Self) *const T {
            return self.cell.getOrInit(f);
        }
    };
}

pub fn OnceCell(comptime T: type) type {
    return struct {
        cell: ?T,
        const Self = @This();

        /// Creates a new empty cell.
        pub fn empty() Self {
            return Self{
                .cell = null,
            };
        }

        /// Creates a new initialized cell.
        pub fn withValue(value: T) Self {
            return Self{
                .cell = value,
            };
        }

        ///Gets a reference to the underlying value.
        // Returns `None` if the cell is empty.
        pub fn get(self: *Self) ?*T {
            if (self.cell == null) {
                return null;
            }
            return &self.cell.?;
        }

        /// Gets the contents of the cell, initializing it with f if the cell was empty.
        pub fn getOrInit(self: *Self, comptime f: fn () T) *T {
            if (self.cell == null) {
                self.cell = f();
            }

            return &self.cell.?;
        }

        /// Takes the value out of this OnceCell, moving it back to an uninitialized state.
        /// Has no effect and returns None if the OnceCell hasn’t been initialized.
        pub fn take(self: *Self) ?T {
            if (self.cell == null) {
                return null;
            }

            var cell = self.cell.?;
            self.cell = null;
            return cell;
        }
    };
}

// --------------------------------------------------------------------------------
//                                   Testing
// --------------------------------------------------------------------------------

const allocator = testing.allocator;

var shared: i32 = 0;

fn incrShared() i32 {
    shared += 1;
    return shared;
}
var cell3 = OnceCell(i32).empty();

test "test init once" {
    _ = cell3.getOrInit(incrShared);
    _ = cell3.getOrInit(incrShared);
    var v = cell3.get();

    try testing.expect(v != null);
    try testing.expect(v.?.* == 1);
    try testing.expect(shared == 1);
}

fn returnMap() std.StringHashMap(i32) {
    var map = std.StringHashMap(i32).init(allocator);
    map.put("b", 2) catch @panic("unable to put b");
    return map;
}

var LazyMap = Lazy(std.StringHashMap(i32), returnMap).init();

test "test lazy" {
    var map = LazyMap.get();
    defer map.*.deinit();
    try map.*.put("c", 3);

    var map2 = LazyMap.get();

    try testing.expect(map2.*.get("c") != null);
    try testing.expect(map2.*.get("c").? == 3);
}
