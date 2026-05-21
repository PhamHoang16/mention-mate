# MentionMate — Unified wizard for Windows (PowerShell 5.1+)
# Docs: https://github.com/PhamHoang16/mention-mate
#
# Usage:
#   .\mention-mate.ps1                       Auto-detect: setup if not configured, update otherwise
#   .\mention-mate.ps1 -Action setup         Run the interactive setup wizard
#   .\mention-mate.ps1 -Action update        Pull the latest image and recreate the container
#   .\mention-mate.ps1 -Help                 Show this help
#
# Or positionally:
#   .\mention-mate.ps1 setup
#   .\mention-mate.ps1 update
#
# If PowerShell blocks the script:
#   powershell -ExecutionPolicy Bypass -File mention-mate.ps1

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('', 'setup', 'update')]
    [string]$Action = '',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# ----- Locate project root -----
function Set-ProjectRoot {
    $scriptDir = Split-Path -Parent $PSCommandPath
    if (Test-Path 'docker-compose.yml') { return }
    elseif (Test-Path (Join-Path $scriptDir 'docker-compose.yml')) { Set-Location $scriptDir }
    elseif (Test-Path (Join-Path $scriptDir '..\docker-compose.yml')) { Set-Location (Join-Path $scriptDir '..') }
    else {
        Write-Host "❌ Could not locate docker-compose.yml. Run from the MentionMate directory." -ForegroundColor Red
        exit 1
    }
}
Set-ProjectRoot

# ----- Constants -----
$IMAGE       = 'ghcr.io/phamhoang16/mention-mate:latest'
$IMAGE_REPO  = 'ghcr.io/phamhoang16/mention-mate'
$EnvFile     = '.env'
$DataDir     = '.\data'
$SessionFile = Join-Path $DataDir 'mentions_session.session'

# ----- Helpers -----
function Write-Step  { param($Msg) Write-Host "`n━━━ $Msg ━━━" -ForegroundColor Cyan }
function Write-Ok    { param($Msg) Write-Host "✅ $Msg" -ForegroundColor Green }
function Write-Info  { param($Msg) Write-Host "ℹ  $Msg" -ForegroundColor Blue }
function Write-Warn  { param($Msg) Write-Host "⚠️  $Msg" -ForegroundColor Yellow }
function Write-Err   { param($Msg) Write-Host "❌ $Msg" -ForegroundColor Red }

function Abort {
    param([string]$Msg, [string]$Detail = '')
    Write-Err $Msg
    if ($Detail) { Write-Host "`n$Detail" }
    exit 1
}

if ($Help) {
    Write-Host @"
MentionMate Wizard (Windows)

Usage:
  .\mention-mate.ps1                  Auto-detect: setup if not configured, update otherwise
  .\mention-mate.ps1 setup            Run the interactive setup wizard
  .\mention-mate.ps1 update           Pull the latest image and recreate the container
  .\mention-mate.ps1 -Help            Show this help

If blocked by ExecutionPolicy:
  powershell -ExecutionPolicy Bypass -File mention-mate.ps1

Documentation: https://github.com/PhamHoang16/mention-mate
"@
    exit 0
}

# ----- ExecutionPolicy check -----
function Test-ExecutionPolicy {
    $policy = Get-ExecutionPolicy -Scope Process
    if ($policy -eq 'Restricted') {
        Abort 'ERR-DIST-005: PowerShell is blocking unsigned scripts.' @"
Run the following and retry:
  Set-ExecutionPolicy -Scope Process Bypass

Or relaunch with:
  powershell -ExecutionPolicy Bypass -File mention-mate.ps1
"@
    }
}

# ----- Docker / compose -----
$Script:ComposeCmd = @('docker', 'compose')

function Test-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Abort 'ERR-DIST-001: docker CLI not found.' 'Install Docker Desktop or Podman Desktop.'
    }
    try {
        docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'docker info exit non-zero' }
    } catch {
        Abort 'ERR-DIST-001: Docker daemon is not running.' 'Start Docker Desktop and retry.'
    }
}

function Test-Compose {
    try {
        docker compose version 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $Script:ComposeCmd = @('docker', 'compose'); return }
    } catch { }

    if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
        Write-Warn 'Only docker-compose v1 (legacy) available. Upgrade Docker for v2.'
        $Script:ComposeCmd = @('docker-compose')
    } else {
        Abort 'Neither docker compose nor docker-compose found.' 'Reinstall Docker.'
    }
}

