param(
    [string]$ToolPrefix = "",
    [string]$OutDir = "build",
    [string]$XPackRoot = "$env:APPDATA\\xPacks\\@xpack-dev-tools\\riscv-none-elf-gcc"
)

$ErrorActionPreference = "Stop"

function Resolve-Command {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        if ($candidate.Contains('\') -or $candidate.Contains('/') -or $candidate.Contains(':')) {
            if (Test-Path $candidate) {
                return (Resolve-Path $candidate).Path
            }
        } else {
            $command = Get-Command $candidate -ErrorAction SilentlyContinue
            if ($command) {
                return $command.Source
            }
        }
    }

    return $null
}

function Get-ToolCandidates {
    param(
        [string]$Prefix,
        [string]$ToolName
    )

    if ([string]::IsNullOrWhiteSpace($Prefix)) {
        return @()
    }

    if ($Prefix.Contains('\') -or $Prefix.Contains('/') -or $Prefix.Contains(':')) {
        return @("${Prefix}${ToolName}.exe", "${Prefix}${ToolName}")
    }

    return @("${Prefix}${ToolName}")
}

function Get-XPackPrefix {
    param([string]$Root)

    if (-not (Test-Path $Root)) {
        return $null
    }

    $versions = Get-ChildItem $Root -Directory | Sort-Object Name -Descending
    foreach ($version in $versions) {
        $binDir = Join-Path $version.FullName ".content\\bin"
        $gccPath = Join-Path $binDir "riscv-none-elf-gcc.exe"
        if (Test-Path $gccPath) {
            return (Join-Path $binDir "riscv-none-elf-")
        }
    }

    return $null
}

function Resolve-Toolchain {
    param(
        [string]$RequestedPrefix,
        [string]$DetectedXPackRoot
    )

    $prefixes = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($RequestedPrefix)) {
        $prefixes.Add($RequestedPrefix)
    } else {
        $prefixes.Add("riscv-none-elf-")
        $prefixes.Add("riscv32-unknown-elf-")
        $prefixes.Add("riscv64-unknown-elf-")
    }

    $xpackPrefix = Get-XPackPrefix -Root $DetectedXPackRoot
    if ($xpackPrefix) {
        $prefixes.Add($xpackPrefix)
    }

    foreach ($prefix in $prefixes) {
        $gcc = Resolve-Command (Get-ToolCandidates -Prefix $prefix -ToolName "gcc")
        $objcopy = Resolve-Command (Get-ToolCandidates -Prefix $prefix -ToolName "objcopy")
        $objdump = Resolve-Command (Get-ToolCandidates -Prefix $prefix -ToolName "objdump")

        if ($gcc -and $objcopy -and $objdump) {
            return [PSCustomObject]@{
                Prefix  = $prefix
                GCC     = $gcc
                Objcopy = $objcopy
                Objdump = $objdump
            }
        }
    }

    return $null
}

Push-Location $PSScriptRoot

try {
    $romDepthWords = 1024
    $romLastAddress = $romDepthWords - 1

    $toolchain = Resolve-Toolchain -RequestedPrefix $ToolPrefix -DetectedXPackRoot $XPackRoot
    if (-not $toolchain) {
        throw "Missing a usable RISC-V GCC toolchain. Install one on PATH, or install the xPack toolchain under '$XPackRoot', or pass -ToolPrefix with the correct prefix/path."
    }

    $cc = $toolchain.GCC
    $objcopy = $toolchain.Objcopy
    $objdump = $toolchain.Objdump

    New-Item -ItemType Directory -Force $OutDir | Out-Null
    Write-Host "Using toolchain prefix '$($toolchain.Prefix)'"

    $commonFlags = @(
        "-march=rv32i",
        "-mabi=ilp32",
        "-msmall-data-limit=0",
        "-Os",
        "-ffreestanding",
        "-fno-builtin",
        "-fdata-sections",
        "-ffunction-sections",
        "-fno-pic",
        "-Wall",
        "-Wextra",
        "-std=c11",
        "-I."
    )

    $linkFlags = @(
        "-nostdlib",
        "-nostartfiles",
        "-Wl,--gc-sections",
        "-Wl,-Map=$OutDir/phase0.map",
        "-T",
        "link.ld"
    )

    & $cc @commonFlags "-c" "start.S" "-o" "$OutDir/start.o"
    if ($LASTEXITCODE -ne 0) {
        throw "Assembling start.S failed."
    }

    & $cc @commonFlags "-c" "phase0_main.c" "-o" "$OutDir/phase0_main.o"
    if ($LASTEXITCODE -ne 0) {
        throw "Compiling phase0_main.c failed."
    }

    & $cc @commonFlags @linkFlags "$OutDir/start.o" "$OutDir/phase0_main.o" "-o" "$OutDir/phase0.elf"
    if ($LASTEXITCODE -ne 0) {
        throw "Linking phase0.elf failed."
    }

    & $objcopy "-O" "binary" "$OutDir/phase0.elf" "$OutDir/phase0.bin"
    if ($LASTEXITCODE -ne 0) {
        throw "Generating phase0.bin failed."
    }

    & $objdump "-d" "$OutDir/phase0.elf" | Set-Content "$OutDir/phase0.dis"

    $binPath = (Resolve-Path "$OutDir/phase0.bin").Path
    $bytes = [System.IO.File]::ReadAllBytes($binPath)
    $lines = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $bytes.Length; $i += 4) {
        $b0 = if ($i -lt $bytes.Length) { $bytes[$i] } else { 0 }
        $b1 = if (($i + 1) -lt $bytes.Length) { $bytes[$i + 1] } else { 0 }
        $b2 = if (($i + 2) -lt $bytes.Length) { $bytes[$i + 2] } else { 0 }
        $b3 = if (($i + 3) -lt $bytes.Length) { $bytes[$i + 3] } else { 0 }
        $lines.Add(("{0:x2}{1:x2}{2:x2}{3:x2}" -f $b3, $b2, $b1, $b0))
    }

    Set-Content "$OutDir/phase0.mem" $lines

    if ($lines.Count -gt $romDepthWords) {
        throw "Firmware image requires $($lines.Count) words, exceeding configured ROM depth $romDepthWords."
    }

    $mifLines = New-Object System.Collections.Generic.List[string]
    $mifLines.Add("DEPTH = $romDepthWords;")
    $mifLines.Add("WIDTH = 32;")
    $mifLines.Add("ADDRESS_RADIX = HEX;")
    $mifLines.Add("DATA_RADIX = HEX;")
    $mifLines.Add("CONTENT BEGIN")

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $mifLines.Add(("{0:X3} : {1};" -f $i, $lines[$i]))
    }

    if ($lines.Count -lt $romDepthWords) {
        $mifLines.Add(("[{0:X3}..{1:X3}] : 00000000;" -f $lines.Count, $romLastAddress))
    }

    $mifLines.Add("END;")
    Set-Content "$OutDir/phase0.mif" $mifLines

    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\\..")).Path
    $quartusDir = (Resolve-Path (Join-Path $repoRoot "quartus\\phase0")).Path
    Set-Content (Join-Path $repoRoot "phase0_fw.mif") $mifLines
    Set-Content (Join-Path $quartusDir "phase0_fw.mif") $mifLines

    Write-Host "Built $OutDir/phase0.elf, $OutDir/phase0.bin, and $OutDir/phase0.mem"
}
finally {
    Pop-Location
}
