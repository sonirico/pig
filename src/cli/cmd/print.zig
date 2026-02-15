const std = @import("std");
const Writer = std.Io.Writer;
const zli = @import("zli");
const pig = @import("pig");
const vips = pig.vips;
const c = vips.c;
const logger = pig.logger;

const Winsize = extern struct {
    row: u16,
    col: u16,
    xpixel: u16,
    ypixel: u16,
};

extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;

pub fn register(writer: *Writer, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, allocator, .{
        .name = "print",
        .description = "Display image in the terminal using Unicode half-block characters",
    }, run);

    try cmd.addPositionalArg(.{
        .name = "file",
        .description = "Input image file (optional if reading from stdin)",
        .required = false,
    });

    try cmd.addFlag(.{
        .name = "kitty",
        .description = "Use Kitty graphics protocol instead of Unicode blocks",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });

    return cmd;
}

fn getTerminalSize() ?Winsize {
    const TIOCGWINSZ: c_ulong = 0x5413;
    var ws: Winsize = std.mem.zeroes(Winsize);
    if (ioctl(1, TIOCGWINSZ, &ws) != 0) return null;
    if (ws.col == 0 or ws.row == 0) return null;
    return ws;
}

fn run(ctx: zli.CommandContext) !void {
    vips.init() catch |err| {
        logger.err("Failed to initialize libvips: {}", .{err});
        return;
    };
    defer vips.shutdown();

    const file = ctx.getArg("file") orelse {
        logger.err("No input provided. Specify a file.", .{});
        ctx.command.printHelp() catch return;
        return;
    };

    const use_kitty = ctx.flag("kitty", bool);

    var image = vips.loadImageFromFile(ctx.allocator, file) catch |err| {
        logger.err("Cannot load image file '{s}': {}", .{ file, err });
        return;
    };
    defer image.deinit();

    const img_w = image.getWidth();
    const img_h = image.getHeight();

    if (use_kitty) {
        // Kitty path: scale to terminal pixel dimensions
        var max_px_w: u32 = img_w;
        var max_px_h: u32 = img_h;

        if (getTerminalSize()) |ws| {
            if (ws.xpixel > 0 and ws.ypixel > 0) {
                max_px_w = ws.xpixel;
                max_px_h = ws.ypixel;
            } else {
                max_px_w = @as(u32, ws.col) * 8;
                max_px_h = @as(u32, ws.row) * 16;
            }
            max_px_w = max_px_w * 9 / 10;
            max_px_h = max_px_h * 9 / 10;
        }

        var display_image = image;
        var scaled = false;
        if (img_w > max_px_w or img_h > max_px_h) {
            const scale_x: f64 = @as(f64, @floatFromInt(max_px_w)) / @as(f64, @floatFromInt(img_w));
            const scale_y: f64 = @as(f64, @floatFromInt(max_px_h)) / @as(f64, @floatFromInt(img_h));
            const scale = @min(scale_x, scale_y);

            display_image = vips.resizeImage(&image, scale, scale) catch |err| {
                logger.err("Failed to scale image for display: {}", .{err});
                return;
            };
            scaled = true;
        }
        defer if (scaled) display_image.deinit();

        var buf: ?*anyopaque = null;
        var buf_len: usize = 0;
        c.vips_error_clear();
        if (c.vips_pngsave_buffer(display_image.handle, &buf, &buf_len, @as(?*anyopaque, null)) != 0) {
            const err_buf = c.vips_error_buffer();
            if (err_buf != null) {
                logger.err("PNG save failed: {s}", .{std.mem.span(err_buf)});
            } else {
                logger.err("Failed to encode image as PNG", .{});
            }
            c.vips_error_clear();
            return;
        }
        defer c.g_free(buf);
        const png_data = @as([*]const u8, @ptrCast(buf.?))[0..buf_len];

        writeKittyGraphics(ctx.writer, png_data) catch {
            logger.err("Failed to write image to terminal", .{});
            return;
        };
    } else {
        // Unicode half-block path: scale to terminal columns
        const ws = getTerminalSize() orelse {
            logger.err("Cannot determine terminal size", .{});
            return;
        };

        const term_cols: u32 = ws.col;
        // Leave 1 row for prompt, 2 pixels per cell row
        const term_rows: u32 = if (ws.row > 1) ws.row - 1 else ws.row;
        const max_pixel_h: u32 = term_rows * 2;

        // Scale to fit terminal: width = term_cols, maintain aspect ratio
        const scale_x: f64 = @as(f64, @floatFromInt(term_cols)) / @as(f64, @floatFromInt(img_w));
        const scale_y: f64 = @as(f64, @floatFromInt(max_pixel_h)) / @as(f64, @floatFromInt(img_h));
        const scale = @min(scale_x, scale_y);

        var display_image = image;
        var scaled = false;
        if (scale < 1.0) {
            display_image = vips.resizeImage(&image, scale, scale) catch |err| {
                logger.err("Failed to scale image for display: {}", .{err});
                return;
            };
            scaled = true;
        } else if (scale_x < scale_y) {
            // Image is narrower than terminal but taller; scale only if needed
            // In this case scale >= 1.0 and we don't upscale
        }
        defer if (scaled) display_image.deinit();

        // Prepare raw RGB pixels
        const prepared = prepareForRender(&display_image) orelse {
            logger.err("Failed to prepare image for rendering", .{});
            return;
        };
        var prep_image = prepared.image;
        defer if (prepared.needs_free) prep_image.deinit();

        const width = prep_image.getWidth();
        const height = prep_image.getHeight();
        const bands: u32 = 3; // After colourspace + flatten, always 3

        // Write to memory to get pixel data
        c.vips_error_clear();
        const data_ptr = c.vips_image_get_data(prep_image.handle);
        if (data_ptr == null) {
            const err_buf = c.vips_error_buffer();
            if (err_buf != null) {
                logger.err("Failed to get pixel data: {s}", .{std.mem.span(err_buf)});
            } else {
                logger.err("Failed to get pixel data", .{});
            }
            c.vips_error_clear();
            return;
        }
        const pixels: [*]const u8 = @ptrCast(data_ptr);
        const stride: u32 = width * bands;

        writeUnicodeBlocks(ctx.writer, pixels, width, height, stride, ctx.allocator) catch {
            logger.err("Failed to write image to terminal", .{});
            return;
        };
    }
}

