const std = @import("std");
const Writer = std.Io.Writer;
const zli = @import("zli");
const logger = pig.logger;
const pig = @import("pig");
const vips = pig.vips;
const vips_custom = pig.vips_custom;
const util = pig.utils;

// Struct for JSON output
const CropResult = struct {
    input_file: []const u8,
    output_file: []const u8,
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    original_width: u32,
    original_height: u32,
    success: bool,
};

pub fn register(writer: *Writer, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, allocator, .{
        .name = "crop",
        .description = "Crop an image to specified dimensions",
    }, run);

    try cmd.addFlag(.{
        .name = "json",
        .description = "Output result in JSON format",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });

    try cmd.addFlag(.{
        .name = "input_file",
        .shortcut = "i",
        .description = "Input image file (if not specified, reads from stdin)",
        .type = .String,
        .default_value = .{ .String = "" },
    });

    try cmd.addFlag(.{
        .name = "output",
        .shortcut = "o",
        .description = "Output image file (if not specified, writes to stdout)",
        .type = .String,
        .default_value = .{ .String = "" },
    });

    try cmd.addPositionalArg(.{
        .name = "x",
        .description = "X coordinate of the crop start position",
        .required = true,
    });

    try cmd.addPositionalArg(.{
        .name = "y",
        .description = "Y coordinate of the crop start position",
        .required = true,
    });

    try cmd.addPositionalArg(.{
        .name = "width",
        .description = "Width of the cropped area",
        .required = true,
    });

    try cmd.addPositionalArg(.{
        .name = "height",
        .description = "Height of the cropped area",
        .required = true,
    });

    return cmd;
}

