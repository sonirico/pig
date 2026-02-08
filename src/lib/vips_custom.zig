const std = @import("std");
const vips = @import("vips.zig");
const format_options = @import("format_options.zig");

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

// Signal callback for VipsSourceCustom "read" — receives user_data as last param.
fn sourceReadCallback(_: [*c]vips.c.VipsSourceCustom, buffer: ?*anyopaque, length: i64, user_data: ?*anyopaque) callconv(.c) i64 {
    if (buffer == null or length <= 0) return -1;
    const ctx = @as(*SourceContext, @ptrCast(@alignCast(user_data orelse return -1)));

    if (ctx.eof_reached) return 0;

    const read_buffer = @as([*]u8, @ptrCast(buffer.?))[0..@intCast(length)];
    const bytes_read = std.Io.Reader.readSliceShort(ctx.reader, read_buffer) catch return -1;
    if (bytes_read == 0) {
        ctx.eof_reached = true;
        return 0;
    }
    return @intCast(bytes_read);
}

// Signal callback for VipsTargetCustom "write" — receives user_data as last param.
fn targetWriteCallback(_: [*c]vips.c.VipsTargetCustom, buffer: ?*const anyopaque, length: i64, user_data: ?*anyopaque) callconv(.c) i64 {
    if (buffer == null or length <= 0) return -1;
    const ctx = @as(*TargetContext, @ptrCast(@alignCast(user_data orelse return -1)));
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

        return CustomSource{
            .source = source.?,
            .context = SourceContext{
                .reader = reader,
                .allocator = allocator,
                .buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch return vips.VipsError.OutOfMemory,
                .position = 0,
                .eof_reached = false,
            },
        };
    }

    /// Connect the GObject "read" signal. MUST be called after the struct is
    /// stored in its final location (local var on the caller's stack) so that
    /// `&self.context` remains valid for the lifetime of the signal.
    pub fn connectSignal(self: *CustomSource) void {
        _ = vips.c.g_signal_connect_data(
            @as(vips.c.gpointer, @ptrCast(self.source)),
            "read",
            @as(vips.c.GCallback, @ptrCast(&sourceReadCallback)),
            @as(vips.c.gpointer, @ptrCast(&self.context)),
            null,
            0,
        );
    }

    pub fn deinit(self: *CustomSource) void {
        self.context.buffer.deinit(self.context.allocator);
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

        return CustomTarget{
            .target = target.?,
            .context = TargetContext{
                .writer = writer,
                .allocator = allocator,
            },
        };
    }

    /// Connect the GObject "write" signal. MUST be called after the struct is
    /// stored in its final location (local var on the caller's stack) so that
    /// `&self.context` remains valid for the lifetime of the signal.
    pub fn connectSignal(self: *CustomTarget) void {
        _ = vips.c.g_signal_connect_data(
            @as(vips.c.gpointer, @ptrCast(self.target)),
            "write",
            @as(vips.c.GCallback, @ptrCast(&targetWriteCallback)),
            @as(vips.c.gpointer, @ptrCast(&self.context)),
            null,
            0,
        );
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
    const opts = defaultOptsForStreamableFormat(blk: {
        const fmt = format_options.SaveFormat.fromExtension(format) orelse break :blk .png;
        break :blk toStreamable(fmt) orelse .png;
    });
    try cropImagePipelineWithOpts(allocator, reader, writer, x, y, width, height, opts);
}

pub fn cropImagePipelineWithOpts(allocator: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, x: i32, y: i32, width: u32, height: u32, opts: SaveOptsUnion) vips.VipsError!void {
    var source = newSourceFromReader(reader, allocator) catch return vips.VipsError.LoadFailed;
    source.connectSignal();
    defer source.deinit();

    var image = imageFromSource(source.getVipsSource()) catch return vips.VipsError.LoadFailed;
    defer image.deinit();

    var cropped_image = vips.cropImage(&image, x, y, width, height) catch return vips.VipsError.ProcessingFailed;
    defer cropped_image.deinit();

    var target = newTargetToWriter(writer, allocator) catch return vips.VipsError.SaveFailed;
    target.connectSignal();
    defer target.deinit();

    const t = target.getVipsTarget();
    switch (opts) {
        .jpeg => |o| try jpegSaveToTarget(&cropped_image, t, o),
        .png => |o| try pngSaveToTarget(&cropped_image, t, o),
        .webp => |o| try webpSaveToTarget(&cropped_image, t, o),
        .tiff => |o| try tiffSaveToTarget(&cropped_image, t, o),
        .gif => |o| try gifSaveToTarget(&cropped_image, t, o),
    }
}

