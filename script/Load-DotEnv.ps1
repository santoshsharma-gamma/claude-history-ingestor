<#
.SYNOPSIS
    Loads a .env file's KEY=VALUE lines into $env: variables for the
    CURRENT PowerShell session - lets jira-usage-report.ps1 (and anything
    else that reads $env:) share the same .env file docker-compose uses,
    instead of needing its own separate copy of the same credentials.

.DESCRIPTION
    Must be run directly in your PowerShell session (dot the file isn't
    even required, since this uses [Environment]::SetEnvironmentVariable
    with "Process" scope, which affects the current process regardless).
    Do NOT run this via `powershell -File Load-DotEnv.ps1` - that spawns
    a separate child process, and the environment variables it sets
    would vanish with that process rather than persisting in your actual
    session (the same class of problem documented in
    docs/jira-ticket-verification.md for jira-usage-report.ps1 itself).

.PARAMETER Path
    Path to the .env file. Defaults to .env in the current directory.

.EXAMPLE
    .\Load-DotEnv.ps1
    .\jira-usage-report.ps1 -Ticket "GGLOBDRA-1900"

.EXAMPLE
    .\Load-DotEnv.ps1 -Path ..\docker\.env
#>

param(
    [string]$Path = ".env"
)

if (-not (Test-Path $Path)) {
    Write-Host "No .env file found at '$Path'."
    return
}

$count = 0
foreach ($line in Get-Content $Path) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#") -or -not $trimmed.Contains("=")) {
        continue
    }
    $parts = $trimmed -split "=", 2
    $key = $parts[0].Trim()
    $value = $parts[1].Trim().Trim('"').Trim("'")
    [Environment]::SetEnvironmentVariable($key, $value, "Process")
    $count++
}

Write-Host "Loaded $count value(s) from '$Path' into this session's environment."
Write-Host "Note: CLAUDE_HISTORY_SOURCE/OPENOBSERVE_URL etc. (used by docker-compose, not this script) get loaded too if present - harmless, just unused here."
