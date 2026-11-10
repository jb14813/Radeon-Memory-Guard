param([string]$PayloadRoot=(Join-Path $PSScriptRoot '..\build\offline-payload'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\RadeonMemoryGuard.psm1') -Force
$module=Get-Module RadeonMemoryGuard
$script:passed=0
function Assert($Value,$Message){if(-not $Value){throw $Message};$script:passed++}
Assert (& $module {[bool](Get-Command Get-RmgBackendPackage -ErrorAction SilentlyContinue)}) 'Offline package selection is not implemented.'
$root=Join-Path $PSScriptRoot ('..\build\offline-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root -Force
& $module {
 function script:Invoke-WebRequest {throw 'Network call was attempted during offline setup'}
 function script:Assert-RmgAdmin {}
 function script:Initialize-RmgStateRoot($Path){$null=New-Item -ItemType Directory -Path $Path -Force}
}
foreach($name in @('osfmount-3.3.1000.exe','Arsenal-DriverFiles.zip')){
 $file=& $module {param($r,$p,$n) Get-RmgBackendPackage -Root $r -PayloadRoot $p -Name $n -Offline} (Join-Path $root 'cache') $PayloadRoot $name
 Assert ([IO.File]::Exists($file)) ('Offline package missing: '+$name)
 Assert ((Get-FileHash $file).Hash -eq (Get-FileHash (Join-Path $PayloadRoot $name)).Hash) 'Bundled package was changed during staging.'
}
$failed=$false
try{& $module {param($r,$p) Get-RmgBackendPackage -Root $r -PayloadRoot $p -Name 'Arsenal-DriverFiles.zip' -Offline} (Join-Path $root 'missing-cache') (Join-Path $root 'missing-payload')}catch{$failed=$true;Assert ($_.Exception.Message -match 'offline|bundled|payload') 'Missing payload fell through to a network request.'}
Assert $failed 'Offline setup accepted a missing payload.'
$bad=Join-Path $root 'bad';$null=New-Item -ItemType Directory -Path $bad
[IO.File]::WriteAllText((Join-Path $bad 'osfmount-3.3.1000.exe'),'untrusted replacement')
$failed=$false
try{& $module {param($r,$p) Get-RmgBackendPackage -Root $r -PayloadRoot $p -Name 'osfmount-3.3.1000.exe' -Offline} (Join-Path $root 'bad-cache') $bad}catch{$failed=$true;Assert ($_.Exception.Message -match 'checksum|hash') 'Wrong error for a corrupted vendor payload.'}
Assert $failed 'Offline setup accepted a corrupted installer.'
$savedProgramFiles=$env:ProgramFiles
try {
 $env:ProgramFiles=Join-Path $root 'fake-program-files'
 & $module {
  $script:OsfInstalls=0;$script:AweInstalls=0;$script:AwePresent=$false
  function script:Get-CimInstance {param($ClassName,$Filter) if($script:AwePresent){[pscustomobject]@{Name='AWEAlloc'}}}
  function script:Install-RmgOsfMount($Setup){if(-not [IO.File]::Exists($Setup)){throw 'OSF payload missing'};$script:OsfInstalls++;$dir=Join-Path $env:ProgramFiles 'OSFMount';$null=New-Item -ItemType Directory -Path $dir -Force;[IO.File]::WriteAllText((Join-Path $dir 'OSFMount.com'),'test stand-in')}
  function script:Install-RmgAweAllocPackage($Zip,$Root){if(-not [IO.File]::Exists($Zip)){throw 'Allocator payload missing'};$script:AweInstalls++;$script:AwePresent=$true}
  function script:Assert-RmgRamProvider {[pscustomobject]@{Ready=$true}}
 }
 $result=Install-RmgRamBackend -StateRoot (Join-Path $root 'full-state') -PayloadRoot $PayloadRoot -Offline
 Assert ($result.Ready -and $result.Offline) 'Complete offline setup did not report offline readiness.'
 Assert ((& $module {$script:OsfInstalls}) -eq 1 -and (& $module {$script:AweInstalls}) -eq 1) 'Both missing dependencies were not installed from bundled payloads.'
 $null=Install-RmgRamBackend -StateRoot (Join-Path $root 'full-state') -PayloadRoot $PayloadRoot -Offline
 Assert ((& $module {$script:OsfInstalls}) -eq 1 -and (& $module {$script:AweInstalls}) -eq 1) 'Healthy offline repair reinstalled shared drivers.'
}finally{$env:ProgramFiles=$savedProgramFiles}
Write-Output "Passed $script:passed offline assertions. Network calls throw; no real driver or service was installed."
