$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\RadeonMemoryGuard.psm1') -Force
$module=Get-Module RadeonMemoryGuard
$root=Join-Path $PSScriptRoot ('..\build\native-fix-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
$script:passed=0
function Assert($condition,$message){if(-not $condition){throw $message};$script:passed++}
& $module {
 $script:NativeHash='84BF65785C9D59206D9800915FDD4B4A5CF13A702836347124328E7A780F57CD'
 $script:FakeDriver=[pscustomobject]@{Name='AMD test';Service='amduw23g-native-test';InstanceId='PCI\VEN_1002&DEV_TEST\1';Version='32.0.32029.2010';DriverHash=$script:NativeHash;Eligible=$true;Reason='Test driver'}
 $script:FakeValue=[pscustomobject]@{Exists=$false;Kind=$null;Value=$null}
 $script:Writes=0;$script:Binding=$true;$script:SvcReads=0;$script:ChangeSvcOnRead=0
 $script:Svc=[pscustomobject]@{Name='AMD External Events Utility';Present=$true;Trusted=$true;State='Running';Start=2;DelayedExists=$false;DelayedValue=0;DriverHash='unknown';Version='test';ClientHash='unknown'}
 function script:Assert-RmgAdmin {}
 function script:Initialize-RmgStateRoot($Path){$null=New-Item -ItemType Directory -Path $Path -Force}
 function script:Get-RmgDrivers {@($script:FakeDriver)}
 function script:Test-RmgBinding($Driver){$script:Binding}
 function script:Read-RmgRegistryValue($Service){$script:FakeValue}
 function script:Get-RmgExternalService {$script:SvcReads++;if($script:ChangeSvcOnRead -eq $script:SvcReads){$copy=$script:Svc.PSObject.Copy();$copy.DriverHash='updated-during-detection';return $copy};$script:Svc}
 function script:Write-RmgRegistryValue($Service,$Exists,$Value){$script:Writes++;$script:FakeValue=[pscustomobject]@{Exists=$Exists;Kind=$(if($Exists){'DWord'}else{$null});Value=$Value}}
}
function Seed-OwnedRecord([string]$Name,[bool]$OriginalExists,$OriginalValue,[string]$Hash='84BF65785C9D59206D9800915FDD4B4A5CF13A702836347124328E7A780F57CD'){
 $directory=Join-Path $root $Name;$null=New-Item -ItemType Directory -Path $directory
 [pscustomobject]@{Schema=1;Records=@([pscustomobject]@{Service='amduw23g-native-test';DriverHash=$Hash;Version='32.0.32029.2010';Original=[pscustomobject]@{Exists=$OriginalExists;Kind=$(if($OriginalExists){'DWord'}else{$null});Value=$OriginalValue};CapturedUtc=[DateTime]::UtcNow.ToString('o');LastAppliedUtc=[DateTime]::UtcNow.ToString('o');Restored=$false})}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $directory 'state.json') -Encoding UTF8
 return $directory
}
$result=@(Invoke-RmgApply -StateRoot (Join-Path $root 'clean'))
Assert ($result[0].Status -eq 'NativeDriverFixed') 'A verified fixed driver must not receive the memory workaround.'
Assert ((& $module {$script:Writes}) -eq 0) 'A clean fixed driver was modified.'
Assert (-not (Test-Path -LiteralPath (Join-Path $root 'clean\state.json'))) 'A clean fixed driver acquired a synthetic original setting.'
& $module {$script:FakeValue=[pscustomobject]@{Exists=$true;Kind='DWord';Value=0}}
$owned=Seed-OwnedRecord 'owned-absent' $false $null
$result=@(Invoke-RmgApply -StateRoot $owned)
Assert ($result[0].Status -eq 'NativeDriverFixedNeedsReload') 'An owned memory override must be retired with an honest activation status.'
Assert (-not (& $module {$script:FakeValue.Exists})) 'The originally absent value was not restored.'
Assert ((Get-Content -LiteralPath (Join-Path $owned 'state.json') -Raw|ConvertFrom-Json).Records[0].Restored) 'Successful retirement was not recorded.'
$writes=& $module {$script:Writes};$null=Invoke-RmgApply -StateRoot $owned
Assert ((& $module {$script:Writes}) -eq $writes) 'Repeated maintenance reapplied or rewrote a retired override.'
& $module {$script:FakeValue=[pscustomobject]@{Exists=$true;Kind='DWord';Value=0}}
$owned=Seed-OwnedRecord 'owned-one' $true 1;$null=Invoke-RmgApply -StateRoot $owned
Assert ((& $module {$script:FakeValue.Value}) -eq 1) 'The original native mode was not restored.'
& $module {$script:FakeValue=[pscustomobject]@{Exists=$true;Kind='DWord';Value=2}}
$owned=Seed-OwnedRecord 'administrator-change' $false $null
$result=@(Invoke-RmgApply -StateRoot $owned)
Assert ($result[0].Status -eq 'NativeFixRestoreConflict' -and (& $module {$script:FakeValue.Value}) -eq 2) 'A later administrator change was overwritten.'
& $module {$script:FakeValue=[pscustomobject]@{Exists=$true;Kind='DWord';Value=0}}
$owned=Seed-OwnedRecord 'different-record-image' $false $null ('A'*64)
$result=@(Invoke-RmgApply -StateRoot $owned)
Assert ($result[0].Status -eq 'NativeFixRestoreConflict' -and (& $module {$script:FakeValue.Exists})) 'A backup belonging to another image was automatically restored.'
& $module {$script:FakeValue=[pscustomobject]@{Exists=$false;Kind=$null;Value=$null};$script:FakeDriver.DriverHash='A'*64}
$result=@(Invoke-RmgApply -StateRoot (Join-Path $root 'same-version-other-image'))
Assert ($result[0].Status -eq 'AppliedNeedsReload') 'A matching version label alone was treated as proven fixed.'
& $module {$script:FakeDriver.DriverHash=$script:NativeHash;$script:FakeDriver.Eligible=$false}
$writes=& $module {$script:Writes};$result=@(Invoke-RmgApply -StateRoot (Join-Path $root 'untrusted'))
Assert ($result[0].Status -eq 'SkippedUnsupported' -and (& $module {$script:Writes}) -eq $writes) 'An untrusted driver was accepted as fixed.'
& $module {$script:FakeDriver.Eligible=$true;$script:Binding=$false}
$result=@(Invoke-RmgApply -StateRoot (Join-Path $root 'binding-changed'))
Assert ($result[0].Status -eq 'SkippedBindingChanged') 'A changed active binding was accepted during retirement.'
& $module {$script:Binding=$true;$script:FakeValue=[pscustomobject]@{Exists=$true;Kind='DWord';Value=0}}
$owned=Seed-OwnedRecord 'whatif' $false $null;$writes=& $module {$script:Writes}
$null=Invoke-RmgApply -StateRoot $owned -WhatIf
Assert ((& $module {$script:Writes}) -eq $writes -and -not (Get-Content -LiteralPath (Join-Path $owned 'state.json') -Raw|ConvertFrom-Json).Records[0].Restored) 'WhatIf changed an override or ownership ledger.'
& $module {
 $script:Svc.DriverHash='220E65D90CCC546CB93C14B7469906B681F38B619A838129005F3B54583A5F30'
 $script:Svc.ClientHash='BC31696C0CA9361C55BB5FF34BF28E327FEF1ECD4C22C87A0852E66BF4C0CD28'
 $script:RamReady=$false;$script:RamBuilds=0;$script:RamRetires=0;$script:ServiceChanges=0
 function script:Initialize-RmgRamCache($Root){$script:RamBuilds++;$script:RamReady=$true}
 function script:Remove-RmgRamCache($Root){$script:RamRetires++;$script:RamReady=$false}
 function script:Set-RmgExternalService($Start,$Running,$DelayedExists,$DelayedValue){$script:ServiceChanges++;$script:Svc.Start=$Start;$script:Svc.State=$(if($Running){'Running'}else{'Stopped'});$script:Svc.DelayedExists=$DelayedExists;$script:Svc.DelayedValue=$DelayedValue}
 function script:Get-RmgBackendPackage {throw 'A fixed native driver must not download RAM dependencies'}
}
$result=Invoke-RmgProtectSsdRam -StateRoot (Join-Path $root 'native-ssd-clean')
Assert ($result.Status -eq 'NativeDriverFixed' -and (& $module {$script:RamBuilds}) -eq 0 -and (& $module {$script:ServiceChanges}) -eq 0) 'A clean native SSD fix allocated RAM or interrupted AMD.'
Assert (-not (Test-Path -LiteralPath (Join-Path $root 'native-ssd-clean\ssd-policy.json'))) 'A clean native SSD fix acquired an unnecessary protection policy.'
$result=Install-RmgRamBackend -StateRoot (Join-Path $root 'native-no-backend') -Offline
Assert ($result.NativeFix -and $result.Provider -eq 'AMD') 'A fixed driver installed or downloaded redundant storage dependencies.'
$legacy=Join-Path $root 'native-retire-ram';$null=New-Item -ItemType Directory -Path $legacy
@{Schema=1;Enabled=$true;Restored=$false;Mode='Ram';Original=@{Start=2;Running=$true;DelayedExists=$false;DelayedValue=0}}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $legacy 'ssd-policy.json') -Encoding UTF8
& $module {$script:RamReady=$true;$script:Svc.Start=3}
$result=@(Invoke-RmgApply -StateRoot $legacy)
$last=Get-Content -LiteralPath (Join-Path $legacy 'last-run.json') -Raw|ConvertFrom-Json
$policy=Get-Content -LiteralPath (Join-Path $legacy 'ssd-policy.json') -Raw|ConvertFrom-Json
Assert ($last.Ssd.Status -eq 'NativeDriverFixed' -and (& $module {$script:RamRetires}) -eq 1) 'Maintenance did not retire the owned legacy RAM cache.'
Assert (-not $policy.Enabled -and $policy.Restored -and (& $module {$script:Svc.Start}) -eq 2 -and (& $module {$script:Svc.State}) -eq 'Running') 'Native retirement did not restore original startup and disable redundant enforcement.'
$changes=& $module {$script:ServiceChanges};$null=Invoke-RmgApply -StateRoot $legacy
Assert ((& $module {$script:ServiceChanges}) -eq $changes) 'Healthy native maintenance restarted AMD again.'
& $module {$script:Svc.ClientHash='different-image'}
Assert (-not (& $module {Test-RmgNativeSsdFix})) 'A changed External Events client was declared validated.'
& $module {$script:Svc.ClientHash='BC31696C0CA9361C55BB5FF34BF28E327FEF1ECD4C22C87A0852E66BF4C0CD28';$script:Svc.Trusted=$false}
Assert (-not (& $module {Test-RmgNativeSsdFix})) 'An untrusted External Events service was declared fixed.'
& $module {$script:Svc.Trusted=$true;$script:Svc.Start=3;$script:SvcReads=0;$script:ChangeSvcOnRead=2;$script:RamReady=$true}
$race=Join-Path $root 'native-update-race';$null=New-Item -ItemType Directory -Path $race
@{Schema=1;Enabled=$true;Restored=$false;Mode='Ram';Original=@{Start=2;Running=$true;DelayedExists=$false;DelayedValue=0}}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $race 'ssd-policy.json') -Encoding UTF8
$retired=& $module {$script:RamRetires};$changes=& $module {$script:ServiceChanges};$failed=$false
try{$null=Invoke-RmgApply -StateRoot $race}catch{$failed=$true}
Assert ($failed -and (& $module {$script:RamRetires}) -eq $retired -and (& $module {$script:ServiceChanges}) -eq $changes) 'A concurrent vendor update was modified during retirement.'
Assert ((Get-Content -LiteralPath (Join-Path $race 'ssd-policy.json') -Raw|ConvertFrom-Json).Enabled) 'An interrupted retirement discarded its recovery policy.'
Write-Output "Passed $script:passed native-driver assertions. Machine driver settings were mocked."
