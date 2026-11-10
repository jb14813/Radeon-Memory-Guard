$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\RadeonMemoryGuard.psm1') -Force
$module=Get-Module RadeonMemoryGuard
$script:passed=0
function Assert($Value,$Message){if(-not $Value){throw $Message};$script:passed++}
Assert (& $module {[bool](Get-Command Read-RmgStorageState -ErrorAction SilentlyContinue)}) 'Storage ownership tracking is missing.'
$root=Join-Path $PSScriptRoot ('..\build\backend-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root -Force
$ledger=[pscustomobject]@{Schema=1;Provider='Arsenal';RootOwned=$false;MiniportOwned=$false;AweOwned=$false;PackageOwned=$false;DeviceInstanceId='';PublishedInf='oem79.inf';Phase='Ready';AuxiliaryOwned=@();AweOriginal=$null;Staging=$false;PriorPublishedInfs=@()}
$path=Join-Path $root 'storage-backend.json'
$ledger|ConvertTo-Json|Set-Content $path
Assert (& $module {[bool](Get-Command New-RmgStorageRegistrationCallback -ErrorAction SilentlyContinue)}) 'Crash-safe controller registration callback is missing.'
$callback=& $module {param($s,$p) New-RmgStorageRegistrationCallback $s $p} $ledger $path
$callback.Invoke('ROOT\SCSIADAPTER\0099')
$registered=Get-Content $path -Raw|ConvertFrom-Json
Assert ($registered.RootOwned -and $registered.DeviceInstanceId -eq 'ROOT\SCSIADAPTER\0099' -and $registered.Phase -eq 'Registered') 'Controller identity was not journaled at registration time.'
$ledger.RootOwned=$false;$ledger.DeviceInstanceId='';$ledger.Phase='Ready';$ledger|ConvertTo-Json|Set-Content $path
Assert ((& $module {param($r) Read-RmgStorageState $r} $root).Provider -eq 'Arsenal') 'Valid backend ledger rejected.'
$ledger.RootOwned='true';$ledger|ConvertTo-Json|Set-Content $path
$failed=$false;try{& $module {param($r) Read-RmgStorageState $r} $root}catch{$failed=$true}
Assert $failed 'A non-boolean ownership claim was accepted.'
$ledger.RootOwned=$true;$ledger.DeviceInstanceId='PCI\UNRELATED';$ledger|ConvertTo-Json|Set-Content $path
$failed=$false;try{& $module {param($r) Read-RmgStorageState $r} $root}catch{$failed=$true}
Assert $failed 'An unrelated device was accepted as owned.'
$ledger.RootOwned=$false;$ledger.DeviceInstanceId='';$ledger|ConvertTo-Json|Set-Content $path
& $module {
 function script:Read-RmgRamState($Root){[pscustomobject]@{Active=$false}}
 function script:Get-RmgStoragePorts {@()}
 function script:Get-CimInstance {param($ClassName,$Filter) throw 'Shared backend cleanup must not inspect or change drivers'}
}
$result=& $module {param($r) Remove-RmgStorageBackend $r} $root
Assert ($result.Status -eq 'PreservedShared') 'Shared storage dependencies were not preserved.'
& $module {
 $script:AuxRemoved=@();$script:AweRestored=$false
 function script:Set-Service {param($Name,$StartupType,$ErrorAction)}
 function script:Remove-RmgOwnedStorageService($Name){$script:AuxRemoved+=,$Name;if($Name -eq 'aimwrfltr'){throw 'Simulated one-service cleanup failure'}}
 function script:Restore-RmgAweConfiguration($Original){$script:AweRestored=$true}
}
$ledger.AuxiliaryOwned=@('aimwrfltr','vhdaccess');$ledger.AweOriginal=[pscustomobject]@{Start=3;ImagePath='test'};$ledger|ConvertTo-Json -Depth 6|Set-Content $path
$failed=$false;try{& $module {param($r,$s) Repair-RmgStorageAuxiliary $r $s} $root $ledger}catch{$failed=$true}
Assert ($failed -and (& $module {$script:AweRestored})) 'Auxiliary failure skipped restoring the shared allocator configuration.'
Assert ((& $module {$script:AuxRemoved}) -contains 'vhdaccess') 'One auxiliary failure prevented cleanup of later services.'
$partial=Get-Content $path -Raw|ConvertFrom-Json
Assert (@($partial.AuxiliaryOwned).Count -eq 1 -and $partial.AuxiliaryOwned[0] -eq 'aimwrfltr' -and $null -eq $partial.AweOriginal) 'Completed auxiliary cleanup was not checkpointed.'
& $module {function script:Remove-RmgOwnedStorageService($Name){$script:AuxRemoved+=,$Name}}
$null=& $module {param($r,$s) Repair-RmgStorageAuxiliary $r $s} $root $partial
Assert (@((Get-Content $path -Raw|ConvertFrom-Json).AuxiliaryOwned).Count -eq 0) 'Repair did not finish previously failed cleanup.'
& $module {
 $script:DisabledChanged=0
 function script:Remove-RmgOwnedStorageService($Name){throw 'Service identity changed'}
 function script:Get-RmgOwnedStorageServicePath($Name){throw 'Service identity changed'}
 function script:Set-Service {param($Name,$StartupType,$ErrorAction) $script:DisabledChanged++}
}
$partial.AuxiliaryOwned=@('deviosvc')
$failed=$false;try{& $module {param($r,$s) Repair-RmgStorageAuxiliary $r $s} $root $partial}catch{$failed=$true}
Assert ($failed -and (& $module {$script:DisabledChanged}) -eq 0) 'Repair disabled a service after its identity changed.'
& $module {
 $script:PackageAttempts=0;$script:AweDeletes=0
 function script:Get-CimInstance {param($ClassName,$Filter) @()}
 function script:Remove-RmgOwnedStorageService($Name){if($Name -eq 'AWEAlloc'){$script:AweDeletes++}}
 function script:Remove-RmgOwnedDriverPackage($Inf){$script:PackageAttempts++;if($script:PackageAttempts -eq 1){throw 'Simulated package still in use'}}
}
$ledger.AuxiliaryOwned=@();$ledger.AweOriginal=$null;$ledger.AweOwned=$true;$ledger.PackageOwned=$true;$ledger|ConvertTo-Json -Depth 6|Set-Content $path
$first=& $module {param($r) Remove-RmgStorageBackend $r} $root
Assert ($first.Status -eq 'BackendRetained') 'Partial package cleanup was not reported.'
$partial=Get-Content $path -Raw|ConvertFrom-Json
Assert (-not $partial.AweOwned -and $partial.PackageOwned) 'Successful allocator cleanup was not checkpointed separately.'
$second=& $module {param($r) Remove-RmgStorageBackend $r} $root
Assert ($second.Status -eq 'RemovedOwned' -and (& $module {$script:AweDeletes}) -eq 1 -and (& $module {$script:PackageAttempts}) -eq 2) 'Retry repeated completed cleanup instead of retrying package removal.'
Assert (& $module {[bool](Get-Command Assert-RmgStorageRegistrationAvailable -ErrorAction SilentlyContinue)}) 'Interrupted registration recovery guard is missing.'
& $module {function script:Get-PnpDevice {param($InstanceId,$ErrorAction) [pscustomobject]@{InstanceId=$InstanceId;Status='Unknown'}}}
$ledger.RootOwned=$true;$ledger.DeviceInstanceId='ROOT\SCSIADAPTER\0099'
$failed=$false;try{& $module {param($s) Assert-RmgStorageRegistrationAvailable $s} $ledger}catch{$failed=$true}
Assert ($failed -and $ledger.DeviceInstanceId -eq 'ROOT\SCSIADAPTER\0099') 'Retry can overwrite an existing unbound owned registration.'
$ledger.RootOwned=$false;$ledger.DeviceInstanceId=''
$packages=Join-Path $root 'packages';$null=New-Item -ItemType Directory -Path $packages
foreach($name in @('older','pinned')){$dir=Join-Path $packages $name;$null=New-Item -ItemType Directory -Path (Join-Path $dir 'x64') -Force;foreach($file in @('phdskmnt.inf','x64\phdskmnt.sys','x64\awealloc.sys')){[IO.File]::WriteAllText((Join-Path $dir $file),'inventory fixture')}}
& $module {
 param($p)
 $script:InventoryRoot=$p
 function script:Get-WindowsDriver {param([switch]$Online) @([pscustomobject]@{Driver='oem12.inf';OriginalFileName=(Join-Path $script:InventoryRoot 'older\phdskmnt.inf')},[pscustomobject]@{Driver='oem79.inf';OriginalFileName=(Join-Path $script:InventoryRoot 'pinned\phdskmnt.inf')})}
 function script:Get-FileHash {param($LiteralPath)
  $value=if($LiteralPath -like '*\older\*'){'old'}elseif($LiteralPath -like '*.inf'){'155F55BEF8B4F27581382A0C88B1A81382AF332917C7EA66276BFBD5D8903EED'}elseif($LiteralPath -like '*awealloc.sys'){$script:StorageHashes.AWEAlloc}else{$script:StorageHashes.phdskmnt}
  [pscustomobject]@{Hash=$value}
 }
} $packages
$pinned=@(& $module {Get-RmgPinnedStoragePackages})
Assert ($pinned.Count -eq 1 -and $pinned[0].Driver -eq 'oem79.inf') 'An older staged package made the pinned package ambiguous.'
$ledger.PackageOwned=$false;$ledger.Staging=$true;$ledger.PriorPublishedInfs=@('oem12.inf');$ledger.PublishedInf=''
& $module {param($r,$s) Recover-RmgStorageStaging $r $s} $root $ledger
Assert ($ledger.PackageOwned -and $ledger.PublishedInf -eq 'oem79.inf' -and -not $ledger.Staging) 'Staging interrupted after pnputil lost ownership of the newly added package.'
$ledger.Staging=$true;$ledger.PriorPublishedInfs=@('oem12.inf','oem79.inf')
& $module {param($r,$s) Recover-RmgStorageStaging $r $s} $root $ledger
Assert $ledger.PackageOwned 'A later setup retry forgot ownership of its previously staged package.'
& $module {function script:Read-RmgRamState($Root){[pscustomobject]@{Active=$true}}}
$failed=$false;try{& $module {param($r) Remove-RmgStorageBackend $r} $root}catch{$failed=$true}
Assert $failed 'Backend removal was allowed while RAM protection is active.'
$manifest=Get-Content (Join-Path $PSScriptRoot '..\installer\dependencies.json') -Raw|ConvertFrom-Json
Assert ((@($manifest.Artifacts.Name|Sort-Object) -join ',') -eq 'Arsenal-DriverFiles.zip,Arsenal-Image-Mounter-source.zip') 'Offline payload contains an unexpected dependency.'
Write-Output "Passed $script:passed backend assertions; no system driver or service was changed."
