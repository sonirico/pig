// Public API surface for pig: used by CLI (main.zig) and future HTTP server.
// All image ops and streaming go through this layer; use save target (VipsTarget) for streaming.

pub const vips = @import("vips.zig");
pub const vips_custom = @import("vips_custom.zig");
pub const utils = @import("utils.zig");
/// Format-specific save options schema: single source of truth for CLI, API, and frontend.
pub const format_options = @import("format_options.zig");
/// Logger (used by utils and by CLI/server entrypoints).
pub const logger = @import("logger.zig");

// Force test discovery in imported files.
test {
    _ = @import("vips_custom.zig");
    _ = @import("format_options.zig");
}