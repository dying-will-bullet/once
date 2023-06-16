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
