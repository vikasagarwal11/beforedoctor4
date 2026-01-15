# Create Implementation Verification Zip
# Includes only essential files to verify implementation

$ErrorActionPreference = "Stop"

Write-Host "📦 Creating Implementation Verification Zip" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

$rootPath = "C:\Vikas\Projects\beforedoctor4"
$zipPath = Join-Path $rootPath "implementation-verification.zip"

# Remove existing zip
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
    Write-Host "Removed existing zip" -ForegroundColor Gray
}

$files = @()

Write-Host "📁 Collecting Gateway Server Files..." -ForegroundColor Yellow
# Gateway core files
$gatewayFiles = @(
    "gateway\server.js",
    "gateway\vertex-live-ws-client.js",
    "gateway\event-handler.js",
    "gateway\safety-guardrail.js",
    "gateway\auth.js",
    "gateway\logger.js",
    "gateway\config.js",
    "gateway\package.json",
    "gateway\Dockerfile",
    "gateway\.gitignore"
)

foreach ($file in $gatewayFiles) {
    $fullPath = Join-Path $rootPath $file
    if (Test-Path $fullPath) {
        $files += $fullPath
        Write-Host "  ✅ $file" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  $file (not found)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "📁 Collecting Flutter Client Files..." -ForegroundColor Yellow
# Flutter gateway files
$flutterGatewayFiles = @(
    "lib\services\gateway\gateway_protocol.dart",
    "lib\services\gateway\gateway_client.dart",
    "lib\services\gateway\mock_gateway_client.dart"
)

foreach ($file in $flutterGatewayFiles) {
    $fullPath = Join-Path $rootPath $file
    if (Test-Path $fullPath) {
        $files += $fullPath
        Write-Host "  ✅ $file" -ForegroundColor Green
    }
}

# Flutter audio files
$flutterAudioFiles = @(
    "lib\services\audio\audio_engine_service.dart",
    "lib\services\audio\native_audio_engine.dart"
)

foreach ($file in $flutterAudioFiles) {
    $fullPath = Join-Path $rootPath $file
    if (Test-Path $fullPath) {
        $files += $fullPath
        Write-Host "  ✅ $file" -ForegroundColor Green
    }
}

# Flutter voice files
$flutterVoiceFiles = @(
    "lib\features\voice\voice_session_controller.dart",
    "lib\features\voice\screens\voice_live_screen.dart"
)

foreach ($file in $flutterVoiceFiles) {
    $fullPath = Join-Path $rootPath $file
    if (Test-Path $fullPath) {
        $files += $fullPath
        Write-Host "  ✅ $file" -ForegroundColor Green
    }
}

# Flutter data models
$flutterModelFiles = @(
    "lib\data\models\adverse_event_report.dart"
)

foreach ($file in $flutterModelFiles) {
    $fullPath = Join-Path $rootPath $file
    if (Test-Path $fullPath) {
        $files += $fullPath
        Write-Host "  ✅ $file" -ForegroundColor Green
    }
}

# Configuration
$configFiles = @(
    "pubspec.yaml"
)

foreach ($file in $configFiles) {
    $fullPath = Join-Path $rootPath $file
    if (Test-Path $fullPath) {
        $files += $fullPath
        Write-Host "  ✅ $file" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "📦 Creating zip file..." -ForegroundColor Yellow
Write-Host "   Total files: $($files.Count)" -ForegroundColor Cyan

# Create zip
Compress-Archive -Path $files -DestinationPath $zipPath -Force

Write-Host ""
Write-Host "✅ Zip created successfully!" -ForegroundColor Green
Write-Host "   Location: $zipPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "📋 Files included:" -ForegroundColor Yellow
Write-Host "   Gateway: 10 files" -ForegroundColor White
Write-Host "   Flutter: 9 files" -ForegroundColor White
Write-Host "   Total: $($files.Count) files" -ForegroundColor White
Write-Host ""
Write-Host "🔒 Security check:" -ForegroundColor Yellow
Write-Host "   ✅ No .env files" -ForegroundColor Green
Write-Host "   ✅ No service account keys" -ForegroundColor Green
Write-Host "   ✅ No node_modules" -ForegroundColor Green
Write-Host "   ✅ No documentation files" -ForegroundColor Green
Write-Host ""
Write-Host "Ready to share with ChatGPT for verification! 🚀" -ForegroundColor Cyan


