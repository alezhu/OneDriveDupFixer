const std = @import("std");
const Allocator = std.mem.Allocator;

// Structure to hold file information for processing
pub const FileEntry = struct {
    path: []const u8, // Full path to the file
    name: []const u8, // Just the filename
    modified_time: i128, // File modification time for comparison
    size: u64,
};

pub const FileEntryMap = struct {
    const Self = @This();
    const FilesHashMap = std.HashMap([]const u8, FileEntry, std.hash_map.StringContext, std.hash_map.default_max_load_percentage);
    allocator: Allocator,
    files: FilesHashMap,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .files = FilesHashMap.init(allocator),
        };
    }

    pub fn get(self: *Self, file: []const u8) ?FileEntry {
        return self.files.get(file);
    }

    pub fn getOrPut(self: *Self, file: []const u8) Allocator.Error!FilesHashMap.GetOrPutResult {
        return self.files.getOrPut(file);
    }
    pub fn iterator(self: *Self) FilesHashMap.Iterator {
        return self.files.iterator();
    }
    pub fn free(self: *FileEntryMap) void {
        var _iterator = self.iterator();
        while (_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.path);
            self.allocator.free(entry.value_ptr.name);
        }
        self.files.deinit();
    }
};