function Invoke-Compose {
    & $Script:ComposeCmd[0] $Script:ComposeCmd[1..($Script:ComposeCmd.Length - 1)] @args
}

# ================================================================
# SETUP
# ================================================================

function Test-Existing {
    Write-Step 'Checking for existing configuration'
    $existing = $false
    if (Test-Path $EnvFile)     { Write-Warn '.env already exists.';        $existing = $true }
    if (Test-Path $SessionFile) { Write-Warn "Session file already exists: $SessionFile"; $existing = $true }

    if ($existing) {
        $answer = Read-Host "`nOverwrite existing config? (y/N) [N]"
        if ($answer -notmatch '^(y|yes)$') { Abort 'Cancelled. Existing configuration kept.' }
        Write-Warn 'Will overwrite .env (session file is preserved).'
    } else {
        Write-Ok 'No prior configuration found — proceeding.'
    }
}

function Read-Validated {
    param([string]$Prompt, [string]$Regex, [string]$ErrMsg, [switch]$Secret)
    while ($true) {
        Write-Host "`n$Prompt"
        if ($Secret) {
            $secure = Read-Host -AsSecureString
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try { $value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
            finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        } else {
            $value = Read-Host
        }

        if ([string]::IsNullOrWhiteSpace($value)) { Write-Err 'Value cannot be empty.'; continue }
        if ($value -notmatch $Regex)              { Write-Err $ErrMsg; continue }
        return $value
    }
}

function Get-UserInputs {
    Write-Step 'Telegram credentials'
    $Script:TG_API_ID = Read-Validated `
        -Prompt '🔑 Enter TG_API_ID (integer, from https://my.telegram.org/apps):' `
        -Regex  '^[0-9]+$' -ErrMsg 'TG_API_ID must be a positive integer.'
    $Script:TG_API_HASH = Read-Validated `
        -Prompt '🔑 Enter TG_API_HASH (32 hex characters, input hidden):' `
        -Regex  '^[a-f0-9]{32}$' -ErrMsg 'TG_API_HASH must be exactly 32 hex characters.' -Secret
    $Script:TG_MY_USERNAME = Read-Validated `
        -Prompt '👤 Enter your Telegram username (without @, e.g. hoangp47):' `
        -Regex  '^[A-Za-z][A-Za-z0-9_]{4,31}$' `
        -ErrMsg 'Username must be 5-32 chars, start with a letter, contain only letters/digits/underscore.'
    $Script:TG_BOT_TOKEN = Read-Validated `
        -Prompt '🤖 Enter TG_BOT_TOKEN from @BotFather (input hidden, format <id>:<secret>):' `
        -Regex  '^[0-9]+:[A-Za-z0-9_-]{30,40}$' `
        -ErrMsg 'Invalid bot token format. Expected: 1234567890:AAAA....' -Secret
}

function Invoke-PullImage {
    Write-Step 'Pulling Docker image'
    Write-Info "Pulling $IMAGE ... (first pull may take 1-2 minutes)"
    docker pull $IMAGE
    if ($LASTEXITCODE -ne 0) {
        Abort 'ERR-DIST-002: Image pull failed.' @"
Test: Invoke-WebRequest -Uri https://ghcr.io -Method Head
See README.md → Troubleshooting.
"@
    }
    Write-Ok 'Image pulled successfully.'
}

function Get-ChatId {
    Write-Step 'Discovering chat_id'
    try {
        $me = Invoke-RestMethod -Uri "https://api.telegram.org/bot$($Script:TG_BOT_TOKEN)/getMe" -TimeoutSec 10
        $botUsername = if ($me.ok) { $me.result.username } else { '' }
    } catch { $botUsername = '' }

    if ($botUsername) {
        Write-Host "`n1. Open Telegram, find @$botUsername (or https://t.me/$botUsername)" -ForegroundColor White
        Write-Host '2. Tap START or send /start to the bot'
        Write-Host '3. Come back here and press Enter'
    } else {
        Write-Warn 'Could not fetch bot username. Try /start with the bot you just created.'
        Write-Host "`nSend /start to the bot in Telegram, then press Enter..."
    }
    Read-Host | Out-Null

    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Write-Info "Calling getUpdates ... (attempt $attempt/$maxAttempts)"
        try {
            $updates = Invoke-RestMethod -Uri "https://api.telegram.org/bot$($Script:TG_BOT_TOKEN)/getUpdates" -TimeoutSec 10
        } catch { Write-Warn "API call failed: $($_.Exception.Message)"; $updates = $null }

        $chatId = $null
        if ($updates -and $updates.ok) {
            foreach ($u in $updates.result) {
                $msg = if ($u.message) { $u.message } elseif ($u.edited_message) { $u.edited_message } else { $null }
                if (-not $msg) { continue }
                $text = "$($msg.text)".Trim().ToLower()
                if ($text.StartsWith('/start')) { $chatId = $msg.chat.id; break }
            }
        }

        if ($chatId) {
            Write-Ok "Found chat_id: $chatId"
            Write-Info 'Sending test message...'
            try {
                $sendResult = Invoke-RestMethod -Method Post `
                    -Uri "https://api.telegram.org/bot$($Script:TG_BOT_TOKEN)/sendMessage" `
                    -Body @{
                        chat_id = $chatId
                        text    = '🔧 MentionMate setup test — if you can read this, your configuration is correct.'
                    } -TimeoutSec 10
            } catch { Write-Warn "Send failed: $($_.Exception.Message)"; $sendResult = $null }

            if ($sendResult -and $sendResult.ok) {
                $confirm = Read-Host "`nDid you receive the test message? (y/N)"
                if ($confirm -match '^(y|yes)$') { $Script:TG_ALERT_CHAT_ID = $chatId; return }
                Write-Warn 'Test not received — chat_id may be wrong. Retrying.'
            }
        } else {
            Write-Warn 'No /start message in recent updates. Did you /start the CORRECT bot?'
        }

        if ($attempt -lt $maxAttempts) {
            $retry = Read-Host "`nRetry? (Y/n)"
            if ($retry -match '^(n|no)$') { break }
            Write-Host 'Send /start to the bot again, then press Enter...'
            Read-Host | Out-Null
        }
    }

    Abort "Could not detect chat_id after $maxAttempts attempts." 'See README.md → Troubleshooting → chat_id.'
}

