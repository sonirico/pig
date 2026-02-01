// Integration test runner: snapshot-based regression tests for pig CLI.
// Runs pig with fixed params, captures output (inspect --json + file size), compares to
// tests/snapshots/expected.json. No regression: dimensions must match, size must not exceed snapshot.
// If results improve (smaller size) or new case: run with --update to refresh snapshots.
// No bash: all logic in Zig.

const std = @import("std");

const SnapshotCase = struct {
    width: u32,
    height: u32,
    size_bytes: u64,
};

const InspectOutput = struct {
    width: u32 = 0,
    height: u32 = 0,
    size_bytes: u64 = 0,
};

const TestCase = struct {
    id: []const u8,
    argv: []const []const u8,
    output_file: []const u8,
};

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    const stdout = child.stdout orelse return error.NoStdout;
    const result = stdout.readToEndAlloc(allocator, 1024 * 1024) catch return error.ReadFail;
    _ = child.wait() catch {};
    return result;
}

fn runPigInspect(allocator: std.mem.Allocator, pig_path: []const u8, cwd: []const u8, file_path: []const u8) !InspectOutput {
    const full_path = try std.fs.path.join(allocator, &.{ cwd, file_path });
    defer allocator.free(full_path);
    const argv = [_][]const u8{ pig_path, "inspect", "--json", full_path };
    const out = try runCommand(allocator, &argv);
    defer allocator.free(out);
    return parseInspectJson(allocator, out);
}

fn parseInspectJson(allocator: std.mem.Allocator, json_slice: []const u8) !InspectOutput {
    const trimmed = std.mem.trim(u8, json_slice, &std.ascii.whitespace);
    const parsed = std.json.parseFromSlice(InspectOutput, allocator, trimmed, .{
        .ignore_unknown_fields = true,
    }) catch return error.ParseJson;
    defer parsed.deinit();
    return parsed.value;
}

fn getFileSize(cwd: []const u8, file_path: []const u8) !u64 {
    const full = try std.fs.path.join(std.heap.page_allocator, &.{ cwd, file_path });
    defer std.heap.page_allocator.free(full);
    const stat = try std.fs.cwd().statFile(full);
    return stat.size;
}

fn loadSnapshot(allocator: std.mem.Allocator, path: []const u8) !std.StringHashMap(SnapshotCase) {
    var map = std.StringHashMap(SnapshotCase).init(allocator);
    const file = std.fs.cwd().openFile(path, .{}) catch return map;
    defer file.close();
    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch return map;
    defer allocator.free(content);
    var parsed = std.json.parseFromSlice(struct { cases: std.json.Value }, allocator, content, .{ .ignore_unknown_fields = true }) catch return map;
    defer parsed.deinit();
    const cases_val = parsed.value.cases;
    if (cases_val != .object) return map;
    var it = cases_val.object.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        if (val != .object) continue;
        const obj = val.object;
        const width_val = obj.get("width") orelse continue;
        const height_val = obj.get("height") orelse continue;
        const size_val = obj.get("size_bytes") orelse continue;
        if (width_val != .integer or height_val != .integer or size_val != .integer) continue;
        const width = width_val.integer;
        const height = height_val.integer;
        const size_bytes = size_val.integer;
        const key_dup = try allocator.dupe(u8, entry.key_ptr.*);
        try map.put(key_dup, .{
            .width = @intCast(width),
            .height = @intCast(height),
            .size_bytes = @intCast(size_bytes),
        });
    }
    return map;
}

fn writeSnapshot(allocator: std.mem.Allocator, path: []const u8, snapshot: std.StringHashMap(SnapshotCase)) !void {
    _ = allocator;
    const dir_path = std.fs.path.dirname(path) orelse ".";
    std.fs.cwd().makePath(dir_path) catch {};
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();
    try w.print("{{\n  \"cases\": {{\n", .{});
    var it = snapshot.iterator();
    var first = true;
    while (it.next()) |entry| {
        if (!first) try w.print(",\n", .{});
        first = false;
        try w.print("    \"{s}\": {{ \"width\": {}, \"height\": {}, \"size_bytes\": {} }}", .{
            entry.key_ptr.*,
            entry.value_ptr.width,
            entry.value_ptr.height,
            entry.value_ptr.size_bytes,
        });
    }
    try w.print("\n  }}\n}}\n", .{});
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(fbs.getWritten());
}

