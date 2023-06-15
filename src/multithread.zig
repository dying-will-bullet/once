const std = @import("std");
const testing = std.testing;

// TODO:
// 1. getConst and getMut
// 2. support argumetns like thread.spawn
// 3. optimise lock

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
        // cell: T = undefined,
        // mutex: std.Thread.Mutex = std.Thread.Mutex{},
        // done: bool = false,

        cell: T,
        mutex: std.Thread.Mutex,
        done: std.atomic.Atomic(u32),
        const Self = @This();

        /// Creates a new empty cell.
        pub fn empty() Self {
            return Self{
                .cell = undefined,
                .mutex = std.Thread.Mutex{},
                .done = std.atomic.Atomic(u32).init(0b00),
            };
        }

        /// Creates a new initialized cell.
        pub fn withValue(value: T) Self {
            return Self{
                .cell = value,
                .mutex = std.Thread.Mutex{},
                .done = std.atomic.Atomic(u32).init(0b01),
            };
        }

        /// Gets the reference to the underlying value.
        /// Returns `null` if the cell is uninitialized, or being initialized.
        /// This method never blocks.
        pub fn get(self: *Self) ?*T {
            if (self.isInitialize()) {
                return &self.cell;
            }
            return null;
        }

        /// Gets the reference to the underlying value, initializing it with `f` if the cell was uninitialized.
        /// Many threads may call `getOrInit` concurrently with different initializing functions,
        /// but it is guaranteed that only one function will be executed.
        /// This method may block when the cell is not initialized.
        pub fn getOrInit(self: *Self, comptime f: fn () T) *T {
            // Fast path check
            if (self.get()) |value| {
                return value;
            }

            self.initialize(f);
            std.debug.assert(self.isInitialize());

            return self.getUnchecked();
        }

        /// Get the reference to the underlying value, without checking if the cell is initialized.
        pub fn getUnchecked(self: *Self) *T {
            std.debug.assert(self.isInitialize());

            return &self.cell;
        }

        /// Takes the value out of this OnceCell, moving it back to an uninitialized state.
        pub fn take(self: *Self) ?T {
            if (self.isInitialize()) {
                defer self.done.store(0b00, .Release);

                var cell = self.cell;
                self.cell = undefined;
                return cell;
            }
            return null;
        }

        /// Gets the reference to the underlying value, blocking the current thread until it is set.
        pub fn wait(self: *Self) *T {
            while (self.done.load(.Monotonic) == 0b00) {
                std.Thread.Futex.wait(&self.done, 0b00);
            }

            // while (self.done.swap(0b00, .Acquire) != 0b01) {
            //     std.Thread.Futex.wait(&self.done, 0b00);
            // }

            return self.getUnchecked();
        }

        // --------------------------------------------------------------------------------
        //                                   Core API
        // --------------------------------------------------------------------------------

        fn isInitialize(self: Self) bool {
            return self.done.load(.Acquire) == 0b01;
        }

        fn initialize(self: *Self, comptime f: fn () T) void {
            @setCold(true);

            self.mutex.lock();
            defer self.mutex.unlock();

            // The first thread to acquire the mutex gets to run the initializer
            if (self.done.loadUnchecked() == 0b00) {
                self.cell = f();
                defer self.done.store(0b01, .Release);
                std.Thread.Futex.wake(&self.done, 1000);
            }
        }
    };
}

// --------------------------------------------------------------------------------
//                                   Testing
// --------------------------------------------------------------------------------

const allocator = testing.allocator;
fn return_1() i32 {
    return 1;
}

fn return_2() i32 {
    return 2;
}

fn returnMap() std.StringHashMap(i32) {
    var map = std.StringHashMap(i32).init(allocator);
    map.put("b", 2) catch @panic("unable to put b");
    return map;
}

var globalMap = OnceCell(std.StringHashMap(i32)).empty();

test "test global map" {
    _ = globalMap.getOrInit(returnMap);
    var r1 = globalMap.get().?;
    try r1.*.put("a", 1);

    try testing.expect(r1.*.get("b") != null);
    try testing.expect(r1.*.get("b").? == 2);

    // must be same hashmap
    _ = globalMap.getOrInit(returnMap);
    var r2 = globalMap.get().?;

    try testing.expect(r2.*.get("a") != null);
    try testing.expect(r2.*.get("a").? == 1);

    defer r2.*.deinit();
}

var globalMap2 = OnceCell(std.StringHashMap(i32)).empty();

