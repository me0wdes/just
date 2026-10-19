param([Parameter(ValueFromRemainingArguments=$true)][string[]]$FlutterArguments)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot
$fs=New-Object -ComObject Scripting.FileSystemObject
$projectRoot=$fs.GetFolder($projectRoot).ShortPath
$env:PUB_CACHE=Join-Path $projectRoot '.tools/pub-cache'
$env:APPDATA=Join-Path $projectRoot '.tools/user-config'
$env:GRADLE_USER_HOME=Join-Path $projectRoot '.tools/gradle'
$env:FLUTTER_SUPPRESS_ANALYTICS='true'
if (Test-Path (Join-Path $projectRoot '.tools/android-sdk')) { $env:ANDROID_HOME=Join-Path $projectRoot '.tools/android-sdk' }
if (Test-Path (Join-Path $projectRoot '.tools/jdk')) { $env:JAVA_HOME=Join-Path $projectRoot '.tools/jdk' }
$null=& (Join-Path $PSScriptRoot 'setup-plugin-links.ps1')
& (Join-Path $projectRoot '.tools/flutter/bin/flutter.bat') @FlutterArguments
$flutterExit=$LASTEXITCODE
$newLinks=& (Join-Path $PSScriptRoot 'setup-plugin-links.ps1')
if($flutterExit -ne 0 -and $newLinks -gt 0 -and $FlutterArguments[0] -eq 'pub'){
  & (Join-Path $projectRoot '.tools/flutter/bin/flutter.bat') @FlutterArguments
  $flutterExit=$LASTEXITCODE
}
exit $flutterExit
