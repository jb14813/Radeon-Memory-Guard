[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid version'}
$build=if($OutputDirectory){[IO.Path]::GetFullPath($OutputDirectory)}else{Join-Path $root 'build'}
$null=New-Item -ItemType Directory -Path $build -Force
$zip=Join-Path $build ('RadeonMemoryGuard-'+$version+'.zip')
if(Test-Path -LiteralPath $zip){throw 'Release already exists; remove that exact generated ZIP before rebuilding.'}
$names=@('RadeonMemoryGuard.ps1','RadeonMemoryGuard.psm1','RadeonRamCache.ps1','README.md','LICENSE','VERSION','THIRD-PARTY-NOTICES.txt')
$files=@($names | ForEach-Object {Join-Path $root $_})
Compress-Archive -LiteralPath $files -DestinationPath $zip -CompressionLevel Optimal
$hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
($hash+'  '+[IO.Path]::GetFileName($zip)) | Set-Content -LiteralPath ($zip+'.sha256') -Encoding ASCII
Write-Output $zip
Write-Output $hash