fn run(ctx: zli.CommandContext) !void {
    // Get flags
    const json_output = ctx.flag("json", bool);
    const input_file = ctx.flag("input_file", []const u8);
    const output_flag = ctx.flag("output", []const u8);

    // Get arguments
    const x_str = ctx.getArg("x") orelse {
        logger.err("X coordinate is required", .{});
        try ctx.command.printHelp();
        return;
    };

    const y_str = ctx.getArg("y") orelse {
        logger.err("Y coordinate is required", .{});
        try ctx.command.printHelp();
        return;
    };

    const width_str = ctx.getArg("width") orelse {
        logger.err("Width is required", .{});
        try ctx.command.printHelp();
        return;
    };

    const height_str = ctx.getArg("height") orelse {
        logger.err("Height is required", .{});
        try ctx.command.printHelp();
        return;
    };

    // Parse coordinates and dimensions
    const x = std.fmt.parseInt(i32, x_str, 10) catch {
        logger.err("Invalid x coordinate: {s}", .{x_str});
        return;
    };

    const y = std.fmt.parseInt(i32, y_str, 10) catch {
        logger.err("Invalid y coordinate: {s}", .{y_str});
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

    // Initialize libvips
    vips.init() catch |err| {
        logger.err("Failed to initialize libvips: {}", .{err});
        return;
    };

    var filename: []const u8 = undefined;

    if (input_file.len > 0) {
        // Use file input
        filename = input_file;
        const input_file_handle = std.fs.cwd().openFile(filename, .{}) catch |err| {
            logger.err("Cannot open file '{s}': {}", .{ filename, err });
            return;
        };
        defer input_file_handle.close();

        // Load image directly from file
        var image = vips.loadImageFromFile(ctx.allocator, filename) catch |err| {
            logger.err("Failed to load image '{s}': {}", .{ filename, err });
            return;
        };
        defer image.deinit();

        // Determine output: stdout if no --output flag, file if --output specified
        const should_output_to_stdout = output_flag.len == 0;

        if (should_output_to_stdout) {
            // Crop and write to stdout
            var cropped_image = vips.cropImage(&image, x, y, width, height) catch |err| {
                logger.err("Failed to crop image: {}", .{err});
                return;
            };
            defer cropped_image.deinit();

            vips.saveImageToWriter(ctx.allocator, &cropped_image, ctx.writer, "png") catch |err| {
                logger.err("Failed to write cropped image to stdout: {}", .{err});
                return;
            };

            // Log success to stderr
            if (json_output) {
                const crop_result = CropResult{
                    .input_file = filename,
                    .output_file = "<stdout>",
                    .x = x,
                    .y = y,
                    .width = width,
                    .height = height,
                    .original_width = 0, // Pipeline doesn't give us this easily
                    .original_height = 0,
                    .success = true,
                };
                logger.json(crop_result, null);
            } else {
                logger.info("Successfully cropped {s} to {}x{} from ({}, {}) -> stdout", .{ filename, width, height, x, y });
            }
        } else {
            // Open output file and create file writer
            const output_file_handle = std.fs.cwd().createFile(output_flag, .{}) catch |err| {
                logger.err("Cannot create output file '{s}': {}", .{ output_flag, err });
                return;
            };
            defer output_file_handle.close();
            // Crop and write to file
            var cropped_image2 = vips.cropImage(&image, x, y, width, height) catch |err| {
                logger.err("Failed to crop image: {}", .{err});
                return;
            };
            defer cropped_image2.deinit();

            vips.saveImage(ctx.allocator, &cropped_image2, output_flag) catch |err| {
                logger.err("Failed to save cropped image: {}", .{err});
                return;
            };

            const crop_result = CropResult{
                .input_file = filename,
                .output_file = output_flag,
                .x = x,
                .y = y,
                .width = width,
                .height = height,
                .original_width = 0, // Pipeline doesn't give us this easily
                .original_height = 0,
                .success = true,
            };

            if (json_output) {
                logger.json(crop_result, ctx.writer);
            } else {
                try ctx.writer.print("Successfully cropped {s} to {}x{} from ({}, {})\n", .{ filename, width, height, x, y });
                try ctx.writer.print("Output saved to: {s}\n", .{output_flag});
            }
        }
    } else {
        // Handle stdin input
        filename = "<stdin>";
        const max_stdin_size: usize = 100 * 1024 * 1024;
        const stdin_data = std.fs.File.stdin().readToEndAlloc(ctx.allocator, max_stdin_size) catch {
            logger.err("Failed to read stdin", .{});
            return;
        };
        defer ctx.allocator.free(stdin_data);

        // For stdin, we need to always have an output file specified
        if (output_flag.len == 0) {
            logger.err("When reading from stdin, you must specify an output file with -o", .{});
            try ctx.command.printHelp();
            return;
        }

        const output_file_handle = std.fs.cwd().createFile(output_flag, .{}) catch |err| {
            logger.err("Cannot create output file '{s}': {}", .{ output_flag, err });
            return;
        };
        defer output_file_handle.close();

        // Load image from stdin buffer, crop, and save to file
        var stdin_image = vips.loadImageFromMemory(stdin_data) catch |err| {
            logger.err("Failed to load image from stdin: {}", .{err});
            return;
        };
        defer stdin_image.deinit();

        var cropped_stdin_image = vips.cropImage(&stdin_image, x, y, width, height) catch |err| {
            logger.err("Failed to crop image: {}", .{err});
            return;
        };
        defer cropped_stdin_image.deinit();

        vips.saveImage(ctx.allocator, &cropped_stdin_image, output_flag) catch |err| {
            logger.err("Failed to save cropped image: {}", .{err});
            return;
        };

        const crop_result = CropResult{
            .input_file = filename,
            .output_file = output_flag,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .original_width = 0,
            .original_height = 0,
            .success = true,
        };

        if (json_output) {
            logger.json(crop_result, ctx.writer);
        } else {
            try ctx.writer.print("Successfully cropped {s} to {}x{} from ({}, {})\n", .{ filename, width, height, x, y });
            try ctx.writer.print("Output saved to: {s}\n", .{output_flag});
        }
    }
}
