param([switch]$SelfSign)
$ErrorActionPreference='Stop'
$result=& (Join-Path $PSScriptRoot '..\tools\Build-Installer.ps1') -SelfSign:$SelfSign
if(-not [IO.File]::Exists($result.Path)){throw 'Installer EXE was not produced'}
$file=Get-Item -LiteralPath $result.Path
$version=(Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\VERSION') -Raw).Trim()
if($file.VersionInfo.ProductVersion.Trim() -ne $version){throw 'Installer version does not match the package'}
if($file.VersionInfo.CompanyName.Trim() -ne 'JZB Apps'){throw 'Installer publisher metadata is missing'}
if($file.VersionInfo.FileDescription -notlike '*Experimental*'){throw 'Installer metadata must identify the experimental build'}
if((Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant() -ne $result.Sha256){throw 'Installer checksum metadata is incorrect'}
$checksum=(Get-Content -LiteralPath ($file.FullName+'.sha256') -Raw).Trim().Split(' ')[0]
if($checksum -ne $result.Sha256){throw 'Installer checksum file is incorrect'}
if($SelfSign){$null=& (Join-Path $PSScriptRoot '..\tools\Verify-Release.ps1') -Path $file.FullName -ExpectedSha256 $result.Sha256}
elseif((Get-AuthenticodeSignature -LiteralPath $file.FullName).Status.ToString() -ne 'NotSigned'){throw 'Unsigned build unexpectedly uses a signing certificate'}
$stream=[IO.File]::OpenRead($file.FullName)
try{$reader=New-Object IO.BinaryReader($stream);if($reader.ReadUInt16() -ne 0x5a4d){throw 'Invalid executable header'};$stream.Position=0x3c;$pe=$reader.ReadUInt32();$stream.Position=$pe;if($reader.ReadUInt32() -ne 0x4550){throw 'Invalid PE signature'}}finally{$stream.Dispose()}
Write-Output "Installer artifact verified: $($file.Name); offline=$($result.Offline); self-signed=$($result.SelfSigned); final SHA-256 matches."
