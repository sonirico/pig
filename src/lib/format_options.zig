// Format-specific save options schema: single source of truth for CLI, API, and frontend.
// No metaprogramming: explicit option specs so the front can map type, range, default, description.

const std = @import("std");

/// Kind of option for UI/validation: type and allowed values.
pub const OptionKind = enum {
    int,
    bool,
    float,
    enum_strings, // allowed values listed in enum_values
};

/// One option for a format: name, type, range/default, description.
/// Frontend can use this to render controls (slider, checkbox, dropdown) and validate.
pub const OptionSpec = struct {
    name: []const u8,
    kind: OptionKind,
    /// For int/float: min value (optional, use null for no min).
    min: ?f64 = null,
    /// For int/float: max value (optional).
    max: ?f64 = null,
    /// Default as string so we can serialize consistently (e.g. "85", "true", "none").
    default_str: []const u8,
    /// Human-readable description (e.g. for tooltips).
    description: []const u8,
    /// For kind == enum_strings: allowed values (e.g. &.{ "none", "exif", "icc" }).
    enum_values: ?[]const []const u8 = null,
};

// --- JPEG save options (aligned with libvips jpegsave_target) ---
pub const jpeg_options = [_]OptionSpec{
    .{
        .name = "q",
        .kind = .int,
        .min = 1,
        .max = 100,
        .default_str = "85",
        .description = "Quality (1-100). Higher = better quality, larger file.",
    },
    .{
        .name = "strip",
        .kind = .bool,
        .default_str = "false",
        .description = "Strip metadata (EXIF, etc.) to reduce size.",
    },
    .{
        .name = "optimize_coding",
        .kind = .bool,
        .default_str = "false",
        .description = "Compute optimal Huffman coding tables.",
    },
    .{
        .name = "interlace",
        .kind = .bool,
        .default_str = "false",
        .description = "Write progressive/interlaced JPEG.",
    },
};

// --- PNG save options (aligned with libvips pngsave_target) ---
pub const png_options = [_]OptionSpec{
    .{
        .name = "compression",
        .kind = .int,
        .min = 0,
        .max = 9,
        .default_str = "6",
        .description = "DEFLATE compression level (0=none, 9=max). No quality loss.",
    },
    .{
        .name = "palette",
        .kind = .bool,
        .default_str = "false",
        .description = "Convert to palette (8bpp) with libimagequant; large size reduction.",
    },
    .{
        .name = "q",
        .kind = .int,
        .min = 1,
        .max = 100,
        .default_str = "80",
        .description = "Quantisation quality when palette=true (libimagequant fidelity).",
    },
    .{
        .name = "strip",
        .kind = .bool,
        .default_str = "false",
        .description = "Strip metadata to reduce size.",
    },
    .{
        .name = "interlace",
        .kind = .bool,
        .default_str = "false",
        .description = "Adam7 interlaced PNG.",
    },
    .{
        .name = "filter",
        .kind = .enum_strings,
        .default_str = "all",
        .description = "PNG row filter: none, sub, up, avg, paeth, all.",
        .enum_values = &.{ "none", "sub", "up", "avg", "paeth", "all" },
    },
    .{
        .name = "effort",
        .kind = .int,
        .min = 1,
        .max = 10,
        .default_str = "7",
        .description = "CPU effort for palette (1-10). Higher = better palette, slower.",
    },
};

/// Format identifier for dispatch and schema lookup.
pub const SaveFormat = enum {
    jpeg,
    png,
    webp,
    tiff,
    gif,
    heif, // HEIC, AVIF (libvips heifsave)
    jp2k, // JPEG 2000 (libvips jp2ksave)
    jxl, // JPEG XL (libvips jxlsave)

    pub fn fromExtension(ext: []const u8) ?SaveFormat {
        if (std.mem.eql(u8, ext, "jpg") or std.mem.eql(u8, ext, "jpeg")) return .jpeg;
        if (std.mem.eql(u8, ext, "png")) return .png;
        if (std.mem.eql(u8, ext, "webp")) return .webp;
        if (std.mem.eql(u8, ext, "tiff") or std.mem.eql(u8, ext, "tif")) return .tiff;
        if (std.mem.eql(u8, ext, "gif")) return .gif;
        if (std.mem.eql(u8, ext, "heic") or std.mem.eql(u8, ext, "heif") or std.mem.eql(u8, ext, "avif")) return .heif;
        if (std.mem.eql(u8, ext, "jp2") or std.mem.eql(u8, ext, "j2k")) return .jp2k;
        if (std.mem.eql(u8, ext, "jxl")) return .jxl;
        return null;
    }

    pub fn toSuffix(self: SaveFormat) []const u8 {
        return switch (self) {
            .jpeg => ".jpg",
            .png => ".png",
            .webp => ".webp",
            .tiff => ".tiff",
            .gif => ".gif",
            .heif => ".avif",
            .jp2k => ".jp2",
            .jxl => ".jxl",
        };
    }

    /// Option specs for this format (for frontend/API schema).
    pub fn optionSpecs(self: SaveFormat) []const OptionSpec {
        return switch (self) {
            .jpeg => &jpeg_options,
            .png => &png_options,
            .webp => &webp_options,
            .tiff => &tiff_options,
            .gif => &gif_options,
            .heif => &heif_options,
            .jp2k => &jp2k_options,
            .jxl => &jxl_options,
        };
    }
};