function Write-EnvFile {
    Write-Step 'Writing configuration to .env'
    $tmp = "$EnvFile.tmp"
    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    @"
# Generated by MentionMate wizard at $now
TG_API_ID=$($Script:TG_API_ID)
TG_API_HASH=$($Script:TG_API_HASH)
TG_MY_USERNAME=$($Script:TG_MY_USERNAME)
TG_BOT_TOKEN=$($Script:TG_BOT_TOKEN)
TG_ALERT_CHAT_ID=$($Script:TG_ALERT_CHAT_ID)
"@ | Set-Content -Path $tmp -Encoding UTF8 -NoNewline

    Move-Item -Force $tmp $EnvFile

    try {
        icacls $EnvFile /inheritance:r 2>&1 | Out-Null
        icacls $EnvFile /grant:r "$($env:USERNAME):(R,W)" 2>&1 | Out-Null
        Write-Ok '.env written with owner-only ACL.'
    } catch {
        Write-Warn "Could not set ACL ($($_.Exception.Message)). File may be readable by other users."
    }
}

function Invoke-TelethonAuth {
    Write-Step 'Telethon userbot login'
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    try { & wsl chmod 777 "$DataDir" 2>$null } catch { }

    if (Test-Path $SessionFile) {
        Write-Info 'Session file already exists — skipping interactive auth.'
        return
    }

    Write-Info 'An interactive container will run — enter your phone (e.g. +84912345678) at the prompt.'
    Write-Info "If 2FA is enabled, you'll be asked for the password after the OTP."

    $cwd = (Get-Location).Path
    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        docker run --rm -it `
            -v "${cwd}\data:/app/data" `
            --env-file $EnvFile `
            $IMAGE `
            python -m mention_mate.auth

        if ($LASTEXITCODE -eq 0 -and (Test-Path $SessionFile)) {
            Write-Ok "Telethon session created: $SessionFile"
            return
        }
        Write-Warn "Auth failed. Retry? ($attempt/$maxAttempts)"
        if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 2 }
    }

    Abort 'ERR-DIST-003: Telethon auth failed.' 'See README.md → Troubleshooting → Telethon auth.'
}

