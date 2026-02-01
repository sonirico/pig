const std = @import("std");
const vips = @import("vips.zig");

// Context structures for custom source/target callbacks
const SourceContext = struct {
    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    position: usize,
    eof_reached: bool,
};

const TargetContext = struct {
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
};

// Callback function for reading from custom source
fn sourceReadCallback(source: [*c]vips.c.VipsSourceCustom, buffer: ?*anyopaque, length: i64) callconv(.c) i64 {
    if (buffer == null or length <= 0 or source == null) return -1;

    // Get context from source user data
    const ctx_ptr = vips.c.g_object_get_data(@ptrCast(source), "zig_context");
    if (ctx_ptr == null) return -1;

    const ctx = @as(*SourceContext, @ptrCast(@alignCast(ctx_ptr)));

    if (ctx.eof_reached) return 0;

    // Read from the reader into our buffer
    const read_buffer = @as([*]u8, @ptrCast(buffer.?))[0..@intCast(length)];
    const bytes_read = ctx.reader.readAll(read_buffer) catch return -1;

    if (bytes_read == 0) {
        ctx.eof_reached = true;
        return 0;
    }

    return @intCast(bytes_read);
}

// Callback function for writing to custom target
fn targetWriteCallback(target: [*c]vips.c.VipsTargetCustom, buffer: ?*const anyopaque, length: i64) callconv(.c) i64 {
    if (buffer == null or length <= 0 or target == null) return -1;

    // Get context from target user data
    const ctx_ptr = vips.c.g_object_get_data(@ptrCast(target), "zig_context");
    if (ctx_ptr == null) return -1;

    const ctx = @as(*TargetContext, @ptrCast(@alignCast(ctx_ptr)));
    const data = @as([*]const u8, @ptrCast(buffer.?))[0..@intCast(length)];

    ctx.writer.writeAll(data) catch return -1;

    return length;
}

// Wrapper for custom source that manages lifecycle
pub const CustomSource = struct {
    source: [*c]vips.c.VipsSourceCustom,
    context: SourceContext,

    pub fn init(reader: *std.Io.Reader, allocator: std.mem.Allocator) vips.VipsError!CustomSource {
        const source = vips.c.vips_source_custom_new();
        if (source == null) {
            return vips.VipsError.LoadFailed;
        }

        var result = CustomSource{
            .source = source.?,
            .context = SourceContext{
                .reader = reader,
                .allocator = allocator,
                .buffer = std.ArrayList(u8).init(allocator),
                .position = 0,
                .eof_reached = false,
            },
        };

        // Store context in the GObject user data
        vips.c.g_object_set_data(@ptrCast(source), "zig_context", &result.context);

        // Set the read callback: instance pointer is GTypeInstance* (same address in GObject)
        const inst = @as(*vips.c.GTypeInstance, @ptrCast(source.?));
        const source_class = @as([*c]vips.c.VipsSourceCustomClass, @ptrCast(inst.g_class));
        source_class.*.read = sourceReadCallback;

        return result;
    }

    pub fn deinit(self: *CustomSource) void {
        self.context.buffer.deinit();
        vips.c.g_object_unref(self.source);
    }

    pub fn getVipsSource(self: *CustomSource) [*c]vips.c.VipsSource {
        return @ptrCast(self.source);
    }
};

