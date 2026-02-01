PROJECT_NAME := pig
DOCKERFILE := Dockerfile
ZIG_VERSION ?= 0.15.2
ZIG ?= zig
OUT_DIR ?= out

# Build configuration
OPTIMIZE ?= ReleaseFast
TARGET ?= native
TARGET_ARCH ?= x86_64
STRIP ?= true
STATIC ?= false
CPU ?= baseline

# Build flags (local zig build)
BUILD_FLAGS := -Doptimize=$(OPTIMIZE) -Dcpu=$(CPU) -Dstrip=$(STRIP)
ifeq ($(STATIC),true)
BUILD_FLAGS += -Dtarget=$(TARGET_ARCH)-linux-musl -Dstatic=true
else
BUILD_FLAGS += -Dtarget=$(TARGET)
endif

.PHONY: help build build-run fmt version install debug release docker-build docker-extract docker-image

help:
	@echo "Usage: make [target] [VAR=value]"
	@echo ""
	@echo "Variables:"
	@echo "  ZIG_VERSION   - Zig version (default: 0.15.2)"
	@echo "  OPTIMIZE      - ReleaseFast | ReleaseSafe | ReleaseSmall | Debug"
	@echo "  TARGET        - Target triple (default: native)"
	@echo "  TARGET_ARCH   - For static: x86_64 | aarch64 (default: x86_64)"
	@echo "  STRIP         - Strip symbols (default: true)"
	@echo "  STATIC        - Static binary, no runtime deps (default: false)"
	@echo "  CPU           - CPU features (default: baseline)"
	@echo "  OUT_DIR       - Where to extract binary from Docker (default: out)"
	@echo ""
	@echo "Targets:"
	@echo "  build         - Compile with zig (needs libvips-dev locally)"
	@echo "  release       - Optimized release (static if STATIC=true)"
	@echo "  debug         - Debug build, no strip, dynamic"
	@echo "  docker-build  - Build static binary inside Docker (no local deps)"
	@echo "  docker-extract - Extract static binary from Docker to $(OUT_DIR)/pig"
	@echo "  docker-image  - Build production image (scratch + binary)"
	@echo "  fmt           - Format Zig source"
	@echo "  install       - Install to /usr/local"
	@echo ""
	@echo "Examples:"
	@echo "  make build OPTIMIZE=Debug STATIC=false"
	@echo "  make docker-build && make docker-extract   # static binary in $(OUT_DIR)/pig"

version:
	@echo "Current configuration:"
	@echo "  ZIG_VERSION: $(ZIG_VERSION)"
	@echo "  ZIG: $(ZIG)"
	@echo "  OPTIMIZE: $(OPTIMIZE)"
	@echo "  TARGET: $(TARGET)"
	@echo "  STRIP: $(STRIP)"
	@echo "  STATIC: $(STATIC)"
	@echo "  CPU: $(CPU)"
	@echo "  BUILD_FLAGS: $(BUILD_FLAGS)"
	@echo ""
	@$(ZIG) version

build:
	@echo "🔨 Compiling with $(ZIG) [$(OPTIMIZE)]..."
	@echo "Flags: $(BUILD_FLAGS)"
	$(ZIG) build $(BUILD_FLAGS)

debug:
	@echo "🐛 Building debug version..."
	$(MAKE) build OPTIMIZE=Debug STRIP=false STATIC=false

release:
	@echo "🚀 Building optimized release..."
	$(MAKE) build OPTIMIZE=ReleaseFast STRIP=true STATIC=true

fmt:
	@echo "📝 Formatting with $(ZIG)..."
	$(ZIG) fmt ./**/*.zig

build-run:
	@echo "🚀 Running with $(ZIG)..."
	$(ZIG) build run $(BUILD_FLAGS)

install: build
	@echo "🔧 Installing with $(ZIG)..."
	sudo $(ZIG) build install --prefix /usr/local $(BUILD_FLAGS)

# --- Docker: isolated static build (no libvips on host) ---
DOCKER_BUILDKIT ?= 1
export DOCKER_BUILDKIT

docker-build:
	@echo "🐳 Building static pig inside Docker (libvips + Zig isolated)..."
	docker build -f $(DOCKERFILE) --target zig-builder -t $(PROJECT_NAME)-builder .

docker-extract: docker-build
	@mkdir -p $(OUT_DIR)
	@echo "📦 Extracting static binary to $(OUT_DIR)/pig..."
	docker build -f $(DOCKERFILE) --target artifact --output type=local,dest=$(OUT_DIR) .
	@chmod +x $(OUT_DIR)/pig
	@echo "Done. Run: $(OUT_DIR)/pig --help"

docker-image:
	@echo "🐳 Building production image (scratch + binary)..."
	docker build -f $(DOCKERFILE) --target production -t $(PROJECT_NAME):latest .