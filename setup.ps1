# MentionMate — Setup wizard for Windows (PowerShell 5.1+)
# Docs: https://github.com/hoangp47/mentionmate
#
# Usage:
#   .\setup.ps1
#   .\setup.ps1 -Verbose
#
# If PowerShell blocks the script:
#   powershell -ExecutionPolicy Bypass -File setup.ps1

[CmdletBinding()]
param(
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# ----- Constants -----
$IMAGE       = 'ghcr.io/hoangp47/mentionmate:latest'
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
MentionMate Setup Wizard (Windows)

Usage:
  .\setup.ps1                   Run the interactive wizard
  .\setup.ps1 -Verbose          Run verbose
  .\setup.ps1 -Help             Show this help

If blocked by ExecutionPolicy:
  powershell -ExecutionPolicy Bypass -File setup.ps1

Documentation: https://github.com/hoangp47/mentionmate/blob/master/docs/SETUP.md
"@
    exit 0
}

# ----- Step 0: Check ExecutionPolicy (FR-DIST-02 EX5) -----
function Test-ExecutionPolicy {
    Write-Step '0/12 Checking PowerShell ExecutionPolicy'
    $policy = Get-ExecutionPolicy -Scope Process
    if ($policy -eq 'Restricted') {
        Abort 'ERR-DIST-005: PowerShell is blocking unsigned scripts.' @"
Run the following and retry:
  Set-ExecutionPolicy -Scope Process Bypass

Or relaunch with:
  powershell -ExecutionPolicy Bypass -File setup.ps1

See SETUP.md §Windows.
"@
    }
    Write-Ok "ExecutionPolicy = $policy (OK)."
}

# ----- Step 1: Check Docker -----
function Test-Docker {
    Write-Step '1/12 Checking Docker'
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Abort 'ERR-DIST-001: docker CLI not found.' @"
Install Docker Desktop or Docker Engine:
  Windows: https://docs.docker.com/desktop/install/windows-install/
  Or Podman Desktop: https://podman.io/docs/installation
"@
    }
    try {
        docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'docker info exit non-zero' }
    } catch {
        Abort 'ERR-DIST-001: Docker daemon is not running.' @"
Start Docker Desktop from the Start menu and retry.
"@
    }
    Write-Ok 'Docker daemon is running.'
}

# ----- Step 2: Check compose v2 -----
$Script:ComposeCmd = @('docker', 'compose')
function Test-Compose {
    Write-Step '2/12 Checking docker compose'
    try {
        docker compose version 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok 'docker compose v2 available.'
            $Script:ComposeCmd = @('docker', 'compose')
            return
        }
    } catch { }

    if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
        Write-Warn 'Only docker-compose v1 (legacy) is available. The wizard will fall back, but upgrading is recommended.'
        $Script:ComposeCmd = @('docker-compose')
    } else {
        Abort 'Neither docker compose nor docker-compose found.' 'Reinstall Docker.'
    }
}

# ----- Step 3: Detect existing install -----
function Test-Existing {
    Write-Step '3/12 Checking for existing configuration'
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

# ----- Step 4-7: Prompt 4 env vars -----
function Read-Validated {
    param(
        [string]$Prompt,
        [string]$Regex,
        [string]$ErrMsg,
        [switch]$Secret
    )
    while ($true) {
        Write-Host "`n$Prompt"
        if ($Secret) {
            $secure = Read-Host -AsSecureString
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try {
                $value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            } finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        } else {
            $value = Read-Host
        }

        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Err 'Value cannot be empty.'
            continue
        }
        if ($value -notmatch $Regex) {
            Write-Err $ErrMsg
            continue
        }
        return $value
    }
}

