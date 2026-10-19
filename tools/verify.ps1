$ErrorActionPreference='Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
  npm --prefix server test
  if ($LASTEXITCODE -ne 0) { throw 'Server tests failed' }
  Push-Location app
  try {
    & (Join-Path $PSScriptRoot 'flutter.ps1') analyze --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analyze failed' }
    & (Join-Path $PSScriptRoot 'flutter.ps1') test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed' }
  } finally { Pop-Location }
} finally { Pop-Location }
