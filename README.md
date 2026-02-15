<div align="center">
  <img src="pig.png" alt="pig mascot" width="96" />

  # pig

  *Fast image processing CLI* — Zig + libvips.

  [![Zig](https://img.shields.io/badge/Zig-0.15+-F7A41D?style=flat&logo=zig&logoColor=white)](https://ziglang.org/)
  [![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
  [![libvips](https://img.shields.io/badge/libvips-8.18+-4B8BBE?style=flat)](https://libvips.github.io/libvips/)
  [![Release](https://img.shields.io/github/v/release/sonirico/pig?style=flat)](https://github.com/sonirico/pig/releases)
</div>

<p align="center">
  <img src="demo.gif" alt="pig print demo" width="640" />
</p>

## Installation

### Quick install

```bash
curl -sSL https://raw.githubusercontent.com/sonirico/pig/main/install.sh | bash
```

### Binary releases

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

All commands read from stdin too, so they work in pipelines.

```bash
pig inspect image.jpg
cat image.jpg | pig inspect
pig inspect --json image.jpg | jq '.width'
```

### Commands

**inspect** — image properties (dimensions, format, size, etc.)
```bash
pig inspect photo.jpg
pig inspect --json photo.jpg
```

**optimize** — compress/convert (format inferred from output extension)
```bash
pig optimize photo.jpg -o out.webp -q 80 --strip
pig optimize photo.png -o out.png --palette -q 80
```

**crop** — extract a region
```bash
pig crop -i photo.jpg -o cropped.png 100 100 800 600   # x y width height
```

**scale** — resize
```bash
pig scale photo.jpg 1920 1080
```

**print** — render image in the terminal
```bash
pig print photo.jpg              # Unicode half-blocks (any true-color terminal)
pig print --kitty photo.jpg      # Kitty graphics protocol
```

### Supported output formats

Format is inferred from the `-o` extension. See `pig optimize --help` for format-specific options.

| Format        | Extensions              | Optional deps |
|---------------|-------------------------|---------------|
| JPEG          | .jpg, .jpeg             | -             |
| PNG           | .png                    | -             |
| WebP          | .webp                   | -             |
| TIFF          | .tiff, .tif             | -             |
| GIF           | .gif                    | -             |
| HEIF / AVIF   | .heic, .heif, .avif     | libheif       |
| JPEG 2000     | .jp2, .j2k              | openjp2       |
| JPEG XL       | .jxl                    | libjxl        |

### Pipeline examples

```bash
# Batch convert to webp
find . -name "*.jpg" -exec sh -c 'pig optimize "$1" -o "${1%.jpg}.webp" -q 80 --strip' _ {} \;

# Sum file sizes
for img in *.jpg; do pig inspect --json "$img"; done | jq '.size_bytes' | paste -sd+ | bc
```

## Roadmap

- Batch mode, config file, progress bars
- Color profiles, watermarks, filters (blur, sharpen)
- Multi-threading for batch ops

## Testing

```bash
zig build test
zig build integration-test
```

## License

MIT
