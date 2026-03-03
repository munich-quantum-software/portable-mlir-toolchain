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
  echo "Usage: $0 -e <zstd_exe_path> -z <zstd_archive_path> -a <mold_archive_path> [-v <mold_version>]"
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

MOLD_VERSION="2.40.4"
while getopts ":e:z:a:v:" opt; do
  case "$opt" in
    e) ZSTD_EXE_PATH="$OPTARG" ;;
    z) ZSTD_ARCHIVE_PATH="$OPTARG" ;;
    a) MOLD_ARCHIVE_PATH="$OPTARG" ;;
    v) MOLD_VERSION="$OPTARG" ;;
    *) usage ;;
  esac
done

[[ -z "${ZSTD_EXE_PATH:-}" || -z "${ZSTD_ARCHIVE_PATH:-}" || -z "${MOLD_ARCHIVE_PATH:-}" ]] && usage

ZSTD_EXE_PATH="$(resolve_abs_path "$ZSTD_EXE_PATH")"
ZSTD_ARCHIVE_PATH="$(resolve_abs_path "$ZSTD_ARCHIVE_PATH")"
MOLD_ARCHIVE_PATH="$(resolve_abs_path "$MOLD_ARCHIVE_PATH")"

if [[ ! -f "$ZSTD_EXE_PATH" ]]; then
  echo "Error: zstd executable not found at $ZSTD_EXE_PATH" >&2
  exit 1
fi
chmod +x "$ZSTD_EXE_PATH"
mkdir -p "$(dirname "$MOLD_ARCHIVE_PATH")"

io_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$io_dir"
}
trap cleanup EXIT

cp "$ZSTD_EXE_PATH" "$io_dir/zstd"
cp "$ZSTD_ARCHIVE_PATH" "$io_dir/zstd.tar.zst"
echo "$MOLD_VERSION" > "$io_dir/mold.version"

run_manylinux_stage "build-mold" "$io_dir"

cp "$io_dir/mold.tar.zst" "$MOLD_ARCHIVE_PATH"
