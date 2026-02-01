const std = @import("std");
const Writer = std.io.Writer;
const zli = @import("zli");
const pig = @import("pig");
const logger = pig.logger;

pub fn register(writer: *Writer, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, allocator, .{
        .name = "scale",
        .description = "Scale image to specified dimensions",
    }, run);

    try cmd.addFlag(.{
        .name = "json",
        .description = "Output in JSON format",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });

    try cmd.addFlag(.{
        .name = "keep-aspect",
        .description = "Maintain aspect ratio",
        .type = .Bool,
        .default_value = .{ .Bool = true },
    });

    try cmd.addFlag(.{
        .name = "interpolation",
        .description = "Interpolation method (nearest, linear, cubic, lanczos)",
        .type = .String,
        .default_value = .{ .String = "lanczos" },
    });

    try cmd.addPositionalArg(.{
        .name = "file",
        .description = "Input image file",
        .required = true,
    });

    try cmd.addPositionalArg(.{
        .name = "width",
        .description = "Target width",
        .required = true,
    });

    try cmd.addPositionalArg(.{
        .name = "height",
        .description = "Target height",
        .required = true,
    });

    return cmd;
}

fn run(ctx: zli.CommandContext) !void {
    const file = ctx.getArg("file") orelse {
        try ctx.command.printHelp();
        return;
    };

    const width_str = ctx.getArg("width") orelse {
        try ctx.command.printHelp();
        return;
    };

    const height_str = ctx.getArg("height") orelse {
        try ctx.command.printHelp();
        return;
    };

    const width = std.fmt.parseInt(u32, width_str, 10) catch {
        logger.err("Invalid width: {s}", .{width_str});
        return;
    };

    const height = std.fmt.parseInt(u32, height_str, 10) catch {
        logger.err("Invalid height: {s}", .{height_str});
        return;
    };

    const json_output = ctx.flag("json", bool);
    const keep_aspect = ctx.flag("keep-aspect", bool);
    const interpolation = ctx.flag("interpolation", []const u8);

    if (json_output) {
        try ctx.writer.print("{{\"command\":\"scale\",\"file\":\"{s}\",\"width\":{},\"height\":{}}}\n", .{ file, width, height });
        try ctx.writer.flush();
    } else {
        try ctx.writer.print("Scaling {s} to {}x{}\n", .{ file, width, height });
        try ctx.writer.print("  Keep aspect ratio: {}\n", .{keep_aspect});
        try ctx.writer.print("  Interpolation: {s}\n", .{interpolation});
        try ctx.writer.flush();

        // IMPLEMENTATION PLACEHOLDER: Real libvips scaling logic
        // 1. Load image with vips_image_new_from_file()
        // 2. Calculate target dimensions respecting aspect ratio if enabled
        // 3. Choose interpolation kernel based on method parameter
        // 4. Resize with vips_resize() or vips_thumbnail() for optimal performance
        // 5. Apply appropriate sharpening for downscaling operations
        // 6. Save scaled image with vips_image_write_to_file()
        // 7. Report original vs final dimensions and scaling factor
    }
}
