#!/bin/bash
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

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
_STEP_START=0
log_step() {
  local msg="$*"
  _STEP_START=$(date +%s)
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  ▶  ${msg}"
  echo "     $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "════════════════════════════════════════════════════════════════"
}
log_done() {
  local elapsed=$(( $(date +%s) - _STEP_START ))
  echo "────────────────────────────────────────────────────────────────"
  echo "  ✔  Done  ($(printf '%dm %02ds' $((elapsed/60)) $((elapsed%60))))"
  echo "────────────────────────────────────────────────────────────────"
  echo ""
}
# ---------------------------------------------------------------------------

# Ensure Ninja is available for fast, parallel builds
log_step "Installing build tools (Ninja)"
uv tool install ninja
log_done

# Ensure `uv`-installed tools are on the PATH
export PATH="$HOME/.local/bin:$PATH"

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
  log_step "Building zstd v${ZSTD_VERSION}"

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
  cmake -G Ninja -S build/cmake -B build_cmake \
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
  log_done
}

build_llvm() {
  local llvm_project_ref=$1
  local install_prefix=$2

  # ── Fetch sources ─────────────────────────────────────────────────────────
  log_step "Downloading LLVM/MLIR source (${llvm_project_ref})"
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
  log_done

  # Change to repo directory
  pushd "$repo_dir" > /dev/null

  # Build LLVM
  local build_dir_stage1="build_lld_release"
  local build_dir_stage2="build_llvm"
  local cmake_args=(
    -S llvm
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX="$install_prefix"
    # Only build the host target to speed up the build and reduce the size of the resulting binaries
    -DLLVM_TARGETS_TO_BUILD="$HOST_TARGET"
    # Use the system clang to build to be compatible with downstream macOS users
    -DCMAKE_C_COMPILER=clang
    -DCMAKE_CXX_COMPILER=clang++
    # Suppress noisy Clang warnings that heavily pollutes the log
    -DLLVM_ENABLE_WARNINGS=OFF
    # Ensure compatibility with older macOS versions by setting the deployment target
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
    # Use Ninja for faster, parallel builds
    -G Ninja
    # No need to build examples, tests, or benchmarks
    -DLLVM_BUILD_EXAMPLES=OFF
    -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_BUILD_TESTS=OFF
    -DLLVM_INCLUDE_TESTS=OFF
    -DLLVM_INCLUDE_BENCHMARKS=OFF
    # Enabling assertions is generally recommended to build LLVM
    -DLLVM_ENABLE_ASSERTIONS=ON
    # We want to use the zstd we just built, so force LLVM to use it and not any system version
    -DLLVM_ENABLE_ZSTD=FORCE_ON
    -DLLVM_USE_STATIC_ZSTD=ON
    -DCMAKE_PREFIX_PATH="$ZSTD_INSTALL_PREFIX"
    # Disable LTO to avoid downstream consumers needing to have the same LTO configuration
    -DLLVM_ENABLE_LTO=OFF
    # Enable RTTI because we rely on it downstream
    -DLLVM_ENABLE_RTTI=ON
    # Disable components we don't need to speed up the build and reduce the size of the resulting binaries
    -DLLVM_ENABLE_LIBXML2=OFF
    -DLLVM_ENABLE_LIBEDIT=OFF
    -DLLVM_ENABLE_LIBPFM=OFF
    # Tools include FileCheck, not, and others that are useful to have in the install
    -DLLVM_INSTALL_UTILS=ON
  )

  # ── Stage 1: build lld with system linker ────────────────────
  log_step "Stage 1 – CMake configure (lld only, Release, system linker)"
  cmake "${cmake_args[@]}" -B "$build_dir_stage1" -DLLVM_ENABLE_PROJECTS="lld"
  log_done

  log_step "Stage 1 – Build lld"
  cmake --build "$build_dir_stage1" --target lld
  log_done

  # Use the just-built lld as the linker for stage 2
  export PATH="$PWD/$build_dir_stage1/bin:$PATH"

  # ── Stage 2: build mlir and lld, using the stage-1 lld as linker ────────────
  log_step "Stage 2 – CMake configure (mlir + lld, Release, stage-1 lld linker)"
  cmake "${cmake_args[@]}" -B "$build_dir_stage2" -DLLVM_ENABLE_PROJECTS="mlir;lld" -DLLVM_ENABLE_LLD=ON
  log_done

  log_step "Stage 2 – Build and install LLVM/MLIR"
  cmake --build "$build_dir_stage2" --target install
  log_done

  # Return to original directory
  popd > /dev/null
  rm -rf "$repo_dir"
}

ZSTD_INSTALL_PREFIX="$PWD/zstd-install"
build_zstd "$ZSTD_INSTALL_PREFIX"
build_llvm "$LLVM_PROJECT_REF" "$INSTALL_PREFIX"

# Bundle zstd into the LLVM install so consuming projects can find it
log_step "Bundling zstd into install tree"
mkdir -p "$INSTALL_PREFIX/include"
mkdir -p "$INSTALL_PREFIX/lib"
cp -r "$ZSTD_INSTALL_PREFIX/include/." "$INSTALL_PREFIX/include/"
cp -r "$ZSTD_INSTALL_PREFIX/lib/."     "$INSTALL_PREFIX/lib/"
log_done

# Strip binaries
log_step "Stripping debug symbols"
if command -v strip >/dev/null 2>&1; then
  find "$INSTALL_PREFIX/bin" -type f -perm -111 -exec strip -S {} + 2>/dev/null || true
  find "$INSTALL_PREFIX/lib" -name "*.a" -exec strip -S {} + 2>/dev/null || true
fi
log_done

# Define archive variables
ARCHIVE_NAME="llvm-mlir_${LLVM_PROJECT_REF}_macos_${UNAME_ARCH}_${HOST_TARGET}.tar.zst"
ARCHIVE_PATH="$PWD/${ARCHIVE_NAME}"

log_step "Creating archive: ${ARCHIVE_NAME}"
pushd "$INSTALL_PREFIX" > /dev/null
tar --use-compress-program="$ZSTD_INSTALL_PREFIX/bin/zstd -19 --long=30 --threads=0" -cf "${ARCHIVE_PATH}" . || {
  echo "Error: Failed to create archive" >&2
  exit 1
}
popd > /dev/null
log_done

# Package zstd executable
ZSTD_ARCHIVE_NAME="zstd-${ZSTD_VERSION}_macos_${UNAME_ARCH}_${HOST_TARGET}.tar.gz"
ZSTD_ARCHIVE_PATH="$PWD/${ZSTD_ARCHIVE_NAME}"
log_step "Packaging zstd: ${ZSTD_ARCHIVE_NAME}"
pushd "$ZSTD_INSTALL_PREFIX/bin" > /dev/null
tar -czf "${ZSTD_ARCHIVE_PATH}" zstd || {
  echo "Error: Failed to create zstd archive" >&2
  exit 1
}
popd > /dev/null
log_done

# Clean up zstd installation
rm -rf "$ZSTD_INSTALL_PREFIX"
