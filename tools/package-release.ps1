param([ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version='0.1.1')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot
& (Join-Path $PSScriptRoot 'verify.ps1')
$outputPath=Join-Path $projectRoot "releases/$Version"
New-Item -ItemType Directory -Force $outputPath | Out-Null
Push-Location (Join-Path $projectRoot 'app')
try {
  & (Join-Path $PSScriptRoot 'flutter.ps1') build windows --release --no-pub --build-name $Version
  if($LASTEXITCODE -ne 0){throw 'Windows release build failed'}
  $runner=Join-Path (Get-Location) 'build/windows/x64/runner/Release'
  # Flutter's deployment guide requires these app-local VC runtime libraries.
  $vsWhere='C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe'
  $vsPath=& $vsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if(-not $vsPath){throw 'Visual Studio C++ redist location not found'}
  $redistVersion=Get-ChildItem -LiteralPath (Join-Path $vsPath 'VC/Redist/MSVC') -Directory | Where-Object {$_.Name -match '^\d+\.\d+\.\d+$'} | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
  if($null -eq $redistVersion){throw 'Versioned Visual C++ redist directory not found'}
  $crtPath=Join-Path $redistVersion.FullName 'x64/Microsoft.VC143.CRT'
  foreach($dll in Get-ChildItem -LiteralPath $crtPath -Filter '*.dll') {
    Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $runner $dll.Name) -Force
  }
  Compress-Archive -Path (Join-Path $runner '*') -DestinationPath (Join-Path $outputPath 'just-windows.zip') -Force
  & (Join-Path $PSScriptRoot 'flutter.ps1') pub run msix:create --build-windows false --install-certificate false --sign-msix false --output-path $outputPath --output-name just-windows --version "$Version.0"
  if($LASTEXITCODE -ne 0){throw 'MSIX packaging failed'}
} finally {Pop-Location}

# The certificate is generated in memory and saved to ignored files only.
# No certificate is installed in any Windows trust store by this script.
$signing=Join-Path $projectRoot '.tools/signing'
New-Item -ItemType Directory -Force $signing | Out-Null
$pfxPath=Join-Path $signing 'day.pfx'
$passwordPath=Join-Path $signing 'password.txt'
if(-not(Test-Path -LiteralPath $pfxPath)){
  $password=[Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
  $rsa=[System.Security.Cryptography.RSA]::Create(2048)
  $request=[System.Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=Didje Day',$rsa,[System.Security.Cryptography.HashAlgorithmName]::SHA256,[System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
  $oids=[System.Security.Cryptography.OidCollection]::new()
  $null=$oids.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
  $request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids,$true))
  $request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new([System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature,$true))
  $certificate=$request.CreateSelfSigned([DateTimeOffset]::Now.AddDays(-1),[DateTimeOffset]::Now.AddYears(3))
  [System.IO.File]::WriteAllBytes($pfxPath,$certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx,$password))
  [System.IO.File]::WriteAllText($passwordPath,$password)
  [System.IO.File]::WriteAllBytes((Join-Path $signing 'day.cer'),$certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
  $certificate.Dispose();$rsa.Dispose()
}
$password=[System.IO.File]::ReadAllText($passwordPath)
$signTool=Get-ChildItem 'C:/Program Files (x86)/Windows Kits/10/bin/*/x64/signtool.exe' | Sort-Object FullName -Descending | Select-Object -First 1
if($null -eq $signTool){throw 'Windows SDK signtool is missing'}
$msixPath=Join-Path $outputPath 'just-windows.msix'
& $signTool.FullName sign /fd SHA256 /f $pfxPath /p $password $msixPath
if($LASTEXITCODE -ne 0){throw 'MSIX signing failed'}
Copy-Item -LiteralPath (Join-Path $signing 'day.cer') -Destination (Join-Path $outputPath 'day-signing.cer') -Force

# Check the CMS signature without installing/trusting the self-signed cert.
Add-Type -AssemblyName System.Security.Cryptography.Pkcs
$archive=[System.IO.Compression.ZipFile]::OpenRead($msixPath)
try {
  $entry=$archive.GetEntry('AppxSignature.p7x');if($null -eq $entry){throw 'MSIX signature missing'}
  $stream=$entry.Open();$buffer=[System.IO.MemoryStream]::new();$stream.CopyTo($buffer);$stream.Dispose()
  $data=$buffer.ToArray();$buffer.Dispose()
  $cms=[System.Security.Cryptography.Pkcs.SignedCms]::new()
  $cms.Decode([byte[]]$data[4..($data.Length-1)])
  $cms.CheckSignature($true)
} finally {$archive.Dispose()}
$files=@('just-windows.zip','just-windows.msix','day-signing.cer')
$sums=foreach($name in $files){$hash=Get-FileHash -LiteralPath (Join-Path $outputPath $name) -Algorithm SHA256;"$($hash.Hash.ToLower())  $name"}
[System.IO.File]::WriteAllLines((Join-Path $outputPath 'SHA256SUMS.txt'),$sums)
& (Join-Path $PSScriptRoot 'check-release.ps1') -Version $Version
Write-Output "Windows artifacts ready: $outputPath"
