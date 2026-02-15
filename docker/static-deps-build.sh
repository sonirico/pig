#!/bin/sh
# Build static deps that Alpine doesn't ship as -static or that have
# transitive dep issues (glib→libmount, lcms2→fast_float, webp→sharpyuv,
# libarchive→openssl). Dep-free leaf libs (zlib, expat, pcre2, jpeg, png)
# come from Alpine packages — see Dockerfile.
set -e

PREFIX=/opt/static
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PATH="$PREFIX/bin:$PATH"
export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
export CFLAGS="-O2"

# Versions
LIBFFI_VER=3.4.4
GLIB_VER=2.82.5
LCMS2_VER=2.16
LIBWEBP_VER=1.4.0
LIBTIFF_VER=4.6.0
LIBEXIF_VER=0.6.24
FFTW_VER=3.3.10
ORC_VER=0.4.35
LIBIMAGEQUANT_VER=2.4.1
CGIF_VER=0.3.2
OPENJPEG_VER=2.5.2
LIBARCHIVE_VER=3.7.4

mkdir -p /tmp/static-build && cd /tmp/static-build

# --- proxy-libintl (implements libintl_* symbols for musl static linking) ---
cat > /tmp/proxy_intl.c << 'INTL_EOF'
#include <stddef.h>
char *libintl_gettext(const char *msgid) { return (char *)msgid; }
char *libintl_dgettext(const char *d, const char *msgid) { (void)d; return (char *)msgid; }
char *libintl_dcgettext(const char *d, const char *msgid, int c) { (void)d; (void)c; return (char *)msgid; }
char *libintl_ngettext(const char *s, const char *p, unsigned long n) { return (char *)(n == 1 ? s : p); }
char *libintl_dngettext(const char *d, const char *s, const char *p, unsigned long n) { (void)d; return (char *)(n == 1 ? s : p); }
char *libintl_dcngettext(const char *d, const char *s, const char *p, unsigned long n, int c) { (void)d; (void)c; return (char *)(n == 1 ? s : p); }
char *libintl_textdomain(const char *d) { return (char *)d; }
char *libintl_bindtextdomain(const char *d, const char *dir) { (void)d; return (char *)dir; }
char *libintl_bind_textdomain_codeset(const char *d, const char *c) { (void)d; return (char *)c; }
INTL_EOF
cc -c -O2 -o /tmp/proxy_intl.o /tmp/proxy_intl.c
ar rcs $PREFIX/lib/libintl.a /tmp/proxy_intl.o
rm -f /tmp/proxy_intl.c /tmp/proxy_intl.o

# --- libatomic.a (needed by glib on musl) ---
ATOMIC_A=$(find /usr/lib/gcc -name "libatomic.a" 2>/dev/null | head -1)
if [ -n "$ATOMIC_A" ]; then
    cp "$ATOMIC_A" $PREFIX/lib/libatomic.a
else
    ar rcs $PREFIX/lib/libatomic.a
fi

# --- libffi ---
curl -sL "https://github.com/libffi/libffi/releases/download/v${LIBFFI_VER}/libffi-${LIBFFI_VER}.tar.gz" | tar xz && cd "libffi-${LIBFFI_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "libffi-${LIBFFI_VER}"

# --- glib (source: need -Dlibmount=disabled to avoid libmount/libblkid) ---
curl -sL "https://download.gnome.org/sources/glib/2.82/glib-${GLIB_VER}.tar.xz" | tar xJ && cd "glib-${GLIB_VER}"
meson setup build --prefix=$PREFIX --libdir=lib -Ddefault_library=static \
    -Dnls=disabled -Dlibmount=disabled -Dselinux=disabled \
    -Dintrospection=disabled -Dtests=false -Dglib_debug=disabled
ninja -C build && ninja -C build install
cd /tmp/static-build && rm -rf "glib-${GLIB_VER}"

