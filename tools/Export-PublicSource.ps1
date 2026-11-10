[CmdletBinding()]
param([Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(Test-Path -LiteralPath $Destination){throw 'Public export destination must be new and empty'}
$null=New-Item -ItemType Directory -Path $Destination
$names=@('RadeonMemoryGuard.ps1','RadeonMemoryGuard.psm1','RadeonRamCache.ps1','README.md','LICENSE','VERSION','SIGNING.md','THIRD-PARTY-NOTICES.txt','CHANGELOG.md','.gitignore')
foreach($name in $names){Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $Destination $name)}
foreach($directory in @('tools','tests','installer','branding','signing','.github')){
 Copy-Item -LiteralPath (Join-Path $root $directory) -Destination (Join-Path $Destination $directory) -Recurse
}
$null=& (Join-Path $root 'tests\Test-PublicSource.ps1') -Directory $Destination
[pscustomobject]@{Path=[IO.Path]::GetFullPath($Destination);CleanHistory=$true;AuditPassed=$true}
