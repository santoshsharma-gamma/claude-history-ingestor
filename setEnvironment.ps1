<#
.SYNOPSIS
    One-time guided setup for a new machine. Asks for the 7 values this
    whole project needs, exactly once each, then writes them to BOTH
    places that need them - the Docker .env file AND your PowerShell
    $PROFILE - so nothing needs typing twice.

.DESCRIPTION
    Two values (OpenObserve user/password) are needed by both Docker
    Compose (via .env) and claude-report.ps1 (via $env: variables) -
    those two systems never share config automatically, which is the
    real source of "why do I have to set this up twice" friction. This
    script exists specifically to remove that friction: answer once,
    both places get updated.

    Safe to re-run any time (e.g. rotating a token) - it replaces its
    own clearly-marked block in $PROFILE rather than duplicating lines
    on every run, and won't touch anything else you've added to your
    profile.

.PARAMETER EnvPath
    Where to write the .env file for docker-compose. Defaults to
    docker\.env, relative to wherever THIS script lives (the project
    root) - deliberately not just ".env" in the current directory, since
    depending on which folder you happen to be standing in when you run
    a script is exactly the kind of mistake that caused real, confusing
    Docker bind-mount failures earlier in this project. Run this script
    from the project root (the folder this file itself is in), or pass
    -EnvPath explicitly if your layout differs.

.EXAMPLE
    cd path\to\claude-history-ingestor    # the project root - docker-compose.yml is in .\docker\ underneath it
    .\setEnvironment.ps1
#>

param(
    [string]$EnvPath = "docker\.env"
)

function Test-TcpReachable {
    # Quick, short-timeout "is anything listening here" check - used to
    # auto-detect the OpenObserve URL below without ever hanging the setup
    # flow waiting on a dead address.
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 800)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $connectTask = $client.ConnectAsync($HostName, $Port)
        $ok = $connectTask.Wait($TimeoutMs) -and $client.Connected
        $client.Close()
        return $ok
    } catch {
        return $false
    }
}

function Find-OpenObserveUrl {
    # Best-effort auto-detection, so nobody has to already know their own
    # container runtime's networking quirks before they can even run this
    # setup. Tries, in order:
    #   1. localhost:$Port - correct for Docker Desktop and most Podman
    #      setups (this is what the whole project assumed until now).
    #   2. The running Podman machine's own IP, when Podman is present and
    #      its default machine has UserModeNetworking disabled - confirmed
    #      necessary on a real machine: `podman machine list --format json`
    #      showed VMType "wsl" and UserModeNetworking false, and
    #      OpenObserve's published port was only reachable at the WSL
    #      distro's own eth0 address (`wsl -d <machine> -- ip -4 addr show
    #      eth0`), e.g. 172.18.34.45, never localhost. When
    #      UserModeNetworking IS true (Podman's gvproxy mode), localhost
    #      already works and step 1 above would have caught it, so this
    #      branch is specifically for the WSL-direct-networking case.
    # Returns $null (caller falls back to asking, with a manual pointer to
    # the same `wsl -d ... ip -4 addr show eth0` command above) if neither
    # works - e.g. OpenObserve isn't running yet, or a container runtime
    # this hasn't seen before.
    param([int]$Port = 5080)

    if (Test-TcpReachable -HostName "localhost" -Port $Port) {
        return "http://localhost:$Port"
    }

    if ((Get-Command podman -ErrorAction SilentlyContinue) -and (Get-Command wsl -ErrorAction SilentlyContinue)) {
        try {
            $machines = podman machine list --format json 2>$null | ConvertFrom-Json
            $running = $machines | Where-Object { $_.Running } | Select-Object -First 1
            if ($running -and -not $running.UserModeNetworking) {
                $ipLine = (wsl -d $running.Name -- ip -4 addr show eth0 2>$null) -join "`n"
                if ($ipLine -match 'inet (\d+\.\d+\.\d+\.\d+)') {
                    $ip = $matches[1]
                    if (Test-TcpReachable -HostName $ip -Port $Port) {
                        return "http://$ip`:$Port"
                    }
                }
            }
        } catch {
            # Best-effort only - any failure here just falls through to $null.
        }
    }

    return $null
}

Write-Host "=== One-time setup: 7 values, entered once, used everywhere ===`n"

# --- 1. Claude history source (Docker only) ---
$defaultHistoryPath = Join-Path $HOME ".claude\projects"
Write-Host "1. Claude Code history folder (Docker reads your local session files from here)"
$historySource = Read-Host "   Path [$defaultHistoryPath]"
if (-not $historySource) { $historySource = $defaultHistoryPath }
# docker-compose bind mounts need forward slashes even on Windows.
$historySource = $historySource -replace '\\', '/'

