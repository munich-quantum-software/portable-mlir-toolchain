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

# Linux in-container build script: build and package the MLIR toolchain
#
# Description:
#   Builds LLVM and MLIR for Linux (arch-aware) inside a container, and packages the results.
#
# Environment:
#   LLVM_PROJECT_REF  llvm-project Git ref or commit SHA (e.g., llvmorg-21.1.8 or 179d30f...)
#   INSTALL_PREFIX    Absolute path for the final install
#   BUILD_WORKSPACE   Path to the build workspace
#
# Outputs:
#   - Installs into $INSTALL_PREFIX
#   - Creates $INSTALL_PREFIX/llvm-mlir_$LLVM_PROJECT_REF_linux_<arch>_<host_target>.tar.zst
#   - Creates $INSTALL_PREFIX/zstd-<zstd_version>_linux_<arch>_<host_target>.tar.gz

set -euo pipefail

: "${STAGE:?STAGE not set}"
: "${IO_DIR:?IO_DIR not set}"
: "${BUILD_WORKSPACE:=/build}"

# shellcheck source=../common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../common.sh"

ZSTD_VERSION="${ZSTD_VERSION:-$(cat "$IO_DIR/zstd.version" 2>/dev/null || echo 1.5.7)}"
MOLD_VERSION="${MOLD_VERSION:-$(cat "$IO_DIR/mold.version" 2>/dev/null || echo 2.40.4)}"
NINJA_VERSION="${NINJA_VERSION:-1.13.0}"
BUILD_TYPE="${BUILD_TYPE:-Release}"

mkdir -p "$BUILD_WORKSPACE" "$IO_DIR"
cd "$BUILD_WORKSPACE"

log_step "Installing build tools (Ninja ${NINJA_VERSION})"
uv tool install "ninja==${NINJA_VERSION}"
log_done

export PATH="$HOME/.local/bin:$PATH"

UNAME_ARCH="$(uname -m)"
if [[ "$UNAME_ARCH" == "x86_64" ]]; then
  HOST_TARGET="X86"
elif [[ "$UNAME_ARCH" == "aarch64" || "$UNAME_ARCH" == "arm64" ]]; then
  HOST_TARGET="AArch64"
else
  echo "Error: Unsupported architecture: ${UNAME_ARCH}." >&2
  exit 1
fi

compress_dir_to_archive() {
  local source_dir="$1"
  local archive_path="$2"
  local zstd_exe="$3"
  pushd "$source_dir" > /dev/null
  tar -cf - . | "$zstd_exe" -19 --long=30 --threads=0 -f -o "$archive_path" -
  popd > /dev/null
}

decompress_archive_to_dir() {
  local archive_path="$1"
  local destination_dir="$2"
  local zstd_exe="$3"
  rm -rf "$destination_dir"
  mkdir -p "$destination_dir"
  "$zstd_exe" -d --long=30 "$archive_path" -c | tar -xf - -C "$destination_dir"
}

download_llvm_source() {
  local llvm_project_ref="$1"
  local repo_dir="$2"

  log_step "Downloading LLVM/MLIR source (${llvm_project_ref})"
  rm -rf "$repo_dir"
  mkdir -p "$repo_dir"
  curl -fL --retry 5 --retry-delay 5 \
    "https://github.com/llvm/llvm-project/archive/${llvm_project_ref}.tar.gz" \
    | tar -xz --strip-components=1 -C "$repo_dir" \
      --exclude='clang' \
      --exclude='lldb' \
      --exclude='polly' \
      --exclude='flang' \
      --exclude='openmp' \
      --exclude='libclc' \
      --exclude='libc' \
      --exclude='llvm/test' \
      --exclude='llvm/unittests' \
      --exclude='mlir/test' \
      --exclude='mlir/unittests'
  log_done
}

build_zstd() {
  local zstd_dir="zstd-${ZSTD_VERSION}"
  local zstd_tarball="zstd-${ZSTD_VERSION}.tar.gz"
  local zstd_checksum_file="${zstd_tarball}.sha256"

  log_step "Building zstd v${ZSTD_VERSION}"
  rm -rf "$zstd_dir" "$zstd_tarball" "$zstd_checksum_file"

  curl -fL --retry 5 --retry-delay 5 \
    "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/${zstd_tarball}" \
    -o "$zstd_tarball"
  curl -fL --retry 5 --retry-delay 5 \
    "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/${zstd_checksum_file}" \
    -o "$zstd_checksum_file"

  if ! sha256sum -c "$zstd_checksum_file" > /dev/null 2>&1; then
    echo "Error: zstd checksum verification failed" >&2
    exit 1
  fi

  tar -xzf "$zstd_tarball"

  local install_prefix="$BUILD_WORKSPACE/zstd-install"
  rm -rf "$install_prefix"

  cmake -S "$zstd_dir/build/cmake" -B "$zstd_dir/build_cmake" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_prefix" \
    -DZSTD_BUILD_STATIC=ON \
    -DZSTD_BUILD_SHARED=OFF

  cmake --build "$zstd_dir/build_cmake" --target install --config Release

  cp "$install_prefix/bin/zstd" "$IO_DIR/zstd"
  chmod +x "$IO_DIR/zstd"
  compress_dir_to_archive "$install_prefix" "$IO_DIR/zstd.tar.zst" "$IO_DIR/zstd"

  rm -rf "$zstd_dir" "$zstd_tarball" "$zstd_checksum_file" "$install_prefix"
  log_done
}

