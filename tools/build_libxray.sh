#!/bin/bash
# Rebuilds Frameworks/LibXray.xcframework from XTLS/libXray (pinned commit).
#
# Output: iOS device arm64 + iOS simulator arm64 (static lib, no macOS/tvOS slices,
# keeping the app bundle small). Requires Xcode command line tools, python3 and Go;
# Go >= 1.27 is downloaded automatically by the toolchain. If GitHub or the Go module
# proxy is not directly reachable, export an HTTPS proxy first, e.g.
#   export HTTPS_PROXY=socks5h://127.0.0.1:1080 ALL_PROXY=socks5h://127.0.0.1:1080
#
# Local fork patches live in tools/libxray-patch/*.patch and are applied on top of the
# pinned upstream commit after the checkout is reset, so the build is reproducible:
#   wuji-traffic-stats.patch  adds the `getTrafficStats` invoke method used by the
#                             WujiTunnel extension to report real uplink/downlink bytes.
#
# Usage:
#   tools/build_libxray.sh              # normal reproducible rebuild
#   LIBXRAY_COMMIT=<sha> tools/build_libxray.sh   # deliberately move to another upstream
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/tools/.cache"
SRC="$CACHE/libXray"
OUT="$ROOT/Frameworks/LibXray.xcframework"
PATCH_DIR="$ROOT/tools/libxray-patch"
# Upstream commit the shipped xcframework is built from; bump together with the patches.
LIBXRAY_COMMIT="${LIBXRAY_COMMIT:-5a0f7d8d1c28b34afb5727b04b26a10f6dbac7e3}"
mkdir -p "$CACHE"

if [ ! -d "$SRC/.git" ]; then
  git clone https://github.com/XTLS/libXray.git "$SRC"
fi
git -C "$SRC" fetch --tags origin
# Pin to the recorded upstream commit and drop any previous patch application.
git -C "$SRC" checkout -f "$LIBXRAY_COMMIT"
git -C "$SRC" reset --hard "$LIBXRAY_COMMIT"
git -C "$SRC" clean -fd

if [ -d "$PATCH_DIR" ]; then
  shopt -s nullglob
  patches=("$PATCH_DIR"/*.patch)
  if [ ${#patches[@]} -eq 0 ]; then
    echo "No patches found in $PATCH_DIR, building upstream as-is"
  fi
  for patch in "${patches[@]}"; do
    echo "Applying $(basename "$patch")"
    git -C "$SRC" apply --whitespace=nowarn "$patch"
  done
  shopt -u nullglob
fi

cd "$SRC"
python3 build/main.py apple go

DEVICE="$SRC/apple_xcframework/iphoneos-arm64/libXray.a"
SIM_LIPO="$SRC/apple_xcframework/iphonesimulator-x86_64-arm64/libXray.a"
SIM_DIR="$CACHE/sim"
mkdir -p "$SIM_DIR"
lipo -thin arm64 "$SIM_LIPO" -output "$SIM_DIR/libXray.a"

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
xcodebuild -create-xcframework \
  -library "$DEVICE" -headers "$SRC/apple_xcframework/include" \
  -library "$SIM_DIR/libXray.a" -headers "$SRC/apple_xcframework/include" \
  -output "$OUT"
echo "Built $OUT from libXray $LIBXRAY_COMMIT + $(ls "$PATCH_DIR"/*.patch 2>/dev/null | wc -l | tr -d ' ') patch(es)"
