#!/bin/bash
# Copyright (c) 2025 Munich Quantum Software Company GmbH
# Copyright (c) 2025 Chair for Design Automation, TUM
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

# macOS build script: build and package the MLIR toolchain
#
# Description:
#   Builds LLVM and MLIR for macOS (arch-aware), and packages the results.
#
# Usage:
#   scripts/toolchain/macos/build.sh -r <llvm_project_ref> -p <install_prefix>
#     llvm_project_ref llvm-project Git ref or commit SHA (e.g., llvmorg-21.1.8 or 179d30f...)
#     install_prefix   Absolute path for the final install
#
# Outputs:
#   - Installs into <install_prefix>
#   - Creates llvm-mlir_<llvm_project_ref>_macos_<arch>_<host_target>.tar.zst in the current directory
#   - Creates zstd-<zstd_version>_macos_<arch>_<host_target>.tar.gz in the current directory

set -euo pipefail

ZSTD_VERSION="1.5.7"

# Parse arguments
while getopts ":r:p:" opt; do
  case $opt in
    r) LLVM_PROJECT_REF="$OPTARG"
    ;;
    p) INSTALL_PREFIX="$OPTARG"
    ;;
    \?) echo "Error: Invalid option -$OPTARG" >&2; exit 1
    ;;
  esac
done

# Check arguments
if [ -z "${LLVM_PROJECT_REF:-}" ]; then
  echo "Error: llvm-project ref (-r) is required" >&2
  echo "Usage: $0 -r <llvm_project_ref> -p <install_prefix>" >&2
  exit 1
fi
if [ -z "${INSTALL_PREFIX:-}" ]; then
  echo "Error: Installation directory (-p) is required" >&2
  echo "Usage: $0 -r <llvm_project_ref> -p <install_prefix>" >&2
  exit 1
fi

# Determine architecture
UNAME_ARCH=$(uname -m)

# Determine target
if [[ "$UNAME_ARCH" == "arm64" || "$UNAME_ARCH" == "aarch64" ]]; then
  HOST_TARGET="AArch64"
elif [[ "$UNAME_ARCH" == "x86_64" ]]; then
  HOST_TARGET="X86"
else
  echo "Error: Unsupported architecture: ${UNAME_ARCH}. Only x86_64 and arm64 are supported." >&2
  exit 1
fi

# Main LLVM setup function
build_zstd() {
  local install_prefix=$1
  echo "Building zstd v$ZSTD_VERSION into $install_prefix..."
  local zstd_dir="zstd-$ZSTD_VERSION"
  local zstd_tarball="zstd-${ZSTD_VERSION}.tar.gz"
  local zstd_checksum="${zstd_tarball}.sha256"
  local zstd_url="https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/${zstd_tarball}"
  local zstd_checksum_url="https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/${zstd_checksum}"

  rm -rf "$zstd_dir" "$zstd_tarball" "$zstd_checksum"

  echo "Downloading zstd tarball..."
  if ! curl -fL --retry 5 --retry-delay 5 "$zstd_url" -o "$zstd_tarball"; then
    echo "Error: Failed to download zstd tarball from $zstd_url" >&2
    exit 1
  fi

  echo "Downloading zstd checksum..."
  if ! curl -fL --retry 5 --retry-delay 5 "$zstd_checksum_url" -o "$zstd_checksum"; then
    echo "Error: Failed to download zstd checksum from $zstd_checksum_url" >&2
    exit 1
  fi

  echo "Verifying checksum..."
  if ! shasum -a 256 -c "$zstd_checksum" > /dev/null 2>&1; then
    echo "Error: zstd checksum verification failed!" >&2
    exit 1
  fi

  echo "Extracting zstd..."
  if ! tar -xzf "$zstd_tarball"; then
    echo "Error: Failed to extract zstd tarball" >&2
    exit 1
  fi

  pushd "$zstd_dir" > /dev/null
  cmake -S build/cmake -B build_cmake \
    -DCMAKE_INSTALL_PREFIX="$install_prefix" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}" \
    -DZSTD_BUILD_STATIC=ON \
    -DZSTD_BUILD_SHARED=OFF
  if ! cmake --build build_cmake --target install -j"$(sysctl -n hw.ncpu)"; then
    echo "Error: Failed to build/install zstd" >&2
    exit 1
  fi
  popd > /dev/null

  rm -rf "$zstd_dir" "$zstd_tarball" "$zstd_checksum"
}

