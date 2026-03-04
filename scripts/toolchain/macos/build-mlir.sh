#!/usr/bin/env bash
# Copyright (c) 2025 - 2026 Munich Quantum Software Company GmbH
# Copyright (c) 2025 - 2026 Chair for Design Automation, TUM
# All rights reserved.
#
# Licensed under the Apache License v2.0 with LLVM Exceptions (the "License"); you
# may not use this file except in compliance with the License. You may obtain a
# copy of the License at https://llvm.org/LICENSE.txt
#
# Unless required by applicable law or agreed to in writing, software distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

set -euo pipefail

usage() {
  echo "Usage: $0 -r <llvm_project_ref> -e <zstd_exe_path> -z <zstd_archive_path> -m <mold_archive_path> -a <mlir_archive_path> [-n <ninja_version>] [-b <Release|Debug>]"
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

NINJA_VERSION="1.13.0"
BUILD_TYPE="Release"
while getopts ":r:e:z:m:a:n:b:" opt; do
  case "$opt" in
    r) LLVM_PROJECT_REF="$OPTARG" ;;
    e) ZSTD_EXE_PATH="$OPTARG" ;;
    z) ZSTD_ARCHIVE_PATH="$OPTARG" ;;
    m) MOLD_ARCHIVE_PATH="$OPTARG" ;;
    a) MLIR_ARCHIVE_PATH="$OPTARG" ;;
    n) NINJA_VERSION="$OPTARG" ;;
    b) BUILD_TYPE="$OPTARG" ;;
    *) usage ;;
  esac
done

[[ -z "${LLVM_PROJECT_REF:-}" || -z "${ZSTD_EXE_PATH:-}" || -z "${ZSTD_ARCHIVE_PATH:-}" || -z "${MOLD_ARCHIVE_PATH:-}" || -z "${MLIR_ARCHIVE_PATH:-}" ]] && usage
[[ "$BUILD_TYPE" != "Release" && "$BUILD_TYPE" != "Debug" ]] && { echo "Error: build type must be Release or Debug" >&2; exit 1; }

ensure_ninja "$NINJA_VERSION"
export MACOSX_DEPLOYMENT_TARGET="11.0"

ZSTD_EXE_PATH="$(resolve_abs_path "$ZSTD_EXE_PATH")"
ZSTD_ARCHIVE_PATH="$(resolve_abs_path "$ZSTD_ARCHIVE_PATH")"
MOLD_ARCHIVE_PATH="$(resolve_abs_path "$MOLD_ARCHIVE_PATH")"
MLIR_ARCHIVE_PATH="$(resolve_abs_path "$MLIR_ARCHIVE_PATH")"

if [[ ! -f "$ZSTD_EXE_PATH" ]]; then
  echo "Error: zstd executable not found at $ZSTD_EXE_PATH" >&2
  exit 1
fi
chmod +x "$ZSTD_EXE_PATH"

tmp_dir="$(mktemp -d)"
zstd_extract_dir="$tmp_dir/zstd"
mold_extract_dir="$tmp_dir/mold"
repo_dir="$tmp_dir/llvm-project"
build_dir="$tmp_dir/build-mlir"
install_dir="$tmp_dir/mlir-install"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

decompress_archive_to_dir "$ZSTD_ARCHIVE_PATH" "$zstd_extract_dir" "$ZSTD_EXE_PATH"
decompress_archive_to_dir "$MOLD_ARCHIVE_PATH" "$mold_extract_dir" "$ZSTD_EXE_PATH"
initialize_llvm_source_tree "$LLVM_PROJECT_REF" "$repo_dir"

UNAME_ARCH="$(uname -m)"
HOST_TARGET="$(host_target_for_arch "$UNAME_ARCH")"
if [[ -z "$HOST_TARGET" ]]; then
  echo "Error: Unsupported architecture: ${UNAME_ARCH}." >&2
  exit 1
fi

export PATH="$mold_extract_dir/bin:$PATH"

mold_linker="$mold_extract_dir/bin/mold"
if [[ ! -x "$mold_linker" && -x "$mold_extract_dir/bin/ld64.mold" ]]; then
  mold_linker="$mold_extract_dir/bin/ld64.mold"
fi
if [[ ! -x "$mold_linker" ]]; then
  echo "Error: mold linker not found in $mold_extract_dir/bin" >&2
  exit 1
fi

# AppleClang on macOS rejects '-fuse-ld=mold'. Provide an ld shim and use -B to pick it.
mold_tool_dir="$tmp_dir/mold-toolchain"
mkdir -p "$mold_tool_dir"
ln -sf "$mold_linker" "$mold_tool_dir/ld"

log_step "CMake configure MLIR (${BUILD_TYPE})"
cmake -S "$repo_dir/llvm" -B "$build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DCMAKE_INSTALL_PREFIX="$install_dir" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
  -DLLVM_TARGETS_TO_BUILD="$HOST_TARGET" \
  -DLLVM_ENABLE_PROJECTS=mlir \
  -DLLVM_BUILD_EXAMPLES=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_BUILD_TESTS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_ENABLE_ASSERTIONS=ON \
  -DLLVM_ENABLE_LTO=OFF \
  -DLLVM_ENABLE_RTTI=ON \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_LIBPFM=OFF \
  -DLLVM_INSTALL_UTILS=ON \
  -DLLVM_OPTIMIZED_TABLEGEN=ON \
  -DLLVM_ENABLE_WARNINGS=OFF \
  -DLLVM_ENABLE_ZSTD=FORCE_ON \
  -DLLVM_USE_STATIC_ZSTD=ON \
  -DCMAKE_PREFIX_PATH="$zstd_extract_dir" \
  "-DCMAKE_C_FLAGS=-B$mold_tool_dir" \
  "-DCMAKE_CXX_FLAGS=-B$mold_tool_dir" \
  "-DCMAKE_EXE_LINKER_FLAGS=-B$mold_tool_dir" \
  "-DCMAKE_SHARED_LINKER_FLAGS=-B$mold_tool_dir" \
  "-DCMAKE_MODULE_LINKER_FLAGS=-B$mold_tool_dir"
log_done

log_step "Build and install MLIR (${BUILD_TYPE})"
cmake --build "$build_dir" --target install --config "$BUILD_TYPE"
log_done

log_step "Stripping debug symbols"
if command -v strip >/dev/null 2>&1; then
  find "$install_dir/bin" -type f -perm -111 -exec strip -S {} + 2>/dev/null || true
  find "$install_dir/lib" -name "*.a" -exec strip -S {} + 2>/dev/null || true
fi
log_done

compress_dir_to_archive "$install_dir" "$MLIR_ARCHIVE_PATH" "$ZSTD_EXE_PATH"
