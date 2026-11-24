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

ARG MANYLINUX_IMAGE
FROM ${MANYLINUX_IMAGE}
RUN manylinux-install-clang -v 23.1.6.0 -c f2f15b723880761ec9c852dc8a46f0de6244b99e59fc632ae998a88fb5ddfeed && \
    dnf -y install gcc-toolset-14-binutils-devel && dnf clean all