// Wrapper for custom target that manages lifecycle
pub const CustomTarget = struct {
    target: [*c]vips.c.VipsTargetCustom,
    context: TargetContext,

    pub fn init(writer: *std.Io.Writer, allocator: std.mem.Allocator) vips.VipsError!CustomTarget {
        const target = vips.c.vips_target_custom_new();
        if (target == null) {
            return vips.VipsError.SaveFailed;
        }

        var result = CustomTarget{
            .target = target.?,
            .context = TargetContext{
                .writer = writer,
                .allocator = allocator,
            },
        };

        // Store context in the GObject user data
        vips.c.g_object_set_data(@ptrCast(target), "zig_context", &result.context);

        // Set the write callback: instance pointer is GTypeInstance* (same address in GObject)
        const inst = @as(*vips.c.GTypeInstance, @ptrCast(target.?));
        const target_class = @as([*c]vips.c.VipsTargetCustomClass, @ptrCast(inst.g_class));
        target_class.*.write = targetWriteCallback;

        return result;
    }

    pub fn deinit(self: *CustomTarget) void {
        vips.c.g_object_unref(self.target);
    }

    pub fn getVipsTarget(self: *CustomTarget) [*c]vips.c.VipsTarget {
        return @ptrCast(self.target);
    }

    pub fn getData(self: *const CustomTarget) []const u8 {
        // No data to return - writes directly to writer
        _ = self;
        return &[_]u8{};
    }

    pub fn takeData(self: *CustomTarget) []u8 {
        // No data to take - writes directly to writer
        _ = self;
        return &[_]u8{};
    }
};

// High-level functions following Go pattern exactly with real readers/writers
pub fn newSourceFromReader(reader: *std.Io.Reader, allocator: std.mem.Allocator) vips.VipsError!CustomSource {
    return CustomSource.init(reader, allocator);
}

pub fn newTargetToWriter(writer: *std.Io.Writer, allocator: std.mem.Allocator) vips.VipsError!CustomTarget {
    return CustomTarget.init(writer, allocator);
}

pub fn imageFromSource(source: *vips.c.VipsSource) vips.VipsError!vips.VipsImage {
    const image = vips.c.vips_image_new_from_source(source, "", @as(?*anyopaque, null));
    if (image == null) {
        return vips.VipsError.LoadFailed;
    }
    return vips.VipsImage{ .handle = image.? };
}

pub fn imageWriteToTarget(image: *const vips.VipsImage, target: *vips.c.VipsTarget, format: []const u8) vips.VipsError!void {
    if (std.mem.eql(u8, format, "png")) {
        if (vips.c.vips_image_write_to_target(image.handle, ".png", target, @as(?*anyopaque, null)) != 0) {
            return vips.VipsError.SaveFailed;
        }
    } else if (std.mem.eql(u8, format, "webp")) {
        try webpSaveToTarget(image, target, WebpSaveOpts{});
    } else {
        if (vips.c.vips_image_write_to_target(image.handle, ".jpg", target, @as(?*anyopaque, null)) != 0) {
            return vips.VipsError.SaveFailed;
        }
    }
}

/// Save options for JPEG (subset used by optimize and API).
pub const JpegSaveOpts = struct {
    q: i32 = 85,
    strip: bool = false,
};

/// Save options for PNG (subset used by optimize and API).
pub const PngSaveOpts = struct {
    compression: i32 = 6,
    palette: bool = false,
    q: i32 = 80,
    strip: bool = false,
};

/// Save options for WebP (aligned with libvips webpsave: Q, lossless, strip via profile).
pub const WebpSaveOpts = struct {
    q: i32 = 80,
    strip: bool = false,
    lossless: bool = false,
};

/// TIFF compression: matches VipsForeignTiffCompression (0=none, 1=jpeg, 2=deflate, ...).
pub const TiffCompression = enum(i32) {
    none = 0,
    jpeg = 1,
    deflate = 2,
    packbits = 3,
    ccittfax4 = 4,
    lzw = 5,
    webp = 6,
    zstd = 7,
    jp2k = 8,
};

/// Save options for TIFF (aligned with libvips tiffsave: compression, Q, strip).
pub const TiffSaveOpts = struct {
    compression: TiffCompression = .none,
    q: i32 = 75,
    strip: bool = false,
};

/// Save options for GIF (aligned with libvips cgifsave: dither, effort, bitdepth, interlace).
pub const GifSaveOpts = struct {
    dither: f64 = 1.0,
    effort: i32 = 7,
    bitdepth: i32 = 8,
    interlace: bool = false,
};

