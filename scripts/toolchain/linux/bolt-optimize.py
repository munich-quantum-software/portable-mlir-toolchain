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

"""Optimize one final ELF binary using a fresh BOLT instrumentation profile."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("a training and validation command is required after --")
    binary = args.binary.resolve(strict=True)
    bolt = shutil.which("llvm-bolt")
    merge = shutil.which("merge-fdata")
    if not bolt or not merge:
        parser.error("llvm-bolt and merge-fdata must be on PATH")
    with tempfile.TemporaryDirectory(prefix="mqt-bolt-") as directory:
        work = Path(directory)
        original = work / "original"
        shutil.copy2(binary, original)
        profile = work / "profile.fdata"
        try:
            subprocess.run([
                bolt, str(original), "-o", str(binary), "-instrument",
                f"-instrumentation-file={profile}",
                f"-instrumentation-binpath={binary}",
                "-instrumentation-file-append-pid",
            ], check=True)
            subprocess.run(command, check=True)
            profiles = sorted(work.glob("profile.fdata*"))
            if not profiles or not any(path.stat().st_size for path in profiles):
                raise RuntimeError(f"No BOLT profile was collected for {binary}")
            merged = work / "merged.fdata"
            with merged.open("w") as stream:
                subprocess.run([merge, *map(str, profiles)], stdout=stream, check=True)
            subprocess.run([
                bolt, str(original), "-o", str(binary), f"-data={merged}",
                "-reorder-blocks=ext-tsp", "-reorder-functions=cdsort",
                "-split-functions", "-split-all-cold", "-split-eh", "-dyno-stats", "-lite",
            ], check=True)
            os.chmod(binary, original.stat().st_mode)
            subprocess.run(command, check=True)
        except BaseException:
            shutil.copy2(original, binary)
            raise


if __name__ == "__main__":
    main()
