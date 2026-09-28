#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIG_BIN="${ZIG:-$(command -v zig || true)}"
# The bridge targets Zig 0.15.2. Prefer the pinned zvm installation over master.
if [ -z "${ZIG:-}" ] && [ -x "$HOME/.zvm/0.15.2/zig" ]; then
  ZIG_BIN="$HOME/.zvm/0.15.2/zig"
fi
if [ -z "$ZIG_BIN" ]; then
  for candidate in "$HOME/.zvm/bin/zig" /opt/homebrew/bin/zig /usr/local/bin/zig; do
    if [ -x "$candidate" ]; then ZIG_BIN="$candidate"; break; fi
  done
fi
if [ -z "$ZIG_BIN" ]; then echo 'Install Zig or set ZIG to its executable path.' >&2; exit 1; fi
if [ "$("$ZIG_BIN" version)" != '0.15.2' ]; then
  echo 'This project uses Zig 0.15.2. Set ZIG to a Zig 0.15.2 executable.' >&2
  exit 1
fi
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$PROJECT_ROOT/build/zig-cache}"
mkdir -p "$PROJECT_ROOT/build/native"
build_arch() {
  local arch="$1"
  local target
  case "$arch" in arm64) target=aarch64;; x86_64) target=x86_64;; *) echo "Unsupported architecture: $arch" >&2; exit 1;; esac
  # Apple clang performs the final link, so the object must carry Zig's runtime
  # helpers (including the x86_64 stack probe used by ReleaseSafe builds).
  "$ZIG_BIN" build-obj "$PROJECT_ROOT/native/src/controller.zig" \
    -fPIC -fcompiler-rt -O ReleaseSafe -lc -target "$target-macos.11.0" \
    -I "$PROJECT_ROOT/native" -isystem "$SDK_PATH/usr/include" \
    -F "$SDK_PATH/System/Library/Frameworks" \
    -femit-bin="$PROJECT_ROOT/build/native/controller-$arch.o"
  xcrun clang -dynamiclib -arch "$arch" -mmacosx-version-min=11.0 -isysroot "$SDK_PATH" \
    "$PROJECT_ROOT/build/native/controller-$arch.o" \
    -framework IOKit -framework CoreFoundation -framework ApplicationServices \
    -install_name @rpath/libcontroller_hid.dylib \
    -o "$PROJECT_ROOT/build/native/libcontroller_hid-$arch.dylib"
}
ARCHITECTURES="${ARCHS:-$(uname -m)}"
OUTPUTS=()
for arch in $ARCHITECTURES; do
  build_arch "$arch"
  OUTPUTS+=("$PROJECT_ROOT/build/native/libcontroller_hid-$arch.dylib")
done
lipo -create "${OUTPUTS[@]}" -output "$PROJECT_ROOT/build/native/libcontroller_hid.dylib"
if [ -n "${TARGET_BUILD_DIR:-}" ]; then
  DESTINATION="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/libcontroller_hid.dylib"
  mkdir -p "$(dirname "$DESTINATION")"
  cp "$PROJECT_ROOT/build/native/libcontroller_hid.dylib" "$DESTINATION"
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$DESTINATION"
fi