function Start-Container {
    Write-Step 'Starting MentionMate container'
    Invoke-Compose up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'ERR-DIST-004: Container did not start.'
        Invoke-Compose logs --tail 50
        Abort 'See README.md → Troubleshooting → Container.'
    }
    Start-Sleep -Seconds 3
    Write-Ok "Container 'mention-mate' is running."
}

function Show-SetupSummary {
    Write-Step 'Done! 🎉'
    $composeStr = $Script:ComposeCmd -join ' '
    Write-Host "`nMentionMate has been installed successfully." -ForegroundColor Green
    Write-Host @"

📝 Useful commands:
  Tail logs:      $composeStr logs -f bot
  Stop:           $composeStr down
  Restart:        $composeStr restart
  Update:         .\mention-mate.ps1 update

📖 Documentation:  https://github.com/PhamHoang16/mention-mate
🐛 Report issues:  https://github.com/PhamHoang16/mention-mate/issues

You will receive an alert on Telegram whenever someone @$($Script:TG_MY_USERNAME) mentions you in any group the userbot is a member of.
"@
}

function Invoke-Setup {
    Write-Host @"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   MentionMate Setup Wizard (Windows)
   github.com/PhamHoang16/mention-mate
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"@
    Test-ExecutionPolicy
    Test-Docker
    Test-Compose
    Test-Existing
    Get-UserInputs
    Invoke-PullImage
    Get-ChatId
    Write-EnvFile
    Invoke-TelethonAuth
    Start-Container
    Show-SetupSummary
}

# ================================================================
# UPDATE
# ================================================================

function Invoke-Update {
    Write-Host "`n━━━ MentionMate Update ━━━`n" -ForegroundColor Cyan
    Test-ExecutionPolicy
    Test-Docker
    Test-Compose

    try {
        $currentImage = docker inspect mention-mate --format '{{.Config.Image}}' 2>$null
        if ($currentImage) { Write-Host "📍 Current version: $currentImage" -ForegroundColor White }
        else { Write-Warn 'No running container detected (may never have been started).' }
    } catch { $currentImage = $null }

    if (Test-Path $SessionFile) {
        $age = (Get-Date) - (Get-Item $SessionFile).LastWriteTime
        if ($age.Days -gt 7) {
            Write-Warn 'Session file is more than 7 days old — backup recommended.'
            $ans = Read-Host 'Back up session now? (Y/n) [Y]'
            if ($ans -notmatch '^(n|no)$') {
                $backup = "$SessionFile.backup.$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
                Copy-Item $SessionFile $backup
                Write-Ok "Backup: $backup"
            }
        }
    }

    Write-Host "`n⬇️  Pulling new image..."
    Invoke-Compose pull
    if ($LASTEXITCODE -ne 0) {
        Abort 'ERR-DIST-002: Pull failed. Check network access to ghcr.io.'
    }

    Write-Host "`n🔄 Recreating container with new image..."
    Invoke-Compose up -d
    if ($LASTEXITCODE -ne 0) {
        Abort 'ERR-DIST-006: Container failed to restart.' 'See README.md → Troubleshooting → Update.'
    }
    Start-Sleep -Seconds 3

    try {
        $newImage = docker inspect mention-mate --format '{{.Config.Image}}' 2>$null
        Write-Ok "Update complete. Image: $newImage"
    } catch { Write-Ok 'Update complete.' }

    $composeStr = $Script:ComposeCmd -join ' '
    Write-Host "`n📝 Tail logs: $composeStr logs -f bot" -ForegroundColor White
}

# ================================================================
# Dispatch
# ================================================================

if ([string]::IsNullOrEmpty($Action)) {
    if ((Test-Path $EnvFile) -and (Test-Path $SessionFile)) {
        Write-Info "Existing installation detected — running 'update'. (Use '.\mention-mate.ps1 setup' to reconfigure.)"
        $Action = 'update'
    } else {
        $Action = 'setup'
    }
}

switch ($Action) {
    'setup'  { Invoke-Setup }
    'update' { Invoke-Update }
    default  { Abort "Unknown action: $Action" }
}
