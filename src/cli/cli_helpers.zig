// CLI-only helpers: use pig lib + zli (not part of the lib module).
const std = @import("std");
const zli = @import("zli");
const pig = @import("pig");
const utils = pig.utils;
const logger = pig.logger;

pub const ReadImageFromCmdResult = struct {
    image: pig.vips.VipsImage,
    filename: []const u8,
    size_bytes: u64,
};

pub fn readImageFromCmd(ctx: zli.CommandContext) ?ReadImageFromCmdResult {
    const stdin_buffer = utils.readStdinBuffer(ctx.allocator) catch null;
    defer if (stdin_buffer) |buf| ctx.allocator.free(buf);

    var image: pig.vips.VipsImage = undefined;
    var filename: []const u8 = undefined;
    var size_bytes: u64 = 0;

    if (stdin_buffer) |buffer| {
        filename = "<stdin>";
        size_bytes = buffer.len;
        image = utils.loadImageFromBuffer(buffer) catch |err| {
            switch (err) {
                pig.vips.VipsError.LoadFailed => logger.err("Cannot load image from stdin", .{}),
                pig.vips.VipsError.OutOfMemory => logger.err("Out of memory", .{}),
                else => logger.err("Failed to load image: {}", .{err}),
            }
            return null;
        };
    } else {
        const file = ctx.getArg("file") orelse {
            logger.err("No input provided. Specify a file or pipe image data to stdin.", .{});
            ctx.command.printHelp() catch return null;
            return null;
        };
        filename = file;

        if (std.fs.cwd().statFile(filename)) |file_stat| {
            size_bytes = file_stat.size;
        } else |err| {
            logger.warn("Cannot get file size: {}", .{err});
            size_bytes = 0;
        }

        image = utils.loadImage(ctx.allocator, file) catch |err| {
            switch (err) {
                utils.LoadError.LoadFailed => logger.err("Cannot load image file '{s}'", .{file}),
                utils.LoadError.OutOfMemory => logger.err("Out of memory", .{}),
                else => logger.err("Failed to load image: {}", .{err}),
            }
            return null;
        };
    }

    return ReadImageFromCmdResult{
        .image = image,
        .filename = filename,
        .size_bytes = size_bytes,
    };
}