/// HEIF compression: matches VipsForeignHeifCompression (0=HEVC, 1=AVC, 2=JPEG, 3=AV1).
pub const HeifCompression = enum(i32) {
    hevc = 0,
    avc = 1,
    jpeg = 2,
    av1 = 3,
};

/// Save options for HEIF/AVIF (aligned with libvips heifsave: Q, lossless, compression).
pub const HeifSaveOpts = struct {
    q: i32 = 80,
    lossless: bool = false,
    compression: HeifCompression = .av1,
};

/// Save options for JPEG 2000 (aligned with libvips jp2ksave: Q, lossless).
pub const Jp2kSaveOpts = struct {
    q: i32 = 80,
    lossless: bool = false,
};

/// Save options for JPEG XL (aligned with libvips jxlsave: Q, effort, lossless).
pub const JxlSaveOpts = struct {
    q: i32 = 80,
    effort: i32 = 7,
    lossless: bool = false,
};

/// Save image to target as JPEG with format-specific options (streaming).
pub fn jpegSaveToTarget(image: *const vips.VipsImage, target: *vips.c.VipsTarget, opts: JpegSaveOpts) vips.VipsError!void {
    const strip_val: vips.c.gint = if (opts.strip) 1 else 0;
    if (vips.c.vips_jpegsave_target(image.handle, target, "Q", opts.q, "strip", strip_val, @as(?*anyopaque, null)) != 0) {
        return vips.VipsError.SaveFailed;
    }
}

/// Save image to target as PNG with format-specific options (streaming).
pub fn pngSaveToTarget(image: *const vips.VipsImage, target: *vips.c.VipsTarget, opts: PngSaveOpts) vips.VipsError!void {
    const strip_val: vips.c.gint = if (opts.strip) 1 else 0;
    const palette_val: vips.c.gint = if (opts.palette) 1 else 0;
    if (vips.c.vips_pngsave_target(
        image.handle,
        target,
        "compression",
        opts.compression,
        "palette",
        palette_val,
        "Q",
        opts.q,
        "strip",
        strip_val,
        @as(?*anyopaque, null),
    ) != 0) {
        return vips.VipsError.SaveFailed;
    }
}

/// Save image to file as JPEG with options (path-based; no streaming).
pub fn jpegSaveToFile(allocator: std.mem.Allocator, image: *const vips.VipsImage, path: []const u8, opts: JpegSaveOpts) vips.VipsError!void {
    const c_path = allocator.dupeZ(u8, path) catch return vips.VipsError.OutOfMemory;
    defer allocator.free(c_path);
    const strip_val: vips.c.gint = if (opts.strip) 1 else 0;
    if (vips.c.vips_jpegsave(image.handle, c_path.ptr, "Q", opts.q, "strip", strip_val, @as(?*anyopaque, null)) != 0) {
        return vips.VipsError.SaveFailed;
    }
}

/// Save image to file as PNG with options (path-based; no streaming).
pub fn pngSaveToFile(allocator: std.mem.Allocator, image: *const vips.VipsImage, path: []const u8, opts: PngSaveOpts) vips.VipsError!void {
    const c_path = allocator.dupeZ(u8, path) catch return vips.VipsError.OutOfMemory;
    defer allocator.free(c_path);
    const strip_val: vips.c.gint = if (opts.strip) 1 else 0;
    const palette_val: vips.c.gint = if (opts.palette) 1 else 0;
    if (vips.c.vips_pngsave(
        image.handle,
        c_path.ptr,
        "compression",
        opts.compression,
        "palette",
        palette_val,
        "Q",
        opts.q,
        "strip",
        strip_val,
        @as(?*anyopaque, null),
    ) != 0) {
        return vips.VipsError.SaveFailed;
    }
}

/// Save image to target as WebP with format-specific options (streaming).
pub fn webpSaveToTarget(image: *const vips.VipsImage, target: *vips.c.VipsTarget, opts: WebpSaveOpts) vips.VipsError!void {
    const strip_val: vips.c.gint = if (opts.strip) 1 else 0;
    const lossless_val: vips.c.gint = if (opts.lossless) 1 else 0;
    if (vips.c.vips_webpsave_target(
        image.handle,
        target,
        "Q",
        opts.q,
        "strip",
        strip_val,
        "lossless",
        lossless_val,
        @as(?*anyopaque, null),
    ) != 0) {
        return vips.VipsError.SaveFailed;
    }
}

