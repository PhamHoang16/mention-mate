# MentionMate — Setup wizard for Windows (PowerShell 5.1+)
# Docs: https://github.com/hoangp47/mentionmate
#
# Usage:
#   .\setup.ps1
#   .\setup.ps1 -Verbose
#
# Nếu PowerShell chặn:
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

Cách dùng:
  .\setup.ps1                   Chạy wizard interactive
  .\setup.ps1 -Verbose          Chạy verbose
  .\setup.ps1 -Help             Hiển thị help

Nếu bị chặn bởi ExecutionPolicy:
  powershell -ExecutionPolicy Bypass -File setup.ps1

Documentation: https://github.com/hoangp47/mentionmate/blob/master/docs/SETUP.md
"@
    exit 0
}

# ----- Step 0: Check ExecutionPolicy (FR-DIST-02 EX5) -----
function Test-ExecutionPolicy {
    Write-Step '0/12 Kiểm tra PowerShell ExecutionPolicy'
    $policy = Get-ExecutionPolicy -Scope Process
    if ($policy -eq 'Restricted') {
        Abort 'ERR-DIST-005: PowerShell đang chặn script chưa sign.' @"
Chạy lệnh sau rồi thử lại:
  Set-ExecutionPolicy -Scope Process Bypass

Hoặc khởi động lại:
  powershell -ExecutionPolicy Bypass -File setup.ps1

Xem SETUP.md §Windows.
"@
    }
    Write-Ok "ExecutionPolicy = $policy (OK)."
}

# ----- Step 1: Check Docker -----
function Test-Docker {
    Write-Step '1/12 Kiểm tra Docker'
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Abort 'ERR-DIST-001: Không tìm thấy docker CLI.' @"
Cài đặt Docker Desktop hoặc Docker Engine:
  Windows: https://docs.docker.com/desktop/install/windows-install/
  Hoặc Podman Desktop: https://podman.io/docs/installation
"@
    }
    try {
        docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'docker info exit non-zero' }
    } catch {
        Abort 'ERR-DIST-001: Docker daemon chưa chạy.' @"
Khởi động Docker Desktop từ Start Menu rồi thử lại.
"@
    }
    Write-Ok 'Docker daemon đang chạy.'
}

# ----- Step 2: Check compose v2 -----
$Script:ComposeCmd = @('docker', 'compose')
function Test-Compose {
    Write-Step '2/12 Kiểm tra docker compose'
    try {
        docker compose version 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok 'docker compose v2 available.'
            $Script:ComposeCmd = @('docker', 'compose')
            return
        }
    } catch { }

    if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
        Write-Warn 'Chỉ có docker-compose v1. Fallback nhưng khuyên upgrade.'
        $Script:ComposeCmd = @('docker-compose')
    } else {
        Abort 'Không tìm thấy docker compose hoặc docker-compose.' 'Reinstall Docker.'
    }
}

