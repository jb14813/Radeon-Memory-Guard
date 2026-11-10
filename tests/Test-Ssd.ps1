$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\RadeonMemoryGuard.psm1') -Force
$module=Get-Module RadeonMemoryGuard
$root=Join-Path $PSScriptRoot ('..\build\ssd-tests-'+[guid]::NewGuid().ToString('N'))
$script:passed=0
function Assert($condition,$message){if(-not $condition){throw $message};$script:passed++}
Assert ($null -ne (Get-Command Invoke-RmgProtectSsd -ErrorAction SilentlyContinue)) 'SSD protection action is not implemented.'
& $module {
 $script:Svc=[pscustomobject]@{Name='AMD External Events Utility';Present=$true;Trusted=$true;Reason='Test service';State='Running';Start=2;DelayedExists=$false;DelayedValue=0;DriverHash='test';Version='test'}
 $script:Changes=0;$script:FailChange=$false
 function script:Assert-RmgAdmin {}
 function script:Initialize-RmgStateRoot($Path){$null=New-Item -ItemType Directory -Path $Path -Force}
 function script:Get-RmgExternalService {$script:Svc}
 function script:Get-RmgDrivers {@()}
 function script:Set-RmgExternalService($Start,$Running,$DelayedExists,$DelayedValue){
  $script:Changes++
  if($script:FailChange){return}
  $script:Svc.Start=$Start;$script:Svc.State=$(if($Running){'Running'}else{'Stopped'})
  if($Start -ne 4){$script:Svc.DelayedExists=$DelayedExists;$script:Svc.DelayedValue=$DelayedValue}
 }
}
$one=Join-Path $root 'one'
$result=Invoke-RmgProtectSsd -StateRoot $one
Assert ($result.Status -eq 'Protected') 'SSD protection did not report success.'
Assert ((& $module {$script:Svc.Start}) -eq 4 -and (& $module {$script:Svc.State}) -eq 'Stopped') 'The service was not disabled and stopped.'
$policy=Get-Content -LiteralPath (Join-Path $one 'ssd-policy.json') -Raw | ConvertFrom-Json
Assert ($policy.Enabled -and $policy.Original.Start -eq 2 -and $policy.Original.Running) 'Original startup and running state were not backed up.'
$changes=& $module {$script:Changes}
$null=Invoke-RmgProtectSsd -StateRoot $one
Assert ((& $module {$script:Changes}) -eq $changes) 'Already-protected service was changed again.'
& $module {$script:Svc.Start=2;$script:Svc.State='Running'}
$result=& $module {param($r) Invoke-RmgSsdEnforcement $r} $one
Assert ($result.Status -eq 'Protected' -and (& $module {$script:Svc.Start}) -eq 4) 'An update resetting the service was not corrected.'
$policy=Get-Content -LiteralPath (Join-Path $one 'ssd-policy.json') -Raw | ConvertFrom-Json
Assert ($policy.Original.Start -eq 2) 'Maintenance overwrote the original backup.'
$null=Invoke-RmgApply -StateRoot $one
$last=Get-Content -LiteralPath (Join-Path $one 'last-run.json') -Raw | ConvertFrom-Json
Assert ($last.Ssd.Status -eq 'Protected') 'Scheduled Apply did not include opted-in SSD enforcement.'
$restored=Invoke-RmgRestoreSsd -StateRoot $one
Assert ($restored.Status -eq 'Restored' -and (& $module {$script:Svc.Start}) -eq 2 -and (& $module {$script:Svc.State}) -eq 'Running') 'Restore did not restore Automatic and Running.'
$changes=& $module {$script:Changes}
$null=& $module {param($r) Invoke-RmgSsdEnforcement $r} $one
Assert ((& $module {$script:Changes}) -eq $changes) 'Disabled opt-in policy was still enforced.'
& $module {$script:Svc.Start=3;$script:Svc.State='Stopped'}
$manual=Join-Path $root 'manual';$null=Invoke-RmgProtectSsd -StateRoot $manual;$null=Invoke-RmgRestoreSsd -StateRoot $manual
Assert ((& $module {$script:Svc.Start}) -eq 3 -and (& $module {$script:Svc.State}) -eq 'Stopped') 'Manual/stopped configuration was not restored.'
& $module {$script:Svc.Start=2;$script:Svc.State='Running';$script:Svc.DelayedExists=$true;$script:Svc.DelayedValue=1}
$delay=Join-Path $root 'delayed';$null=Invoke-RmgProtectSsd -StateRoot $delay;$null=Invoke-RmgRestoreSsd -StateRoot $delay
Assert ((& $module {$script:Svc.DelayedExists}) -and (& $module {$script:Svc.DelayedValue}) -eq 1) 'Delayed automatic startup was not preserved.'
$conflict=Join-Path $root 'conflict';$null=Invoke-RmgProtectSsd -StateRoot $conflict
& $module {$script:Svc.Start=3;$script:Svc.State='Running'}
$result=Invoke-RmgRestoreSsd -StateRoot $conflict
Assert ($result.Status -eq 'RestoreConflict' -and (& $module {$script:Svc.Start}) -eq 3) 'Restore overwrote a later administrator change.'
$policy=Get-Content -LiteralPath (Join-Path $conflict 'ssd-policy.json') -Raw | ConvertFrom-Json
Assert (-not $policy.Enabled) 'Restore left automatic SSD enforcement enabled.'
& $module {$script:Svc.Trusted=$false}
$changes=& $module {$script:Changes};$failed=$false
try{$null=Invoke-RmgProtectSsd -StateRoot (Join-Path $root 'untrusted')}catch{$failed=$true}
Assert ($failed -and (& $module {$script:Changes}) -eq $changes) 'An untrusted service was modified.'
& $module {$script:Svc.Trusted=$true}
$null=Invoke-RmgProtectSsd -StateRoot (Join-Path $root 'whatif') -WhatIf
Assert (-not (Test-Path -LiteralPath (Join-Path $root 'whatif\ssd-policy.json'))) 'WhatIf wrote an opt-in policy.'
& $module {$script:Svc.Start=2;$script:Svc.State='Running';$script:FailChange=$true}
$failed=$false;try{$null=Invoke-RmgProtectSsd -StateRoot (Join-Path $root 'failure')}catch{$failed=$true}
Assert $failed 'Failed service changes were not detected.'
$policy=Get-Content -LiteralPath (Join-Path $root 'failure\ssd-policy.json') -Raw | ConvertFrom-Json
Assert ($policy.Original.Start -eq 2 -and $policy.Original.Running) 'A failed service change lost its backup.'
& $module {$script:FailChange=$false}
$retry=Join-Path $root 'retry';$null=Invoke-RmgProtectSsd -StateRoot $retry
& $module {$script:FailChange=$true}
$failed=$false;try{$null=Invoke-RmgRestoreSsd -StateRoot $retry}catch{$failed=$true}
Assert $failed 'A failed restoration was not detected.'
$failed=$false;try{$null=Invoke-RmgProtectSsd -StateRoot $retry}catch{$failed=$true}
$policy=Get-Content -LiteralPath (Join-Path $retry 'ssd-policy.json') -Raw | ConvertFrom-Json
Assert ($failed -and $policy.Original.Start -eq 2 -and -not $policy.Enabled) 'Re-enabling an unresolved restore replaced its original backup.'
& $module {$script:FailChange=$false}
$result=Invoke-RmgRestoreSsd -StateRoot $retry
Assert ($result.Status -eq 'Restored') 'A failed restore could not be retried.'
$none=Join-Path $root 'default';$changes=& $module {$script:Changes}
$null=Invoke-RmgApply -StateRoot $none
Assert ((& $module {$script:Changes}) -eq $changes) 'Default maintenance modified a service without opt-in.'
$bad=Join-Path $root 'corrupt';$null=New-Item -ItemType Directory -Path $bad -Force
'{"Schema":1,"Enabled":true}' | Set-Content -LiteralPath (Join-Path $bad 'ssd-policy.json')
$failed=$false;try{$null=& $module {param($r) Invoke-RmgSsdEnforcement $r} $bad}catch{$failed=$true}
Assert ($failed -and (& $module {$script:Changes}) -eq $changes) 'Corrupt policy did not fail before modifying the service.'
Write-Output "Passed $script:passed SSD assertions. No real service was modified."
