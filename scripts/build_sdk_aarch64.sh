#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-.}"
TARGET="${TARGET:-aarch64-unknown-linux-gnu}"
PROFILE="${PROFILE:-release}"
SDK_NAME="${SDK_NAME:-hf-tokenizer-sdk-aarch64}"
OUT_DIR="${OUT_DIR:-dist}"

cd "${PROJECT_DIR}"

# shellcheck disable=SC1090
source "${HOME}/.cargo/env"

# 确保 toolchain 在 PATH（由 setup_arm_toolchain.sh 写入 GITHUB_PATH）
command -v aarch64-none-linux-gnu-gcc >/dev/null 2>&1 || {
  echo "ERROR: aarch64-none-linux-gnu-gcc not found in PATH"
  exit 1
}
command -v aarch64-none-linux-gnu-ar >/dev/null 2>&1 || {
  echo "ERROR: aarch64-none-linux-gnu-ar not found in PATH"
  exit 1
}

rustup target add "${TARGET}"

# 指定 cargo 用这个 linker/ar（比依赖 .cargo/config.toml 更可控）
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="aarch64-none-linux-gnu-gcc"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_AR="aarch64-none-linux-gnu-ar"

cargo build --profile "${PROFILE}" --target "${TARGET}"

LIB_PATH="target/${TARGET}/${PROFILE}/libhf_tokenizer_ffi.a"
if [[ ! -f "${LIB_PATH}" ]]; then
  echo "ERROR: not found: ${LIB_PATH}"
  exit 1
fi

rm -rf "${OUT_DIR:?}/${SDK_NAME}"
mkdir -p "${OUT_DIR}/${SDK_NAME}/lib" "${OUT_DIR}/${SDK_NAME}/include"

cp -v "${LIB_PATH}" "${OUT_DIR}/${SDK_NAME}/lib/"

# C 头文件
if [[ -f "include/hf_tokenizer_c.h" ]]; then
  cp -v "include/hf_tokenizer_c.h" "${OUT_DIR}/${SDK_NAME}/include/"
else
  echo "ERROR: include/hf_tokenizer_c.h not found"
  exit 1
fi

# 可选：如果你仓库里也放了 C++ wrapper 头文件，就一起打包
if [[ -f "hf_tokenizer.hpp" ]]; then
  cp -v "hf_tokenizer.hpp" "${OUT_DIR}/${SDK_NAME}/include/"
fi

# README
cat > "${OUT_DIR}/${SDK_NAME}/README.txt" <<'EOF'
HF Tokenizer FFI SDK (aarch64)

Contents:
- lib/libhf_tokenizer_ffi.a
- include/hf_tokenizer_c.h
- (optional) include/hf_tokenizer.hpp

Link example:
aarch64-none-linux-gnu-g++ main.cpp -Iinclude lib/libhf_tokenizer_ffi.a -lpthread -ldl -lm -o demo
EOF

GIT_REV="$(git rev-parse --short HEAD 2>/dev/null || true)"
echo "${GIT_REV}" > "${OUT_DIR}/${SDK_NAME}/VERSION.txt"

cd "${OUT_DIR}"
tar -czf "${SDK_NAME}.tar.gz" "${SDK_NAME}"
sha256sum "${SDK_NAME}.tar.gz" > "${SDK_NAME}.tar.gz.sha256"

ls -lh "${SDK_NAME}.tar.gz" "${SDK_NAME}.tar.gz.sha256"