# ----- Step 3: Detect existing install -----
function Test-Existing {
    Write-Step '3/12 Kiểm tra cấu hình cũ'
    $existing = $false
    if (Test-Path $EnvFile)     { Write-Warn '.env đã tồn tại.';        $existing = $true }
    if (Test-Path $SessionFile) { Write-Warn "session file đã tồn tại: $SessionFile"; $existing = $true }

    if ($existing) {
        $answer = Read-Host "`nGhi đè cấu hình cũ? (y/N) [N]"
        if ($answer -notmatch '^(y|yes)$') { Abort 'Đã hủy. Cấu hình cũ giữ nguyên.' }
        Write-Warn 'Sẽ overwrite .env (session giữ nguyên).'
    } else {
        Write-Ok 'Chưa có cấu hình cũ — proceed.'
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
            Write-Err 'Không được để trống.'
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
    Write-Step '4/12 Nhập cấu hình Telegram'

    $Script:TG_API_ID = Read-Validated `
        -Prompt '🔑 Nhập TG_API_ID (số nguyên, lấy từ https://my.telegram.org/apps):' `
        -Regex  '^[0-9]+$' `
        -ErrMsg 'TG_API_ID phải là số nguyên dương.'

    $Script:TG_API_HASH = Read-Validated `
        -Prompt '🔑 Nhập TG_API_HASH (32 ký tự hex, KHÔNG echo):' `
        -Regex  '^[a-f0-9]{32}$' `
        -ErrMsg 'TG_API_HASH phải là 32 ký tự hex (a-f, 0-9).' `
        -Secret

    $Script:TG_MY_USERNAME = Read-Validated `
        -Prompt '👤 Nhập username Telegram của bạn (KHÔNG có @, vd: hoangp47):' `
        -Regex  '^[A-Za-z][A-Za-z0-9_]{4,31}$' `
        -ErrMsg 'Username 5-32 ký tự, bắt đầu bằng chữ, chỉ chứa chữ/số/_.'

    $Script:TG_BOT_TOKEN = Read-Validated `
        -Prompt '🤖 Nhập TG_BOT_TOKEN từ @BotFather (KHÔNG echo, dạng <số>:<chuỗi>):' `
        -Regex  '^[0-9]+:[A-Za-z0-9_-]{30,40}$' `
        -ErrMsg 'Bot token sai format. Dạng: 1234567890:AAAA....' `
        -Secret
}

# ----- Step 8: Pull image -----
function Invoke-PullImage {
    Write-Step '5/12 Pull Docker image'
    Write-Info "Đang pull $IMAGE ... (lần đầu có thể 1-2 phút)"
    docker pull $IMAGE
    if ($LASTEXITCODE -ne 0) {
        Abort 'ERR-DIST-002: Pull image fail.' @"
Có thể do: (1) mạng không truy cập được ghcr.io, (2) firewall chặn.
Test: Invoke-WebRequest -Uri https://ghcr.io -Method Head
Xem TROUBLESHOOTING.md §Network.
"@
    }
    Write-Ok 'Image đã pull thành công.'
}

# ----- Step 9: Discover chat_id + send test -----
function Get-ChatId {
    Write-Step '6/12 Phát hiện chat_id (sub-flow UC-DIST-05)'

    # Lấy username bot từ getMe
    try {
        $me = Invoke-RestMethod -Uri "https://api.telegram.org/bot$($Script:TG_BOT_TOKEN)/getMe" -TimeoutSec 10
        $botUsername = if ($me.ok) { $me.result.username } else { '' }
    } catch { $botUsername = '' }

    if ($botUsername) {
        Write-Host "`n1. Mở Telegram, tìm @$botUsername (hoặc https://t.me/$botUsername)" -ForegroundColor White
        Write-Host '2. Bấm START hoặc gửi /start cho bot'
        Write-Host '3. Quay lại đây, nhấn Enter'
    } else {
        Write-Warn 'Không lấy được username bot. Cứ thử /start với bot bạn vừa tạo.'
        Write-Host "`nGửi /start cho bot trên Telegram, rồi nhấn Enter..."
    }
    Read-Host | Out-Null

    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Write-Info "Đang gọi getUpdates ... (lần thử $attempt/$maxAttempts)"
        try {
            $updates = Invoke-RestMethod -Uri "https://api.telegram.org/bot$($Script:TG_BOT_TOKEN)/getUpdates" -TimeoutSec 10
        } catch {
            Write-Warn "Không gọi được API: $($_.Exception.Message)"
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
            Write-Ok "Tìm thấy chat_id: $chatId"

            # Round-trip verify (BR-DIST-05-01)
            Write-Info 'Đang gửi test message...'
            try {
                $sendResult = Invoke-RestMethod -Method Post `
                    -Uri "https://api.telegram.org/bot$($Script:TG_BOT_TOKEN)/sendMessage" `
                    -Body @{
                        chat_id = $chatId
                        text    = '🔧 MentionMate setup test — nếu bạn thấy tin nhắn này, cấu hình đang đúng.'
                    } -TimeoutSec 10
            } catch {
                Write-Warn "Gửi test fail: $($_.Exception.Message)"
                $sendResult = $null
            }

            if ($sendResult -and $sendResult.ok) {
                $confirm = Read-Host "`nBạn có nhận được tin nhắn test trên Telegram không? (y/N)"
                if ($confirm -match '^(y|yes)$') {
                    $Script:TG_ALERT_CHAT_ID = $chatId
                    return
                }
                Write-Warn 'User không nhận được — có thể chat_id sai. Thử lại.'
            }
        } else {
            Write-Warn 'Không thấy /start trong update gần đây. Bạn đã gửi /start cho ĐÚNG bot vừa tạo chưa?'
        }

        if ($attempt -lt $maxAttempts) {
            $retry = Read-Host "`nThử lại? (Y/n)"
            if ($retry -match '^(n|no)$') { break }
            Write-Host 'Gửi /start cho bot lần nữa, rồi nhấn Enter...'
            Read-Host | Out-Null
        }
    }

    Abort "Không phát hiện được chat_id sau $maxAttempts lần thử." 'Xem TROUBLESHOOTING.md §chat_id.'
}