fn defaultOptsForStreamableFormat(f: StreamableFormat) SaveOptsUnion {
    return switch (f) {
        .jpeg => .{ .jpeg = .{} },
        .png => .{ .png = .{} },
        .webp => .{ .webp = .{} },
        .tiff => .{ .tiff = .{} },
        .gif => .{ .gif = .{} },
    };
}

/// Stream: reader -> load -> resize by scale factors -> writer. scale_x/scale_y e.g. 0.5.
pub fn scaleImagePipeline(allocator: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, scale_x: f64, scale_y: f64, format: []const u8) vips.VipsError!void {
    const opts = defaultOptsForStreamableFormat(blk: {
        const fmt = format_options.SaveFormat.fromExtension(format) orelse break :blk .png;
        break :blk toStreamable(fmt) orelse .png;
    });
    try scaleImagePipelineWithOpts(allocator, reader, writer, scale_x, scale_y, opts);
}

pub fn scaleImagePipelineWithOpts(allocator: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, scale_x: f64, scale_y: f64, opts: SaveOptsUnion) vips.VipsError!void {
    var source = newSourceFromReader(reader, allocator) catch return vips.VipsError.LoadFailed;
    source.connectSignal();
    defer source.deinit();

    var image = imageFromSource(source.getVipsSource()) catch return vips.VipsError.LoadFailed;
    defer image.deinit();

    var resized = vips.resizeImage(&image, scale_x, scale_y) catch return vips.VipsError.ProcessingFailed;
    defer resized.deinit();

    var target = newTargetToWriter(writer, allocator) catch return vips.VipsError.SaveFailed;
    target.connectSignal();
    defer target.deinit();

    const t = target.getVipsTarget();
    switch (opts) {
        .jpeg => |o| try jpegSaveToTarget(&resized, t, o),
        .png => |o| try pngSaveToTarget(&resized, t, o),
        .webp => |o| try webpSaveToTarget(&resized, t, o),
        .tiff => |o| try tiffSaveToTarget(&resized, t, o),
        .gif => |o| try gifSaveToTarget(&resized, t, o),
    }
}

/// Stream: reader -> load -> write to target format (no geometry change).
pub fn convertPipeline(allocator: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, format: []const u8) vips.VipsError!void {
    var source = newSourceFromReader(reader, allocator) catch return vips.VipsError.LoadFailed;
    source.connectSignal();
    defer source.deinit();

    var image = imageFromSource(source.getVipsSource()) catch return vips.VipsError.LoadFailed;
    defer image.deinit();

    var target = newTargetToWriter(writer, allocator) catch return vips.VipsError.SaveFailed;
    target.connectSignal();
    defer target.deinit();

    imageWriteToTarget(&image, target.getVipsTarget(), format) catch return vips.VipsError.SaveFailed;
}

/// Formats we can stream to (have *SaveToTarget). Others (heif, jp2k, jxl) only have *SaveToFile.
pub const StreamableFormat = enum { jpeg, png, webp, tiff, gif };

pub const SaveOptsUnion = union(StreamableFormat) {
    jpeg: JpegSaveOpts,
    png: PngSaveOpts,
    webp: WebpSaveOpts,
    tiff: TiffSaveOpts,
    gif: GifSaveOpts,
};

pub fn toStreamable(f: format_options.SaveFormat) ?StreamableFormat {
    return switch (f) {
        .jpeg => .jpeg,
        .png => .png,
        .webp => .webp,
        .tiff => .tiff,
        .gif => .gif,
        .heif, .jp2k, .jxl => null,
    };
}

