<h1 align="center"> once ⛳ </h1>

[![CI](https://github.com/Hanaasagi/struct-env/actions/workflows/ci.yaml/badge.svg)](https://github.com/Hanaasagi/struct-env/actions/workflows/ci.yaml)
![](https://img.shields.io/badge/language-zig-%23ec915c)

This library implements the concepts of `Cell` and `Lazy` in Rust, which are used for lazy initialization of variables.

## Examples

### `Lazy`: A value which is initialized on the first access.

```zig
const std = @import("std");
const Lazy = @import("once").Lazy;
const allocator = std.heap.page_allocator;

var global_map = Lazy(
    // Type of Cell
    std.StringHashMap(i32),
    // Cell Init Function
    struct {
        fn f() std.StringHashMap(i32) {
            var map = std.StringHashMap(i32).init(allocator);
            map.put("a", 1) catch @panic("unable to put a");
            return map;
        }
    }.f,
).init();

pub fn main() !void {
    var map_ptr = global_map.get();
    try map_ptr.*.put("b", 2);

    std.debug.assert(map_ptr.*.get("a").? == 1);
    std.debug.assert(map_ptr.*.get("b").? == 2);
}
```

### `OnceCell`: A thread-safe cell which can be written to only once.

```zig
const std = @import("std");
const OnceCell = @import("once").OnceCell;

var shared: usize = 0;

pub fn main() !void {
    var cell = OnceCell([]const u8).empty();

    std.debug.assert(cell.get() == null);

    // Both try to init a cell
    var threads: [8]std.Thread = undefined;
    for (&threads) |*handle| {
        handle.* = try std.Thread.spawn(.{}, struct {
            fn thread_fn(c: *OnceCell([]const u8)) !void {
                _ = c.getOrInit(struct {
                    fn f() []const u8 {
                        shared += 1;
                        return "Hello";
                    }
                }.f);
            }
        }.thread_fn, .{&cell});
    }
    for (threads) |handle| handle.join();

    std.debug.assert(std.mem.eql(u8, cell.get().?.*, "Hello"));
    // Only init once
    std.debug.assert(shared == 1);
}

```

## Installation

## LICENSE

MIT License Copyright (c) 2023, Hanaasagi
