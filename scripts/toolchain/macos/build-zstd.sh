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
  echo "Usage: $0 -a <zstd_archive_path> [-v <zstd_version>] [-n <ninja_version>]"
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

ZSTD_VERSION="1.5.7"
NINJA_VERSION="1.13.0"
while getopts ":a:v:n:" opt; do
  case "$opt" in
    a) ZSTD_ARCHIVE_PATH="$OPTARG" ;;
    v) ZSTD_VERSION="$OPTARG" ;;
    n) NINJA_VERSION="$OPTARG" ;;
    *) usage ;;
  esac
done

[[ -z "${ZSTD_ARCHIVE_PATH:-}" ]] && usage

ensure_ninja "$NINJA_VERSION"
export MACOSX_DEPLOYMENT_TARGET="11.0"

ZSTD_ARCHIVE_PATH="$(resolve_abs_path "$ZSTD_ARCHIVE_PATH")"
mkdir -p "$(dirname "$ZSTD_ARCHIVE_PATH")"

tmp_dir="$(mktemp -d)"
install_dir="$tmp_dir/install"
zstd_tarball="$tmp_dir/zstd-${ZSTD_VERSION}.tar.gz"
zstd_src_dir="$tmp_dir/zstd-${ZSTD_VERSION}"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

log_step "Building zstd v${ZSTD_VERSION}"
curl -fL --retry 5 --retry-delay 5 "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz" -o "$zstd_tarball"

tar -xzf "$zstd_tarball" -C "$tmp_dir"
cmake -S "$zstd_src_dir/build/cmake" -B "$zstd_src_dir/build_cmake" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$install_dir" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
  -DZSTD_BUILD_STATIC=ON \
  -DZSTD_BUILD_SHARED=OFF

cmake --build "$zstd_src_dir/build_cmake" --target install --config Release
tar -C "$install_dir/bin" -czf "$ZSTD_ARCHIVE_PATH" zstd
log_done
