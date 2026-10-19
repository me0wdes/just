$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot
$toolsPath=Join-Path $projectRoot '.tools'
New-Item -ItemType Directory -Force $toolsPath | Out-Null
if (-not (Test-Path (Join-Path $toolsPath 'flutter/bin/flutter.bat'))) {
  $manifest=Invoke-RestMethod 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
  $stable=$manifest.releases | Where-Object { $_.hash -eq $manifest.current_release.stable -and ($_.dart_sdk_arch -eq 'x64' -or -not $_.dart_sdk_arch) } | Select-Object -First 1
  $archive=Join-Path $toolsPath 'flutter-sdk.zip'
  Invoke-WebRequest "$($manifest.base_url)/$($stable.archive)" -OutFile $archive
  if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLower() -ne $stable.sha256) { throw 'Flutter SHA256 mismatch' }
  tar -xf $archive -C $toolsPath
}
& (Join-Path $PSScriptRoot 'flutter.ps1') doctor -v
