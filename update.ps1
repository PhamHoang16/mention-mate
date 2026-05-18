# MentionMate — Update wizard for Windows (PowerShell 5.1+)
# Docs: https://github.com/hoangp47/mentionmate
#
# Usage: .\update.ps1

$ErrorActionPreference = 'Stop'

$IMAGE       = 'ghcr.io/hoangp47/mentionmate'
$SessionFile = '.\data\mentions_session.session'

function Write-Ok    { param($Msg) Write-Host "✅ $Msg" -ForegroundColor Green }
function Write-Warn  { param($Msg) Write-Host "⚠️  $Msg" -ForegroundColor Yellow }
function Write-Err   { param($Msg) Write-Host "❌ $Msg" -ForegroundColor Red }

# Detect compose command
$ComposeCmd = @('docker', 'compose')
try {
    docker compose version 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw }
} catch {
    if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
        $ComposeCmd = @('docker-compose')
    } else {
        Write-Err 'Không tìm thấy docker compose / docker-compose.'
        exit 1
    }
}

if (-not (Test-Path 'docker-compose.yml')) {
    Write-Err 'Không tìm thấy docker-compose.yml. Chạy script này trong thư mục MentionMate.'
    exit 1
}

Write-Host "`n━━━ MentionMate Update ━━━`n" -ForegroundColor Cyan

# Step 1: Current version
try {
    $currentImage = docker inspect mentionmate --format '{{.Config.Image}}' 2>$null
    if ($currentImage) { Write-Host "📍 Phiên bản hiện tại: $currentImage" -ForegroundColor White }
    else { Write-Warn 'Không phát hiện container hiện tại (có thể chưa từng up).' }
} catch { $currentImage = $null }

# Step 2: Session backup warning
if (Test-Path $SessionFile) {
    $age = (Get-Date) - (Get-Item $SessionFile).LastWriteTime
    if ($age.Days -gt 7) {
        Write-Warn "Session file > 7 ngày — recommend backup trước update."
        $ans = Read-Host 'Backup session ngay? (Y/n) [Y]'
        if ($ans -notmatch '^(n|no)$') {
            $backup = "$SessionFile.backup.$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
            Copy-Item $SessionFile $backup
            Write-Ok "Backup: $backup"
        }
    }
}

# Step 3: Pull
Write-Host "`n⬇️  Đang pull image mới..."
& $ComposeCmd[0] $ComposeCmd[1..($ComposeCmd.Length-1)] pull
if ($LASTEXITCODE -ne 0) {
    Write-Err 'ERR-DIST-002: Pull fail. Kiểm tra mạng truy cập ghcr.io.'
    exit 1
}

# Step 4: Recreate (compose up -d sẽ tự skip nếu image không đổi)
Write-Host "`n🔄 Recreating container với image mới..."
& $ComposeCmd[0] $ComposeCmd[1..($ComposeCmd.Length-1)] up -d
if ($LASTEXITCODE -ne 0) {
    Write-Err 'ERR-DIST-006: Container không khởi động lại.'
    Write-Err 'Xem TROUBLESHOOTING.md §Update.'
    exit 1
}

Start-Sleep -Seconds 3

# Step 5: Verify
try {
    $newImage = docker inspect mentionmate --format '{{.Config.Image}}' 2>$null
    Write-Ok "Update xong. Image: $newImage"
} catch {
    Write-Ok 'Update xong.'
}

$composeStr = $ComposeCmd -join ' '
Write-Host "`n📝 Xem log: $composeStr logs -f bot" -ForegroundColor White