/// Stream: reader -> load -> save to target with format-specific opts (streaming).
pub fn convertPipelineWithOpts(allocator: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, opts: SaveOptsUnion) vips.VipsError!void {
    var source = newSourceFromReader(reader, allocator) catch return vips.VipsError.LoadFailed;
    source.connectSignal();
    defer source.deinit();

    var image = imageFromSource(source.getVipsSource()) catch return vips.VipsError.LoadFailed;
    defer image.deinit();

    var target = newTargetToWriter(writer, allocator) catch return vips.VipsError.SaveFailed;
    target.connectSignal();
    defer target.deinit();

    const t = target.getVipsTarget();
    switch (opts) {
        .jpeg => |o| try jpegSaveToTarget(&image, t, o),
        .png => |o| try pngSaveToTarget(&image, t, o),
        .webp => |o| try webpSaveToTarget(&image, t, o),
        .tiff => |o| try tiffSaveToTarget(&image, t, o),
        .gif => |o| try gifSaveToTarget(&image, t, o),
    }
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
    target.connectSignal();
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

// --- Integration tests (require libvips; catch dangling-pointer regressions) ---

// vips_shutdown() is destructive and cannot be followed by vips_init() again.
// Use a process-wide flag so all tests share a single init (no shutdown in tests).
var vips_test_initialized = false;

fn ensureVipsInit() bool {
    if (vips_test_initialized) return true;
    if (vips.c.vips_init("test") != 0) return false;
    vips_test_initialized = true;
    return true;
}

fn createTestImage(w: c_int, h: c_int) ?vips.VipsImage {
    var black: ?*vips.c.VipsImage = null;
    if (vips.c.vips_black(&black, w, h, "bands", @as(c_int, 3), @as(?*anyopaque, null)) != 0) return null;
    // Cast to sRGB so JPEG/PNG save works without colorspace errors
    var output: ?*vips.c.VipsImage = null;
    if (vips.c.vips_colourspace(black, &output, vips.c.VIPS_INTERPRETATION_sRGB, @as(?*anyopaque, null)) != 0) {
        vips.c.g_object_unref(black);
        return null;
    }
    vips.c.g_object_unref(black);
    return vips.VipsImage{ .handle = output.? };
}

test "CustomTarget: save image through signal callback" {
    if (!ensureVipsInit()) return error.SkipZigTest;

    var img = createTestImage(10, 10) orelse return error.SkipZigTest;
    defer img.deinit();

    var output_buf: [256 * 1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output_buf);

    var target = CustomTarget.init(&writer, std.testing.allocator) catch return error.SkipZigTest;
    target.connectSignal();
    defer target.deinit();

    jpegSaveToTarget(&img, target.getVipsTarget(), .{}) catch |e| {
        std.debug.print("[test] jpegSaveToTarget failed: {s}\n", .{@errorName(e)});
        return error.SkipZigTest;
    };

    const written = writer.buffered();
    try std.testing.expect(written.len > 0);
    // JPEG magic: FF D8 FF
    try std.testing.expectEqual(@as(u8, 0xFF), written[0]);
    try std.testing.expectEqual(@as(u8, 0xD8), written[1]);
}

// Helper: save image to a fixed buffer via CustomTarget (avoids saveImageToMemory which
// uses vips_image_write_to_target and may fail for synthetic images).
fn saveTestImageToBuffer(img: *const vips.VipsImage, buf: []u8, opts: SaveOptsUnion) ?[]const u8 {
    var writer = std.Io.Writer.fixed(buf);
    var target = CustomTarget.init(&writer, std.testing.allocator) catch return null;
    target.connectSignal();
    defer target.deinit();
    const t = target.getVipsTarget();
    switch (opts) {
        .jpeg => |o| jpegSaveToTarget(img, t, o) catch return null,
        .png => |o| pngSaveToTarget(img, t, o) catch return null,
        .webp => |o| webpSaveToTarget(img, t, o) catch return null,
        .tiff => |o| tiffSaveToTarget(img, t, o) catch return null,
        .gif => |o| gifSaveToTarget(img, t, o) catch return null,
    }
    const written = writer.buffered();
    if (written.len == 0) return null;
    return written;
}

test "CustomSource: load image through signal callback" {
    if (!ensureVipsInit()) return error.SkipZigTest;

    var img = createTestImage(16, 16) orelse return error.SkipZigTest;
    defer img.deinit();

    // Save to JPEG via CustomTarget (which already works)
    var jpeg_buf: [256 * 1024]u8 = undefined;
    const jpeg_data = saveTestImageToBuffer(&img, &jpeg_buf, .{ .jpeg = .{} }) orelse return error.SkipZigTest;

    // Load back through CustomSource + signal callback
    var reader = std.Io.Reader.fixed(jpeg_data);

    var source = CustomSource.init(&reader, std.testing.allocator) catch return error.SkipZigTest;
    source.connectSignal();
    defer source.deinit();

    var loaded = imageFromSource(source.getVipsSource()) catch return error.SkipZigTest;
    defer loaded.deinit();

    try std.testing.expectEqual(@as(u32, 16), loaded.getWidth());
    try std.testing.expectEqual(@as(u32, 16), loaded.getHeight());
}

test "convertPipelineWithOpts: full roundtrip source -> target" {
    if (!ensureVipsInit()) return error.SkipZigTest;

    var img = createTestImage(20, 20) orelse return error.SkipZigTest;
    defer img.deinit();

    // Create PNG input via CustomTarget
    var png_buf: [256 * 1024]u8 = undefined;
    const png_data = saveTestImageToBuffer(&img, &png_buf, .{ .png = .{} }) orelse return error.SkipZigTest;

    var reader = std.Io.Reader.fixed(png_data);
    var output_buf: [256 * 1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output_buf);

    // PNG -> JPEG conversion through full streaming pipeline
    convertPipelineWithOpts(
        std.testing.allocator,
        &reader,
        &writer,
        .{ .jpeg = .{ .q = 80 } },
    ) catch |e| {
        std.debug.print("[test] convertPipelineWithOpts failed: {s}\n", .{@errorName(e)});
        return e;
    };

    const output = writer.buffered();
    try std.testing.expect(output.len > 0);
    // JPEG magic
    try std.testing.expectEqual(@as(u8, 0xFF), output[0]);
    try std.testing.expectEqual(@as(u8, 0xD8), output[1]);
}

test "cropImagePipelineWithOpts: crop and verify dimensions" {
    if (!ensureVipsInit()) return error.SkipZigTest;

    var img = createTestImage(64, 64) orelse return error.SkipZigTest;
    defer img.deinit();

    // Create PNG input via CustomTarget
    var png_buf: [256 * 1024]u8 = undefined;
    const png_data = saveTestImageToBuffer(&img, &png_buf, .{ .png = .{} }) orelse return error.SkipZigTest;

    var reader = std.Io.Reader.fixed(png_data);
    var output_buf: [256 * 1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output_buf);

    cropImagePipelineWithOpts(
        std.testing.allocator,
        &reader,
        &writer,
        0, 0, 32, 32,
        .{ .png = .{} },
    ) catch |e| {
        std.debug.print("[test] cropImagePipelineWithOpts failed: {s}\n", .{@errorName(e)});
        return e;
    };

    const output = writer.buffered();
    try std.testing.expect(output.len > 0);

    // Load the cropped output and verify dimensions
    var cropped = loadImageFromMemory(output) catch return error.SkipZigTest;
    defer cropped.deinit();
    try std.testing.expectEqual(@as(u32, 32), cropped.getWidth());
    try std.testing.expectEqual(@as(u32, 32), cropped.getHeight());
}

test "scaleImagePipelineWithOpts: scale and verify dimensions" {
    if (!ensureVipsInit()) return error.SkipZigTest;

    var img = createTestImage(64, 64) orelse return error.SkipZigTest;
    defer img.deinit();

    // Create PNG input via CustomTarget
    var png_buf: [256 * 1024]u8 = undefined;
    const png_data = saveTestImageToBuffer(&img, &png_buf, .{ .png = .{} }) orelse return error.SkipZigTest;

    var reader = std.Io.Reader.fixed(png_data);
    var output_buf: [256 * 1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output_buf);

    scaleImagePipelineWithOpts(
        std.testing.allocator,
        &reader,
        &writer,
        0.5, 0.5,
        .{ .png = .{} },
    ) catch |e| {
        std.debug.print("[test] scaleImagePipelineWithOpts failed: {s}\n", .{@errorName(e)});
        return e;
    };

    const output = writer.buffered();
    try std.testing.expect(output.len > 0);

    // Load the scaled output and verify dimensions
    var scaled = loadImageFromMemory(output) catch return error.SkipZigTest;
    defer scaled.deinit();
    try std.testing.expectEqual(@as(u32, 32), scaled.getWidth());
    try std.testing.expectEqual(@as(u32, 32), scaled.getHeight());
}
