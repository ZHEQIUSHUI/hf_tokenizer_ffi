#!/usr/bin/env bash
set -euo pipefail

URL="${URL:-https://developer.arm.com/-/media/Files/downloads/gnu-a/9.2-2019.12/binrel/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz}"
FOLDER="${FOLDER:-gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu}"
ARCHIVE="${ARCHIVE:-${FOLDER}.tar.xz}"

# 如果已经可用就直接返回
if command -v aarch64-none-linux-gnu-gcc >/dev/null 2>&1; then
  echo "aarch64-none-linux-gnu-gcc already exists: $(command -v aarch64-none-linux-gnu-gcc)"
  aarch64-none-linux-gnu-gcc -v
  exit 0
fi

# 下载
if [[ ! -f "${ARCHIVE}" ]]; then
  echo "Downloading ${URL}"
  # GitHub runner 默认有 curl；也可换成 wget
  curl -L "${URL}" -o "${ARCHIVE}"
else
  echo "${ARCHIVE} already exists"
fi

# 解压
if [[ ! -d "${FOLDER}" ]]; then
  echo "Extracting ${ARCHIVE}"
  tar -xf "${ARCHIVE}"
else
  echo "${FOLDER} already exists"
fi

# 将 toolchain bin 加入 PATH
TOOLCHAIN_BIN="$(pwd)/${FOLDER}/bin"
if [[ ! -d "${TOOLCHAIN_BIN}" ]]; then
  echo "ERROR: toolchain bin not found: ${TOOLCHAIN_BIN}"
  exit 1
fi

# GitHub Actions：把 PATH 持久化到后续 steps
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${TOOLCHAIN_BIN}" >> "${GITHUB_PATH}"
else
  export PATH="${PATH}:${TOOLCHAIN_BIN}"
fi

# 校验
command -v aarch64-none-linux-gnu-gcc >/dev/null 2>&1 || {
  echo "ERROR: aarch64-none-linux-gnu-gcc not found after setup"
  exit 1
}

aarch64-none-linux-gnu-gcc -v