const PreparedImage = struct {
    image: vips.VipsImage,
    needs_free: bool,
};

/// Convert image to sRGB uint8 with no alpha, suitable for raw pixel access.
fn prepareForRender(image: *const vips.VipsImage) ?PreparedImage {
    var current: *c.VipsImage = image.handle;
    var needs_free = false;

    // Convert to sRGB colourspace
    var srgb: ?*c.VipsImage = null;
    c.vips_error_clear();
    if (c.vips_colourspace(current, &srgb, c.VIPS_INTERPRETATION_sRGB, @as(?*anyopaque, null)) != 0) {
        return null;
    }
    if (needs_free) c.g_object_unref(current);
    current = srgb.?;
    needs_free = true;

    // Flatten alpha if present (bands > 3)
    if (c.vips_image_get_bands(current) > 3) {
        var flat: ?*c.VipsImage = null;
        c.vips_error_clear();
        if (c.vips_flatten(current, &flat, @as(?*anyopaque, null)) != 0) {
            c.g_object_unref(current);
            return null;
        }
        c.g_object_unref(current);
        current = flat.?;
    }

    // Cast to uint8
    if (c.vips_image_get_format(current) != c.VIPS_FORMAT_UCHAR) {
        var cast: ?*c.VipsImage = null;
        c.vips_error_clear();
        if (c.vips_cast(current, &cast, c.VIPS_FORMAT_UCHAR, @as(?*anyopaque, null)) != 0) {
            c.g_object_unref(current);
            return null;
        }
        c.g_object_unref(current);
        current = cast.?;
    }

    return PreparedImage{
        .image = vips.VipsImage{ .handle = current },
        .needs_free = needs_free,
    };
}

/// Write a u8 as decimal digits directly into buf. Returns number of bytes written (1-3).
inline fn writeU8Dec(buf: []u8, val: u8) usize {
    if (val >= 100) {
        buf[0] = '0' + val / 100;
        buf[1] = '0' + (val / 10) % 10;
        buf[2] = '0' + val % 10;
        return 3;
    } else if (val >= 10) {
        buf[0] = '0' + val / 10;
        buf[1] = '0' + val % 10;
        return 2;
    } else {
        buf[0] = '0' + val;
        return 1;
    }
}

