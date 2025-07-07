const std = @import("std");
const utils = @import("utils.zig");
const Processor = @import("processor.zig").Processor;
const build_options = @import("build_options");
const printf = utils.printf;
const print = utils.print;
const Allocator = std.mem.Allocator;
const windows = std.os.windows;




// Structure to hold parsed command line arguments
const Args = struct {
    folder_path: []const u8,
    suffix: ?[]const u8,
};

pub fn main() !void {
    // Set UTF-8 for console
    _ = windows.kernel32.SetConsoleOutputCP(65001);
    // _ = windows.kernel32.SetConsoleCP(65001);

    // Initialize general purpose allocator for memory management
    const allocator = std.heap.page_allocator;


    printf("OneDriveDupFixer: {s}\n", .{build_options.version});


    // Parse command line arguments
    const raw_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw_args);

    // Parse and validate arguments
    const args = parseArgs(raw_args) catch |err| {
        switch (err) {
            error.InvalidArguments => {
                printf("Usage: {s} [--suffix|-s <suffix>] <folder>\n", .{raw_args[0]});
                print("  --suffix, -s - suffix (include '-') to search for in filenames \n");
                print("  folder       - path to folder to process\n");
                print("\nIf suffix is not provided, computer name will be used as default.\n");
                return;
            },
            else => return err,
        }
    };

    // Get suffix from arguments or use computer name as default
    var suffix_buf: [256]u8 = undefined;
    const suffix = if (args.suffix) |s|
        s
    else
        getComputerNameSuffix(&suffix_buf) catch |err| {
            print("Error: Could not determine suffix. Computer name is not available and no suffix was provided.\n");
            print("Please provide a suffix using --suffix or -s parameter.\n");
            return err;
        };

    printf("Processing folder: {s}\n", .{args.folder_path});
    printf("Using suffix: {s}\n", .{suffix});
    print("Starting processing...\n\n");

    // Process the folder and get results
    var processor = Processor.init(allocator, args.folder_path, suffix);
    defer _ = processor.free();
    const result = processor.process() catch |err| {
        printf("Error: {}\n", .{err});
        return;
    };


    // Print final statistics
    print("\n=== Processing Results ===\n");
    printf("File pairs processed: {d}\n", .{result.processed});
    printf("Files backed up (.bak): {d}\n", .{result.backed_up});
    printf("Files renamed: {d}\n", .{result.renamed});
    printf("Errors encountered: {d}\n", .{result.errors});
    printf("Files deleted: {d}", .{result.deleted});
    printf("Access denied (skipped): {d}\n", .{result.access_denied});
}

// Parse command line arguments and return structured result
fn parseArgs(raw_args: [][:0]u8) !Args {
    if (raw_args.len < 2) {
        return error.InvalidArguments;
    }

    var suffix: ?[]const u8 = null;
    var folder_path: ?[]const u8 = null;
    var i: usize = 1;

    // Parse arguments
    while (i < raw_args.len) {
        const arg = raw_args[i];

        if (std.mem.eql(u8, arg, "--suffix") or std.mem.eql(u8, arg, "-s")) {
            // Check if suffix value is provided
            if (i + 1 >= raw_args.len) {
                print("Error: --suffix/-s requires a value\n");
                return error.InvalidArguments;
            }
            suffix = raw_args[i + 1];
            i += 2; // Skip both the flag and its value
        } else if (folder_path == null) {
            // First non-flag argument is the folder path
            folder_path = arg;
            i += 1;
        } else {
            // Too many arguments
            print("Error: Too many arguments provided\n");
            return error.InvalidArguments;
        }
    }

    // Validate that folder path was provided
    if (folder_path == null) {
        print("Error: Folder path is required\n");
        return error.InvalidArguments;
    }

    return Args{
        .folder_path = folder_path.?,
        .suffix = suffix,
    };
}

// Get computer name and format it as a suffix with dash prefix
// Returns error if computer name cannot be determined
fn getComputerNameSuffix(buf: []u8) ![]const u8 {
    // Try to get computer name from environment variable
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "COMPUTERNAME")) |computer_name| {
        defer std.heap.page_allocator.free(computer_name);
        // Format as "-COMPUTERNAME"
        const result = std.fmt.bufPrint(buf, "-{s}", .{computer_name}) catch |err| {
            printf("Error formatting suffix: {}\n", .{err});
            return error.FormatError;
        };
        return result;
    } else |_| {
        // Return error instead of fallback if computer name is not available
        return error.ComputerNameNotAvailable;
    }
}



