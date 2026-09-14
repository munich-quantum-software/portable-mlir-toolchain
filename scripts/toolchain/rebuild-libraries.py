#!/usr/bin/env python3
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

"""Rebuild a consumer's native LLVM/MLIR archive dependencies for PGO."""

import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--base-sdk", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--install", type=Path, required=True)
    parser.add_argument("--targets", type=Path, required=True, help="JSON list of LLVM/MLIR archive targets")
    parser.add_argument("--profile", type=Path, help="Use this merged profile; omitted instruments the libraries")
    args = parser.parse_args()
    if platform.system() not in {"Linux", "Darwin"}:
        parser.error("native library PGO requires Linux or macOS")
    source, base, build, install = (p.resolve() for p in [args.source, args.base_sdk, args.build, args.install])
    if any(a == b or a.is_relative_to(b) or b.is_relative_to(a)
           for a, b in [(base, build), (base, install), (build, install)]):
        parser.error("base SDK, build, and installation directories must not overlap")
    if not (source / "llvm/CMakeLists.txt").is_file():
        parser.error("--source must contain llvm/CMakeLists.txt")
    if args.profile and not args.profile.is_file():
        parser.error("the requested profile does not exist")
    compiler = shutil.which(os.environ.get("CC", "clang"))
    cxx = shutil.which(os.environ.get("CXX", "clang++"))
    if not compiler or not cxx or "clang" not in subprocess.check_output([cxx, "--version"], text=True).lower():
        parser.error("set CC and CXX to Clang or Apple Clang")
    archives = sorted((base / "lib").glob("libLLVM*.a")) + sorted((base / "lib").glob("libMLIR*.a"))
    available = {p.stem.removeprefix("lib") for p in archives}
    targets = json.loads(args.targets.read_text())
    if not isinstance(targets, list) or not targets or any(not isinstance(t, str) or t not in available for t in targets):
        parser.error("archive targets must be a nonempty subset of the base SDK's LLVM/MLIR archives")
    if len(targets) != len(set(targets)):
        parser.error("archive targets must be unique")
    generators = {
        "LLVM_TABLEGEN": "llvm-tblgen", "MLIR_TABLEGEN": "mlir-tblgen",
        "MLIR_PDLL_TABLEGEN": "mlir-pdll", "MLIR_SRC_SHARDER_TABLEGEN": "mlir-src-sharder",
        "MLIR_LINALG_ODS_YAML_GEN": "mlir-linalg-ods-yaml-gen",
    }
    for tool in [*generators.values(), "llvm-config"]:
        if not (base / "bin" / tool).is_file():
            parser.error(f"base SDK is missing {tool}")
    config = str(base / "bin/llvm-config")
    version = subprocess.check_output([config, "--version"], text=True).strip()
    source_versions = dict(re.findall(r"set\(LLVM_VERSION_(MAJOR|MINOR|PATCH)\s+(\d+)\)",
                                     (source / "cmake/Modules/LLVMVersion.cmake").read_text()))
    source_version = ".".join(source_versions[key] for key in ["MAJOR", "MINOR", "PATCH"])
    if source_version != version:
        parser.error(f"source version {source_version} differs from base SDK version {version}")
    if subprocess.check_output([config, "--assertion-mode"], text=True).strip() != "OFF":
        parser.error("native library PGO requires an assertion-free base SDK")
    cmake = [
        "cmake", "-S", str(source / "llvm"), "-B", str(build), "-G", "Ninja",
        "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_INSTALL_PREFIX={install}",
        f"-DCMAKE_C_COMPILER={compiler}", f"-DCMAKE_CXX_COMPILER={cxx}",
        f"-DLLVM_ENABLE_PROJECTS={'mlir;bolt' if any('BOLT' in p.name for p in archives) else 'mlir'}",
        "-DLLVM_TARGETS_TO_BUILD=host", "-DLLVM_ENABLE_ASSERTIONS=OFF", "-DLLVM_ENABLE_LTO=OFF",
        "-DLLVM_BUILD_TOOLS=ON", "-DLLVM_BUILD_TESTS=OFF", "-DLLVM_INCLUDE_TESTS=OFF",
        "-DLLVM_BUILD_EXAMPLES=OFF", "-DLLVM_INCLUDE_EXAMPLES=OFF", "-DLLVM_INCLUDE_BENCHMARKS=OFF",
        "-DLLVM_ENABLE_LIBXML2=OFF", "-DLLVM_ENABLE_LIBEDIT=OFF", "-DLLVM_ENABLE_LIBPFM=OFF",
        "-DLLVM_ENABLE_ZSTD=OFF", "-DLLVM_ENABLE_WARNINGS=OFF", "-DLLVM_INSTALL_UTILS=ON",
        "-DLLVM_PARALLEL_LINK_JOBS=1",
        *[f"-D{variable}={base / 'bin' / tool}" for variable, tool in generators.items()],
        f"-DLLVM_BUILD_INSTRUMENTED={'OFF' if args.profile else 'IR'}",
        f"-DLLVM_PROFDATA_FILE={args.profile.resolve() if args.profile else ''}",
        f"-DLLVM_PROFILE_DATA_DIR={build / 'build-profiles'}",
        *[f"-DCMAKE_{key}={os.environ[key]}" for key in ["AR", "RANLIB"] if key in os.environ],
    ]
    if platform.system() == "Darwin":
        cmake.append("-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0")
    else:
        cmake.append("-DLLVM_USE_LINKER=lld")
    subprocess.run(cmake, check=True)
    subprocess.run(["cmake", "--build", str(build), "--target", *targets], check=True)
    if not install.exists():
        shutil.copytree(base, install, symlinks=True)
    for component in ["llvm-headers", "mlir-headers", "cmake-exports", "mlir-cmake-exports"]:
        subprocess.run(["cmake", "--install", str(build), "--component", component], check=True)
    built = set()
    for archive in sorted((build / "lib").glob("*.a")):
        shutil.copy2(archive, install / "lib" / archive.name)
        (install / "lib" / archive.name).touch()
        built.add(archive.stem.removeprefix("lib"))
    if not set(targets) <= built:
        raise RuntimeError("one or more requested archives were not installed")


if __name__ == "__main__":
    main()