/// Write "\x1b[38;2;R;G;Bm" into buf. Returns bytes written.
inline fn writeFgEsc(buf: []u8, r: u8, g: u8, b: u8) usize {
    const prefix = "\x1b[38;2;";
    @memcpy(buf[0..prefix.len], prefix);
    var pos: usize = prefix.len;
    pos += writeU8Dec(buf[pos..], r);
    buf[pos] = ';';
    pos += 1;
    pos += writeU8Dec(buf[pos..], g);
    buf[pos] = ';';
    pos += 1;
    pos += writeU8Dec(buf[pos..], b);
    buf[pos] = 'm';
    pos += 1;
    return pos;
}

/// Write "\x1b[48;2;R;G;Bm" into buf. Returns bytes written.
inline fn writeBgEsc(buf: []u8, r: u8, g: u8, b: u8) usize {
    const prefix = "\x1b[48;2;";
    @memcpy(buf[0..prefix.len], prefix);
    var pos: usize = prefix.len;
    pos += writeU8Dec(buf[pos..], r);
    buf[pos] = ';';
    pos += 1;
    pos += writeU8Dec(buf[pos..], g);
    buf[pos] = ';';
    pos += 1;
    pos += writeU8Dec(buf[pos..], b);
    buf[pos] = 'm';
    pos += 1;
    return pos;
}

fn writeUnicodeBlocks(writer: *Writer, pixels: [*]const u8, width: u32, height: u32, stride: u32, allocator: std.mem.Allocator) !void {
    // Max bytes per pixel: fg(~19) + bg(~19) + ▀(3) = 41; plus reset(4) + newline(1) per row
    const max_per_pixel = 42;
    const row_buf = try allocator.alloc(u8, @as(usize, width) * max_per_pixel + 8);
    defer allocator.free(row_buf);

    var y: u32 = 0;
    while (y < height) : (y += 2) {
        var pos: usize = 0;
        const has_bottom = (y + 1 < height);

        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const top_off: usize = @as(usize, y) * stride + @as(usize, x) * 3;
            pos += writeFgEsc(row_buf[pos..], pixels[top_off], pixels[top_off + 1], pixels[top_off + 2]);

            if (has_bottom) {
                const bot_off: usize = @as(usize, y + 1) * stride + @as(usize, x) * 3;
                pos += writeBgEsc(row_buf[pos..], pixels[bot_off], pixels[bot_off + 1], pixels[bot_off + 2]);
            }

            // ▀ (U+2580) = 0xe2 0x96 0x80
            row_buf[pos] = 0xe2;
            row_buf[pos + 1] = 0x96;
            row_buf[pos + 2] = 0x80;
            pos += 3;
        }

        // Reset + newline
        const reset = "\x1b[0m\n";
        @memcpy(row_buf[pos .. pos + reset.len], reset);
        pos += reset.len;

        // Flush the entire row in one write
        try writer.writeAll(row_buf[0..pos]);
    }
}

fn writeKittyGraphics(writer: *Writer, png_data: []const u8) !void {
    const raw_chunk_size: usize = 3072;
    var offset: usize = 0;
    var first = true;

    while (offset < png_data.len) {
        const remaining = png_data.len - offset;
        const raw_len = @min(remaining, raw_chunk_size);
        const is_last = (offset + raw_len >= png_data.len);
        const chunk = png_data[offset .. offset + raw_len];

        const encoded_len = std.base64.standard.Encoder.calcSize(raw_len);
        var b64_buf: [4096]u8 = undefined;
        const encoded = std.base64.standard.Encoder.encode(b64_buf[0..encoded_len], chunk);

        if (first) {
            if (is_last) {
                try writer.writeAll("\x1b_Ga=T,f=100;");
            } else {
                try writer.writeAll("\x1b_Ga=T,f=100,m=1;");
            }
            first = false;
        } else {
            if (is_last) {
                try writer.writeAll("\x1b_Gm=0;");
            } else {
                try writer.writeAll("\x1b_Gm=1;");
            }
        }

        try writer.writeAll(encoded);
        try writer.writeAll("\x1b\\");

        offset += raw_len;
    }

    try writer.writeAll("\n");
}
