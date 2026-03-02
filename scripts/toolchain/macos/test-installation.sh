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
  echo "Usage: $0 -a <archive_path> -z <zstd_install_prefix>"
  exit 1
}

while getopts "a:z:" opt; do
  case $opt in
    a) ARCHIVE_PATH="$OPTARG" ;;
    z) ZSTD_INSTALL_PREFIX="$OPTARG" ;;
    *) usage ;;
  esac
done

[[ -z "${ARCHIVE_PATH:-}" || -z "${ZSTD_INSTALL_PREFIX:-}" ]] && usage

ZSTD_BIN="$ZSTD_INSTALL_PREFIX/bin/zstd"

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

echo "Testing installation from ${ARCHIVE_PATH}..."

TEST_INSTALL_DIR=$(mktemp -d)
TEST_BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_INSTALL_DIR" "$TEST_BUILD_DIR"' EXIT

log_step "Extracting archive"
# macOS ships BSD tar; use explicit decompress + pipe instead of --use-compress-program
"$ZSTD_BIN" -d --long=30 "$ARCHIVE_PATH" -c | tar -xf - -C "$TEST_INSTALL_DIR"
log_done

log_step "Verifying archive structure"
# Verify basic structure
for d in bin include; do
  if [ ! -d "$TEST_INSTALL_DIR/$d" ]; then
    echo "Error: $d not found in installation" >&2
    exit 1
  fi
done

# Find the cmake config directories
MLIR_CMAKE_DIR=$(find "$TEST_INSTALL_DIR" -type d -name mlir -path "*/cmake/*" 2>/dev/null | head -1)
LLVM_CMAKE_DIR=$(find "$TEST_INSTALL_DIR" -type d -name llvm -path "*/cmake/*" 2>/dev/null | head -1)

if [ -z "$MLIR_CMAKE_DIR" ]; then
  echo "Error: MLIR cmake directory not found in installation" >&2
  exit 1
fi
if [ -z "$LLVM_CMAKE_DIR" ]; then
  echo "Error: LLVM cmake directory not found in installation" >&2
  exit 1
fi

echo "Found MLIR cmake dir: $MLIR_CMAKE_DIR"
echo "Found LLVM cmake dir: $LLVM_CMAKE_DIR"
log_done

log_step "Verifying key binaries"
export PATH="$TEST_INSTALL_DIR/bin:$PATH"
mlir-opt --version
mlir-translate --version
log_done

# Locate integration test sources relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
INTEGRATION_SRC="$REPO_ROOT/tests/integration"

if [ ! -d "$INTEGRATION_SRC" ]; then
  echo "Error: integration test sources not found at $INTEGRATION_SRC" >&2
  exit 1
fi

log_step "CMake configure – integration test"
cmake -G Ninja \
  -S "$INTEGRATION_SRC" \
  -B "$TEST_BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  "-DCMAKE_PREFIX_PATH=$TEST_INSTALL_DIR" \
  "-DMLIR_DIR=$MLIR_CMAKE_DIR" \
  "-DLLVM_DIR=$LLVM_CMAKE_DIR"
log_done

log_step "CMake build – integration test"
cmake --build "$TEST_BUILD_DIR"
log_done

log_step "Running integration test binary"
"$TEST_BUILD_DIR/hello_mlir"
log_done

echo "Integration test passed!"