# --- 2. OpenObserve URL (claude-report.ps1 only - NOT written to .env) ---
# Docker Compose never needs this: containers on the compose network reach
# OpenObserve at the fixed internal address http://openobserve:5080 (see
# docker-compose.yml), regardless of what your host machine sees. This
# value is purely "what address does OpenObserve's published port answer
# on FROM THIS MACHINE" - which varies per machine/container runtime, not
# per checkout of this repo, so it belongs in $PROFILE only, same as the
# JIRA values below, never hardcoded into claude-report.ps1 itself.
Write-Host "`n2. OpenObserve URL - used by claude-report.ps1 (NOT docker-compose, which has its own internal address)"
Write-Host "   Make sure OpenObserve is already running (docker/podman compose up -d) before this step, so detection has something to find."
$detectedUrl = Find-OpenObserveUrl
if ($detectedUrl) {
    Write-Host "   Auto-detected: $detectedUrl"
    $ooUrl = Read-Host "   URL [$detectedUrl]"
    if (-not $ooUrl) { $ooUrl = $detectedUrl }
} else {
    # Auto-detection genuinely couldn't reach anything on port 5080 - not
    # necessarily wrong, e.g. OpenObserve just isn't running yet - so this
    # falls back to asking, with the same manual steps Find-OpenObserveUrl
    # tries automatically, spelled out in case they need to be run by hand
    # (wrong Podman machine name, WSL not on PATH, etc).
    Write-Host "   Couldn't auto-detect a reachable OpenObserve - is it running? (docker/podman compose up -d)"
    Write-Host "   If it IS running and this still can't find it: for a Podman machine using WSL directly (not"
    Write-Host "   gvproxy), find its IP with 'wsl -d podman-machine-default -- ip -4 addr show eth0' and use"
    Write-Host "   http://<that IP>:5080 below."
    $ooUrl = Read-Host "   URL [http://localhost:5080]"
    if (-not $ooUrl) { $ooUrl = "http://localhost:5080" }
}

# --- 3 & 4. OpenObserve credentials (shared by Docker AND claude-report.ps1) ---
Write-Host "`n3. OpenObserve login - used by BOTH docker-compose AND claude-report.ps1"
$ooUser = Read-Host "   Username/email [user@gamma.co.uk]"
if (-not $ooUser) { $ooUser = "user@gamma.co.uk" }
$ooPasswordSecure = Read-Host "   Password" -AsSecureString
$ooPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ooPasswordSecure))

# --- 5, 6, 7. JIRA credentials (claude-report.ps1 only) ---
Write-Host "`n4. JIRA - used by claude-report.ps1"
$jiraBase = Read-Host "   Base URL [https://gammatelecom.atlassian.net]"
if (-not $jiraBase) { $jiraBase = "https://gammatelecom.atlassian.net" }
$jiraUser = Read-Host "   Your JIRA email [user@gamma.co.uk]"
if (-not $jiraUser) { $jiraUser = "user@gamma.co.uk" }
$jiraTokenSecure = Read-Host "   API token (create at https://id.atlassian.com/manage-profile/security/api-tokens)" -AsSecureString
$jiraToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($jiraTokenSecure))

# --- Write .env for docker-compose ---
$envFolder = Split-Path $EnvPath -Parent
if ($envFolder -and -not (Test-Path $envFolder)) {
    Write-Host "`nCan't write to '$EnvPath' - the folder '$envFolder' doesn't exist here."
    Write-Host "Run this script from the project root (the folder containing this script AND the docker\ subfolder), or pass -EnvPath explicitly."
    return
}
$envContent = @"
CLAUDE_HISTORY_SOURCE=$historySource
OPENOBSERVE_USER=$ooUser
OPENOBSERVE_PASSWORD=$ooPassword
"@
Set-Content -Path $EnvPath -Value $envContent -NoNewline
Write-Host "`nWrote $EnvPath (for docker compose up)"

# --- Update $PROFILE with a clearly-marked, replaceable block ---
$beginMarker = "# ===== BEGIN claude-history-ingestor managed env vars (auto-generated by setEnvironment.ps1) ====="
$endMarker   = "# ===== END claude-history-ingestor managed env vars ====="
$block = @"
$beginMarker
`$env:OPENOBSERVE_URL = "$ooUrl"
`$env:OPENOBSERVE_USER = "$ooUser"
`$env:OPENOBSERVE_PASSWORD = "$ooPassword"
`$env:JIRA_BASE = "$jiraBase"
`$env:JIRA_USER = "$jiraUser"
`$env:JIRA_TOKEN = "$jiraToken"
$endMarker
"@

if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}
$existing = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($existing -and $existing.Contains($beginMarker)) {
    # Replace the existing managed block in place - re-running this
    # script (e.g. after rotating a token) updates it cleanly instead of
    # duplicating five more lines below the old ones.
    $pattern = [regex]::Escape($beginMarker) + "(.|\n)*?" + [regex]::Escape($endMarker)
    $updated = [regex]::Replace($existing, $pattern, $block)
    Set-Content -Path $PROFILE -Value $updated -NoNewline
} else {
    Add-Content -Path $PROFILE -Value "`n$block"
}
Write-Host "Updated $PROFILE (for claude-report.ps1 - and OpenObserve creds are shared with docker-compose too)"

Write-Host "`n=== Done ==="
Write-Host "Docker: cd to this folder, run 'docker compose up -d'"
Write-Host "PowerShell: close and reopen your terminal (profile changes need a fresh session), then just run:"
Write-Host "  .\claude-report.ps1 -Ticket `"YOUR-TICKET`""