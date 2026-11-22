#!/bin/bash
# Rebuilds Frameworks/LibXray.xcframework from XTLS/libXray (pinned commit).
#
# Output: 3 library slices (static libraries) in one xcframework:
#   - ios-arm64             iOS device, thin arm64
#   - ios-arm64-simulator   iOS simulator, thin arm64
#   - macos-arm64_x86_64    macOS universal (Apple Silicon + Intel)
# No tvOS slice is shipped, keeping the app/extension bundles small. Requires Xcode
# command line tools, python3 and Go; the Go toolchain required by libXray's go.mod
# (currently 1.27.3) is downloaded automatically by GOTOOLCHAIN=auto. If GitHub or the
# Go module proxy is not directly reachable, export an HTTPS proxy first, e.g.
#   export HTTPS_PROXY=socks5h://127.0.0.1:1080 ALL_PROXY=socks5h://127.0.0.1:1080
# When GitHub is unreachable but the pinned commit is already cached in
# tools/.cache/libXray, the script keeps going from that commit instead of failing.
#
# Local fork patches live in tools/libxray-patch/*.patch and are applied on top of the
# pinned upstream commit after the checkout is reset, so the build is reproducible:
#   wuji-traffic-stats.patch  adds the `getTrafficStats` invoke method used by the
#                             WujiTunnel extension to report real uplink/downlink bytes.
#
# Upstream's `build/main.py apple go` builds every Apple slice (iOS/tvOS/macOS); this
# script selects the iOS device/simulator slices plus the macOS universal slice and
# assembles them into the shipped xcframework.
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
if ! git -C "$SRC" fetch --tags origin; then
  # Rebuilding offline is safe when the pinned commit is already in the cache: the
  # checkout below is by commit SHA, so a stale ref cache cannot change the result.
  if git -C "$SRC" cat-file -e "$LIBXRAY_COMMIT^{commit}" 2>/dev/null; then
    echo "WARNING: git fetch failed; building offline from cached commit $LIBXRAY_COMMIT" >&2
  else
    echo "ERROR: git fetch failed and pinned commit $LIBXRAY_COMMIT is not cached" >&2
    exit 1
  fi
fi
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

# Build products of upstream's builder (all slices are rebuilt from scratch).
DEVICE="$SRC/apple_xcframework/iphoneos-arm64/libXray.a"
SIM_FAT="$SRC/apple_xcframework/iphonesimulator-x86_64-arm64/libXray.a"
MACOS="$SRC/apple_xcframework/macosx-x86_64-arm64/libXray.a"
HEADERS="$SRC/apple_xcframework/include"
for product in "$DEVICE" "$SIM_FAT" "$MACOS"; do
  if [ ! -f "$product" ]; then
    echo "missing upstream build product: $product" >&2
    exit 1
  fi
done

# Ship the iOS simulator slice thin arm64 (the xcframework is only for the iOS app).
SIM_DIR="$CACHE/sim"
mkdir -p "$SIM_DIR"
lipo -thin arm64 "$SIM_FAT" -output "$SIM_DIR/libXray.a"

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
xcodebuild -create-xcframework \
  -library "$DEVICE" -headers "$HEADERS" \
  -library "$SIM_DIR/libXray.a" -headers "$HEADERS" \
  -library "$MACOS" -headers "$HEADERS" \
  -output "$OUT"
echo "Built $OUT from libXray $LIBXRAY_COMMIT + $(ls "$PATCH_DIR"/*.patch 2>/dev/null | wc -l | tr -d ' ') patch(es)"
echo "Slices: ios-arm64 (thin arm64), ios-arm64-simulator (thin arm64), macos-arm64_x86_64 (arm64+x86_64)"
