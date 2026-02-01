const std = @import("std");
const Writer = std.Io.Writer;
const zli = @import("zli");

const version = @import("version.zig");
const optimize = @import("cmd/optimize.zig");
const inspect = @import("cmd/inspect.zig");
const crop = @import("cmd/crop.zig");
const scale = @import("cmd/scale.zig");

pub fn build(writer: *Writer, allocator: std.mem.Allocator) !*zli.Command {
    const root = try zli.Command.init(writer, allocator, .{
        .name = "pig",
        .description = "High-performance image processing toolkit",
    }, showHelp);

    try root.addCommands(&.{
        try optimize.register(writer, allocator),
        try inspect.register(writer, allocator),
        try crop.register(writer, allocator),
        try scale.register(writer, allocator),
        try version.register(writer, allocator),
    });

    return root;
}

fn showHelp(ctx: zli.CommandContext) !void {
    try ctx.command.printHelp();
}
