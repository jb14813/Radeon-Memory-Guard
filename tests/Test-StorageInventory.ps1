$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\RadeonMemoryGuard.psm1') -Force
$module=Get-Module RadeonMemoryGuard
& $module {
 $script:InventoryError=2
 function script:Get-ChildItem {param($LiteralPath) @([pscustomobject]@{PSPath='test6';PSChildName='Scsi Port 6'},[pscustomobject]@{PSPath='test7';PSChildName='Scsi Port 7'})}
 function script:Get-ItemProperty {param($LiteralPath) [pscustomobject]@{Driver='phdskmnt'}}
 function script:Invoke-RmgStorageAdapterCheck($Port){if($Port -eq 7){throw (New-Object ComponentModel.Win32Exception($script:InventoryError))}}
}
$ports=@(& $module {Get-RmgStoragePorts})
if($ports.Count -ne 1 -or $ports[0] -ne 6){throw 'Stale adapter registry entries prevented discovery of the live controller'}
& $module {$script:InventoryError=5}
$failed=$false;try{$null=& $module {Get-RmgStoragePorts}}catch{$failed=$true}
if(-not $failed){throw 'Access-denied adapter failures were silently ignored'}
Write-Output 'Passed 2 adapter inventory assertions; no real storage requests were issued.'
