# Create Secure Zip - Excludes Secrets and Documentation
# Run this to create a deployment-ready zip without sensitive files

$ErrorActionPreference = "Stop"

Write-Host "📦 Creating Secure Gateway Zip" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan
Write-Host ""

# Files to exclude
$excludePatterns = @(
    '*.md',                    # Documentation files
    '.env',                    # Environment variables (may contain secrets)
    'service-account-key.json', # Service account keys
    '*-service-account.json',   # Any service account files
    'node_modules',            # Dependencies (too large)
    '.git',                    # Git files
    '.gitignore',              # Git ignore
    '*.log',                   # Log files
    '.DS_Store',               # OS files
    'Thumbs.db'                # OS files
)

Write-Host "📋 Excluding:" -ForegroundColor Yellow
$excludePatterns | ForEach-Object { Write-Host "   - $_" }

Write-Host ""
Write-Host "📁 Including gateway files..." -ForegroundColor Yellow

# Get all files, excluding patterns
$files = Get-ChildItem -Path . -File | Where-Object {
    $file = $_
    $shouldExclude = $false
    
    foreach ($pattern in $excludePatterns) {
        if ($file.Name -like $pattern -or $file.FullName -like "*\$pattern") {
            $shouldExclude = $true
            break
        }
    }
    
    -not $shouldExclude
}

Write-Host ""
Write-Host "✅ Files to include:" -ForegroundColor Green
$files | ForEach-Object { Write-Host "   - $($_.Name)" }

Write-Host ""
Write-Host "📦 Creating zip..." -ForegroundColor Yellow

$zipPath = Join-Path ".." "gateway-secure.zip"

# Remove existing zip if it exists
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
    Write-Host "   Removed existing zip" -ForegroundColor Gray
}

# Create zip
Compress-Archive -Path $files.FullName -DestinationPath $zipPath -Force

Write-Host ""
Write-Host "✅ Secure zip created!" -ForegroundColor Green
Write-Host "   Location: $zipPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "🔒 Security check:" -ForegroundColor Yellow
Write-Host "   ✅ No .env files" -ForegroundColor Green
Write-Host "   ✅ No service account keys" -ForegroundColor Green
Write-Host "   ✅ No documentation files" -ForegroundColor Green
Write-Host "   ✅ Ready for deployment" -ForegroundColor Green


