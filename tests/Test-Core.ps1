$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\RadeonMemoryGuard.psm1') -Force
$module = Get-Module RadeonMemoryGuard
$root = Join-Path $PSScriptRoot ('..\build\tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root -Force
$script:passed = 0
function Assert($condition, $message) {
    if (-not $condition) { throw $message }
    $script:passed++
}
& $module {
    param($FirstBackup)
    $script:FirstBackup=$FirstBackup
    $script:FakeValue = [pscustomobject]@{ Exists=$true; Kind='DWord'; Value=1 }
    $script:FakeDrivers = @([pscustomobject]@{ Service='amduw23g-test-one'; InstanceId='PCI\VEN_1002&DEV_TEST\1'; DriverHash=('A'*64); Version='1'; Eligible=$true; Reason='Supported setting found'; Name='AMD test adapter' })
    $script:Writes = 0
    $script:BindingChanged = $false
    $script:FailWrite = $false
    function script:Assert-RmgAdmin {}
    function script:Initialize-RmgStateRoot($Path) { $null=New-Item -ItemType Directory -Path $Path -Force }
    function script:Get-RmgDrivers { $script:FakeDrivers }
    function script:Read-RmgRegistryValue($Service) { $script:FakeValue }
    function script:Write-RmgRegistryValue($Service,$Exists,$Value) {
        if($script:Writes -eq 0) {
            if(-not (Test-Path -LiteralPath $script:FirstBackup)){throw 'Registry write occurred before backup publication.'}
            $backup=Get-Content -LiteralPath $script:FirstBackup -Raw | ConvertFrom-Json
            if($backup.Records[0].Original.Value -ne 1){throw 'Backup did not preserve the pre-write value.'}
        }
        $script:Writes++
        if($script:FailWrite){return}
        $script:FakeValue=[pscustomobject]@{ Exists=$Exists; Kind=$(if($Exists){'DWord'}else{$null}); Value=$Value }
    }
    function script:Test-RmgBinding($Driver) { -not $script:BindingChanged }
} (Join-Path $root 'one\state.json')
$first = @(Invoke-RmgApply -StateRoot (Join-Path $root 'one'))
Assert ($first[0].Status -eq 'AppliedNeedsReload') 'First application must explicitly require activation.'
Assert ((& $module { $script:FakeValue.Value }) -eq 0) 'Apply did not set zero.'
$ledger = Get-Content -LiteralPath (Join-Path $root 'one\state.json') -Raw | ConvertFrom-Json
Assert ($ledger.Records[0].Original.Value -eq 1) 'Original value was not saved.'
$null = Invoke-RmgApply -StateRoot (Join-Path $root 'one')
Assert ((& $module { $script:Writes }) -eq 1) 'Idempotent application wrote again.'
$null = Invoke-RmgRestore -StateRoot (Join-Path $root 'one')
Assert ((& $module { $script:FakeValue.Value }) -eq 1) 'Restore lost the original value.'
& $module { $script:FakeValue=[pscustomobject]@{Exists=$false;Kind=$null;Value=$null} }
$null = Invoke-RmgApply -StateRoot (Join-Path $root 'absent')
$null = Invoke-RmgRestore -StateRoot (Join-Path $root 'absent')
Assert (-not (& $module { $script:FakeValue.Exists })) 'Restore did not restore absence.'
& $module { $script:FakeValue=[pscustomobject]@{Exists=$true;Kind='String';Value='custom'} }
$blocked = @(Invoke-RmgApply -StateRoot (Join-Path $root 'wrong-type'))
Assert ($blocked[0].Status -eq 'SkippedUnexpectedValueType') 'Unexpected types must be preserved.'
& $module { $script:FakeDrivers[0].Eligible=$false }
$blocked = @(Invoke-RmgApply -StateRoot (Join-Path $root 'unsupported'))
Assert ($blocked[0].Status -eq 'SkippedUnsupported') 'Unsupported drivers must not be modified.'
& $module { $script:FakeDrivers[0].Eligible=$true; $script:FakeValue=[pscustomobject]@{Exists=$true;Kind='DWord';Value=1}; $script:BindingChanged=$true }
$blocked = @(Invoke-RmgApply -StateRoot (Join-Path $root 'binding-changed'))
Assert ($blocked[0].Status -eq 'SkippedBindingChanged') 'Driver replacement during discovery must stop a write.'
& $module { $script:BindingChanged=$false }
$null = Invoke-RmgApply -StateRoot (Join-Path $root 'conflict')
& $module { $script:FakeValue=[pscustomobject]@{Exists=$true;Kind='DWord';Value=2} }
$restored = @(Invoke-RmgRestore -StateRoot (Join-Path $root 'conflict'))
Assert ($restored[0].Status -eq 'RestoreConflict') 'Restore must preserve later administrator changes.'
& $module { $script:FakeDrivers[0].Service='amduw23g-new-driver-service'; $script:FakeValue=[pscustomobject]@{Exists=$true;Kind='DWord';Value=1} }
$updated = @(Invoke-RmgApply -StateRoot (Join-Path $root 'one'))
Assert ($updated[0].Service -eq 'amduw23g-new-driver-service') 'A changed service name was not rediscovered.'
$ledger = Get-Content -LiteralPath (Join-Path $root 'one\state.json') -Raw | ConvertFrom-Json
Assert (@($ledger.Records).Count -eq 2) 'New services need independent backup records.'
$before = & $module { $script:Writes }
$null = Invoke-RmgApply -StateRoot (Join-Path $root 'whatif') -WhatIf
Assert ((& $module { $script:Writes }) -eq $before) 'WhatIf modified a setting.'
Assert (-not (Test-Path -LiteralPath (Join-Path $root 'whatif\state.json'))) 'WhatIf created a ledger.'
$badRoot=Join-Path $root 'corrupt';$null=New-Item -ItemType Directory -Path $badRoot
Set-Content -LiteralPath (Join-Path $badRoot 'state.json') -Value '{invalid'
$failed=$false;try{$null=Invoke-RmgApply -StateRoot $badRoot}catch{$failed=$true}
Assert $failed 'A corrupt ledger must fail before modifying the registry.'
& $module {$script:FailWrite=$true;$script:FakeValue=[pscustomobject]@{Exists=$true;Kind='DWord';Value=1}}
$failed=$false;try{$null=Invoke-RmgApply -StateRoot (Join-Path $root 'write-failure')}catch{$failed=$true}
Assert $failed 'A failed registry write was not detected by readback.'
$safe=Get-Content -LiteralPath (Join-Path $root 'write-failure\state.json') -Raw | ConvertFrom-Json
Assert ($safe.Records[0].Original.Value -eq 1) 'Failed writes must retain the original backup.'
$markerPath=Join-Path $root 'marker.bin'
$marker=[Text.Encoding]::Unicode.GetBytes("Gmx_MgpuProcessWatcherSupport`0")
$bytes=New-Object byte[] (262140+$marker.Length)
[Array]::Copy($marker,0,$bytes,262140,$marker.Length)
[IO.File]::WriteAllBytes($markerPath,$bytes)
Assert (& $module {param($p) Test-RmgMarker $p} $markerPath) 'A setting marker split across read buffers was missed.'
[IO.File]::WriteAllBytes($markerPath,[Text.Encoding]::Unicode.GetBytes('Gmx_MgpuProcessWatcherSupport'))
Assert (-not (& $module {param($p) Test-RmgMarker $p} $markerPath)) 'An unterminated fragment was accepted as a setting.'
[IO.File]::WriteAllText($markerPath,'Unrelated driver data')
Assert (-not (& $module {param($p) Test-RmgMarker $p} $markerPath)) 'Unsupported driver bytes passed the marker probe.'
Write-Output "Passed $script:passed core assertions. No machine registry or scheduled task was modified."
