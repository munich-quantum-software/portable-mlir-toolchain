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
  echo "Usage: $0 -e <zstd_exe_path> -z <zstd_archive_path> -m <mold_archive_path> -a <mlir_archive_path> [-n <ninja_version>] [-b <Release|Debug>]"
  exit 1
}

NINJA_VERSION="1.13.0"
BUILD_TYPE="Release"
while getopts "e:z:m:a:n:b:" opt; do
  case $opt in
    e) ZSTD_EXE_PATH="$OPTARG" ;;
    z) ZSTD_ARCHIVE_PATH="$OPTARG" ;;
    m) MOLD_ARCHIVE_PATH="$OPTARG" ;;
    a) MLIR_ARCHIVE_PATH="$OPTARG" ;;
    n) NINJA_VERSION="$OPTARG" ;;
    b) BUILD_TYPE="$OPTARG" ;;
    *) usage ;;
  esac
done

[[ -z "${ZSTD_EXE_PATH:-}" || -z "${ZSTD_ARCHIVE_PATH:-}" || -z "${MOLD_ARCHIVE_PATH:-}" || -z "${MLIR_ARCHIVE_PATH:-}" ]] && usage
[[ "$BUILD_TYPE" != "Release" && "$BUILD_TYPE" != "Debug" ]] && { echo "Error: build type must be Release or Debug" >&2; exit 1; }

if [[ ! -x "$ZSTD_EXE_PATH" ]]; then
  if [[ -f "$ZSTD_EXE_PATH" ]]; then
    chmod +x "$ZSTD_EXE_PATH"
  fi
fi
if [[ ! -x "$ZSTD_EXE_PATH" ]]; then
  echo "Error: zstd not found or not executable at '$ZSTD_EXE_PATH'" >&2
  exit 1
fi

# shellcheck source=./common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

ensure_ninja "$NINJA_VERSION"

echo "Testing installation from ${MLIR_ARCHIVE_PATH}..."

TEST_ZSTD_DIR=$(mktemp -d)
TEST_MOLD_DIR=$(mktemp -d)
TEST_MLIR_DIR=$(mktemp -d)
TEST_BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_ZSTD_DIR" "$TEST_MOLD_DIR" "$TEST_MLIR_DIR" "$TEST_BUILD_DIR"' EXIT

decompress_archive_to_dir "$ZSTD_ARCHIVE_PATH" "$TEST_ZSTD_DIR" "$ZSTD_EXE_PATH"
decompress_archive_to_dir "$MOLD_ARCHIVE_PATH" "$TEST_MOLD_DIR" "$ZSTD_EXE_PATH"
decompress_archive_to_dir "$MLIR_ARCHIVE_PATH" "$TEST_MLIR_DIR" "$ZSTD_EXE_PATH"

MLIR_CMAKE_DIR=$(find "$TEST_MLIR_DIR" -type d -name mlir -path "*/cmake/*" 2>/dev/null | head -1)
LLVM_CMAKE_DIR=$(find "$TEST_MLIR_DIR" -type d -name llvm -path "*/cmake/*" 2>/dev/null | head -1)

if [[ -z "$MLIR_CMAKE_DIR" ]]; then
  echo "Error: MLIR cmake directory not found in installation" >&2
  exit 1
fi
if [[ -z "$LLVM_CMAKE_DIR" ]]; then
  echo "Error: LLVM cmake directory not found in installation" >&2
  exit 1
fi

echo "Found MLIR cmake dir: $MLIR_CMAKE_DIR"
echo "Found LLVM cmake dir: $LLVM_CMAKE_DIR"
log_done

log_step "Verifying key binaries"
export PATH="$TEST_MLIR_DIR/bin:$TEST_MOLD_DIR/bin:$PATH"
mlir-opt --version
mlir-translate --version
if [[ -x "$TEST_MOLD_DIR/bin/mold" ]]; then
  "$TEST_MOLD_DIR/bin/mold" --version
fi
log_done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
INTEGRATION_SRC="$REPO_ROOT/tests/integration"

if [[ ! -d "$INTEGRATION_SRC" ]]; then
  echo "Error: integration test sources not found at $INTEGRATION_SRC" >&2
  exit 1
fi

log_step "CMake configure - integration test"
cmake -G Ninja \
  -S "$INTEGRATION_SRC" \
  -B "$TEST_BUILD_DIR" \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  "-DCMAKE_PREFIX_PATH=$TEST_ZSTD_DIR;$TEST_MLIR_DIR" \
  "-DMLIR_DIR=$MLIR_CMAKE_DIR" \
  "-DLLVM_DIR=$LLVM_CMAKE_DIR" \
  -DLLVM_USE_LINKER=mold
log_done

log_step "CMake build - integration test"
cmake --build "$TEST_BUILD_DIR"
log_done

log_step "Running integration test binary"
"$TEST_BUILD_DIR/hello_mlir"
log_done

echo "Integration test passed!"
