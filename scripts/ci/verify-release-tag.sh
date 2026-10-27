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
: "${RELEASE_TAG:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}"
# Require an existing annotated tag with a GitHub-verified signature on this revision.
tag_sha=$(gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$RELEASE_TAG" --jq '.object | select(.type == "tag") | .sha')
[[ -n "$tag_sha" ]] || { echo "Release requires a signed annotated tag" >&2; exit 1; }
gh api "repos/$GITHUB_REPOSITORY/git/tags/$tag_sha" |
  jq -e --arg sha "$GITHUB_SHA" '.verification.verified and .object.type == "commit" and .object.sha == $sha' >/dev/null
