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

$1 == "cmd" { command = $2 }
# LC_BUILD_VERSION also contains tool versions, which are not deployment targets.
(command == "LC_BUILD_VERSION" && $1 == "minos") ||
(command == "LC_VERSION_MIN_MACOSX" && $1 == "version") {
    seen = 1
    if ($2 != target && $2 != target ".0") {
        print "Unexpected macOS deployment target: " $2 " (expected " target ")" > "/dev/stderr"
        bad = 1
    }
}
END {
    if (!seen) print "Missing macOS deployment target" > "/dev/stderr"
    exit (bad || !seen)
}
