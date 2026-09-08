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
  echo "Usage: $0 -z <zstd_archive_path> -a <mlir_archive_path> [-b <Release|Debug>]"
  exit 1
}

BUILD_TYPE="Release"
while getopts "z:a:b:" opt; do
  case "$opt" in
    z) ZSTD_ARCHIVE_PATH="$OPTARG" ;;
    a) MLIR_ARCHIVE_PATH="$OPTARG" ;;
    b) BUILD_TYPE="$OPTARG" ;;
    *) usage ;;
  esac
done

[[ -z "${ZSTD_ARCHIVE_PATH:-}" || -z "${MLIR_ARCHIVE_PATH:-}" ]] && usage
[[ "$BUILD_TYPE" != "Release" && "$BUILD_TYPE" != "Debug" ]] && { echo "Error: build type must be Release or Debug" >&2; exit 1; }

# shellcheck source=./common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

if [[ "${LLVM_ENABLE_ASSERTIONS:-ON}" == "OFF" && "${MQT_MANYLINUX_TEST:-0}" != "1" ]]; then
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  root_dir="$(repo_root_from_script_dir "$script_dir")"
  sudo docker run --rm \
    -v "$root_dir":/work:ro \
    -v "$(resolve_abs_path "$ZSTD_ARCHIVE_PATH")":/zstd.tar.gz:ro \
    -v "$(resolve_abs_path "$MLIR_ARCHIVE_PATH")":/mlir.tar.zst:ro \
    -e MQT_MANYLINUX_TEST=1 \
    -e LLVM_ENABLE_ASSERTIONS="${LLVM_ENABLE_ASSERTIONS:-ON}" \
    "$(manylinux_image_for_host)" \
    bash -euc 'uv tool install ninja==1.13.0; export PATH="$HOME/.local/bin:$PATH"; exec bash "$@"' bash \
    /work/scripts/toolchain/linux/test-installation.sh \
    -z /zstd.tar.gz -a /mlir.tar.zst -b "$BUILD_TYPE"
  exit
fi

echo "Testing installation from ${MLIR_ARCHIVE_PATH}..."

TEST_ZSTD_DIR=$(mktemp -d)
TEST_MLIR_DIR=$(mktemp -d)
TEST_BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_ZSTD_DIR" "$TEST_MLIR_DIR" "$TEST_BUILD_DIR"' EXIT

extract_zstd_executable "$ZSTD_ARCHIVE_PATH" "$TEST_ZSTD_DIR" >/dev/null
ZSTD_EXE_PATH="$TEST_ZSTD_DIR/zstd"

log_step "Extracting MLIR archive"
"$ZSTD_EXE_PATH" -d --long=31 "$MLIR_ARCHIVE_PATH" -c | tar -xf - -C "$TEST_MLIR_DIR"
log_done

log_step "Verifying key binaries"
export PATH="$TEST_MLIR_DIR/bin:$PATH"
mlir-opt --version
mlir-translate --version
if [[ -x "$TEST_MLIR_DIR/bin/mold" ]]; then
  "$TEST_MLIR_DIR/bin/mold" --version
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
  -DEXPECTED_LLVM_ASSERTIONS="${LLVM_ENABLE_ASSERTIONS:-ON}" \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION="$(if [[ "${LLVM_ENABLE_ASSERTIONS:-ON}" == "OFF" ]]; then echo ON; else echo OFF; fi)" \
  "-DCMAKE_PREFIX_PATH=$TEST_MLIR_DIR" \
  -DLLVM_USE_LINKER="$(if [[ "${LLVM_ENABLE_ASSERTIONS:-ON}" == "OFF" ]]; then echo bfd; else echo mold; fi)"
log_done

log_step "CMake build - integration test"
cmake --build "$TEST_BUILD_DIR"
log_done

log_step "Running integration test binary"
"$TEST_BUILD_DIR/hello_mlir"
log_done

if [[ "${LLVM_ENABLE_ASSERTIONS:-ON}" == "OFF" ]]; then
  log_step "BOLT integration and failure recovery"
  cp "$TEST_BUILD_DIR/hello_mlir" "$TEST_BUILD_DIR/original"
  mqt-bolt-optimize "$TEST_BUILD_DIR/hello_mlir" -- "$TEST_BUILD_DIR/hello_mlir"
  cp "$TEST_BUILD_DIR/original" "$TEST_BUILD_DIR/hello_mlir"
  if mqt-bolt-optimize "$TEST_BUILD_DIR/hello_mlir" -- false > "$TEST_BUILD_DIR/expected-failure.log" 2>&1; then
    echo "Error: BOLT accepted a failed training command" >&2
    exit 1
  fi
  cmp "$TEST_BUILD_DIR/original" "$TEST_BUILD_DIR/hello_mlir"
  log_done
fi

echo "Integration test passed!"
