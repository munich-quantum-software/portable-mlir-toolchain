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

set -euo pipefail
cd "$(dirname "$0")/.."
check_paths() {
  local expected="$1"
  shift
  local actual
  actual=$(printf '%s\0' "$@" | bash scripts/ci/changed-platforms.sh)
  [[ "$actual" == "$expected" ]] || { echo "Wrong platform selection: $actual" >&2; exit 1; }
}
all=$'run-linux=true\nrun-macos=true\nrun-windows=true'
check_paths "$all" scripts/toolchain/common.sh
check_paths "$all" tests/integration/main.cpp
check_paths "$all" .github/workflows/build-portable-mlir-toolchain.yml
check_paths $'run-linux=true\nrun-macos=false\nrun-windows=false' .github/workflows/build-mlir-linux-runner.yml
check_paths $'run-linux=false\nrun-macos=true\nrun-windows=true' scripts/toolchain/macos/deleted.sh scripts/toolchain/windows/new.ps1
check_paths $'run-linux=false\nrun-macos=false\nrun-windows=false' README.md

# Exercise deletion and rename enumeration with a real Git diff.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
mkdir -p "$tmp/scripts/toolchain/linux"
touch "$tmp/scripts/toolchain/linux/old.sh"
git -C "$tmp" add .
# Compare index/tree objects without creating an unsigned test commit.
tree=$(git -C "$tmp" write-tree)
rm "$tmp/scripts/toolchain/linux/old.sh"
git -C "$tmp" add -u
[[ "$(git -C "$tmp" diff --cached --no-renames --name-only -z "$tree" | bash scripts/ci/changed-platforms.sh)" == $'run-linux=true\nrun-macos=false\nrun-windows=false' ]]

# Stub the GitHub API; reject unsigned tags and tags for another revision.
mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/bin/bash
if [[ "$2" == */git/ref/* ]]; then
  [[ "$TAG_KIND" == tag ]] && echo abc
  exit 0
fi
printf '{"verification":{"verified":%s},"object":{"type":"commit","sha":"%s"}}' "$TAG_VERIFIED" "$TAG_COMMIT"
STUB
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" RELEASE_TAG=v1 GITHUB_REPOSITORY=owner/repo GITHUB_SHA=123
export TAG_KIND=tag TAG_VERIFIED=true TAG_COMMIT=123
bash scripts/ci/verify-release-tag.sh
for bad in unsigned wrong-commit lightweight; do
  export TAG_KIND=tag TAG_VERIFIED=true TAG_COMMIT=123
  case "$bad" in
    unsigned) TAG_VERIFIED=false ;;
    wrong-commit) TAG_COMMIT=456 ;;
    lightweight) TAG_KIND=commit ;;
  esac
  if bash scripts/ci/verify-release-tag.sh; then echo "Accepted $bad tag" >&2; exit 1; fi
done
# Exercise the Linux wrapper without a Docker daemon, including a failed stage.
cat > "$tmp/bin/docker" <<'DOCKER'
#!/bin/bash
set -euo pipefail
[[ " $* " != *' --privileged '* && " $* " == *' --user '* && " $* " == *':/work:ro '* ]]
for argument in "$@"; do
  case "$argument" in
    *:/build:rw) workspace=${argument%:/build:rw} ;;
    *:/io:rw) io=${argument%:/io:rw} ;;
  esac
done
printf '%s\n' "$workspace" >> "$WORKSPACE_LOG"
touch "$workspace/build-output"
[[ "${FAIL_STAGE:-0}" != 1 ]] || exit 7
touch "$io/zstd"
DOCKER
chmod +x "$tmp/bin/docker"
export HOST_BUILD_WORKSPACE="$tmp/builds" WORKSPACE_LOG="$tmp/workspaces"
bash scripts/toolchain/linux/build-zstd.sh -a "$tmp/one.tar.gz" &
one=$!
bash scripts/toolchain/linux/build-zstd.sh -a "$tmp/two.tar.gz" &
two=$!
wait "$one"
wait "$two"
[[ "$(sort -u "$WORKSPACE_LOG" | wc -l)" -eq 2 ]]
if FAIL_STAGE=1 bash scripts/toolchain/linux/build-zstd.sh -a "$tmp/failed.tar.gz"; then
  echo 'Failed build was accepted' >&2; exit 1
fi
[[ -z "$(ls -A "$HOST_BUILD_WORKSPACE")" ]]
# CI must use the runner work disk instead of a potentially quota-limited /tmp.
env -u HOST_BUILD_WORKSPACE RUNNER_TEMP="$tmp/runner" TMPDIR="$tmp" \
  bash scripts/toolchain/linux/build-zstd.sh -a "$tmp/runner.tar.gz"
[[ "$(tail -n 1 "$WORKSPACE_LOG")" == "$tmp/runner/"* ]]
[[ -z "$(ls -A "$tmp/runner")" ]]

# Tool versions nested under LC_BUILD_VERSION must not be read as OS versions.
checker=scripts/toolchain/macos/check-deployment-target.awk
printf 'cmd LC_BUILD_VERSION\nminos 13.3\nntools 1\ntool LD\nversion 1234.5\n' |
  awk -v target=13.3 -f "$checker"
printf 'cmd LC_VERSION_MIN_MACOSX\nversion 13.3.0\nsdk 26.5\n' |
  awk -v target=13.3 -f "$checker"
for metadata in $'cmd LC_BUILD_VERSION\nminos 14.0' $'cmd LC_VERSION_MIN_MACOSX\nversion 14.0' $'cmd LC_UUID\nversion 13.3'; do
  if printf '%s\n' "$metadata" | awk -v target=13.3 -f "$checker"; then
    echo 'Invalid deployment metadata was accepted' >&2; exit 1
  fi
done
echo 'CI helper tests passed'
