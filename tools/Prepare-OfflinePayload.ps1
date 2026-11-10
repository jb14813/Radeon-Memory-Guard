[CmdletBinding()]
param([string]$CacheDirectory,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $CacheDirectory){$CacheDirectory=Join-Path $root 'build\offline-inputs'}
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root 'build\offline-payload'}
$null=New-Item -ItemType Directory -Path $CacheDirectory -Force
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$manifest=Get-Content (Join-Path $root 'installer\dependencies.json') -Raw | ConvertFrom-Json
foreach($item in $manifest.Artifacts){
 if($item.Name -notmatch '^[A-Za-z0-9.-]+$'){throw 'Invalid dependency filename'}
 $inputPath=Join-Path $CacheDirectory $item.Name
 if(-not [IO.File]::Exists($inputPath)){Invoke-WebRequest -UseBasicParsing -Uri $item.Url -OutFile $inputPath}
 if((Get-FileHash -LiteralPath $inputPath).Hash -ne $item.Sha256){throw ('Dependency checksum mismatch: '+$item.Name)}
 $target=Join-Path $OutputDirectory $item.Name
 Copy-Item -LiteralPath $inputPath -Destination $target -Force
 if((Get-FileHash -LiteralPath $target).Hash -ne $item.Sha256){throw 'Payload staging hash mismatch'}
}
$signature=Get-AuthenticodeSignature (Join-Path $OutputDirectory 'osfmount-3.3.1000.exe')
if($signature.Status.ToString() -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '^CN=PassMark Software Pty Ltd,'){throw 'Invalid original OSFMount signature'}
Copy-Item -LiteralPath (Join-Path $root 'THIRD-PARTY-NOTICES.txt') -Destination (Join-Path $OutputDirectory 'THIRD-PARTY-NOTICES.txt') -Force
[pscustomobject]@{Path=[IO.Path]::GetFullPath($OutputDirectory);Artifacts=$manifest.Artifacts.Count}
