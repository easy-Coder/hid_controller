#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$PROJECT_ROOT/scripts/build_native.sh"
ZIG_BIN="${ZIG:-$HOME/.zvm/0.15.2/zig}"
if [ ! -x "$ZIG_BIN" ]; then ZIG_BIN="$(command -v zig)"; fi
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$PROJECT_ROOT/build/zig-cache}"
case "$(uname -m)" in arm64) TEST_TARGET=aarch64;; x86_64) TEST_TARGET=x86_64;; esac
"$ZIG_BIN" test "$PROJECT_ROOT/native/src/key_state.zig" -target "$TEST_TARGET-macos.11.0" \
  -L "$SDK_PATH/usr/lib"
"$ZIG_BIN" test "$PROJECT_ROOT/native/src/switch_report.zig" -target "$TEST_TARGET-macos.11.0" \
  -L "$SDK_PATH/usr/lib"
python3 "$PROJECT_ROOT/scripts/smoke_native.py"
