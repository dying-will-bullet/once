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
