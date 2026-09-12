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

"""Build Unix SDK library variants while retaining the base SDK's native tools."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import time


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--source-id", required=True, help="Resolved LLVM commit or source archive SHA-256")
    parser.add_argument("--base-sdk", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--install", type=Path, required=True)
    parser.add_argument("--lto", choices=["OFF", "Thin", "Full"], required=True)
    parser.add_argument("--phase", choices=["plain", "generate", "use"], default="plain")
    parser.add_argument("--profile", type=Path)
    parser.add_argument("--targets", type=Path, help="JSON archive target list; omitted means all LLVM/MLIR archives")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--lto-workers", type=int, default=1)
    parser.add_argument("--define", action="append", default=[], help="Additional CMake KEY=VALUE")
    args = parser.parse_args()
    if (args.phase == "use") != (args.profile is not None):
        parser.error("--profile is required only for --phase use")
    if min(args.jobs, args.lto_workers) < 1 or platform.system() not in {"Linux", "Darwin"}:
        parser.error("a positive job count and a Linux or macOS host are required")
    source, base, build, install = (p.resolve() for p in [args.source, args.base_sdk, args.build, args.install])
    if any(a == b or a.is_relative_to(b) or b.is_relative_to(a) for a, b in [(base, install), (build, install)]):
        parser.error("base SDK, build, and installation directories must not overlap")
    if not (source / "llvm/CMakeLists.txt").is_file():
        parser.error("--source must contain llvm/CMakeLists.txt")
    if args.profile and not args.profile.is_file():
        parser.error("the requested profile does not exist")
    compiler = shutil.which(os.environ.get("CC", "clang"))
    cxx = shutil.which(os.environ.get("CXX", "clang++"))
    if not compiler or not cxx:
        parser.error("set CC and CXX to the selected Clang toolchain")
    version = subprocess.check_output([cxx, "--version"], text=True)
    if "clang" not in version.lower():
        parser.error("library variants currently support Clang and Apple Clang")
    archives = sorted((base / "lib").glob("libLLVM*.a")) + sorted((base / "lib").glob("libMLIR*.a"))
    available = {p.name.removeprefix("lib").removesuffix(".a") for p in archives}
    targets = sorted(available) if args.targets is None else json.loads(args.targets.read_text())
    if not targets or not isinstance(targets, list) or any(t not in available for t in targets):
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
    llvm_version = subprocess.check_output([str(base / "bin/llvm-config"), "--version"], text=True).strip()
    version_file = source / "cmake/Modules/LLVMVersion.cmake"
    source_versions = dict(re.findall(r"set\(LLVM_VERSION_(MAJOR|MINOR|PATCH)\s+(\d+)\)", version_file.read_text()))
    source_version = ".".join(source_versions[key] for key in ["MAJOR", "MINOR", "PATCH"])
    if source_version != llvm_version:
        parser.error(f"source version {source_version} differs from base SDK version {llvm_version}")
    assertions = subprocess.check_output([str(base / "bin/llvm-config"), "--assertion-mode"], text=True).strip()
    if assertions != "OFF":
        parser.error("release library variants require an assertion-free base SDK")
    protected = {"CMAKE_BUILD_TYPE", "CMAKE_INSTALL_PREFIX", "CMAKE_C_COMPILER", "CMAKE_CXX_COMPILER",
                 "LLVM_ENABLE_LTO", "LLVM_ENABLE_ASSERTIONS", "LLVM_BUILD_INSTRUMENTED", "LLVM_PROFDATA_FILE"}
    if any("=" not in item or item.split("=", 1)[0] in protected for item in args.define):
        parser.error("--define must use KEY=VALUE and must not override the variant contract")
    identity = {
        "source": str(source), "source_id": args.source_id,
        "source_cmake_sha256": digest(source / "llvm/CMakeLists.txt"),
        "base_sdk": str(base), "llvm_version": llvm_version, "compiler": cxx,
        "compiler_sha256": digest(Path(cxx)), "c_compiler": compiler,
        "base_archives_sha256": {p.name: digest(p) for p in archives},
        "compiler_version": version, "platform": platform.platform(), "machine": platform.machine(),
        "install": str(install), "lto": args.lto, "assertions": False, "defines": args.define,
        "lto_workers": args.lto_workers,
    }
    identity["compiler_configs_sha256"] = {
        str(path): digest(path) for path in sorted(Path(cxx).parent.glob("*.cfg"))
    }
    if platform.system() == "Darwin":
        identity["xcode"] = subprocess.check_output(["xcodebuild", "-version"], text=True)
        identity["macos_sdk"] = subprocess.check_output(["xcrun", "--show-sdk-build-version"], text=True).strip()
    build.mkdir(parents=True, exist_ok=True)
    contract = build / "variant-contract.json"
    if contract.exists() and json.loads(contract.read_text()) != identity:
        parser.error("build identity changed; use a fresh build and installation directory")
    contract.write_text(json.dumps(identity, indent=2) + "\n")
    cmake = [
        "cmake", "-S", str(source / "llvm"), "-B", str(build), "-G", "Ninja",
        "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_INSTALL_PREFIX={install}",
        f"-DCMAKE_C_COMPILER={compiler}", f"-DCMAKE_CXX_COMPILER={cxx}",
        f"-DLLVM_ENABLE_PROJECTS={'mlir;bolt' if any('BOLT' in p.name for p in archives) else 'mlir'}",
        "-DLLVM_TARGETS_TO_BUILD=host",
        "-DLLVM_ENABLE_ASSERTIONS=OFF", f"-DLLVM_ENABLE_LTO={args.lto}",
        "-DLLVM_BUILD_TOOLS=ON", "-DLLVM_BUILD_TESTS=OFF", "-DLLVM_INCLUDE_TESTS=OFF",
        "-DLLVM_BUILD_EXAMPLES=OFF", "-DLLVM_INCLUDE_EXAMPLES=OFF", "-DLLVM_INCLUDE_BENCHMARKS=OFF",
        "-DLLVM_ENABLE_LIBXML2=OFF", "-DLLVM_ENABLE_LIBEDIT=OFF", "-DLLVM_ENABLE_LIBPFM=OFF",
        "-DLLVM_ENABLE_ZSTD=OFF", "-DLLVM_ENABLE_WARNINGS=OFF", "-DLLVM_INSTALL_UTILS=ON",
        "-DLLVM_PARALLEL_LINK_JOBS=1",
        *[f"-D{variable}={base / 'bin' / tool}" for variable, tool in generators.items()],
        f"-DLLVM_BUILD_INSTRUMENTED={'IR' if args.phase == 'generate' else 'OFF'}",
        f"-DLLVM_PROFDATA_FILE={args.profile.resolve() if args.profile else ''}",
        f"-DLLVM_PROFILE_DATA_DIR={build / 'build-profiles'}",
        *[f"-D{item}" for item in args.define],
    ]
    if platform.system() == "Darwin":
        cmake += ["-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0"]
        linker_flags = f"-Wl,-mllvm,-threads={args.lto_workers}"
    else:
        cmake += ["-DLLVM_USE_LINKER=lld"]
        linker_flags = f"-fuse-ld=lld -Wl,--thinlto-jobs={args.lto_workers},--lto-partitions={args.lto_workers}"
    cmake += [f"-DCMAKE_{kind}_LINKER_FLAGS={linker_flags}" for kind in ["EXE", "SHARED", "MODULE"]]
    started = time.monotonic()
    record = identity | {"phase": args.phase, "targets": targets, "all_archives": set(targets) == available,
                         "profile_sha256": digest(args.profile) if args.profile else None, "configure": cmake}
    report = build / f"variant-{args.phase}.json"
    report.write_text(json.dumps(record, indent=2) + "\n")
    try:
        subprocess.run(cmake, check=True)
        subprocess.run(["cmake", "--build", str(build), "--target", *targets, "-j", str(args.jobs)], check=True)
        if not install.exists():
            shutil.copytree(base, install, symlinks=True)
        for component in ["llvm-headers", "mlir-headers", "cmake-exports", "mlir-cmake-exports"]:
            subprocess.run(["cmake", "--install", str(build), "--component", component], check=True)
        built = {}
        for archive in sorted((build / "lib").glob("*.a")):
            destination = install / "lib" / archive.name
            shutil.copy2(archive, destination)
            destination.touch()
            built[archive.name] = digest(destination)
        if not {f"lib{target}.a" for target in targets} <= built.keys():
            raise RuntimeError("one or more requested archives were not installed")
        record |= {"archives_sha256": built, "returncode": 0}
        (install / "library-variant.json").write_text(json.dumps(record, indent=2) + "\n")
    except (subprocess.CalledProcessError, OSError, RuntimeError) as error:
        record |= {"returncode": getattr(error, "returncode", 1), "error": str(error)}
        raise
    finally:
        record["elapsed_seconds"] = time.monotonic() - started
        report.write_text(json.dumps(record, indent=2) + "\n")


if __name__ == "__main__":
    main()