// --- WebP save options (aligned with libvips webpsave) ---
pub const webp_options = [_]OptionSpec{
    .{
        .name = "Q",
        .kind = .int,
        .min = 1,
        .max = 100,
        .default_str = "80",
        .description = "Quality (1-100).",
    },
    .{
        .name = "strip",
        .kind = .bool,
        .default_str = "false",
        .description = "Strip metadata.",
    },
    .{
        .name = "lossless",
        .kind = .bool,
        .default_str = "false",
        .description = "Use lossless compression.",
    },
};

// --- TIFF save options (aligned with libvips tiffsave: compression, Q, strip) ---
pub const tiff_options = [_]OptionSpec{
    .{
        .name = "compression",
        .kind = .enum_strings,
        .default_str = "none",
        .description = "Compression: none, jpeg, deflate, lzw, webp, zstd, etc.",
        .enum_values = &.{ "none", "jpeg", "deflate", "packbits", "ccittfax4", "lzw", "webp", "zstd", "jp2k" },
    },
    .{
        .name = "q",
        .kind = .int,
        .min = 1,
        .max = 100,
        .default_str = "75",
        .description = "JPEG compression quality when compression=jpeg.",
    },
    .{
        .name = "strip",
        .kind = .bool,
        .default_str = "false",
        .description = "Strip metadata.",
    },
};

// Libvips has more savers: vipssave, fitssave, rawsave, csvsave, matrixsave, magicksave,
// ppmsave, radsave, heifsave, niftisave, jp2ksave, jxlsave, dzsave. We add the most common.

// --- HEIF/AVIF save options (aligned with libvips heifsave: Q, lossless, compression) ---
pub const heif_options = [_]OptionSpec{
    .{
        .name = "Q",
        .kind = .int,
        .min = 1,
        .max = 100,
        .default_str = "80",
        .description = "Quality (1-100).",
    },
    .{
        .name = "lossless",
        .kind = .bool,
        .default_str = "false",
        .description = "Enable lossless compression.",
    },
    .{
        .name = "compression",
        .kind = .enum_strings,
        .default_str = "av1",
        .description = "Codec: hevc, avc, jpeg, av1 (av1 for AVIF).",
        .enum_values = &.{ "hevc", "avc", "jpeg", "av1" },
    },
};

// --- JPEG 2000 save options (aligned with libvips jp2ksave: Q, lossless) ---
pub const jp2k_options = [_]OptionSpec{
    .{
        .name = "Q",
        .kind = .int,
        .min = 1,
        .max = 100,
        .default_str = "80",
        .description = "Quality (1-100).",
    },
    .{
        .name = "lossless",
        .kind = .bool,
        .default_str = "false",
        .description = "Enable lossless compression.",
    },
};

// --- JPEG XL save options (aligned with libvips jxlsave: Q, effort, lossless) ---
pub const jxl_options = [_]OptionSpec{
    .{
        .name = "Q",
        .kind = .int,
        .min = 1,
        .max = 100,
        .default_str = "80",
        .description = "Quality (1-100).",
    },
    .{
        .name = "effort",
        .kind = .int,
        .min = 1,
        .max = 9,
        .default_str = "7",
        .description = "Encoding effort (1-9). Higher = smaller file, slower.",
    },
    .{
        .name = "lossless",
        .kind = .bool,
        .default_str = "false",
        .description = "Enable lossless compression.",
    },
};

// --- GIF save options (aligned with libvips cgifsave: dither, effort, bitdepth, interlace) ---
pub const gif_options = [_]OptionSpec{
    .{
        .name = "dither",
        .kind = .float,
        .min = 0,
        .max = 1,
        .default_str = "1.0",
        .description = "Amount of dithering (0-1).",
    },
    .{
        .name = "effort",
        .kind = .int,
        .min = 1,
        .max = 10,
        .default_str = "7",
        .description = "Quantisation effort (1-10).",
    },
    .{
        .name = "bitdepth",
        .kind = .int,
        .min = 1,
        .max = 8,
        .default_str = "8",
        .description = "Bits per pixel (1-8).",
    },
    .{
        .name = "interlace",
        .kind = .bool,
        .default_str = "false",
        .description = "Write interlaced (progressive) GIF.",
    },
};