/// Save image to file as WebP with options (path-based; no streaming).
pub fn webpSaveToFile(allocator: std.mem.Allocator, image: *const vips.VipsImage, path: []const u8, opts: WebpSaveOpts) vips.VipsError!void {
    const c_path = allocator.dupeZ(u8, path) catch return vips.VipsError.OutOfMemory;
    defer allocator.free(c_path);
    const strip_val: vips.c.gint = if (opts.strip) 1 else 0;
    const lossless_val: vips.c.gint = if (opts.lossless) 1 else 0;
    if (vips.c.vips_webpsave(
        image.handle,
        c_path.ptr,
        "Q",
        opts.q,
        "strip",
        strip_val,
        "lossless",
        lossless_val,
        @as(?*anyopaque, null),
    ) != 0) {
        return vips.VipsError.SaveFailed;
    }
}

/// Save image to target as TIFF with format-specific options (streaming).
pub fn tiffSaveToTarget(image: *const vips.VipsImage, target: *vips.c.VipsTarget, opts: TiffSaveOpts) vips.VipsError!void {
    const strip_val: vips.c.gint = if (opts.strip) 1 else 0;
    const compression_val: vips.c.gint = @intFromEnum(opts.compression);
    if (vips.c.vips_tiffsave_target(
        image.handle,
        target,
        "compression",
        compression_val,
        "Q",
        opts.q,
        "strip",
        strip_val,
        @as(?*anyopaque, null),
    ) != 0) {
        return vips.VipsError.SaveFailed;
    }
}

/// Save image to file as TIFF with options (path-based; no streaming).
pub fn tiffSaveToFile(allocator: std.mem.Allocator, image: *const vips.VipsImage, path: []const u8, opts: TiffSaveOpts) vips.VipsError!void {
    const c_path = allocator.dupeZ(u8, path) catch return vips.VipsError.OutOfMemory;
    defer allocator.free(c_path);
    const strip_val: vips.c.gint = if (opts.strip) 1 else 0;
    const compression_val: vips.c.gint = @intFromEnum(opts.compression);
    if (vips.c.vips_tiffsave(
        image.handle,
        c_path.ptr,
        "compression",
        compression_val,
        "Q",
        opts.q,
        "strip",
        strip_val,
        @as(?*anyopaque, null),
    ) != 0) {
        return vips.VipsError.SaveFailed;
    }
}

/// Save image to target as GIF with format-specific options (streaming).
pub fn gifSaveToTarget(image: *const vips.VipsImage, target: *vips.c.VipsTarget, opts: GifSaveOpts) vips.VipsError!void {
    const interlace_val: vips.c.gint = if (opts.interlace) 1 else 0;
    if (vips.c.vips_gifsave_target(
        image.handle,
        target,
        "dither",
        opts.dither,
        "effort",
        opts.effort,
        "bitdepth",
        opts.bitdepth,
        "interlace",
        interlace_val,
        @as(?*anyopaque, null),
    ) != 0) {
        return vips.VipsError.SaveFailed;
    }
}

/// Save image to file as GIF with options (path-based; no streaming).
pub fn gifSaveToFile(allocator: std.mem.Allocator, image: *const vips.VipsImage, path: []const u8, opts: GifSaveOpts) vips.VipsError!void {
    const c_path = allocator.dupeZ(u8, path) catch return vips.VipsError.OutOfMemory;
    defer allocator.free(c_path);
    const interlace_val: vips.c.gint = if (opts.interlace) 1 else 0;
    if (vips.c.vips_gifsave(
        image.handle,
        c_path.ptr,
        "dither",
        opts.dither,
        "effort",
        opts.effort,
        "bitdepth",
        opts.bitdepth,
        "interlace",
        interlace_val,
        @as(?*anyopaque, null),
    ) != 0) {
        return vips.VipsError.SaveFailed;
    }
}

