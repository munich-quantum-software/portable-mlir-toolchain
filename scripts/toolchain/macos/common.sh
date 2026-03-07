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

# shellcheck source=../common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../common.sh"

remove_path_if_exists() {
  local p="$1"
  if [[ -e "$p" ]]; then
    rm -rf "$p"
  fi
}

ensure_ninja() {
  local version="${1:-1.13.0}"
  export PATH="$HOME/.local/bin:$PATH"

  if command -v ninja >/dev/null 2>&1; then
    local current
    current="$(ninja --version 2>/dev/null || true)"
    if [[ "$current" == "$version" ]]; then
      return
    fi
  fi

  log_step "Installing build tools (Ninja ${version})"
  uv tool install "ninja==${version}"
  log_done
}

compress_dir_to_archive() {
  local source_dir="$1"
  local archive_path="$2"
  local zstd_exe="$3"

  mkdir -p "$(dirname "$archive_path")"
  rm -f "$archive_path"

  log_step "Compressing $source_dir to $archive_path"
  pushd "$source_dir" > /dev/null
  tar -cf - . | "$zstd_exe" -19 --long=31 --threads=0 -f -o "$archive_path" -
  popd > /dev/null
  log_done
}

decompress_archive_to_dir() {
  local archive_path="$1"
  local destination_dir="$2"
  local zstd_exe="$3"

  remove_path_if_exists "$destination_dir"
  mkdir -p "$destination_dir"

  log_step "Decompressing $archive_path"
  "$zstd_exe" -d --long=31 "$archive_path" -c | tar -xf - -C "$destination_dir"
  log_done
}

initialize_llvm_source_tree() {
  local llvm_project_ref="$1"
  local repo_dir="$2"
  local temp_archive
  temp_archive="$(mktemp -t llvm-project-"${llvm_project_ref}".XXXXXX.tar.gz)"

  log_step "Downloading LLVM/MLIR source (${llvm_project_ref})"
  remove_path_if_exists "$repo_dir"
  mkdir -p "$repo_dir"

  curl -fL --retry 5 --retry-delay 5 \
    "https://github.com/llvm/llvm-project/archive/${llvm_project_ref}.tar.gz" \
    -o "$temp_archive"

  tar -xzf "$temp_archive" --strip-components=1 -C "$repo_dir" \
    --exclude='clang' \
    --exclude='lldb' \
    --exclude='polly' \
    --exclude='flang' \
    --exclude='openmp' \
    --exclude='libclc' \
    --exclude='libc' \
    --exclude='llvm/test' \
    --exclude='llvm/unittests' \
    --exclude='mlir/test' \
    --exclude='mlir/unittests'

  rm -f "$temp_archive"
  log_done
}

host_target_for_arch() {
  local arch="$1"
  if [[ "$arch" == "arm64" || "$arch" == "aarch64" ]]; then
    echo "AArch64"
  elif [[ "$arch" == "x86_64" ]]; then
    echo "X86"
  else
    echo ""
  fi
}