build_llvm() {
  local llvm_project_ref=$1
  local install_prefix=$2

  echo "Building MLIR $llvm_project_ref into $install_prefix..."

  # Fetch LLVM project source archive
  local repo_dir="$PWD/llvm-project"
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
      --exclude='mlir/test' \
      --exclude='llvm/unittests' \
      --exclude='mlir/unittests'

  # Change to repo directory
  pushd "$repo_dir" > /dev/null

  # Build LLVM
  local build_dir="build_llvm"
  local cmake_args=(
    -S llvm -B "$build_dir"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_C_COMPILER=clang
    -DCMAKE_CXX_COMPILER=clang++
    -DCMAKE_INSTALL_PREFIX="$install_prefix"
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
    -DLLVM_BUILD_EXAMPLES=OFF
    -DLLVM_BUILD_TESTS=OFF
    -DLLVM_ENABLE_ASSERTIONS=ON
    -DLLVM_ENABLE_ZSTD=OFF
    -DLLVM_ENABLE_LTO=OFF
    -DLLVM_ENABLE_RTTI=ON
    -DLLVM_ENABLE_LIBXML2=OFF
    -DLLVM_ENABLE_LIBEDIT=OFF
    -DLLVM_ENABLE_LIBPFM=OFF
    -DLLVM_INCLUDE_BENCHMARKS=OFF
    -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_INCLUDE_TESTS=OFF
    -DLLVM_INSTALL_UTILS=ON
    -DLLVM_TARGETS_TO_BUILD="$HOST_TARGET"
  )

  # Build lld first to use it as linker
  cmake "${cmake_args[@]}" -DLLVM_ENABLE_PROJECTS="lld"
  cmake --build "$build_dir" --target lld
  # Use the just-built lld as the linker
  export PATH="$PWD/$build_dir/bin:$PATH"
  cmake "${cmake_args[@]}" -DLLVM_ENABLE_PROJECTS="mlir;lld" -DLLVM_ENABLE_LLD=ON

  cmake --build "$build_dir" --target install

  # Return to original directory
  popd > /dev/null
  rm -rf "$repo_dir"
}

ZSTD_INSTALL_PREFIX="$PWD/zstd-install"
build_zstd "$ZSTD_INSTALL_PREFIX"
build_llvm "$LLVM_PROJECT_REF" "$INSTALL_PREFIX"

# Prune non-essential tools
if [[ -d "$INSTALL_PREFIX/bin" ]]; then
  rm -f "$INSTALL_PREFIX/bin/clang*" \
        "$INSTALL_PREFIX/bin/llvm-bolt" \
        "$INSTALL_PREFIX/bin/perf2bolt" \
        2>/dev/null || true
fi

# Remove non-essential directories
rm -rf "$INSTALL_PREFIX/lib/clang" "$INSTALL_PREFIX/share" 2>/dev/null || true

# Strip binaries
if command -v strip >/dev/null 2>&1; then
  find "$INSTALL_PREFIX/bin" -type f -perm -111 -exec strip -S {} + 2>/dev/null || true
  find "$INSTALL_PREFIX/lib" -name "*.a" -exec strip -S {} + 2>/dev/null || true
fi

# Define archive variables
ARCHIVE_NAME="llvm-mlir_${LLVM_PROJECT_REF}_macos_${UNAME_ARCH}_${HOST_TARGET}.tar.zst"
ARCHIVE_PATH="$PWD/${ARCHIVE_NAME}"

# Change to installation directory
pushd "$INSTALL_PREFIX" > /dev/null

# Emit compressed archive (.tar.zst)
tar --use-compress-program="$ZSTD_INSTALL_PREFIX/bin/zstd -19 --long=30 --threads=0" -cf "${ARCHIVE_PATH}" . || {
  echo "Error: Failed to create archive" >&2
  exit 1
}

# Return to original directory
popd > /dev/null

# Package zstd executable
ZSTD_ARCHIVE_NAME="zstd-${ZSTD_VERSION}_macos_${UNAME_ARCH}_${HOST_TARGET}.tar.gz"
ZSTD_ARCHIVE_PATH="$PWD/${ZSTD_ARCHIVE_NAME}"
echo "Packaging zstd into ${ZSTD_ARCHIVE_NAME}..."
pushd "$ZSTD_INSTALL_PREFIX/bin" > /dev/null
tar -czf "${ZSTD_ARCHIVE_PATH}" zstd || {
  echo "Error: Failed to create zstd archive" >&2
  exit 1
}
popd > /dev/null

# Clean up zstd installation
rm -rf "$ZSTD_INSTALL_PREFIX"