/// Parse extension from path (e.g. "out.png" -> "png").
pub fn extensionFromPath(path: []const u8) ?[]const u8 {
    if (path.len == 0) return null;
    const last_dot = std.mem.lastIndexOf(u8, path, ".") orelse return null;
    if (last_dot + 1 >= path.len) return null;
    return path[last_dot + 1 ..];
}

// --- Unit tests (no libvips; prevent regressions on schema and format dispatch) ---
test "SaveFormat.fromExtension" {
    try std.testing.expect(SaveFormat.fromExtension("jpg").? == .jpeg);
    try std.testing.expect(SaveFormat.fromExtension("jpeg").? == .jpeg);
    try std.testing.expect(SaveFormat.fromExtension("png").? == .png);
    try std.testing.expect(SaveFormat.fromExtension("webp").? == .webp);
    try std.testing.expect(SaveFormat.fromExtension("tiff").? == .tiff);
    try std.testing.expect(SaveFormat.fromExtension("tif").? == .tiff);
    try std.testing.expect(SaveFormat.fromExtension("gif").? == .gif);
    try std.testing.expect(SaveFormat.fromExtension("heic").? == .heif);
    try std.testing.expect(SaveFormat.fromExtension("avif").? == .heif);
    try std.testing.expect(SaveFormat.fromExtension("jp2").? == .jp2k);
    try std.testing.expect(SaveFormat.fromExtension("jxl").? == .jxl);
    try std.testing.expect(SaveFormat.fromExtension("") == null);
    try std.testing.expect(SaveFormat.fromExtension("PNG") == null); // case-sensitive
}

test "SaveFormat.toSuffix" {
    try std.testing.expectEqualStrings(".jpg", SaveFormat.jpeg.toSuffix());
    try std.testing.expectEqualStrings(".png", SaveFormat.png.toSuffix());
    try std.testing.expectEqualStrings(".webp", SaveFormat.webp.toSuffix());
    try std.testing.expectEqualStrings(".tiff", SaveFormat.tiff.toSuffix());
    try std.testing.expectEqualStrings(".gif", SaveFormat.gif.toSuffix());
    try std.testing.expectEqualStrings(".avif", SaveFormat.heif.toSuffix());
    try std.testing.expectEqualStrings(".jp2", SaveFormat.jp2k.toSuffix());
    try std.testing.expectEqualStrings(".jxl", SaveFormat.jxl.toSuffix());
}

test "SaveFormat.optionSpecs" {
    const jpeg_specs = SaveFormat.jpeg.optionSpecs();
    try std.testing.expect(jpeg_specs.len >= 2);
    try std.testing.expectEqualStrings("q", jpeg_specs[0].name);
    try std.testing.expect(jpeg_specs[0].kind == .int);
    try std.testing.expect(jpeg_specs[0].min.? == 1);
    try std.testing.expect(jpeg_specs[0].max.? == 100);

    const png_specs = SaveFormat.png.optionSpecs();
    try std.testing.expect(png_specs.len >= 5);
    try std.testing.expectEqualStrings("compression", png_specs[0].name);
    try std.testing.expect(SaveFormat.png.optionSpecs()[2].name.len > 0); // "q"

    try std.testing.expect(SaveFormat.tiff.optionSpecs().len >= 2);
    try std.testing.expect(SaveFormat.gif.optionSpecs().len >= 2);
    try std.testing.expect(SaveFormat.heif.optionSpecs().len >= 2);
    try std.testing.expect(SaveFormat.jp2k.optionSpecs().len >= 2);
    try std.testing.expect(SaveFormat.jxl.optionSpecs().len >= 2);
}

test "extensionFromPath" {
    try std.testing.expectEqualStrings("png", extensionFromPath("out.png").?);
    try std.testing.expectEqualStrings("jpg", extensionFromPath("a/b/c.jpg").?);
    try std.testing.expectEqualStrings("webp", extensionFromPath("file.webp").?);
    try std.testing.expect(extensionFromPath("noext") == null);
    try std.testing.expect(extensionFromPath("") == null);
    try std.testing.expect(extensionFromPath(".") == null);
    try std.testing.expectEqualStrings("png", extensionFromPath("/path/to/image.png").?);
}
