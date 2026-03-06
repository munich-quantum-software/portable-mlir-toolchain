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

resolve_abs_path() {
  local p="$1"
  case "$p" in
    /*) printf '%s\n' "$p" ;;
    *) printf '%s\n' "$PWD/$p" ;;
  esac
}

manylinux_image_for_host() {
  local arch
  arch="$(uname -m)"
  if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
    echo "quay.io/pypa/manylinux_2_28_aarch64:2026.02.28-1"
  else
    echo "quay.io/pypa/manylinux_2_28_x86_64:2026.02.28-1"
  fi
}

repo_root_from_script_dir() {
  local script_dir="$1"
  (cd "$script_dir/../../.." && pwd)
}

run_manylinux_stage() {
  local stage="$1"
  local io_dir="$2"
  local llvm_project_ref="${3:-}"
  local build_type="${4:-Release}"

  local script_dir root_dir in_container_script base_image
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" &>/dev/null && pwd)"
  root_dir="$(repo_root_from_script_dir "$script_dir")"
  in_container_script="/work${script_dir#"${root_dir}"}/in-container.sh"
  base_image="$(manylinux_image_for_host)"

  mkdir -p "$io_dir"

  local env_args=(
    -e HOME=/work
    -e STAGE="$stage"
    -e IO_DIR=/io
    -e BUILD_WORKSPACE=/build
    -e CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-4}"
    -e BUILD_TYPE="$build_type"
  )

  if [[ -n "$llvm_project_ref" ]]; then
    env_args+=( -e LLVM_PROJECT_REF="$llvm_project_ref" )
  fi

  local host_build_workspace_default="${root_dir}/.build-work"
  if [[ -d "/mnt" && -w "/mnt" ]]; then
    host_build_workspace_default="/mnt/portable-mlir-toolchain-build"
  fi
  local host_build_workspace="${HOST_BUILD_WORKSPACE:-$host_build_workspace_default}"
  mkdir -p "$host_build_workspace"

  sudo docker run --rm --privileged \
    -v "$root_dir":/work:rw \
    -v "$io_dir":/io:rw \
    -v "$host_build_workspace":/build:rw \
    "${env_args[@]}" \
    "$base_image" \
    bash -euo pipefail "$in_container_script"
}

extract_zstd_executable() {
  local zstd_archive_path="$1"
  local destination_dir="$2"
  mkdir -p "$destination_dir"
  tar -xzf "$zstd_archive_path" -C "$destination_dir"
  chmod +x "$destination_dir/zstd"
  printf '%s\n' "$destination_dir/zstd"
}