# ----- Step 10: Write .env + restrict ACL -----
function Write-EnvFile {
    Write-Step '7/12 Ghi cấu hình vào .env'
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

    # Restrict ACL — chỉ owner đọc/ghi (NFR-SEC-03)
    try {
        icacls $EnvFile /inheritance:r 2>&1 | Out-Null
        icacls $EnvFile /grant:r "$($env:USERNAME):(R,W)" 2>&1 | Out-Null
        Write-Ok ".env đã ghi với ACL owner-only."
    } catch {
        Write-Warn "Không set được ACL ($($_.Exception.Message)). File có thể đọc được bởi user khác."
    }
}

# ----- Step 11: Telethon auth -----
function Invoke-TelethonAuth {
    Write-Step '8/12 Đăng nhập Telethon userbot'
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

    if (Test-Path $SessionFile) {
        Write-Info 'Session file đã tồn tại — skip auth interactive.'
        return
    }

    Write-Info 'Sẽ chạy 1 container interactive — nhập SĐT (vd +84912345678) khi được hỏi.'
    Write-Info 'Nếu account có 2FA, sẽ hỏi password sau OTP.'

    $cwd = (Get-Location).Path
    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        docker run --rm -it `
            -v "${cwd}\data:/app/data" `
            --env-file $EnvFile `
            $IMAGE `
            python /app/scripts/auth.py

        if ($LASTEXITCODE -eq 0 -and (Test-Path $SessionFile)) {
            Write-Ok "Telethon session đã tạo: $SessionFile"
            return
        }
        Write-Warn "Auth fail. Thử lại? ($attempt/$maxAttempts)"
        if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 2 }
    }

    Abort 'ERR-DIST-003: Telethon auth fail.' 'Xem TROUBLESHOOTING.md §Auth.'
}

# ----- Step 12: Start container -----
function Start-Container {
    Write-Step '9/12 Khởi động container MentionMate'
    & $Script:ComposeCmd[0] $Script:ComposeCmd[1..($Script:ComposeCmd.Length-1)] up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'ERR-DIST-004: Container không start.'
        & $Script:ComposeCmd[0] $Script:ComposeCmd[1..($Script:ComposeCmd.Length-1)] logs --tail 50
        Abort 'Xem TROUBLESHOOTING.md §Container.'
    }
    Start-Sleep -Seconds 3
    Write-Ok "Container 'mentionmate' đang chạy."
}

# ----- Step 13: Summary -----
function Show-Summary {
    Write-Step '10/12 Hoàn tất! 🎉'
    $composeStr = $Script:ComposeCmd -join ' '
    Write-Host "`nMentionMate đã được cài đặt thành công." -ForegroundColor Green

    Write-Host @"

📝 Lệnh hữu ích:
  Xem log:        $composeStr logs -f bot
  Dừng:           $composeStr down
  Khởi động lại:  $composeStr restart
  Cập nhật:       .\update.ps1

📖 Documentation:  https://github.com/hoangp47/mentionmate
🐛 Báo lỗi:        https://github.com/hoangp47/mentionmate/issues

Bạn sẽ nhận alert trên Telegram khi có ai đó @$($Script:TG_MY_USERNAME) trong group có userbot tham gia.
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