build_mold() {
  local zstd_exe="$IO_DIR/zstd"
  local zstd_archive="$IO_DIR/zstd.tar.zst"

  [[ -x "$zstd_exe" ]] || { echo "Error: missing zstd executable artifact" >&2; exit 1; }
  [[ -f "$zstd_archive" ]] || { echo "Error: missing zstd archive artifact" >&2; exit 1; }

  local zstd_extract_dir="$BUILD_WORKSPACE/zstd-extract"
  local mold_src_dir="$BUILD_WORKSPACE/mold-${MOLD_VERSION}"
  local mold_install_dir="$BUILD_WORKSPACE/mold-install"
  local mold_tarball="$BUILD_WORKSPACE/mold-${MOLD_VERSION}.tar.gz"

  log_step "Building mold v${MOLD_VERSION}"
  decompress_archive_to_dir "$zstd_archive" "$zstd_extract_dir" "$zstd_exe"
  rm -rf "$mold_src_dir" "$mold_install_dir" "$mold_tarball"

  curl -fL --retry 5 --retry-delay 5 \
    "https://github.com/rui314/mold/archive/refs/tags/v${MOLD_VERSION}.tar.gz" -o "$mold_tarball"
  tar -xzf "$mold_tarball" -C "$BUILD_WORKSPACE"

  cmake -S "$mold_src_dir" -B "$mold_src_dir/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$mold_install_dir" \
    -DCMAKE_PREFIX_PATH="$zstd_extract_dir" \
    -DMOLD_LTO=ON \
    -DMOLD_USE_SYSTEM_TBB=OFF \
    -DMOLD_USE_SYSTEM_MIMALLOC=OFF \
    -DMOLD_USE_MIMALLOC=ON

  cmake --build "$mold_src_dir/build" --target install --config Release
  if [[ ! -x "$mold_install_dir/bin/mold" && -x "$mold_install_dir/bin/ld64.mold" ]]; then
    ln -sf ld64.mold "$mold_install_dir/bin/mold"
  fi
  compress_dir_to_archive "$mold_install_dir" "$IO_DIR/mold.tar.zst" "$zstd_exe"

  rm -rf "$zstd_extract_dir" "$mold_src_dir" "$mold_install_dir" "$mold_tarball"
  log_done
}

build_mlir() {
  : "${LLVM_PROJECT_REF:?LLVM_PROJECT_REF not set}"

  local zstd_exe="$IO_DIR/zstd"
  local zstd_archive="$IO_DIR/zstd.tar.zst"
  local mold_archive="$IO_DIR/mold.tar.zst"

  [[ -x "$zstd_exe" ]] || { echo "Error: missing zstd executable artifact" >&2; exit 1; }
  [[ -f "$zstd_archive" ]] || { echo "Error: missing zstd archive artifact" >&2; exit 1; }
  [[ -f "$mold_archive" ]] || { echo "Error: missing mold archive artifact" >&2; exit 1; }

  local zstd_extract_dir="$BUILD_WORKSPACE/zstd-extract"
  local mold_extract_dir="$BUILD_WORKSPACE/mold-extract"
  local mlir_install_dir="$BUILD_WORKSPACE/mlir-install"
  local repo_dir="$BUILD_WORKSPACE/llvm-project"
  local build_dir="$BUILD_WORKSPACE/build_mlir"

  decompress_archive_to_dir "$zstd_archive" "$zstd_extract_dir" "$zstd_exe"
  decompress_archive_to_dir "$mold_archive" "$mold_extract_dir" "$zstd_exe"

  download_llvm_source "$LLVM_PROJECT_REF" "$repo_dir"

  local mold_bin_dir="$mold_extract_dir/bin"
  export PATH="$mold_bin_dir:$PATH"

  log_step "CMake configure MLIR (${BUILD_TYPE})"
  cmake -S "$repo_dir/llvm" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_INSTALL_PREFIX="$mlir_install_dir" \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
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
    -DLLVM_USE_LINKER=mold
  log_done

  log_step "Build and install MLIR (${BUILD_TYPE})"
  cmake --build "$build_dir" --target install --config "$BUILD_TYPE"
  log_done

  local llvm_lib_dir="$mlir_install_dir/lib"
  if [[ -x "$mlir_install_dir/bin/llvm-config" ]]; then
    llvm_lib_dir="$($mlir_install_dir/bin/llvm-config --libdir)"
  elif [[ -d "$mlir_install_dir/lib64" && ! -d "$mlir_install_dir/lib" ]]; then
    llvm_lib_dir="$mlir_install_dir/lib64"
  fi
  log_done

  log_step "Stripping debug symbols"
  if command -v strip >/dev/null 2>&1; then
    find "$mlir_install_dir/bin" -type f -executable -exec strip --strip-debug {} + 2>/dev/null || true
    find "$llvm_lib_dir" -name "*.a" -exec strip --strip-debug {} + 2>/dev/null || true
  fi
  log_done

  compress_dir_to_archive "$mlir_install_dir" "$IO_DIR/mlir.tar.zst" "$zstd_exe"

  rm -rf "$zstd_extract_dir" "$mold_extract_dir" "$mlir_install_dir" "$repo_dir" "$build_dir"
}

case "$STAGE" in
  build-zstd)
    build_zstd
    ;;
  build-mold)
    build_mold
    ;;
  build-mlir)
    build_mlir
    ;;
  *)
    echo "Error: unsupported STAGE '$STAGE'" >&2
    exit 1
    ;;
esac
