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
  echo "Usage: $0 -e <zstd_exe_path> -z <zstd_archive_path> -a <mold_archive_path> [-v <mold_version>] [-n <ninja_version>]"
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

MOLD_VERSION="2.40.4"
NINJA_VERSION="1.13.0"
while getopts ":e:z:a:v:n:" opt; do
  case "$opt" in
    e) ZSTD_EXE_PATH="$OPTARG" ;;
    z) ZSTD_ARCHIVE_PATH="$OPTARG" ;;
    a) MOLD_ARCHIVE_PATH="$OPTARG" ;;
    v) MOLD_VERSION="$OPTARG" ;;
    n) NINJA_VERSION="$OPTARG" ;;
    *) usage ;;
  esac
done

[[ -z "${ZSTD_EXE_PATH:-}" || -z "${ZSTD_ARCHIVE_PATH:-}" || -z "${MOLD_ARCHIVE_PATH:-}" ]] && usage

ensure_ninja "$NINJA_VERSION"
export MACOSX_DEPLOYMENT_TARGET="11.0"

ZSTD_EXE_PATH="$(resolve_abs_path "$ZSTD_EXE_PATH")"
ZSTD_ARCHIVE_PATH="$(resolve_abs_path "$ZSTD_ARCHIVE_PATH")"
MOLD_ARCHIVE_PATH="$(resolve_abs_path "$MOLD_ARCHIVE_PATH")"

tmp_dir="$(mktemp -d)"
zstd_extract_dir="$tmp_dir/zstd"
mold_install_dir="$tmp_dir/mold-install"
mold_tarball="$tmp_dir/mold-${MOLD_VERSION}.tar.gz"
mold_src_dir="$tmp_dir/mold-${MOLD_VERSION}"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

decompress_archive_to_dir "$ZSTD_ARCHIVE_PATH" "$zstd_extract_dir" "$ZSTD_EXE_PATH"

log_step "Building mold v${MOLD_VERSION}"
curl -fL --retry 5 --retry-delay 5 "https://github.com/rui314/mold/archive/refs/tags/v${MOLD_VERSION}.tar.gz" -o "$mold_tarball"
tar -xzf "$mold_tarball" -C "$tmp_dir"

cmake -S "$mold_src_dir" -B "$mold_src_dir/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$mold_install_dir" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
  -DCMAKE_PREFIX_PATH="$zstd_extract_dir" \
  -DMOLD_LTO=ON \
  -DMOLD_USE_SYSTEM_TBB=OFF \
  -DMOLD_USE_SYSTEM_MIMALLOC=OFF \
  -DMOLD_USE_MIMALLOC=ON

cmake --build "$mold_src_dir/build" --target install --config Release
if [[ ! -x "$mold_install_dir/bin/mold" && -x "$mold_install_dir/bin/ld64.mold" ]]; then
  ln -sf ld64.mold "$mold_install_dir/bin/mold"
fi
log_done

compress_dir_to_archive "$mold_install_dir" "$MOLD_ARCHIVE_PATH" "$ZSTD_EXE_PATH"
