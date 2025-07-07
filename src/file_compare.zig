const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

// Buffer size for reading files in chunks - optimized for performance
const BUFFER_SIZE = 64 * 1024; // 64KB chunks

/// Compares two files by content for equality
/// Returns true if files are identical, false otherwise
/// Uses ArenaAllocator for memory management
pub fn compareFiles(allocator: std.mem.Allocator, file_path1: []const u8, file_path2: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const _allocator = arena.allocator();

    // Open both files
    const file1 = std.fs.cwd().openFile(file_path1, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => {
                print("Error: File not found: {s}\n", .{file_path1});
                return false;
            },
            else => return err,
        }
    };
    defer file1.close();

    const file2 = std.fs.cwd().openFile(file_path2, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => {
                print("Error: File not found: {s}\n", .{file_path2});
                return false;
            },
            else => return err,
        }
    };
    defer file2.close();

    // Get file sizes first - quick check for different sizes
    const file1_size = try file1.getEndPos();
    const file2_size = try file2.getEndPos();

    // If sizes are different, files are not equal
    if (file1_size != file2_size) {
        return false;
    }

    // If both files are empty, they are equal
    if (file1_size == 0) {
        return true;
    }

    // Allocate buffers for reading chunks
    const buffer1 = try _allocator.alloc(u8, BUFFER_SIZE);
    const buffer2 = try _allocator.alloc(u8, BUFFER_SIZE);

    // Compare files chunk by chunk
    var bytes_read: usize = 0;
    while (bytes_read < file1_size) {
        const chunk_size = @min(BUFFER_SIZE, file1_size - bytes_read);

        // Read chunks from both files
        const read1 = try file1.readAll(buffer1[0..chunk_size]);
        const read2 = try file2.readAll(buffer2[0..chunk_size]);

        // Check if read sizes match
        if (read1 != read2) {
            return false;
        }

        // Compare the chunks byte by byte
        if (!std.mem.eql(u8, buffer1[0..read1], buffer2[0..read2])) {
            return false;
        }

        bytes_read += read1;

        // Break if we've read less than expected (end of file)
        if (read1 < chunk_size) {
            break;
        }
    }

    return true;
}
