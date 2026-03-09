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

$ErrorActionPreference = 'Continue'

function Show-DiskUsage {
    param([string]$Label)

    Write-Host ""
    Write-Host "=== Disk usage ($Label) ==="
    Get-PSDrive -PSProvider FileSystem | Sort-Object Name | Format-Table -AutoSize
}

function Remove-IfExists {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path $Path) {
        Write-Host "Removing $Path"
        Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Show-DiskUsage -Label 'before cleanup'

# Big optional stacks we do not need for this workflow.
$pathsToRemove = @(
    'C:\azureCLI',
    'C:\azureDevOpsCli',
    'C:\Android\android-sdk',
    'C:\hostedtoolcache',
    'C:\Julia',
    'C:\mingw32',
    'C:\mingw64',
    'C:\npm',
    'C:\ghcup',
    'C:\rtools45',
    'C:\msys64',
    'C:\Strawberry',
    'C:\PostgreSQL',
    'C:\aliyun-cli',
    'C:\temp',
    'C:\Program Files\Amazon',
    'C:\Program Files\Android',
    'C:\Program Files\Azure Cosmos DB Emulator',
    'C:\Program Files\dotnet',
    'C:\Program Files\ghc',
    'C:\Program Files\Google',
    'C:\Program Files\Internet Explorer',
    'C:\Program Files\LLVM',
    'C:\Program Files\Microsoft\Edge',
    'C:\Program Files\Mozilla Firefox',
    'C:\Program Files\MySQL',
    'C:\Program Files\nodejs',
    'C:\Program Files\Windows Mail',
    'C:\Program Files\Windows Media Player',
    'C:\Program Files\Windows NT',
    'C:\Program Files\Windows Photo Viewer',
    'C:\Program Files (x86)\Android',
    'C:\Program Files (x86)\Epic Games',
    'C:\Program Files (x86)\Internet Explorer',
    'C:\Program Files (x86)\Google',
    'C:\Program Files (x86)\Microsoft\Edge',
    'C:\Program Files (x86)\Windows Mail',
    'C:\Program Files (x86)\Windows Media Player',
    'C:\Program Files (x86)\Windows NT',
    'C:\Program Files (x86)\Windows Photo Viewer',
    'C:\Selenium',
    'C:\SeleniumWebDrivers',
    'C:\vcpkg',
    "$env:AGENT_TOOLSDIRECTORY",
    'C:\Miniconda'
)

foreach ($path in $pathsToRemove) {
    if ($path) {
        Remove-IfExists -Path $path
    }
}

try {
    wsl --shutdown | Out-Null
    Remove-IfExists -Path "$env:LOCALAPPDATA\Packages\CanonicalGroupLimited.Ubuntu*"
    Remove-IfExists -Path "$env:LOCALAPPDATA\Packages\TheDebianProject.DebianGNULinux*"
    Remove-IfExists -Path "$env:LOCALAPPDATA\Packages\kali-linux.*"
} catch {
    # Intentionally swallowing errors so best-effort cleanup can continue.
}

try {
    docker system prune -af --volumes | Out-Null
} catch {
    # Intentionally swallowing errors so best-effort cleanup can continue.
}
Remove-IfExists -Path 'C:\ProgramData\Docker'

Remove-IfExists -Path 'C:\Windows\Temp'
Remove-IfExists -Path "$env:TEMP"
Remove-IfExists -Path "$env:LOCALAPPDATA\Temp"

try {
    dotnet nuget locals all --clear | Out-Null
} catch {
    # Intentionally swallowing errors so best-effort cleanup can continue.
}

# Recreate user temp directories for later workflow steps.
foreach ($tempPath in @($env:TEMP, "$env:LOCALAPPDATA\Temp")) {
    if ($tempPath -and -not (Test-Path $tempPath)) {
        New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
    }
}

Show-DiskUsage -Label 'after cleanup'

# Never fail the workflow step because cleanup could not remove something.
exit 0
