const std = @import("std");
const Writer = std.Io.Writer;
const zli = @import("zli");
const logger = pig.logger;
const pig = @import("pig");
const vips = pig.vips;
const format_options = pig.format_options;

pub fn register(writer: *Writer, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, allocator, .{
        .name = "optimize",
        .description = "Optimize image file for size and quality (format-specific options)",
    }, run);

    try cmd.addFlag(.{
        .name = "palette",
        .description = "PNG: use palette (libimagequant) for smaller size",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });

    try cmd.addFlag(.{
        .name = "q",
        .shortcut = "q",
        .description = "Quality: JPEG 1-100; PNG palette quantisation 1-100",
        .type = .String,
        .default_value = .{ .String = "85" },
    });

    try cmd.addFlag(.{
        .name = "strip",
        .description = "Strip metadata (EXIF, ICC, etc.) to reduce size",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });

    try cmd.addFlag(.{
        .name = "output",
        .shortcut = "o",
        .description = "Output file path (format from extension: .jpg, .png, .webp, .tiff, .gif, .avif, .heic, .jp2, .jxl)",
        .type = .String,
        .default_value = .{ .String = "" },
    });

    try cmd.addFlag(.{
        .name = "json",
        .description = "Output result in JSON format",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });

    try cmd.addPositionalArg(.{
        .name = "file",
        .description = "Input image file",
        .required = true,
    });

    return cmd;
}

fn run(ctx: zli.CommandContext) !void {
    const file = ctx.getArg("file") orelse {
        try ctx.command.printHelp();
        return;
    };

    const palette = ctx.flag("palette", bool);
    const quality_str = ctx.flag("q", []const u8);
    const strip = ctx.flag("strip", bool);
    const output_flag = ctx.flag("output", []const u8);
    const json_output = ctx.flag("json", bool);

    const quality = std.fmt.parseInt(i32, quality_str, 10) catch 85;
    if (quality < 1 or quality > 100) {
        logger.err("Quality must be 1-100, got {s}", .{quality_str});
        return;
    }

    if (output_flag.len == 0) {
        logger.err("optimize requires -o/--output (output path). Format is inferred from extension.", .{});
        try ctx.command.printHelp();
        return;
    }

    vips.init() catch |err| {
        logger.err("Failed to initialize libvips: {}", .{err});
        return;
    };

    var image = vips.loadImageFromFile(ctx.allocator, file) catch |err| {
        logger.err("Failed to load image '{s}': {}", .{ file, err });
        return;
    };
    defer image.deinit();

    const ext = format_options.extensionFromPath(output_flag) orelse {
        logger.err("Output path has no extension: {s}. Use .jpg, .png, .webp, .tiff, .gif, .avif, .heic, .jp2, .jxl", .{output_flag});
        return;
    };
    const save_format = format_options.SaveFormat.fromExtension(ext) orelse {
        logger.err("Unsupported output format: {s}. Use .jpg, .png, .webp, .tiff, .gif, .avif, .heic, .jp2, .jxl", .{ext});
        return;
    };

    switch (save_format) {
        .jpeg => {
            vips.saveImageToFileJpeg(ctx.allocator, &image, output_flag, .{
                .q = quality,
                .strip = strip,
            }) catch |err| {
                logger.err("Failed to save JPEG: {}", .{err});
                return;
            };
        },
        .png => {
            vips.saveImageToFilePng(ctx.allocator, &image, output_flag, .{
                .compression = 6,
                .palette = palette,
                .q = quality,
                .strip = strip,
            }) catch |err| {
                logger.err("Failed to save PNG: {}", .{err});
                return;
            };
        },
        .webp => {
            vips.saveImageToFileWebp(ctx.allocator, &image, output_flag, .{
                .q = quality,
                .strip = strip,
                .lossless = false,
            }) catch |err| {
                logger.err("Failed to save WebP: {}", .{err});
                return;
            };
        },
        .tiff => {
            vips.saveImageToFileTiff(ctx.allocator, &image, output_flag, .{
                .compression = .deflate,
                .q = quality,
                .strip = strip,
            }) catch |err| {
                logger.err("Failed to save TIFF: {}", .{err});
                return;
            };
        },
        .gif => {
            vips.saveImageToFileGif(ctx.allocator, &image, output_flag, .{
                .dither = 1.0,
                .effort = 7,
                .bitdepth = 8,
                .interlace = false,
            }) catch |err| {
                logger.err("Failed to save GIF: {}", .{err});
                return;
            };
        },
        .heif => {
            vips.saveImageToFileHeif(ctx.allocator, &image, output_flag, .{
                .q = quality,
                .lossless = false,
                .compression = .av1,
            }) catch |err| {
                logger.err("Failed to save HEIF/AVIF (need libvips with libheif): {}", .{err});
                return;
            };
        },
        .jp2k => {
            vips.saveImageToFileJp2k(ctx.allocator, &image, output_flag, .{
                .q = quality,
                .lossless = false,
            }) catch |err| {
                logger.err("Failed to save JPEG 2000 (need libvips with openjp2): {}", .{err});
                return;
            };
        },
        .jxl => {
            vips.saveImageToFileJxl(ctx.allocator, &image, output_flag, .{
                .q = quality,
                .effort = 7,
                .lossless = false,
            }) catch |err| {
                logger.err("Failed to save JPEG XL (need libvips with libjxl): {}", .{err});
                return;
            };
        },
    }

    if (json_output) {
        const result = struct {
            command: []const u8 = "optimize",
            input: []const u8,
            output: []const u8,
            format: []const u8,
            palette: bool,
            quality: i32,
            strip: bool,
            success: bool = true,
        }{
            .input = file,
            .output = output_flag,
            .format = ext,
            .palette = palette,
            .quality = quality,
            .strip = strip,
        };
        logger.json(result, ctx.writer);
    } else {
        try ctx.writer.print("Optimized {s} -> {s} (format: {s}, q: {}, strip: {}, palette: {})\n", .{
            file,
            output_flag,
            ext,
            quality,
            strip,
            palette,
        });
        try ctx.writer.flush();
    }
}