/// Save image to file as HEIF/AVIF with options (path-based). Requires libvips built with libheif.
pub fn heifSaveToFile(allocator: std.mem.Allocator, image: *const vips.VipsImage, path: []const u8, opts: HeifSaveOpts) vips.VipsError!void {
    const c_path = allocator.dupeZ(u8, path) catch return vips.VipsError.OutOfMemory;
    defer allocator.free(c_path);
    const lossless_val: vips.c.gint = if (opts.lossless) 1 else 0;
    const compression_val: vips.c.gint = @intFromEnum(opts.compression);
    if (vips.c.vips_heifsave(
        image.handle,
        c_path.ptr,
        "Q",
        opts.q,
        "lossless",
        lossless_val,
        "compression",
        compression_val,
        @as(?*anyopaque, null),
    ) != 0) {
        return vips.VipsError.SaveFailed;
    }
}

/// Save image to file as JPEG 2000 with options (path-based). Requires libvips built with openjp2.
pub fn jp2kSaveToFile(allocator: std.mem.Allocator, image: *const vips.VipsImage, path: []const u8, opts: Jp2kSaveOpts) vips.VipsError!void {
    const c_path = allocator.dupeZ(u8, path) catch return vips.VipsError.OutOfMemory;
    defer allocator.free(c_path);
    const lossless_val: vips.c.gint = if (opts.lossless) 1 else 0;
    if (vips.c.vips_jp2ksave(
        image.handle,
        c_path.ptr,
        "Q",
        opts.q,
        "lossless",
        lossless_val,
        @as(?*anyopaque, null),
    ) != 0) {
        return vips.VipsError.SaveFailed;
    }
}

/// Save image to file as JPEG XL with options (path-based). Requires libvips built with libjxl.
pub fn jxlSaveToFile(allocator: std.mem.Allocator, image: *const vips.VipsImage, path: []const u8, opts: JxlSaveOpts) vips.VipsError!void {
    const c_path = allocator.dupeZ(u8, path) catch return vips.VipsError.OutOfMemory;
    defer allocator.free(c_path);
    const lossless_val: vips.c.gint = if (opts.lossless) 1 else 0;
    if (vips.c.vips_jxlsave(
        image.handle,
        c_path.ptr,
        "Q",
        opts.q,
        "effort",
        opts.effort,
        "lossless",
        lossless_val,
        @as(?*anyopaque, null),
    ) != 0) {
        return vips.VipsError.SaveFailed;
    }
}

// Complete pipeline function following Go pattern exactly with real I/O
pub fn cropImagePipeline(allocator: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, x: i32, y: i32, width: u32, height: u32, format: []const u8) vips.VipsError!void {
    // 1. source from reader (REAL READER!)
    var source = newSourceFromReader(reader, allocator) catch return vips.VipsError.LoadFailed;
    defer source.deinit();

    // 2. image from source
    var image = imageFromSource(source.getVipsSource()) catch return vips.VipsError.LoadFailed;
    defer image.deinit();

    // 3. vips.crop(image)
    var cropped_image = vips.cropImage(&image, x, y, width, height) catch return vips.VipsError.ProcessingFailed;
    defer cropped_image.deinit();

    // 4. target to writer (REAL WRITER!)
    var target = newTargetToWriter(writer, allocator) catch return vips.VipsError.SaveFailed;
    defer target.deinit();

    // 5. save to target (writes directly to writer via callback!)
    imageWriteToTarget(&cropped_image, target.getVipsTarget(), format) catch return vips.VipsError.SaveFailed;
}

// Simple compatibility functions for existing code
pub fn loadImageFromMemory(buffer: []const u8) vips.VipsError!vips.VipsImage {
    // Use simple memory source for compatibility
    const source = vips.c.vips_source_new_from_memory(buffer.ptr, buffer.len);
    if (source == null) {
        return vips.VipsError.LoadFailed;
    }
    defer vips.c.g_object_unref(source);

    const image = vips.c.vips_image_new_from_source(source, "", @as(?*anyopaque, null));
    if (image == null) {
        return vips.VipsError.LoadFailed;
    }

    return vips.VipsImage{ .handle = image.? };
}

