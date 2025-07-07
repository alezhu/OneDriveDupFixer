const std = @import("std");
const utils = @import("utils.zig");
const Progress = @import("progress.zig").Progress;
const FileEntryMap = @import("file_entry_map.zig").FileEntryMap;
const FileEntry = @import("file_entry_map.zig").FileEntry;
const print = utils.print;
const printf = utils.printf;

const STR_ACCESS_DENIED_DIR = "Access denied to directory: {s} (skipped)";
const STR_ACCESS_DENIED_FILE = "Access denied to file: {s} (skipped)";

// Structure to track processing results and statistics
pub const ProcessResult = struct {
    processed: u32, // Number of file pairs processed
    backed_up: u32, // Number of files renamed to .bak
    renamed: u32, // Number of suffixed files renamed to base name
    errors: u32, // Number of errors encountered
    access_denied: u32, // Number of files/folders skipped due to access denial
    deleted: u32, // Number of deleted files
};

pub const Processor = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    folder_path: []const u8,
    suffix: []const u8,
    dirQueue: std.ArrayList([]const u8),
    result: ProcessResult = std.mem.zeroes(ProcessResult),
    progress: Progress,

    pub fn init(
        allocator: std.mem.Allocator,
        folder_path: []const u8,
        suffix: []const u8,
    ) Self {
        return Self{
            .allocator = allocator,
            .folder_path = folder_path,
            .suffix = suffix,
            .dirQueue = std.ArrayList([]const u8).init(allocator),
            .progress = Progress.init(allocator),
        };
    }

    pub fn free(self: *Self) void {
        for (self.dirQueue.items) |subdir| {
            self.allocator.free(subdir);
        }
        self.dirQueue.deinit();
    }

    pub fn process(self: *Self) !ProcessResult {
        self.result = std.mem.zeroes(ProcessResult);

        // Check if we have access to the root folder
        if (!_hasAccess(self.folder_path, true)) {
            printf("Access denied to folder: {s}\n", .{self.folder_path});
            self.result.access_denied += 1;
        } else {
            // Initialize progress spinner
            // Process the root folder and then recursively process all subdirectories
            const root_copy = try self.allocator.dupe(u8, self.folder_path);
            try self.dirQueue.append(root_copy);
            while (self.dirQueue.pop()) |dir| {
                try self._processDirectory(dir);
            }
            // Clear progress line and move to next line
            self.progress.logLine("Processing completed.");
        }

        return self.result;
    }

    // Process a single directory (find and process file pairs locally)
    fn _processDirectory(self: *Self, dir_path: []const u8) !void {
        // Show progress for current directory
        self.progress.showProgress(dir_path);

        // Check if we have access to the directory
        if (!_hasAccess(dir_path, true)) {
            self.progress.logLineFmt(STR_ACCESS_DENIED_DIR, .{dir_path});
            self.result.access_denied += 1;
            return;
        }

        // HashMap to track base names and their files in current directory only
        var base_files = FileEntryMap.init(self.allocator);
        defer _ = base_files.free();
        var suffixed_files = FileEntryMap.init(self.allocator);
        defer _ = suffixed_files.free();

        try self._collectFiles(dir_path, &base_files, &suffixed_files);
        try self._processFiles(dir_path, &base_files, &suffixed_files);
    }

    fn _collectFiles(self: *Self, dir_path: []const u8, base_files: *FileEntryMap, suffixed_files: *FileEntryMap) !void {
        // Try to open the directory for iteration
        var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch |err| {
            switch (err) {
                error.AccessDenied => {
                    self.progress.logLineFmt(STR_ACCESS_DENIED_DIR, .{dir_path});
                    self.result.access_denied += 1;
                    return;
                },
                else => {
                    self.progress.logLineFmt("Failed to open directory {s}: {}", .{ dir_path, err });
                    return;
                },
            }
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            // Build full path for the current entry
            const full_path = try std.fmt.allocPrint(self.allocator, "{s}{c}{s}", .{ dir_path, std.fs.path.sep, entry.name });

            switch (entry.kind) {
                .file => {
                    // Check if we have access to the file
                    if (!_hasAccess(full_path, false)) {
                        self.progress.logLineFmt(STR_ACCESS_DENIED_FILE, .{full_path});
                        self.result.access_denied += 1;
                        self.allocator.free(full_path);
                        continue;
                    }

                    // Get file statistics (including modification time)
                    const stat = std.fs.cwd().statFile(full_path) catch |err| {
                        switch (err) {
                            error.AccessDenied => {
                                self.progress.logLineFmt(STR_ACCESS_DENIED_FILE, .{full_path});
                                self.result.access_denied += 1;
                            },
                            else => {
                                self.progress.logLineFmt("Error getting file info for {s}: {}", .{ full_path, err });
                            },
                        }
                        self.allocator.free(full_path);
                        continue;
                    };

                    // Check if filename contains the suffix
                    const is_suffixed = std.mem.indexOf(u8, entry.name, self.suffix) != null;
                    const name_copy = try self.allocator.dupe(u8, entry.name);

                    const file_entry = FileEntry{
                        .path = full_path,
                        .name = name_copy,
                        .modified_time = stat.mtime,
                        .size = stat.size,
                    };

                    if (is_suffixed) {
                        // This is a suffixed file, get its base name
                        const base_name = self._getBaseName(entry.name) catch {
                            self.allocator.free(full_path);
                            self.allocator.free(name_copy);
                            continue;
                        };

                        const gop = try suffixed_files.getOrPut(base_name);
                        if (!gop.found_existing) {
                            gop.value_ptr.* = file_entry;
                        } else {
                            // Duplicate suffixed file, free the current one
                            self.allocator.free(full_path);
                            self.allocator.free(name_copy);
                            self.allocator.free(base_name);
                        }
                    } else {
                        // This is a base file, use its name as key
                        const base_name = try self.allocator.dupe(u8, entry.name);

                        const gop = try base_files.getOrPut(base_name);
                        if (!gop.found_existing) {
                            gop.value_ptr.* = file_entry;
                        } else {
                            // Duplicate base file, free the current one
                            self.allocator.free(full_path);
                            self.allocator.free(name_copy);
                            self.allocator.free(base_name);
                        }
                    }
                },
                .directory => {
                    // Check if we have access to the subdirectory
                    if (!_hasAccess(full_path, true)) {
                        self.progress.logLineFmt(STR_ACCESS_DENIED_DIR, .{full_path});
                        self.result.access_denied += 1;
                        self.allocator.free(full_path);
                        continue;
                    }

                    // Store subdirectory for later processing
                    try self.dirQueue.append(full_path);
                },
                else => {
                    // Skip other file types (symlinks, etc.)
                    self.allocator.free(full_path);
                },
            }
        }
    }

    // Extract base name from a filename by removing the suffix
    fn _getBaseName(self: *Self, filename: []const u8) ![]const u8 {
        // Find the suffix position in the filename
        if (std.mem.indexOf(u8, filename, self.suffix)) |pos| {
            // Extract the part before the suffix
            const base_name = filename[0..pos];
            // Find and preserve the file extension
            const extension = if (std.mem.lastIndexOf(u8, filename, ".")) |ext_pos|
                filename[ext_pos..]
            else
                "";

            // Combine base name with extension (removing the suffix part)
            return try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base_name, extension });
        }
        // If no suffix found, return a copy of the original filename
        return try self.allocator.dupe(u8, filename);
    }

    fn _processFiles(self: *Self, dir_path: []const u8, base_files: *FileEntryMap, suffixed_files: *FileEntryMap) !void {
        // Process file pairs in current directory
        var base_iterator = base_files.iterator();
        while (base_iterator.next()) |base_entry| {
            const base_name = base_entry.key_ptr.*;
            const base_file = base_entry.value_ptr.*;

            if (suffixed_files.get(base_name)) |suffixed_file| {
                // Found a pair in the same directory!
                self.result.processed += 1;

                // Check access to both files before processing
                if (!_hasAccess(base_file.path, false)) {
                    self.progress.logLineFmt(STR_ACCESS_DENIED_FILE, .{base_file.path});
                    self.result.access_denied += 1;
                    continue;
                }

                if (!_hasAccess(suffixed_file.path, false)) {
                    self.progress.logLineFmt(STR_ACCESS_DENIED_FILE, .{suffixed_file.path});
                    self.result.access_denied += 1;
                    continue;
                }

                if (base_file.modified_time == suffixed_file.modified_time) {
                    if (base_file.size == suffixed_file.size) {

                        // Compare file contents
                        var arena = std.heap.ArenaAllocator.init(self.allocator);
                        defer arena.deinit();

                        const allocator = arena.allocator();
                        const base_data = try allocator.alloc(u8, base_file.size);
                        _ = std.fs.cwd().readFile(base_file.path, base_data) catch |err| {
                            self.progress.logLineFmt("Error reading {s}: {}", .{ base_file.path, err });
                            self.result.errors += 1;
                            continue;
                        };
                        const suffixed_data = try allocator.alloc(u8, suffixed_file.size);
                        _ = std.fs.cwd().readFile(suffixed_file.path,suffixed_data) catch |err| {
                            self.progress.logLineFmt("Error reading {s}: {}", .{ suffixed_file.path, err });
                            self.result.errors += 1;
                            continue;
                        };

                        if (std.mem.eql(u8, base_data, suffixed_data)) {
                            // Files are identical, delete the suffixed file
                            std.fs.deleteFileAbsolute(suffixed_file.path) catch |err| {
                                switch (err) {
                                    error.AccessDenied => {
                                        self.progress.logLineFmt("Access denied when deleting {s} (skipped)", .{suffixed_file.path});
                                        self.result.access_denied += 1;
                                        continue;
                                    },
                                    else => {
                                        self.progress.logLineFmt("Error deleting {s}: {}", .{ suffixed_file.path, err });
                                        self.result.errors += 1;
                                        continue;
                                    },
                                }
                            };
                            self.progress.logLineFmt("Deleted: {s} ", .{suffixed_file.path});
                            self.result.deleted += 1;
                            continue;
                        }
                    }
                }

                // Check if base file is older than suffixed file
                if (base_file.modified_time < suffixed_file.modified_time) {
                    // Create backup name by adding .bak extension
                    const backup_path = try std.fmt.allocPrint(self.allocator, "{s}.bak", .{base_file.path});
                    defer self.allocator.free(backup_path);

                    // Rename base file to .bak
                    std.fs.renameAbsolute(base_file.path, backup_path) catch |err| {
                        switch (err) {
                            error.AccessDenied => {
                                self.progress.logLineFmt("Access denied when backing up {s} (skipped)", .{base_file.path});
                                self.result.access_denied += 1;
                                continue;
                            },
                            else => {
                                self.progress.logLineFmt("Error backing up {s}: {}", .{ base_file.path, err });
                                self.result.errors += 1;
                                continue;
                            },
                        }
                    };

                    self.progress.logLineFmt("Backed up: {s} -> {s}", .{ base_file.path, backup_path });
                    self.result.backed_up += 1;

                    // Rename suffixed file to base name (remove suffix)
                    const new_path = try std.fmt.allocPrint(self.allocator, "{s}{c}{s}", .{ dir_path, std.fs.path.sep, base_name });
                    defer self.allocator.free(new_path);

                    std.fs.renameAbsolute(suffixed_file.path, new_path) catch |err| {
                        switch (err) {
                            error.AccessDenied => {
                                self.progress.logLineFmt("Access denied when renaming {s} (skipped)", .{suffixed_file.path});
                                self.result.access_denied += 1;
                                continue;
                            },
                            else => {
                                self.progress.logLineFmt("Error renaming {s} -> {s}: {}", .{ suffixed_file.path, new_path, err });
                                self.result.errors += 1;
                                continue;
                            },
                        }
                    };

                    self.progress.logLineFmt("Renamed: {s} -> {s}", .{ suffixed_file.path, new_path });
                    self.result.renamed += 1;
                } else {
                    // Skip if base file is newer or same age
                    self.progress.logLineFmt("Skipped: {s} (newer or equal modification time)\n", .{base_file.path});
                }
            }
        }
    }
};

// Check if we have access to a file or directory
fn _hasAccess(path: []const u8, is_directory: bool) bool {
    if (is_directory) {
        // Try to open directory for reading
        var dir = std.fs.openDirAbsolute(path, .{ .iterate = false }) catch |err| {
            switch (err) {
                error.AccessDenied => return false,
                else => return false, // Treat other errors as access denied for safety
            }
        };
        dir.close();
        return true;
    } else {
        // Try to get file statistics (this requires read access)
        _ = std.fs.cwd().statFile(path) catch |err| {
            switch (err) {
                error.AccessDenied => return false,
                else => return false, // Treat other errors as access denied for safety
            }
        };
        return true;
    }
}
