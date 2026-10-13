```powershell
$ErrorActionPreference = "Stop"

# Run from the Flutter project root (the folder containing pubspec.yaml).
if (-not (Test-Path "pubspec.yaml")) {
  throw "Run this script from the Pack Master project root (where pubspec.yaml is located)."
}

Write-Host "Preparing Android platform files..."
flutter create . --platforms android --project-name inv_management
if ($LASTEXITCODE -ne 0) {
  throw "flutter create failed."
}

$manifest = "android/app/src/main/AndroidManifest.xml"
if (-not (Test-Path $manifest)) {
  throw "AndroidManifest.xml was not generated."
}

$xml = Get-Content $manifest -Raw

# Set the Android application name.
if ($xml -match 'android:label="[^"]*"') {
  $xml = [regex]::Replace(
    $xml,
    'android:label="[^"]*"',
    'android:label="Pack Master"',
    1
  )
} else {
  $xml = $xml -replace '<application', '<application android:label="Pack Master"'
}

# Ensure INTERNET permission exists in the main manifest.
if ($xml -notmatch 'android\.permission\.INTERNET') {
  $xml = [regex]::Replace(
    $xml,
    '(<manifest\b[^>]*>)',
    "`$1`r`n    <uses-permission android:name=`"android.permission.INTERNET`" />",
    1
  )
}

# Save the updated AndroidManifest.xml.
Set-Content -Path $manifest -Value $xml -Encoding UTF8

Write-Host "Android app name set to Pack Master."
Write-Host "INTERNET permission verified."

Write-Host "Installing Flutter dependencies..."
flutter pub get
if ($LASTEXITCODE -ne 0) {
  throw "flutter pub get failed."
}

$projectUrl = "https://bnnqbrqlgubodkauguoj.supabase.co"
$publishableKey = Read-Host "Paste the Supabase publishable key"

if ([string]::IsNullOrWhiteSpace($publishableKey)) {
  throw "Supabase publishable key is required."
}

Write-Host "Building Pack Master APK..."
flutter build apk --release `
  "--dart-define=SUPABASE_URL=$projectUrl" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$publishableKey"

if ($LASTEXITCODE -ne 0) {
  throw "APK build failed."
}

Write-Host ""
Write-Host "Build completed successfully!"
Write-Host "APK: build\app\outputs\flutter-apk\app-release.apk"
```