pub fn saveImageToMemory(allocator: std.mem.Allocator, image: *const vips.VipsImage, format: []const u8) vips.VipsError![]u8 {
    // Use simple memory target for compatibility
    const target = vips.c.vips_target_new_to_memory();
    if (target == null) {
        return vips.VipsError.SaveFailed;
    }
    defer vips.c.g_object_unref(target);

    const format_str = if (std.mem.eql(u8, format, "png")) ".png" else if (std.mem.eql(u8, format, "webp")) ".webp" else ".jpg";

    if (vips.c.vips_image_write_to_target(image.handle, format_str, target, @as(?*anyopaque, null)) != 0) {
        return vips.VipsError.SaveFailed;
    }

    var length: usize = 0;
    const data_ptr = vips.c.vips_target_steal(target, &length);
    if (data_ptr == null or length == 0) {
        return vips.VipsError.SaveFailed;
    }

    // Copy the data to our own allocation
    const data = allocator.alloc(u8, length) catch return vips.VipsError.OutOfMemory;
    @memcpy(data, @as([*]u8, @ptrCast(data_ptr))[0..length]);

    // Free the vips memory
    vips.c.g_free(data_ptr);

    return data;
}

/// Stream image directly to writer via VipsTarget (no full buffer in memory).
pub fn saveImageToWriter(allocator: std.mem.Allocator, image: *const vips.VipsImage, writer: *std.Io.Writer, format: []const u8) vips.VipsError!void {
    var target = newTargetToWriter(writer, allocator) catch return vips.VipsError.SaveFailed;
    defer target.deinit();
    imageWriteToTarget(image, target.getVipsTarget(), format) catch return vips.VipsError.SaveFailed;
}

// --- Unit tests (no libvips; prevent regressions on save-opts defaults) ---
test "JpegSaveOpts defaults" {
    const opts = JpegSaveOpts{};
    try std.testing.expect(opts.q == 85);
    try std.testing.expect(opts.strip == false);
}

test "PngSaveOpts defaults" {
    const opts = PngSaveOpts{};
    try std.testing.expect(opts.compression == 6);
    try std.testing.expect(opts.palette == false);
    try std.testing.expect(opts.q == 80);
    try std.testing.expect(opts.strip == false);
}

test "WebpSaveOpts defaults" {
    const opts = WebpSaveOpts{};
    try std.testing.expect(opts.q == 80);
    try std.testing.expect(opts.strip == false);
    try std.testing.expect(opts.lossless == false);
}

test "TiffSaveOpts defaults" {
    const opts = TiffSaveOpts{};
    try std.testing.expect(opts.compression == .none);
    try std.testing.expect(opts.q == 75);
    try std.testing.expect(opts.strip == false);
}

test "GifSaveOpts defaults" {
    const opts = GifSaveOpts{};
    try std.testing.expect(opts.dither == 1.0);
    try std.testing.expect(opts.effort == 7);
    try std.testing.expect(opts.bitdepth == 8);
    try std.testing.expect(opts.interlace == false);
}

test "HeifSaveOpts defaults" {
    const opts = HeifSaveOpts{};
    try std.testing.expect(opts.q == 80);
    try std.testing.expect(opts.lossless == false);
    try std.testing.expect(opts.compression == .av1);
}

test "Jp2kSaveOpts defaults" {
    const opts = Jp2kSaveOpts{};
    try std.testing.expect(opts.q == 80);
    try std.testing.expect(opts.lossless == false);
}

test "JxlSaveOpts defaults" {
    const opts = JxlSaveOpts{};
    try std.testing.expect(opts.q == 80);
    try std.testing.expect(opts.effort == 7);
    try std.testing.expect(opts.lossless == false);
}
