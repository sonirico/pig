#!/bin/sh
# Build all static deps for libvips into /opt/static (no .so, only .a).
# Run from Alpine with build-base, curl, meson, ninja, cmake, etc.
set -e

PREFIX=/opt/static
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
export PATH=$PREFIX/bin:$PATH
export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
export CFLAGS="-O2"

# Versions (single place to bump)
ZLIB_VER=1.3.1
LIBFFI_VER=3.4.4
PCRE2_VER=10.42
EXPAT_VER=2.6.0
LIBPNG_VER=1.6.43
LIBJPEG_VER=3.0.2
GLIB_VER=2.76.6
LIBTIFF_VER=4.6.0
LIBWEBP_VER=1.4.0
LIBEXIF_VER=0.6.24
FFTW_VER=3.3.10
ORC_VER=0.4.35
LCMS2_VER=2.16
LIBIMAGEQUANT_VER=4.2.2
CGIF_VER=0.3.2
OPENJPEG_VER=2.5.2
CFITSIO_VER=4.3.0
LIBARCHIVE_VER=3.7.4

mkdir -p /tmp/static-build && cd /tmp/static-build

# --- zlib ---
curl -sL "https://zlib.net/zlib-${ZLIB_VER}.tar.gz" | tar xz && cd "zlib-${ZLIB_VER}"
./configure --prefix=$PREFIX --static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "zlib-${ZLIB_VER}"

# --- libffi ---
curl -sL "https://github.com/libffi/libffi/releases/download/v${LIBFFI_VER}/libffi-${LIBFFI_VER}.tar.gz" | tar xz && cd "libffi-${LIBFFI_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "libffi-${LIBFFI_VER}"

# --- pcre2 ---
curl -sL "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VER}/pcre2-${PCRE2_VER}.tar.gz" | tar xz && cd "pcre2-${PCRE2_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "pcre2-${PCRE2_VER}"

# --- expat ---
curl -sL "https://github.com/libexpat/libexpat/releases/download/R_2_6_0/expat-${EXPAT_VER}.tar.gz" | tar xz && cd "expat-${EXPAT_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "expat-${EXPAT_VER}"

# --- libpng ---
curl -sL -o libpng.tar.xz "https://downloads.sourceforge.net/project/libpng/libpng16/${LIBPNG_VER}/libpng-${LIBPNG_VER}.tar.xz" && tar xJf libpng.tar.xz && cd "libpng-${LIBPNG_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "libpng-${LIBPNG_VER}" libpng.tar.xz

# --- libjpeg-turbo ---
curl -sL "https://github.com/libjpeg-turbo/libjpeg-turbo/archive/${LIBJPEG_VER}.tar.gz" | tar xz && cd "libjpeg-turbo-${LIBJPEG_VER}"
cmake -B build -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=lib -DENABLE_SHARED=OFF -DENABLE_STATIC=ON
cmake --build build -j$(nproc) && cmake --install build
cd /tmp/static-build && rm -rf "libjpeg-turbo-${LIBJPEG_VER}"

# --- glib ---
curl -sL "https://download.gnome.org/sources/glib/2.76/glib-${GLIB_VER}.tar.xz" | tar xJ && cd "glib-${GLIB_VER}"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
meson setup build --prefix=$PREFIX -Ddefault_library=static -Dnls=disabled -Dlibmount=disabled -Dselinux=disabled
ninja -C build && ninja -C build install
cd /tmp/static-build && rm -rf "glib-${GLIB_VER}"

# --- libtiff ---
curl -sL "https://download.osgeo.org/libtiff/tiff-${LIBTIFF_VER}.tar.gz" | tar xz && cd "tiff-${LIBTIFF_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "tiff-${LIBTIFF_VER}"

# --- libwebp ---
curl -sL "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${LIBWEBP_VER}.tar.gz" | tar xz && cd "libwebp-${LIBWEBP_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "libwebp-${LIBWEBP_VER}"

# --- libexif ---
curl -sL "https://github.com/libexif/libexif/releases/download/v${LIBEXIF_VER}/libexif-${LIBEXIF_VER}.tar.bz2" | tar xj && cd "libexif-${LIBEXIF_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "libexif-${LIBEXIF_VER}"

# --- fftw ---
curl -sL "https://www.fftw.org/fftw-${FFTW_VER}.tar.gz" | tar xz && cd "fftw-${FFTW_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "fftw-${FFTW_VER}"

# --- orc ---
curl -sL "https://gstreamer.freedesktop.org/src/orc/orc-${ORC_VER}.tar.xz" | tar xJ && cd "orc-${ORC_VER}"
meson setup build --prefix=$PREFIX -Ddefault_library=static
ninja -C build && ninja -C build install
cd /tmp/static-build && rm -rf "orc-${ORC_VER}"

# --- lcms2 ---
curl -sL "https://github.com/mm2/Little-CMS/releases/download/lcms2.16/lcms2-${LCMS2_VER}.tar.gz" | tar xz && cd "lcms2-${LCMS2_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "lcms2-${LCMS2_VER}"

# --- libimagequant ---
curl -sL "https://github.com/lovell/libimagequant/archive/${LIBIMAGEQUANT_VER}.tar.gz" | tar xz && cd "libimagequant-${LIBIMAGEQUANT_VER}"
meson setup build --prefix=$PREFIX -Ddefault_library=static
ninja -C build && ninja -C build install
cd /tmp/static-build && rm -rf "libimagequant-${LIBIMAGEQUANT_VER}"

# --- cgif ---
curl -sL "https://github.com/dloebl/cgif/archive/refs/tags/V${CGIF_VER}.tar.gz" | tar xz && cd "cgif-${CGIF_VER}"
meson setup build --prefix=$PREFIX -Ddefault_library=static
ninja -C build && ninja -C build install
cd /tmp/static-build && rm -rf "cgif-${CGIF_VER}"

# --- openjpeg ---
curl -sL "https://github.com/uclouvain/openjpeg/archive/refs/tags/v${OPENJPEG_VER}.tar.gz" | tar xz && cd "openjpeg-${OPENJPEG_VER}"
cmake -B build -DCMAKE_INSTALL_PREFIX=$PREFIX -DBUILD_SHARED_LIBS=OFF
cmake --build build -j$(nproc) && cmake --install build
cd /tmp/static-build && rm -rf "openjpeg-${OPENJPEG_VER}"

# --- cfitsio ---
curl -sL "https://heasarc.gsfc.nasa.gov/FTP/software/fitsio/c/cfitsio-${CFITSIO_VER}.tar.gz" | tar xz && cd "cfitsio-${CFITSIO_VER}"
./configure --prefix=$PREFIX --enable-reentrant
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "cfitsio-${CFITSIO_VER}"

# --- libarchive ---
curl -sL "https://github.com/libarchive/libarchive/releases/download/v${LIBARCHIVE_VER}/libarchive-${LIBARCHIVE_VER}.tar.gz" | tar xz && cd "libarchive-${LIBARCHIVE_VER}"
./configure --prefix=$PREFIX --disable-shared --enable-static --without-openssl --without-xml2
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf "libarchive-${LIBARCHIVE_VER}"

find $PREFIX/lib -name "*.so*" -delete 2>/dev/null || true
rm -rf /tmp/static-build
