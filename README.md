# OneDrive Duplicate Fixer

A command-line utility that fixes OneDrive synchronization issues by managing duplicate files and resolving version conflicts.

## Problem Description

OneDrive sometimes creates synchronization conflicts instead of properly updating files. When this happens, OneDrive may:

1. **Create a duplicate file** with a suffix matching your computer name (e.g., `document-MYPC.docx`)
2. **Overwrite the original file** with an older version
3. **Leave you with two files**: the original (older version) and the suffixed file (newer version)

This creates a frustrating situation where you have to manually identify which file is newer and resolve the conflict.

## What **OneDrive Duplicate Fixer** Does

**OneDrive Duplicate Fixer** automatically resolves these conflicts by:

1. **Scanning directories** recursively for file pairs (base file + suffixed file)
2. **Comparing modification times** to determine which file is newer
3. **Taking appropriate action** based on the comparison:
    - If files are identical: **deletes the duplicate**
    - If suffixed file is newer: **backs up the older file** (adds `.bak` extension) and **renames the newer file** to the base name
    - If base file is newer: **skips processing** (no action needed)

## Features

- ✅ **Recursive directory processing**
- ✅ **Automatic computer name detection** (uses `COMPUTERNAME` environment variable)
- ✅ **Custom suffix support** (override default computer name)
- ✅ **Safe processing** with backup creation (`.bak` files)
- ✅ **Access permission handling** (gracefully skips inaccessible files)
- ✅ **Real-time progress indication** with spinner
- ✅ **Detailed processing statistics**
- ✅ **Content comparison** for identical files
- ✅ **UTF-8 console output support**

## Installation

### Download Pre-built Binary (Recommended)

1. Go to the [GitHub Releases page](https://github.com/alezhu/OneDriveDupFixer/releases)
2. Download the latest `OneDriveDupFixer-*.zip` file
3. Extract the archive to a folder of your choice
4. The executable `OneDriveDupFixer.exe` is ready to use

### Building from Source

If you prefer to build from source:

#### Prerequisites
- [Zig](https://ziglang.org/) compiler (tested with Zig 0.14+)
- Windows operating system (uses Windows-specific APIs)

#### Build Steps
1. Clone or download the project
2. Navigate to the project directory
3. Build the executable:

```bash
zig build -Doptimize=ReleaseFast
```

The executable will be created in `zig-out/bin/OneDriveDupFixer.exe`

## Usage

### Basic Usage

```bash
OneDriveDupFixer.exe <folder_path>
```

This will process the specified folder using your computer name as the suffix.

### Custom Suffix

```bash
OneDriveDupFixer.exe --suffix <suffix> <folder_path>
OneDriveDupFixer.exe -s <suffix> <folder_path>
```

Use a custom suffix instead of the computer name.

### Examples

```bash
# Process Documents folder using computer name
OneDriveDupFixer.exe "C:\Users\Username\Documents"

# Process with custom suffix
OneDriveDupFixer.exe --suffix "-LAPTOP" "C:\Users\Username\Documents"

# Process current directory
OneDriveDupFixer.exe .
```

## How It Works

### File Processing Logic

1. **Discovery**: Scans directories for files with and without the specified suffix
2. **Pairing**: Matches base files with their suffixed counterparts
3. **Comparison**: Compares modification times and file content
4. **Action**: Takes appropriate action based on comparison results

### Processing Actions

| Scenario | Action |
|----------|--------|
| Files are identical (same content) | Delete suffixed file |
| Suffixed file is newer | Backup base file → Rename suffixed file |
| Base file is newer or equal | Skip (no action) |

### Example Scenario

**Before:**
```
document.docx          (modified: 2024-01-01 10:00, older version)
document-MYPC.docx     (modified: 2024-01-01 15:30, newer version)
```

**After:**
```
document.docx          (the newer version, renamed from document-MYPC.docx)
document.docx.bak      (the older version, backed up)
```

## Output Information

The tool provides detailed information during processing:

- **Progress indicator**: Shows current directory being processed
- **Action logs**: Details each file operation performed
- **Access denied notifications**: Lists files/folders that couldn't be accessed
- **Final statistics**: Summary of all operations performed

### Sample Output

```
OneDriveDupFixer: v1.0.0
Processing folder: C:\Users\Username\Documents
Using suffix: -MYPC
Starting processing...

[|] Processing: C:\Users\Username\Documents\Projects
Backed up: C:\Users\Username\Documents\report.docx -> C:\Users\Username\Documents\report.docx.bak
Renamed: C:\Users\Username\Documents\report-MYPC.docx -> C:\Users\Username\Documents\report.docx
Deleted: C:\Users\Username\Documents\photo-MYPC.jpg
Processing completed.

=== Processing Results ===
File pairs processed: 15
Files backed up (.bak): 8
Files renamed: 8
Errors encountered: 0
Files deleted: 7
Access denied (skipped): 2
```

## Safety Features

- **Backup creation**: Original files are backed up with `.bak` extension before modification
- **Access control**: Gracefully handles permission-denied scenarios
- **Content verification**: Compares file contents before deletion
- **Non-destructive**: Only processes files that have clear version relationships

## Limitations

- **Windows only**: Uses Windows-specific APIs
- **OneDrive-specific**: Designed for OneDrive synchronization conflicts
- **Suffix matching**: Requires files to follow the `filename-SUFFIX.ext` pattern
- **Single suffix**: Processes only one suffix type per execution

## Troubleshooting

### Common Issues

**"Access denied" errors**:
- Run as administrator if processing system folders
- Ensure files aren't open in other applications
- Check folder permissions

**No computer name detected**:
- Manually specify suffix with `--suffix` parameter
- Verify `COMPUTERNAME` environment variable is set

**Files not being processed**:
- Ensure files follow the expected naming pattern
- Check that both base and suffixed files exist in the same directory
- Verify file permissions


## License

This project is provided as-is. Use at your own risk and always backup important data before running bulk file operations.

## Disclaimer

⚠️ **Always backup your important files before running this tool.** While the tool creates `.bak` files as safeguards, it's recommended to have a separate backup of critical data.

The tool is designed to be safe, but file operations always carry inherent risks. Test on a small set of files first to ensure it works as expected for your specific use case.
