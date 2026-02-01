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
mkdir -p /tmp/static-build && cd /tmp/static-build

# --- zlib ---
curl -sL https://zlib.net/zlib-1.3.1.tar.gz | tar xz && cd zlib-1.3.1
./configure --prefix=$PREFIX --static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf zlib-1.3.1

# --- libffi ---
curl -sL https://github.com/libffi/libffi/releases/download/v3.4.4/libffi-3.4.4.tar.gz | tar xz && cd libffi-3.4.4
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf libffi-3.4.4

# --- pcre2 ---
curl -sL https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.42/pcre2-10.42.tar.gz | tar xz && cd pcre2-10.42
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf pcre2-10.42

# --- expat ---
curl -sL https://github.com/libexpat/libexpat/releases/download/R_2_6_0/expat-2.6.0.tar.gz | tar xz && cd expat-2.6.0
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf expat-2.6.0

# --- libpng ---
curl -sL -o libpng.tar.xz "https://downloads.sourceforge.net/project/libpng/libpng16/1.6.43/libpng-1.6.43.tar.xz" && tar xJf libpng.tar.xz && cd libpng-1.6.43
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf libpng-1.6.43 libpng.tar.xz

# --- libjpeg-turbo ---
curl -sL https://github.com/libjpeg-turbo/libjpeg-turbo/archive/3.0.2.tar.gz | tar xz && cd libjpeg-turbo-3.0.2
cmake -B build -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_INSTALL_LIBDIR=lib -DENABLE_SHARED=OFF -DENABLE_STATIC=ON
cmake --build build -j$(nproc) && cmake --install build
cd /tmp/static-build && rm -rf libjpeg-turbo-3.0.2

# --- glib ---
curl -sL https://download.gnome.org/sources/glib/2.76/glib-2.76.6.tar.xz | tar xJ && cd glib-2.76.6
# Ensure meson finds our static libffi (and other deps) in $PREFIX
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
meson setup build --prefix=$PREFIX -Ddefault_library=static -Dnls=disabled -Dlibmount=disabled -Dselinux=disabled
ninja -C build && ninja -C build install
cd /tmp/static-build && rm -rf glib-2.76.6

# --- libtiff ---
curl -sL https://download.osgeo.org/libtiff/tiff-4.6.0.tar.gz | tar xz && cd tiff-4.6.0
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf tiff-4.6.0

# --- libwebp ---
curl -sL https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.4.0.tar.gz | tar xz && cd libwebp-1.4.0
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf libwebp-1.4.0

# --- libexif ---
curl -sL https://github.com/libexif/libexif/releases/download/libexif-0_6_24-release/libexif-0.6.24.tar.bz2 | tar xj && cd libexif-0.6.24
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf libexif-0.6.24

# --- fftw ---
curl -sL https://www.fftw.org/fftw-3.3.10.tar.gz | tar xz && cd fftw-3.3.10
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf fftw-3.3.10

# --- orc ---
curl -sL https://gstreamer.freedesktop.org/src/orc/orc-0.4.35.tar.xz | tar xJ && cd orc-0.4.35
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf orc-0.4.35

# --- lcms2 ---
curl -sL https://github.com/mm2/Little-CMS/releases/download/lcms2.16/lcms2-2.16.tar.gz | tar xz && cd lcms2-2.16
./configure --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf lcms2-2.16

# --- libimagequant ---
curl -sL https://github.com/lovell/libimagequant/archive/4.2.2.tar.gz | tar xz && cd libimagequant-4.2.2
meson setup build --prefix=$PREFIX -Ddefault_library=static
ninja -C build && ninja -C build install
cd /tmp/static-build && rm -rf libimagequant-4.2.2

# --- cgif ---
curl -sL https://github.com/dloebl/cgif/archive/refs/tags/V0.3.2.tar.gz | tar xz && cd cgif-0.3.2
meson setup build --prefix=$PREFIX -Ddefault_library=static
ninja -C build && ninja -C build install
cd /tmp/static-build && rm -rf cgif-0.3.2

# --- openjpeg ---
curl -sL https://github.com/uclouvain/openjpeg/archive/refs/tags/v2.5.2.tar.gz | tar xz && cd openjpeg-2.5.2
cmake -B build -DCMAKE_INSTALL_PREFIX=$PREFIX -DBUILD_SHARED_LIBS=OFF
cmake --build build -j$(nproc) && cmake --install build
cd /tmp/static-build && rm -rf openjpeg-2.5.2

# --- cfitsio ---
curl -sL https://heasarc.gsfc.nasa.gov/FTP/software/fitsio/c/cfitsio-4.3.0.tar.gz | tar xz && cd cfitsio-4.3.0
./configure --prefix=$PREFIX --enable-reentrant
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf cfitsio-4.3.0

# --- libarchive ---
curl -sL https://github.com/libarchive/libarchive/releases/download/v3.7.4/libarchive-3.7.4.tar.gz | tar xz && cd libarchive-3.7.4
./configure --prefix=$PREFIX --disable-shared --enable-static --without-openssl --without-xml2
make -j$(nproc) && make install
cd /tmp/static-build && rm -rf libarchive-3.7.4

# Remove any .so that might have been installed (we want only .a)
find $PREFIX/lib -name "*.so*" -delete 2>/dev/null || true
rm -rf /tmp/static-build