function Get-UserInputs {
    Write-Step '4/12 Telegram credentials'

    $Script:TG_API_ID = Read-Validated `
        -Prompt '🔑 Enter TG_API_ID (integer, from https://my.telegram.org/apps):' `
        -Regex  '^[0-9]+$' `
        -ErrMsg 'TG_API_ID must be a positive integer.'

    $Script:TG_API_HASH = Read-Validated `
        -Prompt '🔑 Enter TG_API_HASH (32 hex characters, input hidden):' `
        -Regex  '^[a-f0-9]{32}$' `
        -ErrMsg 'TG_API_HASH must be exactly 32 hex characters (a-f, 0-9).' `
        -Secret

    $Script:TG_MY_USERNAME = Read-Validated `
        -Prompt '👤 Enter your Telegram username (without @, e.g. hoangp47):' `
        -Regex  '^[A-Za-z][A-Za-z0-9_]{4,31}$' `
        -ErrMsg 'Username must be 5-32 chars, start with a letter, contain only letters/digits/underscore.'

    $Script:TG_BOT_TOKEN = Read-Validated `
        -Prompt '🤖 Enter TG_BOT_TOKEN from @BotFather (input hidden, format <id>:<secret>):' `
        -Regex  '^[0-9]+:[A-Za-z0-9_-]{30,40}$' `
        -ErrMsg 'Invalid bot token format. Expected: 1234567890:AAAA....' `
        -Secret
}

# ----- Step 8: Pull image -----
function Invoke-PullImage {
    Write-Step '5/12 Pulling Docker image'
    Write-Info "Pulling $IMAGE ... (first pull may take 1-2 minutes)"
    docker pull $IMAGE
    if ($LASTEXITCODE -ne 0) {
        Abort 'ERR-DIST-002: Image pull failed.' @"
Possible causes: (1) network can't reach ghcr.io, (2) firewall is blocking it.
Test: Invoke-WebRequest -Uri https://ghcr.io -Method Head
See TROUBLESHOOTING.md §Network.
"@
    }
    Write-Ok 'Image pulled successfully.'
}

# ----- Step 9: Discover chat_id + send test -----
function Get-ChatId {
    Write-Step '6/12 Discovering chat_id (sub-flow UC-DIST-05)'

    # Fetch bot username from getMe
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
        } catch {
            Write-Warn "API call failed: $($_.Exception.Message)"
            $updates = $null
        }

        $chatId = $null
        if ($updates -and $updates.ok) {
            foreach ($u in $updates.result) {
                $msg = if ($u.message) { $u.message } elseif ($u.edited_message) { $u.edited_message } else { $null }
                if (-not $msg) { continue }
                $text = "$($msg.text)".Trim().ToLower()
                if ($text.StartsWith('/start')) {
                    $chatId = $msg.chat.id
                    break
                }
            }
        }

        if ($chatId) {
            Write-Ok "Found chat_id: $chatId"

            # Round-trip verify (BR-DIST-05-01)
            Write-Info 'Sending test message...'
            try {
                $sendResult = Invoke-RestMethod -Method Post `
                    -Uri "https://api.telegram.org/bot$($Script:TG_BOT_TOKEN)/sendMessage" `
                    -Body @{
                        chat_id = $chatId
                        text    = '🔧 MentionMate setup test — if you can read this, your configuration is correct.'
                    } -TimeoutSec 10
            } catch {
                Write-Warn "Send failed: $($_.Exception.Message)"
                $sendResult = $null
            }

            if ($sendResult -and $sendResult.ok) {
                $confirm = Read-Host "`nDid you receive the test message on Telegram? (y/N)"
                if ($confirm -match '^(y|yes)$') {
                    $Script:TG_ALERT_CHAT_ID = $chatId
                    return
                }
                Write-Warn "Test message not received — chat_id may be wrong. Retrying."
            }
        } else {
            Write-Warn 'No /start message in recent updates. Did you /start the CORRECT bot you just created?'
        }

        if ($attempt -lt $maxAttempts) {
            $retry = Read-Host "`nRetry? (Y/n)"
            if ($retry -match '^(n|no)$') { break }
            Write-Host 'Send /start to the bot again, then press Enter...'
            Read-Host | Out-Null
        }
    }

    Abort "Could not detect chat_id after $maxAttempts attempts." 'See TROUBLESHOOTING.md §chat_id.'
}

