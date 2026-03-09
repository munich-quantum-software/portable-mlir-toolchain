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
  echo "Usage: $0 -r <llvm_project_ref> -z <zstd_archive_path> -m <mold_archive_path> -a <mlir_archive_path> [-b <Release|Debug>]"
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

BUILD_TYPE="Release"
while getopts ":r:z:m:a:b:" opt; do
  case "$opt" in
    r) LLVM_PROJECT_REF="$OPTARG" ;;
    z) ZSTD_ARCHIVE_PATH="$OPTARG" ;;
    m) MOLD_ARCHIVE_PATH="$OPTARG" ;;
    a) MLIR_ARCHIVE_PATH="$OPTARG" ;;
    b) BUILD_TYPE="$OPTARG" ;;
    *) usage ;;
  esac
done

[[ -z "${LLVM_PROJECT_REF:-}" || -z "${ZSTD_ARCHIVE_PATH:-}" || -z "${MOLD_ARCHIVE_PATH:-}" || -z "${MLIR_ARCHIVE_PATH:-}" ]] && usage
[[ "$BUILD_TYPE" != "Release" && "$BUILD_TYPE" != "Debug" ]] && { echo "Error: build type must be Release or Debug" >&2; exit 1; }

ZSTD_ARCHIVE_PATH="$(resolve_abs_path "$ZSTD_ARCHIVE_PATH")"
MOLD_ARCHIVE_PATH="$(resolve_abs_path "$MOLD_ARCHIVE_PATH")"
MLIR_ARCHIVE_PATH="$(resolve_abs_path "$MLIR_ARCHIVE_PATH")"

if [[ ! -f "$ZSTD_ARCHIVE_PATH" ]]; then
  echo "Error: zstd archive not found at $ZSTD_ARCHIVE_PATH" >&2
  exit 1
fi
if [[ ! -f "$MOLD_ARCHIVE_PATH" ]]; then
  echo "Error: mold archive not found at $MOLD_ARCHIVE_PATH" >&2
  exit 1
fi
mkdir -p "$(dirname "$MLIR_ARCHIVE_PATH")"

io_dir="$(mktemp -d)"
zstd_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$io_dir" "$zstd_dir"
}
trap cleanup EXIT

extract_zstd_executable "$ZSTD_ARCHIVE_PATH" "$zstd_dir" >/dev/null
cp "$zstd_dir/zstd" "$io_dir/zstd"
cp "$MOLD_ARCHIVE_PATH" "$io_dir/mold.tar.zst"

run_manylinux_stage "build-mlir" "$io_dir" "$LLVM_PROJECT_REF" "$BUILD_TYPE"

cp "$io_dir/mlir.tar.zst" "$MLIR_ARCHIVE_PATH"
