const std = @import("std");

pub const printf = std.debug.print;

pub fn print(comptime msg: []const u8) void {
    printf(msg, .{});
}
