const std = @import("std");

const LogLevel = enum(u8) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
};

var log_level: LogLevel = .info;
var writer: *std.io.Writer = undefined;

pub fn init(level: LogLevel, w: *std.io.Writer) void {
    log_level = level;
    writer = w;
}

pub fn deinit() void {}

/// Print error to stderr and flush immediately
pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(log_level) <= @intFromEnum(LogLevel.err)) {
        writer.print("Error: " ++ fmt ++ "\n", args) catch return;
    }
}

/// Print warning to stderr and flush immediately
pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(log_level) <= @intFromEnum(LogLevel.warn)) {
        writer.print("Warning: " ++ fmt ++ "\n", args) catch return;
    }
}

/// Print info to stdout and flush immediately
pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(log_level) <= @intFromEnum(LogLevel.info)) {
        writer.print(fmt ++ "\n", args) catch return;
    }
}

/// Print debug to stderr and flush immediately
pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(log_level) <= @intFromEnum(LogLevel.debug)) {
        writer.print("Debug: " ++ fmt ++ "\n", args) catch return;
    }
}

pub fn json(value: anytype, w: ?*std.io.Writer) void {
    std.json.Stringify.value(value, .{
        .whitespace = .indent_2,
    }, w orelse writer) catch return;
}
