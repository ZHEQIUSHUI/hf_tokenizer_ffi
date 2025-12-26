#!/usr/bin/env bash
set -euo pipefail

echo "[build_sdk_x86_64] start"

PROJECT_DIR="${PROJECT_DIR:-.}"   # Cargo.toml 所在目录
TARGET="${TARGET:-x86_64-unknown-linux-gnu}"
PROFILE="${PROFILE:-release}"

SDK_NAME="${SDK_NAME:-hf-tokenizer-sdk-x86_64}"
OUT_DIR="${OUT_DIR:-dist}"

cd "${PROJECT_DIR}"

# 安装 rust/cargo（CI 非交互）
if ! command -v cargo >/dev/null 2>&1; then
  echo "[build_sdk_x86_64] installing rustup/cargo"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
# shellcheck disable=SC1090
source "${HOME}/.cargo/env"

echo "[build_sdk_x86_64] rust versions"
rustup --version
rustc --version
cargo --version

# x86_64 target 通常默认就有，但加一下更稳
rustup target add "${TARGET}" || true

echo "[build_sdk_x86_64] cargo build"
cargo build --profile "${PROFILE}" --target "${TARGET}"

LIB_PATH="target/${TARGET}/${PROFILE}/libhf_tokenizer_ffi.a"
if [[ ! -f "${LIB_PATH}" ]]; then
  echo "ERROR: not found: ${LIB_PATH}"
  exit 1
fi

echo "[build_sdk_x86_64] package sdk"
rm -rf "${OUT_DIR:?}/${SDK_NAME}"
mkdir -p "${OUT_DIR}/${SDK_NAME}/lib" "${OUT_DIR}/${SDK_NAME}/include"

cp -v "${LIB_PATH}" "${OUT_DIR}/${SDK_NAME}/lib/"

if [[ -f "include/hf_tokenizer_c.h" ]]; then
  cp -v "include/hf_tokenizer_c.h" "${OUT_DIR}/${SDK_NAME}/include/"
else
  echo "ERROR: include/hf_tokenizer_c.h not found"
  exit 1
fi

if [[ -f "hf_tokenizer.hpp" ]]; then
  cp -v "hf_tokenizer.hpp" "${OUT_DIR}/${SDK_NAME}/include/"
fi

cat > "${OUT_DIR}/${SDK_NAME}/README.txt" <<'EOF'
HF Tokenizer FFI SDK (x86_64)

Contents:
- lib/libhf_tokenizer_ffi.a
- include/hf_tokenizer_c.h
- (optional) include/hf_tokenizer.hpp

Link example:
g++ main.cpp -Iinclude lib/libhf_tokenizer_ffi.a -lpthread -ldl -lm -o demo
EOF

GIT_REV="$(git rev-parse --short HEAD 2>/dev/null || true)"
echo "${GIT_REV}" > "${OUT_DIR}/${SDK_NAME}/VERSION.txt"

tar -czf "${OUT_DIR}/${SDK_NAME}.tar.gz" -C "${OUT_DIR}" "${SDK_NAME}"
sha256sum "${OUT_DIR}/${SDK_NAME}.tar.gz" > "${OUT_DIR}/${SDK_NAME}.tar.gz.sha256"

echo "[build_sdk_x86_64] done"
ls -lh "${OUT_DIR}/${SDK_NAME}.tar.gz" "${OUT_DIR}/${SDK_NAME}.tar.gz.sha256"
