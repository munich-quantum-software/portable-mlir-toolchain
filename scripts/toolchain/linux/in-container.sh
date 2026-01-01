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

# Usage: ./scripts/toolchain/linux/build.sh -r llvmorg-21.1.8 [-p /path/to/llvm-install]

set -euo pipefail

: "${LLVM_PROJECT_REF:?LLVM_PROJECT_REF (commit) not set}"
: "${INSTALL_PREFIX:?INSTALL_PREFIX not set}"
: "${BUILD_TYPE:=Release}"

cd /work

# Determine architecture
UNAME_ARCH=$(uname -m)

# Determine target
if [[ "$UNAME_ARCH" == "x86_64" ]]; then
  HOST_TARGET="X86"
elif [[ "$UNAME_ARCH" == "aarch64" || "$UNAME_ARCH" == "arm64" ]]; then
  HOST_TARGET="AArch64"
else
  echo "Error: Unsupported architecture: ${UNAME_ARCH}. Only x86_64 and aarch64 are supported." >&2
  exit 1
fi

# Main LLVM setup function
build_llvm() {
  local llvm_project_ref=$1
  local install_prefix=$2
  local build_type=$3

  echo "Building MLIR $llvm_project_ref ($build_type) into $install_prefix..."

  # Fetch LLVM project source archive
  local repo_dir="$PWD/llvm-project"
  rm -rf "$repo_dir"
  mkdir -p "$repo_dir"
  curl -fL --retry 5 --retry-delay 5 \
    "https://github.com/llvm/llvm-project/archive/${llvm_project_ref}.tar.gz" \
    | tar -xz --strip-components=1 -C "$repo_dir"

  # Change to repo directory
  pushd "$repo_dir" > /dev/null

  # Build LLVM
  local build_dir="build_llvm"
  local cmake_args=(
    -S llvm -B "$build_dir"
    -DCMAKE_BUILD_TYPE="$build_type"
    -DCMAKE_C_COMPILER=gcc
    -DCMAKE_CXX_COMPILER=g++
    -DCMAKE_INSTALL_PREFIX="$install_prefix"
    -DLLVM_BUILD_EXAMPLES=OFF
    -DLLVM_BUILD_TESTS=OFF
    -DLLVM_ENABLE_ASSERTIONS=ON
    -DLLVM_ENABLE_LTO=OFF
    -DLLVM_ENABLE_RTTI=ON
    -DLLVM_INCLUDE_BENCHMARKS=OFF
    -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_INCLUDE_TESTS=OFF
    -DLLVM_INSTALL_UTILS=ON
    -DLLVM_OPTIMIZED_TABLEGEN=ON
    -DLLVM_TARGETS_TO_BUILD="$HOST_TARGET"
  )

  if [[ "$build_type" == "Debug" ]]; then
    cmake_args+=(-DLLVM_USE_SPLIT_DWARF=ON)
    # Build lld first to use it as linker
    cmake "${cmake_args[@]}" -DLLVM_ENABLE_PROJECTS="lld"
    cmake --build "$build_dir" --target lld
    # Use the just-built lld as the linker
    export PATH="$PWD/$build_dir/bin:$PATH"
    cmake "${cmake_args[@]}" -DLLVM_ENABLE_PROJECTS="mlir;lld" -DLLVM_ENABLE_LLD=ON
  else
    cmake "${cmake_args[@]}" -DLLVM_ENABLE_PROJECTS="mlir"
  fi

  cmake --build "$build_dir" --target install --config "$build_type"

  # Return to original directory
  popd > /dev/null
}

build_llvm "$LLVM_PROJECT_REF" "$INSTALL_PREFIX" "$BUILD_TYPE"

# Prune non-essential tools
if [[ -d "$INSTALL_PREFIX/bin" ]]; then
  rm -f "$INSTALL_PREFIX/bin/clang*" \
        "$INSTALL_PREFIX/bin/lld*" \
        "$INSTALL_PREFIX/bin/llvm-bolt" \
        "$INSTALL_PREFIX/bin/perf2bolt" \
        2>/dev/null || true
fi
rm -rf "$INSTALL_PREFIX/lib/clang" 2>/dev/null || true

# Strip binaries
if [[ "$BUILD_TYPE" == "Release" ]] && command -v strip >/dev/null 2>&1; then
  find "$INSTALL_PREFIX/bin" -type f -executable -exec strip --strip-debug {} + 2>/dev/null || true
  find "$INSTALL_PREFIX/lib" -name "*.a" -exec strip --strip-debug {} + 2>/dev/null || true
fi

# Define archive variables
BUILD_TYPE_SUFFIX=""
if [[ "$BUILD_TYPE" == "Debug" ]]; then
  BUILD_TYPE_SUFFIX="_debug"
fi
ARCHIVE_NAME="llvm-mlir_${LLVM_PROJECT_REF}_linux_${UNAME_ARCH}_${HOST_TARGET}${BUILD_TYPE_SUFFIX}.tar.zst"
ARCHIVE_PATH="$PWD/${ARCHIVE_NAME}"

# Change to installation directory
pushd "$INSTALL_PREFIX" > /dev/null

# Emit compressed archive (.tar.zst)
ZSTD_CLEVEL=19 tar --use-compress-program zstd -cf "${ARCHIVE_PATH}" . || {
  echo "Error: Failed to create archive" >&2
  exit 1
}

# Return to original directory
popd > /dev/null