# --- lcms2 (source: Alpine's .pc drags in fast_float/threaded sub-libs) ---
curl -sL "https://github.com/mm2/Little-CMS/releases/download/lcms2.16/lcms2-${LCMS2_VER}.tar.gz" | tar xz && cd "lcms2-${LCMS2_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "lcms2-${LCMS2_VER}"

# --- libwebp (source: need sharpyuv merge for vips) ---
curl -sL "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${LIBWEBP_VER}.tar.gz" | tar xz && cd "libwebp-${LIBWEBP_VER}"
cmake -B build -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_ANIM_UTILS=OFF \
    -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
    -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF \
    -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF
cmake --build build -j$(nproc) && cmake --install build
cd /tmp/static-build && rm -rf "libwebp-${LIBWEBP_VER}"
# Merge sharpyuv into libwebp.a (vips meson doesn't resolve the transitive dep)
mkdir -p /tmp/sharpyuv_merge && cd /tmp/sharpyuv_merge
ar x $PREFIX/lib/libsharpyuv.a
ar rs $PREFIX/lib/libwebp.a *.o
cd /tmp/static-build && rm -rf /tmp/sharpyuv_merge

# --- libtiff ---
curl -sL "https://download.osgeo.org/libtiff/tiff-${LIBTIFF_VER}.tar.gz" | tar xz && cd "tiff-${LIBTIFF_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "tiff-${LIBTIFF_VER}"

# --- libexif ---
curl -sL "https://github.com/libexif/libexif/releases/download/v${LIBEXIF_VER}/libexif-${LIBEXIF_VER}.tar.bz2" | tar xj && cd "libexif-${LIBEXIF_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static --disable-nls
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "libexif-${LIBEXIF_VER}"

# --- fftw ---
curl -sL "https://www.fftw.org/fftw-${FFTW_VER}.tar.gz" | tar xz && cd "fftw-${FFTW_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "fftw-${FFTW_VER}"

# --- orc ---
curl -sL "https://gstreamer.freedesktop.org/src/orc/orc-${ORC_VER}.tar.xz" | tar xJ && cd "orc-${ORC_VER}"
meson setup build --prefix=$PREFIX --libdir=lib -Ddefault_library=static
ninja -C build && ninja -C build install
cd /tmp/static-build && rm -rf "orc-${ORC_VER}"

# --- libimagequant ---
curl -sL "https://github.com/lovell/libimagequant/archive/v${LIBIMAGEQUANT_VER}.tar.gz" | tar xz && cd "libimagequant-${LIBIMAGEQUANT_VER}"
meson setup build --prefix=$PREFIX --libdir=lib -Ddefault_library=static
ninja -C build && ninja -C build install
cd /tmp/static-build && rm -rf "libimagequant-${LIBIMAGEQUANT_VER}"

# --- cgif ---
curl -sL "https://github.com/dloebl/cgif/archive/refs/tags/V${CGIF_VER}.tar.gz" | tar xz && cd "cgif-${CGIF_VER}"
meson setup build --prefix=$PREFIX --libdir=lib -Ddefault_library=static
ninja -C build && ninja -C build install
cd /tmp/static-build && rm -rf "cgif-${CGIF_VER}"

# --- openjpeg ---
curl -sL "https://github.com/uclouvain/openjpeg/archive/refs/tags/v${OPENJPEG_VER}.tar.gz" | tar xz && cd "openjpeg-${OPENJPEG_VER}"
cmake -B build -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=OFF
cmake --build build -j$(nproc) && cmake --install build
cd /tmp/static-build && rm -rf "openjpeg-${OPENJPEG_VER}"

# --- libarchive (source: Alpine's links against openssl) ---
curl -sL "https://github.com/libarchive/libarchive/releases/download/v${LIBARCHIVE_VER}/libarchive-${LIBARCHIVE_VER}.tar.gz" | tar xz && cd "libarchive-${LIBARCHIVE_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static --without-openssl --without-xml2
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "libarchive-${LIBARCHIVE_VER}"

# Final cleanup
find $PREFIX/lib -name "*.so*" -delete 2>/dev/null || true
rm -rf /tmp/static-build