test "test global map take" {
    _ = globalMap2.getOrInit(returnMap);
    var r1 = globalMap2.take().?;
    defer r1.deinit();

    try testing.expect(r1.get("b") != null);
    try testing.expect(r1.get("b").? == 2);

    var r2 = globalMap2.take();
    try testing.expect(r2 == null);

    _ = globalMap2.getOrInit(returnMap);

    var r3 = globalMap2.take().?;
    defer r3.deinit();
    try testing.expect(r3.get("b") != null);
    try testing.expect(r3.get("b").? == 2);
}

test "test assume init" {
    var cell1 = OnceCell(i32).empty();
    const r1 = cell1.getOrInit(return_1);
    const r2 = cell1.getUnchecked();

    try testing.expect(r1.* == 1);
    try testing.expect(r2.* == 1);
}

test "test cell multi init" {
    var cell1 = OnceCell(i32).empty();
    var cell2 = OnceCell(i32).empty();

    const r1 = cell1.getOrInit(return_1);
    const r2 = cell1.getOrInit(return_1);
    const r3 = cell1.getOrInit(return_1);

    try testing.expect(r1.* == 1);
    try testing.expectEqual(r1, r2);
    try testing.expectEqual(r2, r3);

    const a1 = cell2.getOrInit(return_2);
    const a2 = cell2.getOrInit(return_2);
    const a3 = cell2.getOrInit(return_2);

    try testing.expect(a1.* == 2);
    try testing.expectEqual(a1, a2);
    try testing.expectEqual(a2, a3);
}

var shared: i32 = 0;

fn incrShared() i32 {
    shared += 1;
    return shared;
}

var cell3 = OnceCell(i32).empty();

test "test multithread shared value" {
    var threads: [10]std.Thread = undefined;
    defer for (threads) |handle| handle.join();

    for (&threads) |*handle| {
        handle.* = try std.Thread.spawn(.{}, struct {
            fn thread_fn(x: u8) void {
                _ = x;
                _ = cell3.getOrInit(incrShared);
            }
        }.thread_fn, .{0});
    }

    try testing.expectEqual(@as(i32, 1), shared);
}

var cell4 = OnceCell(i32).empty();

// FIXME:
// test "test wait" {
//     var threads: [10]std.Thread = undefined;
//     defer for (threads) |handle| handle.join();

//     for (&threads) |*handle| {
//         handle.* = try std.Thread.spawn(.{}, struct {
//             fn thread_fn(x: u8) void {
//                 _ = x;
//                 _ = cell4.wait();
//             }
//         }.thread_fn, .{0});
//     }

//     _ = cell4.getOrInit(return_1);
// }

var LazyMap = Lazy(std.StringHashMap(i32), returnMap).init();

test "test lazy" {
    var map = LazyMap.get();
    defer map.*.deinit();
    try map.*.put("c", 3);

    var map2 = LazyMap.get();

    try testing.expect(map2.*.get("c") != null);
    try testing.expect(map2.*.get("c").? == 3);
}

const MutexStringHashMap = struct {
    mutex: std.Thread.Mutex,
    str_map: std.StringHashMap(i32),

    const Self = @This();
    pub fn init() Self {
        return Self{
            .mutex = std.Thread.Mutex{},
            .str_map = std.StringHashMap(i32).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.str_map.deinit();
    }

    pub fn borrow(self: *Self) *std.StringHashMap(i32) {
        self.mutex.lock();
        return &self.str_map;
    }

    pub fn restore(self: *Self) void {
        self.mutex.unlock();
    }
};

fn returnMutexMap() MutexStringHashMap {
    return MutexStringHashMap.init();
}

var LazyMutexMap = Lazy(MutexStringHashMap, returnMutexMap).init();

test "test lazy mutex map" {
    var obj = LazyMutexMap.get();
    defer obj.*.deinit();

    var map = obj.*.borrow();
    try map.*.put("v", 0);
    obj.*.restore();

    var threads: [10]std.Thread = undefined;

    for (&threads) |*handle| {
        handle.* = try std.Thread.spawn(.{}, struct {
            fn thread_fn(x: u8) !void {
                _ = x;
                var o = LazyMutexMap.get();
                var m = o.*.borrow();

                const v = m.get("v").?;
                try m.put("v", v + 1);
                o.*.restore();
            }
        }.thread_fn, .{0});
    }

    for (threads) |handle| handle.join();

    const map2 = obj.*.borrow();
    try testing.expectEqual(@as(i32, 10), map2.*.get("v").?);
}
