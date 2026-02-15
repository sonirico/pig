# =============================================================================
# pig – 100% static CLI binary.
# Strategy: Alpine -static for truly dep-free leaf libs (zlib, expat, pcre2,
# jpeg, png). Everything else from source to avoid transitive dep mismatches.
# =============================================================================
# syntax=docker/dockerfile:1
FROM alpine:3.22 AS base

RUN apk add --no-cache \
    build-base \
    cmake \
    curl \
    gettext-dev \
    git \
    linux-headers \
    meson \
    ninja \
    pkgconfig \
    python3 \
    tar \
    xz \
    bzip2 \
    # Dep-free leaf libs: -dev (headers) + -static (.a)
    zlib-dev zlib-static \
    expat-dev expat-static \
    pcre2-dev pcre2-static \
    libjpeg-turbo-dev libjpeg-turbo-static \
    libpng-dev libpng-static

# =============================================================================
# Static deps: source-build everything else into /opt/static
# =============================================================================
FROM base AS static-deps
ARG PREFIX=/opt/static
WORKDIR /tmp

# Seed /opt/static with Alpine's dep-free .a and .pc files
RUN mkdir -p $PREFIX/lib $PREFIX/lib/pkgconfig && \
    for lib in z expat pcre2-8 jpeg png16; do \
        cp -f /usr/lib/lib${lib}.a $PREFIX/lib/ 2>/dev/null || true; \
    done && \
    for pc in zlib expat libpcre2-8 libjpeg libpng16 libpng; do \
        [ -f "/usr/lib/pkgconfig/${pc}.pc" ] && \
            sed 's|^libdir=.*|libdir=/opt/static/lib|' "/usr/lib/pkgconfig/${pc}.pc" \
            > "$PREFIX/lib/pkgconfig/${pc}.pc" || true; \
    done

COPY docker/static-deps-build.sh /tmp/
RUN chmod +x /tmp/static-deps-build.sh && /tmp/static-deps-build.sh

# =============================================================================
# libvips static
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
        --libdir=lib \
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
        -Dcfitsio=disabled \
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
    && (find $PREFIX/lib -name "*.so*" -delete 2>/dev/null || true) \
    && cd / && rm -rf /tmp/vips-*

# =============================================================================
# Zig build
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

RUN --mount=type=cache,target=/root/.cache/zig \
    --mount=type=cache,target=/app/.zig-cache \
    zig build -Doptimize=ReleaseSmall -Dstrip=true -Dstatic=true

# =============================================================================
FROM scratch AS artifact
COPY --from=zig-builder /app/zig-out/bin/pig /pig

FROM scratch AS production
COPY --from=zig-builder /app/zig-out/bin/pig /pig
ENTRYPOINT ["/pig"]
