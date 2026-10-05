#!/bin/bash
# CodeWeavers가 LGPL로 공개한 CrossOver 소스에서 Wine DLL 몇 개만 빌드해 Resources/WineOverrides에 넣는다.
# 이 DLL들은 Sikarugir(Wine 10) 엔진 앞에 놓여 그 버전의 버그를 대신한다.
#   wbemprox.dll: Wine 10은 WMI 표마다 잠금을 쿼리가 끝날 때까지 잡고 있어서,
#                 게임과 안티치트가 같은 표를 동시에 조회하면 멈춘다 (블루 아카이브 타이틀 멈춤).
# 필요: brew install mingw-w64 bison flex
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${CROSSOVER_VERSION:-26.3.0}"
VENDOR="vendor"
SRC="$VENDOR/sources/wine"
BUILD="$VENDOR/build-wine"
OUT="Resources/WineOverrides"
DLLS=(wbemprox)

export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
if [[ -z "${SDKROOT:-}" ]]; then
    SDKROOT=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)
    [[ -n "$SDKROOT" ]] && export SDKROOT
fi
command -v x86_64-w64-mingw32-gcc >/dev/null || { echo "mingw-w64가 필요합니다: brew install mingw-w64 bison flex"; exit 1; }

if [[ ! -d "$SRC" ]]; then
    mkdir -p "$VENDOR"
    TARBALL="$VENDOR/crossover-sources-$VERSION.tar.gz"
    curl -fL -o "$TARBALL" "https://media.codeweavers.com/pub/crossover/source/crossover-sources-$VERSION.tar.gz"
    tar -xzf "$TARBALL" -C "$VENDOR"
fi

mkdir -p "$BUILD"
if [[ ! -f "$BUILD/Makefile" ]]; then
    (cd "$BUILD" && "../sources/wine/configure" --enable-archs=x86_64 --host=x86_64-apple-darwin CC="clang -arch x86_64" \
        --without-x --without-freetype --without-gnutls --without-gstreamer --without-vulkan --without-opencl \
        --without-cups --without-sane --without-krb5 --without-sdl --without-usb --without-pcap --without-gphoto \
        --without-netapi --without-capi --without-inotify --without-ffmpeg --disable-tests > configure.log)
fi

mkdir -p "$OUT/x86_64-windows"
for dll in "${DLLS[@]}"; do
    make -C "$BUILD" -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 8)" "dlls/$dll/x86_64-windows/$dll.dll" > "$BUILD/make-$dll.log"
    x86_64-w64-mingw32-strip -o "$OUT/x86_64-windows/$dll.dll" "$BUILD/dlls/$dll/x86_64-windows/$dll.dll"
    echo "빌드됨: $OUT/x86_64-windows/$dll.dll"
done
echo "CrossOver $VERSION LGPL 소스: https://media.codeweavers.com/pub/crossover/source/crossover-sources-$VERSION.tar.gz" > "$OUT/SOURCE.txt"
