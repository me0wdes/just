param([ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version='0.1.1')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot
$smokeRoot=Join-Path $projectRoot ".tools/release-smoke/$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $smokeRoot | Out-Null
Expand-Archive -LiteralPath (Join-Path $projectRoot "releases/$Version/just-windows.zip") -DestinationPath (Join-Path $smokeRoot 'app')
$smokeData=Join-Path $smokeRoot 'data'
$releasedProc=Start-Process -FilePath (Join-Path $smokeRoot 'app/day_planner.exe') -ArgumentList @('--data-directory',('"'+$smokeData+'"')) -WindowStyle Hidden -PassThru
try {
  $null=$releasedProc.WaitForInputIdle(10000)
  for($attempt=0;$attempt -lt 50;$attempt++) {
    $releasedProc.Refresh()
    if($releasedProc.HasExited){throw "Release process exited: $($releasedProc.ExitCode)"}
    if(Test-Path -LiteralPath (Join-Path $smokeData 'day.sqlite')){break}
    Start-Sleep -Milliseconds 100
  }
  if(-not(Test-Path -LiteralPath (Join-Path $smokeData 'day.sqlite'))){throw 'No release database created'}
  Write-Output "Release ZIP bootstrap PASS: live process created isolated database at $smokeData"
} finally {
  # This process was created by this test with an empty private test directory.
  # Hidden windows are excluded from Process.MainWindowHandle, so close by PID.
  if(-not $releasedProc.HasExited){Stop-Process -Id $releasedProc.Id -Force}
}
