#!/usr/bin/env bash
set -euo pipefail

# SDK_NAME / OUT_DIR 可由 CI 传入；默认值如下
SDK_NAME="${SDK_NAME:-hf-tokenizer-sdk-windows-x86_64}"
OUT_DIR="${OUT_DIR:-dist}"
TARGET="${TARGET:-x86_64-pc-windows-gnu}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/$SDK_NAME"
mkdir -p "$OUT_DIR/$SDK_NAME/include" "$OUT_DIR/$SDK_NAME/lib" "$OUT_DIR/$SDK_NAME/bin"

# --- ensure rustup/cargo visible in MSYS2 ---
if ! command -v rustup >/dev/null 2>&1; then
  # 尝试从 USERPROFILE 推导
  if [ -n "${USERPROFILE:-}" ]; then
    # 把 \ 转成 /，并把 C:\ 变成 /c/
    up="$(echo "$USERPROFILE" | sed 's|\\|/|g')"
    up="/${up:0:1,,}${up:2}"   # "C:/Users/.." -> "/c/Users/.."
    export PATH="$up/.cargo/bin:$PATH"
  fi
fi

if ! command -v rustup >/dev/null 2>&1; then
  echo "ERROR: rustup not found in PATH under MSYS2."
  echo "Try exporting PATH like: /c/Users/runneradmin/.cargo/bin:\$PATH"
  exit 1
fi
# -------------------------------------------

echo "[1/4] Ensure rust toolchain"
rustup toolchain install stable --profile minimal
rustup default stable
rustup target add "$TARGET"

echo "[2/4] Build Rust FFI (cdylib + staticlib)"
# 如果你需要固定用 mingw gcc：
# export CC=x86_64-w64-mingw32-gcc
# export CXX=x86_64-w64-mingw32-g++
# export AR=x86_64-w64-mingw32-ar
# export RANLIB=x86_64-w64-mingw32-ranlib

cargo build -p hf_tokenizer_ffi --release --target "$TARGET"

BIN_DIR="target/$TARGET/release"

# 期望产物：
#   hf_tokenizer_ffi.dll
#   libhf_tokenizer_ffi.a
#   libhf_tokenizer_ffi.dll.a
test -f "$BIN_DIR/hf_tokenizer_ffi.dll"
test -f "$BIN_DIR/libhf_tokenizer_ffi.a"
test -f "$BIN_DIR/libhf_tokenizer_ffi.dll.a"

echo "[3/4] Stage SDK layout"
# headers（按你仓库实际 include 位置调整）
cp -v include/hf_tokenizer_c.h "$OUT_DIR/$SDK_NAME/include/"
# 如果你还有 C++ 头也要打包：
# cp -v include/hf_tokenizer.hpp "$OUT_DIR/$SDK_NAME/include/"

cp -v "$BIN_DIR/libhf_tokenizer_ffi.a" "$OUT_DIR/$SDK_NAME/lib/"
cp -v "$BIN_DIR/libhf_tokenizer_ffi.dll.a" "$OUT_DIR/$SDK_NAME/lib/"
cp -v "$BIN_DIR/hf_tokenizer_ffi.dll" "$OUT_DIR/$SDK_NAME/bin/"

echo "[4/4] Pack + sha256"
ARCHIVE="$OUT_DIR/$SDK_NAME.zip"
rm -f "$ARCHIVE" "$ARCHIVE.sha256"

# windows 上更建议 zip
( cd "$OUT_DIR" && zip -r "$SDK_NAME.zip" "$SDK_NAME" )

# MSYS2 有 sha256sum
sha256sum "$ARCHIVE" > "$ARCHIVE.sha256"

echo "DONE: $ARCHIVE"
