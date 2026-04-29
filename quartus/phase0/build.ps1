param(
    [ValidateSet("map", "fit", "asm", "sta", "compile")]
    [string]$Stage = "compile"
)

$ErrorActionPreference = "Stop"

$revision = "piano_phase0_top"

function Get-QuartusExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $resolved = Get-Command $Command -ErrorAction Stop
    $toolDir = Split-Path -Parent $resolved.Source
    $toolName = Split-Path -Leaf $resolved.Source
    $quartusRoot = Split-Path -Parent $toolDir
    $bin64Tool = Join-Path (Join-Path $quartusRoot "bin64") $toolName

    if (Test-Path $bin64Tool) {
        return $bin64Tool
    }

    return $resolved.Source
}

function Invoke-QuartusTool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $tool = Get-QuartusExecutable -Command $Command
    & $tool @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE."
    }
}

Push-Location $PSScriptRoot
try {
    & (Join-Path $PSScriptRoot "..\\..\\fw\\phase0\\build.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "Firmware build failed with exit code $LASTEXITCODE."
    }

    switch ($Stage) {
        "map" {
            Invoke-QuartusTool -Command "quartus_map" -Arguments @(
                "--read_settings_files=on",
                "--write_settings_files=off",
                $revision
            )
        }
        "fit" {
            Invoke-QuartusTool -Command "quartus_fit" -Arguments @(
                "--read_settings_files=on",
                "--write_settings_files=off",
                $revision
            )
        }
        "asm" {
            Invoke-QuartusTool -Command "quartus_asm" -Arguments @(
                "--read_settings_files=on",
                "--write_settings_files=off",
                $revision
            )
        }
        "sta" {
            Invoke-QuartusTool -Command "quartus_sta" -Arguments @(
                $revision
            )
        }
        "compile" {
            Invoke-QuartusTool -Command "quartus_sh" -Arguments @(
                "--flow",
                "compile",
                $revision
            )
        }
    }
}
finally {
    Pop-Location
}
