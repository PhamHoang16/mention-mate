# MentionMate — Update wizard for Windows (PowerShell 5.1+)
# Docs: https://github.com/hoangp47/mention-mate
#
# Usage: .\update.ps1

$ErrorActionPreference = 'Stop'

$IMAGE       = 'ghcr.io/hoangp47/mention-mate'
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
        Write-Err 'Neither docker compose nor docker-compose found.'
        exit 1
    }
}

if (-not (Test-Path 'docker-compose.yml')) {
    Write-Err 'docker-compose.yml not found. Run this script from the MentionMate directory.'
    exit 1
}

Write-Host "`n━━━ MentionMate Update ━━━`n" -ForegroundColor Cyan

# Step 1: Current version
try {
    $currentImage = docker inspect mention-mate --format '{{.Config.Image}}' 2>$null
    if ($currentImage) { Write-Host "📍 Current version: $currentImage" -ForegroundColor White }
    else { Write-Warn 'No running container detected (may never have been started).' }
} catch { $currentImage = $null }

# Step 2: Session backup warning
if (Test-Path $SessionFile) {
    $age = (Get-Date) - (Get-Item $SessionFile).LastWriteTime
    if ($age.Days -gt 7) {
        Write-Warn "Session file is more than 7 days old — backup recommended before updating."
        $ans = Read-Host 'Back up session now? (Y/n) [Y]'
        if ($ans -notmatch '^(n|no)$') {
            $backup = "$SessionFile.backup.$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
            Copy-Item $SessionFile $backup
            Write-Ok "Backup: $backup"
        }
    }
}

# Step 3: Pull
Write-Host "`n⬇️  Pulling new image..."
& $ComposeCmd[0] $ComposeCmd[1..($ComposeCmd.Length-1)] pull
if ($LASTEXITCODE -ne 0) {
    Write-Err 'ERR-DIST-002: Pull failed. Check network access to ghcr.io.'
    exit 1
}

# Step 4: Recreate (compose up -d skips automatically if the image hasn't changed)
Write-Host "`n🔄 Recreating container with new image..."
& $ComposeCmd[0] $ComposeCmd[1..($ComposeCmd.Length-1)] up -d
if ($LASTEXITCODE -ne 0) {
    Write-Err 'ERR-DIST-006: Container failed to restart.'
    Write-Err 'See TROUBLESHOOTING.md §Update.'
    exit 1
}

Start-Sleep -Seconds 3

# Step 5: Verify
try {
    $newImage = docker inspect mention-mate --format '{{.Config.Image}}' 2>$null
    Write-Ok "Update complete. Image: $newImage"
} catch {
    Write-Ok 'Update complete.'
}

$composeStr = $ComposeCmd -join ' '
Write-Host "`n📝 Tail logs: $composeStr logs -f bot" -ForegroundColor White
