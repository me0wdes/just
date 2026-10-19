param([string]$Version='0.1.1')
$ErrorActionPreference='Stop'
$releasePath=Join-Path (Split-Path $PSScriptRoot) "releases/$Version"
$required=@('day_planner.exe','flutter_windows.dll','msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','data/app.so','data/flutter_assets/assets/sounds/complete.wav','data/flutter_assets/assets/sounds/undo.wav','data/flutter_assets/assets/fonts/OFL.txt','data/flutter_assets/assets/icons/itshover/gear-icon.svg','data/flutter_assets/assets/licenses/ItsHover-Apache-2.0.txt','data/flutter_assets/shaders/rose_gold.frag')
foreach($package in @('just-windows.zip','just-windows.msix')) {
  $archive=[System.IO.Compression.ZipFile]::OpenRead((Join-Path $releasePath $package))
  try {
    $names=@($archive.Entries | ForEach-Object {$_.FullName.Replace('\','/')})
    foreach($name in $required) {
      if($name -notin $names){throw "$package missing $name"}
    }
    if($names | Where-Object {$_ -match 'kernel_blob|\.pfx$|password\.txt$'}){throw "$package contains a development or private signing file"}
  } finally {$archive.Dispose()}
}
Write-Output 'Release contents PASS: AOT, assets and VC runtime included; private signing files absent.'
