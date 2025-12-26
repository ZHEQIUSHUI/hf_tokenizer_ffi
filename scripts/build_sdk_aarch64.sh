#!/usr/bin/env bash
set -euo pipefail

echo "[build_sdk] start"

# ===== 可调整参数 =====
BUILD_DIR="${BUILD_DIR:-build_aarch64}"
URL="${URL:-https://developer.arm.com/-/media/Files/downloads/gnu-a/9.2-2019.12/binrel/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz}"
FOLDER="${FOLDER:-gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu}"
ARCHIVE="${ARCHIVE:-${FOLDER}.tar.xz}"

TARGET="${TARGET:-aarch64-unknown-linux-gnu}"
PROFILE="${PROFILE:-release}"

SDK_NAME="${SDK_NAME:-hf-tokenizer-sdk-aarch64}"
OUT_DIR="${OUT_DIR:-dist}"
PROJECT_DIR="${PROJECT_DIR:-.}"   # Cargo.toml 所在目录
# ======================

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "[build_sdk] toolchain check"
if ! command -v aarch64-none-linux-gnu-gcc >/dev/null 2>&1; then
  # 下载
  if [[ ! -f "${ARCHIVE}" ]]; then
    echo "[build_sdk] downloading toolchain: ${URL}"
    if command -v wget >/dev/null 2>&1; then
      wget -O "${ARCHIVE}" "${URL}"
    else
      curl -L "${URL}" -o "${ARCHIVE}"
    fi
  else
    echo "[build_sdk] toolchain archive exists: ${ARCHIVE}"
  fi

  # 解压
  if [[ ! -d "${FOLDER}" ]]; then
    echo "[build_sdk] extracting: ${ARCHIVE}"
    tar -xf "${ARCHIVE}"
  else
    echo "[build_sdk] toolchain folder exists: ${FOLDER}"
  fi

  # 立刻对当前 shell 生效（关键！）
  export PATH="${PATH}:$(pwd)/${FOLDER}/bin"
fi

echo "[build_sdk] verify compiler"
command -v aarch64-none-linux-gnu-gcc >/dev/null 2>&1 || {
  echo "ERROR: aarch64-none-linux-gnu-gcc not found after setup"
  echo "PWD=$(pwd)"
  echo "List:"
  ls -la
  echo "Try list toolchain bin:"
  ls -la "${FOLDER}/bin" || true
  exit 1
}
aarch64-none-linux-gnu-gcc -v

# 回到项目目录
cd "${GITHUB_WORKSPACE:-$(pwd)/..}" || true
cd "${PROJECT_DIR}"

# 安装 rust/cargo（CI 非交互）
if ! command -v cargo >/dev/null 2>&1; then
  echo "[build_sdk] installing rustup/cargo"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
# shellcheck disable=SC1090
source "${HOME}/.cargo/env"

echo "[build_sdk] rust versions"
rustup --version
rustc --version
cargo --version

echo "[build_sdk] add rust target: ${TARGET}"
rustup target add "${TARGET}"

# 指定 cargo 使用 ARM toolchain 链接
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="aarch64-none-linux-gnu-gcc"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_AR="aarch64-none-linux-gnu-ar"

echo "[build_sdk] cargo build"
cargo build --profile "${PROFILE}" --target "${TARGET}"

LIB_PATH="target/${TARGET}/${PROFILE}/libhf_tokenizer_ffi.a"
if [[ ! -f "${LIB_PATH}" ]]; then
  echo "ERROR: not found: ${LIB_PATH}"
  exit 1
fi

echo "[build_sdk] package sdk"
rm -rf "${OUT_DIR:?}/${SDK_NAME}"
mkdir -p "${OUT_DIR}/${SDK_NAME}/lib" "${OUT_DIR}/${SDK_NAME}/include"

cp -v "${LIB_PATH}" "${OUT_DIR}/${SDK_NAME}/lib/"

# 头文件路径按你项目实际情况：include/hf_tokenizer_c.h
if [[ -f "include/hf_tokenizer_c.h" ]]; then
  cp -v "include/hf_tokenizer_c.h" "${OUT_DIR}/${SDK_NAME}/include/"
else
  echo "ERROR: include/hf_tokenizer_c.h not found"
  exit 1
fi

# 可选：如果你仓库根有 hf_tokenizer.hpp，则一起打包
if [[ -f "hf_tokenizer.hpp" ]]; then
  cp -v "hf_tokenizer.hpp" "${OUT_DIR}/${SDK_NAME}/include/"
fi

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

tar -czf "${OUT_DIR}/${SDK_NAME}.tar.gz" -C "${OUT_DIR}" "${SDK_NAME}"
sha256sum "${OUT_DIR}/${SDK_NAME}.tar.gz" > "${OUT_DIR}/${SDK_NAME}.tar.gz.sha256"

echo "[build_sdk] done"
ls -lh "${OUT_DIR}/${SDK_NAME}.tar.gz" "${OUT_DIR}/${SDK_NAME}.tar.gz.sha256"
