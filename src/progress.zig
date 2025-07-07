const std = @import("std");
const utils = @import("utils.zig");
const printf = utils.printf;
const print = utils.print;
const Allocator = std.mem.Allocator;

const SLASH: u8 = '\\';
const SPINNER_CHARS = [_]u8{ '/', '|', SLASH, '-' };
const CLEAR_LINE = "\r\x1b[K";

// Progress spinner for visual feedback
pub const Progress = struct {
    counter: usize,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{ .counter = 0, .allocator = allocator };
    }

    pub fn next(self: *Self) u8 {
        const char = SPINNER_CHARS[self.counter % SPINNER_CHARS.len];
        self.counter += 1;
        return char;
    }

    pub fn showProgress(self: *Self, current_dir: []const u8) void {
        // Show progress with spinner
        printf("{s}[{c}] Processing: {s}", .{ CLEAR_LINE, self.next(), current_dir });
        // Flush output to ensure immediate display
        std.io.getStdOut().writer().context.sync() catch {};
    }
    pub fn logLineFmt(self: *Self, comptime fmt: []const u8, args: anytype) void {
        _ = self;
        printf("{s}" ++ fmt ++ "\n", .{CLEAR_LINE} ++ args);
        // Flush output to ensure immediate display
        std.io.getStdOut().writer().context.sync() catch {};
    }
    pub fn logLine(self: *Self, msg: []const u8) void {
        _ = self;
        printf("{s}{s}\n", .{ CLEAR_LINE, msg });
        // Flush output to ensure immediate display
        std.io.getStdOut().writer().context.sync() catch {};
    }
};
