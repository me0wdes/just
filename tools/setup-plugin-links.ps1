param([string]$AppPath=(Join-Path (Split-Path $PSScriptRoot) 'app'))
$ErrorActionPreference='Stop'
$manifest=Join-Path $AppPath '.flutter-plugins-dependencies'
if(-not(Test-Path -LiteralPath $manifest)){return 0}
$plugins=Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json
$linkRoot=Join-Path $AppPath 'windows/flutter/ephemeral/.plugin_symlinks'
New-Item -ItemType Directory -Force -Path $linkRoot | Out-Null
$created=0
foreach($plugin in $plugins.plugins.windows){
  if($plugin.name -notmatch '^[a-zA-Z0-9_]+$'){throw 'Invalid plugin name'}
  $destination=Join-Path $linkRoot $plugin.name
  if(-not(Test-Path -LiteralPath $destination)){
    New-Item -ItemType Junction -Path $destination -Target $plugin.path | Out-Null
    $created++
  }
}
return $created
