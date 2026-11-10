$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\RadeonMemoryGuard.psm1') -Force
$module=Get-Module RadeonMemoryGuard
$root=Join-Path $PSScriptRoot ('..\build\ram-tests-'+[guid]::NewGuid().ToString('N'))
$script:passed=0
function Assert($condition,$message){if(-not $condition){throw $message};$script:passed++}
Assert ($null -ne (Get-Command Invoke-RmgProtectSsdRam -ErrorAction SilentlyContinue)) 'RAM protection action is not implemented.'
& $module {
 $script:Svc=[pscustomobject]@{Name='AMD External Events Utility';Present=$true;Trusted=$true;Reason='Test';State='Stopped';Start=4;DelayedExists=$false;DelayedValue=0;DriverHash='test';Version='test'}
 $script:RamReady=$false;$script:RamBuilds=0;$script:RamRetires=0;$script:RamFail=$false;$script:ServiceChanges=0
 function script:Assert-RmgAdmin {}
 function script:Initialize-RmgStateRoot($Path){$null=New-Item -ItemType Directory -Path $Path -Force}
 function script:Get-RmgExternalService {$script:Svc}
 function script:Get-RmgRamCacheStatus($StateRoot){[pscustomobject]@{Ready=$script:RamReady;CapacityBytes=64MB}}
 function script:Initialize-RmgRamCache($StateRoot){$script:RamBuilds++;if($script:RamFail){throw 'Simulated RAM provider failure'};$script:RamReady=$true}
 function script:Remove-RmgRamCache($StateRoot){$script:RamRetires++;$script:RamReady=$false}
 function script:Set-RmgExternalService($Start,$Running,$DelayedExists,$DelayedValue){$script:ServiceChanges++;$script:Svc.Start=$Start;$script:Svc.State=$(if($Running){'Running'}else{'Stopped'});$script:Svc.DelayedExists=$DelayedExists;$script:Svc.DelayedValue=$DelayedValue}
}
$one=Join-Path $root 'one';$null=New-Item -ItemType Directory -Path $one -Force
@{Schema=1;Enabled=$true;Restored=$false;CapturedUtc='test';Original=@{Start=2;Running=$true;DelayedExists=$false;DelayedValue=0};DriverHash='test';Version='test'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $one 'ssd-policy.json')
$result=Invoke-RmgProtectSsdRam -StateRoot $one
Assert ($result.Status -eq 'ProtectedInRam') 'RAM protection did not report success.'
Assert ((& $module {$script:Svc.State}) -eq 'Running' -and (& $module {$script:Svc.Start}) -eq 3) 'The AMD service was not kept running with controlled startup.'
$policy=Get-Content -LiteralPath (Join-Path $one 'ssd-policy.json') -Raw | ConvertFrom-Json
Assert ($policy.Mode -eq 'Ram' -and $policy.Original.Start -eq 2 -and $policy.Original.Running) 'Switching protection modes lost the original service backup.'
$builds=& $module {$script:RamBuilds};$changes=& $module {$script:ServiceChanges}
$null=& $module {param($r) Invoke-RmgSsdEnforcement $r} $one
Assert ((& $module {$script:RamBuilds}) -eq $builds -and (& $module {$script:ServiceChanges}) -eq $changes) 'Healthy RAM protection unnecessarily restarted the service or volume.'
& $module {$script:RamReady=$false}
$result=& $module {param($r) Invoke-RmgSsdEnforcement $r} $one
Assert ($result.Status -eq 'ProtectedInRam' -and (& $module {$script:Svc.State}) -eq 'Running') 'Missing RAM storage was not rebuilt before restarting AMD.'
& $module {$script:RamReady=$false;$script:RamFail=$true}
$failed=$false;try{$null=& $module {param($r) Invoke-RmgSsdEnforcement $r} $one}catch{$failed=$true}
Assert ($failed -and (& $module {$script:Svc.State}) -eq 'Stopped') 'RAM initialization failure started AMD on an unprotected destination.'
& $module {$script:RamFail=$false}
$null=& $module {param($r) Invoke-RmgSsdEnforcement $r} $one
$restored=Invoke-RmgRestoreSsd -StateRoot $one
Assert ($restored.Status -eq 'Restored' -and (& $module {$script:RamRetires}) -eq 1) 'Restoring RAM mode did not release its storage.'
Assert ((& $module {$script:Svc.Start}) -eq 2 -and (& $module {$script:Svc.State}) -eq 'Running') 'RAM restoration did not restore the original AMD service configuration.'
$null=Invoke-RmgProtectSsdRam -StateRoot (Join-Path $root 'whatif') -WhatIf
Assert (-not (Test-Path -LiteralPath (Join-Path $root 'whatif\ssd-policy.json'))) 'WhatIf modified RAM protection policy.'
$ledgerRoot=Join-Path $root 'ledger';$null=New-Item -ItemType Directory -Path $ledgerRoot -Force
$source=& $module {$script:RamSource};$backup=& $module {$script:RamBackup}
$ledger=[pscustomobject]@{Schema=1;Id=('a'*32);Source=$source;Backup=$backup;CapacityBytes=64MB;OriginalExists=$false;OriginalHash='';Active=$true;Phase='Creating';VolumeRoot='';Target='';PreviousTarget='';DiskNumber=-1;DiskUniqueId=''}
$ledger | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ledgerRoot 'ram-cache.json')
$read=& $module {param($r) Read-RmgRamState $r} $ledgerRoot
Assert ($read.CapacityBytes -eq 64MB) 'Valid RAM ledger was rejected.'
$ledger.Source='C:\unrelated.exe';$ledger | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ledgerRoot 'ram-cache.json')
$failed=$false;try{$null=& $module {param($r) Read-RmgRamState $r} $ledgerRoot}catch{$failed=$true}
Assert $failed 'A ledger selecting another executable was accepted.'
$ledger.Source=$source;$ledger.CapacityBytes=128MB;$ledger | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ledgerRoot 'ram-cache.json')
$failed=$false;try{$null=& $module {param($r) Read-RmgRamState $r} $ledgerRoot}catch{$failed=$true}
Assert $failed 'An unexpected RAM allocation size was accepted.'
& $module {Initialize-RmgRamNative}
$failed=$false;try{$null=[RmgRamNative]::IsPhysicalMemory(999,0)}catch{$failed=$true}
Assert $failed 'An invalid adapter number reached a storage request.'
$failed=$false;try{[RmgRamNative]::Remove(0,[uint32]::MaxValue)}catch{$failed=$true}
Assert $failed 'The all-devices sentinel was accepted for RAM removal.'
$update=Join-Path $root 'update';$null=Invoke-RmgProtectSsdRam -StateRoot $update
& $module {$script:Svc.Start=2;$script:Svc.State='Running'}
$result=Invoke-RmgRestoreSsd -StateRoot $update
Assert ($result.Status -eq 'Restored' -and (& $module {$script:Svc.Start}) -eq 2) 'An update resetting Automatic startup prevented RAM restoration.'
$failure=Join-Path $root 'restore-failure';$null=Invoke-RmgProtectSsdRam -StateRoot $failure
& $module {function script:Remove-RmgRamCache($StateRoot){throw 'Simulated detach failure'}}
$failed=$false;try{$null=Invoke-RmgRestoreSsd -StateRoot $failure}catch{$failed=$true}
$policy=Get-Content -LiteralPath (Join-Path $failure 'ssd-policy.json') -Raw | ConvertFrom-Json
Assert ($failed -and $policy.Enabled) 'Failed RAM cleanup disabled the startup recovery policy.'
& $module {
 param($r)
 $script:DefaultState=$r;$script:InstallRoot=Join-Path $r 'fake-program-files';$script:TaskRemoved=$false
 function script:Read-RmgRamState($Root){[pscustomobject]@{Active=$true}}
 function script:Invoke-RmgRestoreSsd {[pscustomobject]@{Status='RestoreConflict'}}
 function script:Stop-RmgMaintenance {param([switch]$KeepRegistration)$script:TaskRemoved=$true}
} $failure
$failed=$false;try{$null=Uninstall-RmgMaintenance}catch{$failed=$true}
Assert ($failed -and -not (& $module {$script:TaskRemoved})) 'Uninstall removed recovery maintenance while RAM restoration was incomplete.'
$policy.Enabled=$false;$policy | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $failure 'ssd-policy.json')
$failed=$false;try{$null=Uninstall-RmgMaintenance -KeepSetting}catch{$failed=$true}
Assert ($failed -and -not (& $module {$script:TaskRemoved})) 'KeepSetting stranded an active RAM cache after an earlier restore conflict.'
Write-Output "Passed $script:passed RAM assertions. No machine service, cache, or volume was modified."
