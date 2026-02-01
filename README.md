<div align="center">
  <img src="pig.png" alt="pig mascot" width="96" />

  # pig

  *Fast image processing CLI* - Zig + libvips. Batch ops and pipelines.

  [![Zig](https://img.shields.io/badge/Zig-0.15+-F7A41D?style=flat&logo=zig&logoColor=white)](https://ziglang.org/)
  [![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
  [![libvips](https://img.shields.io/badge/libvips-8.18+-4B8BBE?style=flat)](https://libvips.github.io/libvips/)
  [![Release](https://img.shields.io/github/v/release/sonirico/pig?style=flat)](https://github.com/sonirico/pig/releases)
</div>

Fast image processing CLI tool built with Zig and libvips. Designed for high-performance batch operations and pipeline integration.

## Installation

### Quick install

```bash
curl -sSL https://raw.githubusercontent.com/sonirico/pig/main/install.sh | bash
```

### Binary releases

Download the latest release for your platform:

```bash
# Linux x86_64
curl -L https://github.com/sonirico/pig/releases/latest/download/pig-linux-x86_64 -o pig
chmod +x pig

# macOS (Intel)
curl -L https://github.com/sonirico/pig/releases/latest/download/pig-darwin-x86_64 -o pig
chmod +x pig

# macOS (Apple Silicon)
curl -L https://github.com/sonirico/pig/releases/latest/download/pig-darwin-arm64 -o pig
chmod +x pig

# Windows
curl -L https://github.com/sonirico/pig/releases/latest/download/pig-windows-x86_64.exe -o pig.exe
```

### Docker

```bash
docker pull ghcr.io/sonirico/pig:latest
docker run --rm -v $(pwd):/workspace ghcr.io/sonirico/pig inspect /workspace/image.jpg
```

### From source

Requires Zig 0.15+ and libvips development headers:

```bash
# Ubuntu/Debian
sudo apt install libvips-dev

# macOS
brew install vips

# Build
git clone https://github.com/sonirico/pig.git
cd pig
zig build -Doptimize=ReleaseFast
```

## Usage

All commands support reading from stdin for pipeline operations:

```bash
# Basic inspection
pig inspect image.jpg

# Pipeline usage
cat image.jpg | pig inspect

# JSON output for scripting
pig inspect --json image.jpg | jq '.width'
```

### Commands

**inspect** – Analyze image properties (dimensions, format, size, etc.)
```bash
pig inspect photo.jpg
pig inspect --json photo.jpg  # JSON for pipelines
```

**optimize** – Compress/convert images (format from output extension)
```bash
pig optimize photo.jpg -o out.png -q 80 --strip
pig optimize photo.png -o out.webp -q 80 --strip
pig optimize photo.png -o out.png --palette -q 80  # Palette (8bpp) for PNG
```

**crop** – Extract image regions
```bash
pig crop -i photo.jpg -o cropped.png 100 100 800 600   # x y width height
```

**scale** – Resize images
```bash
pig scale photo.jpg 1920 1080
```

### Supported output formats (optimize)

Format is inferred from the `-o` path extension. Options (quality, strip, palette, etc.) are format-specific; see `pig optimize --help`.

| Format        | Extensions              | libvips saver | Optional build deps   |
|---------------|-------------------------|---------------|------------------------|
| JPEG          | .jpg, .jpeg             | jpegsave      | -                     |
| PNG           | .png                    | pngsave       | -                     |
| WebP          | .webp                   | webpsave      | -                     |
| TIFF          | .tiff, .tif             | tiffsave      | -                     |
| GIF           | .gif                    | gifsave       | -                     |
| HEIF / AVIF   | .heic, .heif, .avif     | heifsave      | libheif               |
| JPEG 2000     | .jp2, .j2k               | jp2ksave      | openjp2               |
| JPEG XL       | .jxl                    | jxlsave       | libjxl                |

Other libvips savers not yet wired in pig: vipssave, ppmsave, radsave, fitssave, rawsave, csvsave, matrixsave, magicksave, niftisave, dzsave. Reference: `.test/libvips` and `src/lib/format_options.zig`.

### Pipeline examples

```bash
# Batch optimization (output path required; format from extension)
find . -name "*.jpg" -exec sh -c 'pig optimize "$1" -o "${1%.jpg}.webp" -q 80 --strip' _ {} \;

# Inspect multiple files
for img in *.jpg; do pig inspect --json "$img"; done | jq '.size_bytes' | paste -sd+ | bc

# Convert and optimize
pig optimize input.tiff -o output.jpg -q 90 --strip
```

## Development Status

### Implemented
- [x] CLI with zli (inspect, optimize, crop, scale, version)
- [x] Image inspection with full metadata and JSON
- [x] libvips integration; format detection; pipeline (stdin/stdout)
- [x] **optimize** with format-specific options: JPEG, PNG, WebP, TIFF, GIF, HEIF/AVIF, JP2K, JXL (see table above)
- [x] **crop** with file or stdout output
- [x] **scale** (resize)
- [x] Snapshot-based integration tests (Zig runner, no bash); `zig build integration-test`; `-Dupdate=true` to refresh snapshots
- [x] Format options schema in `src/lib/format_options.zig` (single source of truth for CLI/API/frontend)

### Planned
- [ ] Batch processing mode; config file; progress bars
- [ ] Color profile management; watermarking; filters (blur, sharpen)
- [ ] More savers (PPM, Radiance, vipssave) if needed
- [ ] Multi-threading for batch; plugin system

### Research
- [ ] SIMD; WebAssembly target; GPU; streaming for very large files

## Testing

- **Unit tests**: `zig build test`
- **Integration tests** (snapshot-based, Zig runner in `tests/integration.zig`): `zig build integration-test`  
  Runs `pig` with fixed params, compares output (dimensions + file size) to `tests/snapshots/expected.json`. No regression: size must not exceed snapshot. To refresh snapshots when results improve or cases change: `zig build integration-test -Dupdate=true`. Fixtures in `tests/fixtures/`; see `tests/fixtures/README.md`.

## Contributing

This project uses Zig 0.15 and follows standard practices. PRs welcome for bug fixes and feature implementations from the TODO list.

## License

MIT
