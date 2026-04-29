param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("orchestrator", "manual-reader", "implementer", "verifier")]
    [string]$Role,

    [string]$PythonExe = "python",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RunnerArgs
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")

if (-not $env:REPO_ROOT) {
    $env:REPO_ROOT = $RepoRoot
}
if (-not $env:WINDOWS_REPO_ROOT) {
    $env:WINDOWS_REPO_ROOT = $RepoRoot
}

& $PythonExe `
  (Join-Path $RepoRoot "scripts/teambus_role_runner.py") `
  --config (Join-Path $RepoRoot "runner/roles.json") `
  $Role `
  @RunnerArgs