# ----- Step 10: Write .env + restrict ACL -----
function Write-EnvFile {
    Write-Step '7/12 Writing configuration to .env'
    $tmp = "$EnvFile.tmp"
    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    @"
# Generated by MentionMate setup wizard at $now
TG_API_ID=$($Script:TG_API_ID)
TG_API_HASH=$($Script:TG_API_HASH)
TG_MY_USERNAME=$($Script:TG_MY_USERNAME)
TG_BOT_TOKEN=$($Script:TG_BOT_TOKEN)
TG_ALERT_CHAT_ID=$($Script:TG_ALERT_CHAT_ID)
"@ | Set-Content -Path $tmp -Encoding UTF8 -NoNewline

    Move-Item -Force $tmp $EnvFile

    # Restrict ACL — owner read/write only (NFR-SEC-03)
    try {
        icacls $EnvFile /inheritance:r 2>&1 | Out-Null
        icacls $EnvFile /grant:r "$($env:USERNAME):(R,W)" 2>&1 | Out-Null
        Write-Ok ".env written with owner-only ACL."
    } catch {
        Write-Warn "Could not set ACL ($($_.Exception.Message)). File may be readable by other users."
    }
}

# ----- Step 11: Telethon auth -----
function Invoke-TelethonAuth {
    Write-Step '8/12 Telethon userbot login'
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

    if (Test-Path $SessionFile) {
        Write-Info 'Session file already exists — skipping interactive auth.'
        return
    }

    Write-Info 'An interactive container will run — enter your phone number (e.g. +84912345678) when prompted.'
    Write-Info "If your account has 2FA, you'll be asked for the password after the OTP."

    $cwd = (Get-Location).Path
    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        docker run --rm -it `
            -v "${cwd}\data:/app/data" `
            --env-file $EnvFile `
            $IMAGE `
            python /app/scripts/auth.py

        if ($LASTEXITCODE -eq 0 -and (Test-Path $SessionFile)) {
            Write-Ok "Telethon session created: $SessionFile"
            return
        }
        Write-Warn "Auth failed. Retry? ($attempt/$maxAttempts)"
        if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 2 }
    }

    Abort 'ERR-DIST-003: Telethon auth failed.' 'See TROUBLESHOOTING.md §Auth.'
}

# ----- Step 12: Start container -----
function Start-Container {
    Write-Step '9/12 Starting MentionMate container'
    & $Script:ComposeCmd[0] $Script:ComposeCmd[1..($Script:ComposeCmd.Length-1)] up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'ERR-DIST-004: Container did not start.'
        & $Script:ComposeCmd[0] $Script:ComposeCmd[1..($Script:ComposeCmd.Length-1)] logs --tail 50
        Abort 'See TROUBLESHOOTING.md §Container.'
    }
    Start-Sleep -Seconds 3
    Write-Ok "Container 'mentionmate' is running."
}

# ----- Step 13: Summary -----
function Show-Summary {
    Write-Step '10/12 Done! 🎉'
    $composeStr = $Script:ComposeCmd -join ' '
    Write-Host "`nMentionMate has been installed successfully." -ForegroundColor Green

    Write-Host @"

📝 Useful commands:
  Tail logs:      $composeStr logs -f bot
  Stop:           $composeStr down
  Restart:        $composeStr restart
  Update:         .\update.ps1

📖 Documentation:  https://github.com/hoangp47/mentionmate
🐛 Report issues:  https://github.com/hoangp47/mentionmate/issues

You will receive an alert on Telegram whenever someone @$($Script:TG_MY_USERNAME) mentions you in any group the userbot is a member of.
"@
}

# ----- Main -----
Write-Host @"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   MentionMate Setup Wizard (Windows)
   github.com/hoangp47/mentionmate
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
Show-Summary
