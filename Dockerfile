# =============================================================================
# pig – 100% static CLI binary. All deps built from source into /opt/static.
# Use: make docker-build && make docker-extract  (binary in ./out/pig)
# Optimized: .dockerignore + COPY order + BuildKit cache so only changed layers rebuild.
# =============================================================================
# syntax=docker/dockerfile:1
FROM alpine:3.22 AS base

RUN apk add --no-cache \
    build-base \
    cmake \
    curl \
    gettext-dev \
    git \
    meson \
    ninja \
    pkgconfig \
    python3 \
    tar \
    xz \
    bzip2

# =============================================================================
# Static deps: build all libs into /opt/static (only .a, no .so)
# =============================================================================
FROM base AS static-deps
ARG PREFIX=/opt/static
WORKDIR /tmp

COPY docker/static-deps-build.sh /tmp/
RUN chmod +x /tmp/static-deps-build.sh && /tmp/static-deps-build.sh

# =============================================================================
# libvips static (against /opt/static), no rsvg/poppler/openexr/heif/jxl
# =============================================================================
FROM static-deps AS vips-static
ARG VIPS_VERSION=8.18.0
ARG PREFIX=/opt/static
ENV PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
ENV PATH=$PREFIX/bin:$PATH
ENV CPPFLAGS="-I$PREFIX/include"
ENV LDFLAGS="-L$PREFIX/lib"

RUN curl -sL "https://github.com/libvips/libvips/releases/download/v${VIPS_VERSION}/vips-${VIPS_VERSION}.tar.xz" | tar xJ && \
    cd vips-${VIPS_VERSION} && \
    meson setup build \
        --prefix=$PREFIX \
        --buildtype=release \
        -Ddefault_library=static \
        -Ddeprecated=false \
        -Dexamples=false \
        -Dcplusplus=false \
        -Ddocs=false \
        -Dintrospection=disabled \
        -Dvapi=false \
        -Dmodules=disabled \
        -Dimagequant=enabled \
        -Djpeg=enabled \
        -Dpng=enabled \
        -Dtiff=enabled \
        -Dwebp=enabled \
        -Dheif=disabled \
        -Dnsgif=true \
        -Dcgif=enabled \
        -Dpoppler=disabled \
        -Drsvg=disabled \
        -Dlcms=enabled \
        -Djpeg-xl=disabled \
        -Dfftw=enabled \
        -Dorc=enabled \
        -Dcfitsio=enabled \
        -Dopenjpeg=enabled \
        -Dopenexr=disabled \
        -Darchive=enabled \
        -Dexif=enabled \
        -Dzlib=enabled \
        -Dppm=true \
        -Danalyze=false \
        -Dradiance=false \
        -Dfuzzing_engine=none \
    && ninja -C build && ninja -C build install \
    && find $PREFIX/lib -name "*.so*" -delete 2>/dev/null || true \
    && cd / && rm -rf /tmp/vips-*

# =============================================================================
# Zig build: pig 100% static (PKG_CONFIG_PATH + LIBRARY_PATH = /opt/static)
# =============================================================================
FROM vips-static AS zig-builder
ARG ZIG_VERSION=0.15.2
ARG PREFIX=/opt/static

RUN curl -sL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" | tar xJ && \
    mv zig-x86_64-linux-${ZIG_VERSION} /usr/local/zig && \
    ln -s /usr/local/zig/zig /usr/local/bin/zig

ENV PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
ENV LIBRARY_PATH=$PREFIX/lib
ENV CPATH=$PREFIX/include
ENV PKG_CONFIG_SYSROOT_DIR=/

WORKDIR /app
COPY build.zig build.zig.zon ./
COPY src/ ./src/

# BuildKit cache: zig global + project cache so unchanged files don't recompile
RUN --mount=type=cache,target=/root/.cache/zig \
    --mount=type=cache,target=/app/.zig-cache \
    zig build -Doptimize=ReleaseFast -Dstrip=true -Dstatic=true

# =============================================================================
# Artifact: only the binary (docker build --output type=local,dest=./out)
# =============================================================================
FROM scratch AS artifact
COPY --from=zig-builder /app/zig-out/bin/pig /pig

# =============================================================================
# Production: minimal image, only the static binary
# =============================================================================
FROM scratch AS production
COPY --from=zig-builder /app/zig-out/bin/pig /pig
ENTRYPOINT ["/pig"]