fn getCwd(allocator: std.mem.Allocator) ![]const u8 {
    return std.process.getCwdAlloc(allocator) catch return error.NoCwd;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var update_snapshots = false;
    var pig_path: []const u8 = "zig-out/bin/pig";
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    var i: usize = 1;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "--update")) {
            update_snapshots = true;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--pig") and i + 1 < args.len) {
            pig_path = args[i + 1];
            i += 2;
        } else {
            i += 1;
        }
    }

    const cwd = try getCwd(allocator);
    defer allocator.free(cwd);

    const out_dir = "tests/out";
    std.fs.cwd().makePath(out_dir) catch {};

    const cases = [_]TestCase{
        .{ .id = "optimize:sample_5x5.png->optimized.png:q80:strip", .argv = &.{ pig_path, "optimize", "tests/fixtures/sample_5x5.png", "-o", "tests/out/optimized.png", "-q", "80", "--strip" }, .output_file = "tests/out/optimized.png" },
        .{ .id = "optimize:sample_5x5.png->optimized.jpg:q85:strip", .argv = &.{ pig_path, "optimize", "tests/fixtures/sample_5x5.png", "-o", "tests/out/optimized.jpg", "-q", "85", "--strip" }, .output_file = "tests/out/optimized.jpg" },
        .{ .id = "optimize:sample_5x5.png->optimized.webp:q80:strip", .argv = &.{ pig_path, "optimize", "tests/fixtures/sample_5x5.png", "-o", "tests/out/optimized.webp", "-q", "80", "--strip" }, .output_file = "tests/out/optimized.webp" },
        .{ .id = "optimize:sample_5x5.png->optimized.tiff:q75:strip", .argv = &.{ pig_path, "optimize", "tests/fixtures/sample_5x5.png", "-o", "tests/out/optimized.tiff", "-q", "75", "--strip" }, .output_file = "tests/out/optimized.tiff" },
        .{ .id = "optimize:sample_5x5.png->optimized.gif:q80", .argv = &.{ pig_path, "optimize", "tests/fixtures/sample_5x5.png", "-o", "tests/out/optimized.gif", "-q", "80" }, .output_file = "tests/out/optimized.gif" },
        .{ .id = "crop:sample_5x5.png->crop_2x2.png:1:1:2:2", .argv = &.{ pig_path, "crop", "-i", "tests/fixtures/sample_5x5.png", "-o", "tests/out/crop_2x2.png", "1", "1", "2", "2" }, .output_file = "tests/out/crop_2x2.png" },
    };

    const snapshot_path = "tests/snapshots/expected.json";
    var snapshot = loadSnapshot(allocator, snapshot_path) catch std.StringHashMap(SnapshotCase).init(allocator);
    defer {
        var it = snapshot.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        snapshot.deinit();
    }
    var updated = false;
    var failed = false;

    for (cases) |tc| {
        var proc = std.process.Child.init(tc.argv, allocator);
        proc.stdin_behavior = .Ignore;
        proc.stdout_behavior = .Ignore;
        proc.stderr_behavior = .Pipe;
        proc.spawn() catch {
            std.debug.print("integration: failed to run pig for case {s}\n", .{tc.id});
            failed = true;
            continue;
        };
        const term = proc.wait() catch {
            std.debug.print("integration: pig failed for case {s}\n", .{tc.id});
            failed = true;
            continue;
        };
        switch (term) {
            .Exited => |code| if (code != 0) {
                std.debug.print("integration: pig exited {} for case {s}\n", .{ code, tc.id });
                failed = true;
                continue;
            },
            else => {
                std.debug.print("integration: pig failed for case {s}\n", .{tc.id});
                failed = true;
                continue;
            },
        }

        const size_bytes = getFileSize(cwd, tc.output_file) catch {
            std.debug.print("integration: missing output file for case {s}\n", .{tc.id});
            failed = true;
            continue;
        };
        const inspect_out = runPigInspect(allocator, pig_path, cwd, tc.output_file) catch {
            std.debug.print("integration: inspect failed for case {s}\n", .{tc.id});
            failed = true;
            continue;
        };

        const existing = snapshot.getPtr(tc.id);
        if (existing) |prev| {
            if (inspect_out.width != prev.width or inspect_out.height != prev.height) {
                std.debug.print("integration: dimension mismatch for {s}: got {}x{}, snapshot {}x{}\n", .{ tc.id, inspect_out.width, inspect_out.height, prev.width, prev.height });
                failed = true;
                continue;
            }
            if (size_bytes > prev.size_bytes) {
                std.debug.print("integration: size regression for {s}: got {} bytes, snapshot {} bytes\n", .{ tc.id, size_bytes, prev.size_bytes });
                failed = true;
                continue;
            }
            if (update_snapshots and size_bytes < prev.size_bytes) {
                prev.size_bytes = size_bytes;
                updated = true;
            }
        } else {
            if (!update_snapshots) {
                std.debug.print("integration: new case {s} (run with --update to add snapshot): {}x{} {} bytes\n", .{ tc.id, inspect_out.width, inspect_out.height, size_bytes });
                failed = true;
                continue;
            }
            const id_dup = try allocator.dupe(u8, tc.id);
            try snapshot.put(id_dup, .{
                .width = inspect_out.width,
                .height = inspect_out.height,
                .size_bytes = size_bytes,
            });
            updated = true;
        }
    }

    if (updated) {
        writeSnapshot(allocator, snapshot_path, snapshot) catch {
            std.debug.print("integration: failed to write snapshot\n", .{});
            failed = true;
        };
    }

    if (failed) {
        std.process.exit(1);
    }
}
