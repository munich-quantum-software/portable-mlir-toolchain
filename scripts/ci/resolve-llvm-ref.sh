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
ref=${1:?Expected an LLVM ref}
[[ "$ref" =~ ^[A-Za-z0-9._-]+$ ]] || { echo 'Use a tag, SHA, or branch without slashes' >&2; exit 1; }
sha=$(gh api "repos/llvm/llvm-project/commits/$ref" --jq .sha)
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid LLVM commit for $ref" >&2; exit 1; }
archive_ref=$sha
if [[ "$ref" =~ ^llvmorg-[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  archive_ref=$ref
fi
printf 'sha=%s\narchive-ref=%s\n' "$sha" "$archive_ref"
