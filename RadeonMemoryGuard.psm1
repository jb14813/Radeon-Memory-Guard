#Requires -Version 5.1
Set-StrictMode -Version 2
$script:Setting = 'Gmx_MgpuProcessWatcherSupport'
$script:DefaultState = Join-Path $env:ProgramData 'JZBApps-RadeonMemoryGuard'
$script:InstallRoot = Join-Path $env:ProgramFiles 'JZB Apps\Radeon Memory Guard'
$script:TaskName = 'JZBApps-RadeonMemoryGuard'
$script:PackageFiles = @('RadeonMemoryGuard.ps1','RadeonMemoryGuard.psm1','RadeonRamCache.ps1','RadeonStorage.ps1','README.md','VALIDATION.md','LICENSE','VERSION','THIRD-PARTY-NOTICES.txt')

function Assert-RmgAdmin {
    if ([IntPtr]::Size -ne 8) { throw 'Use 64-bit Windows PowerShell.' }
    if ($PSVersionTable.PSEdition -eq 'Core') { throw 'Use Windows PowerShell 5.1 for administrator actions. PowerShell 7 supports Status and tests.' }
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this action in an administrator PowerShell.' }
}
function Assert-RmgPlainDirectory($Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Reparse-point directory refused: $cursor" }
        $parent = Split-Path $cursor -Parent
        if ($parent -eq $cursor) { break }; $cursor = $parent
    }
}
function Initialize-RmgStateRoot($Path) {
    Assert-RmgPlainDirectory $Path
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($sid in @('S-1-5-18','S-1-5-32-544','S-1-5-32-545')) {
        $rights = if ($sid -eq 'S-1-5-32-545') {'ReadAndExecute'} else {'FullControl'}
        $identity = New-Object Security.Principal.SecurityIdentifier($sid)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity,$rights,'ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
    }
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    if (Test-Path -LiteralPath $Path) {
        $owner=(Get-Acl -LiteralPath $Path).GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($owner -notin @('S-1-5-18','S-1-5-32-544')) { throw "Existing directory is not owned by SYSTEM or Administrators: $Path" }
        Set-Acl -LiteralPath $Path -AclObject $acl
    } else {
        # Windows PowerShell uses the .NET Framework overload: ACL is set at creation.
        $null=[IO.Directory]::CreateDirectory($Path,$acl)
    }
}
function Write-RmgJson($Path,$Data) {
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(($Data | ConvertTo-Json -Depth 12))
        $file=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {$file.Write($bytes,0,$bytes.Length);$file.Flush($true)}finally{$file.Dispose()}
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp,$Path,($Path+'.previous')) }
        else { [IO.File]::Move($temp,$Path) }
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
}
function Read-RmgState($Root) {
    $path = Join-Path $Root 'state.json'
    if (-not (Test-Path -LiteralPath $path)) { return [pscustomobject]@{Schema=1;Records=@()} }
    $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
    if ($state.Schema -ne 1 -or $null -eq $state.Records) { throw 'Unsupported or incomplete state ledger.' }
    return $state
}
function Test-RmgMarker($Path) {
    if (-not ('RmgBinarySearch' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public static class RmgBinarySearch {
 public static bool Contains(string path,string marker) {
  byte[] needle=Encoding.Unicode.GetBytes(marker+"\0");
  byte[] buffer=new byte[262144+needle.Length];
  using(var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read)) {
   int carry=0,read;
   while((read=file.Read(buffer,carry,262144))>0) {
    int total=carry+read;
    for(int n=0;n<=total-needle.Length;n++) {
     int k=0;while(k<needle.Length && buffer[n+k]==needle[k])k++;
     if(k==needle.Length)return true;
    }
    carry=Math.Min(needle.Length-1,total);
    Buffer.BlockCopy(buffer,total-carry,buffer,0,carry);
   }
  }
  return false;
 }
}
'@
    }
    return [RmgBinarySearch]::Contains($Path,$script:Setting)
}
function Get-RmgDrivers {
    $probes = @{}
    foreach ($device in @(Get-PnpDevice -Class Display -PresentOnly -ErrorAction Stop)) {
        if ($device.InstanceId -notmatch '^PCI\\VEN_1002&') { continue }
        $service = [string](Get-Item -LiteralPath ('Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\' + $device.InstanceId)).GetValue('Service')
        if ($service -notmatch '^[A-Za-z0-9_-]+$') { continue }
        $driver = [ordered]@{Name=$device.FriendlyName;InstanceId=$device.InstanceId;Service=$service;DriverPath='';DriverHash='';Version='';Eligible=$false;Reason='Not an AMD kernel display driver'}
        try {
            $serviceKey = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\' + $service
            $raw = [string](Get-Item -LiteralPath $serviceKey).GetValue('ImagePath')
            $path = [IO.Path]::GetFullPath(($raw -replace '^\\SystemRoot',$env:WINDIR))
            $allowed = @((Join-Path $env:WINDIR 'System32\DriverStore\FileRepository\'),(Join-Path $env:WINDIR 'System32\drivers\'))
            if ([IO.Path]::GetFileName($path) -ine 'amdkmdag.sys' -or -not @($allowed | Where-Object {$path.StartsWith($_,[StringComparison]::OrdinalIgnoreCase)}).Count) { throw 'Unexpected driver path' }
            $file = Get-Item -LiteralPath $path
            $driver.DriverPath=$path; $driver.Version=$file.VersionInfo.FileVersion
            if (-not $probes.ContainsKey($path)) {
                $signature = Get-AuthenticodeSignature -LiteralPath $path
                if ($signature.Status.ToString() -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=Microsoft Windows Hardware Compatibility Publisher,') { throw 'A valid Microsoft hardware signature is required' }
                $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
                if (-not (Test-RmgMarker $path)) { throw 'Driver does not expose the process-watcher setting' }
                $probes[$path]=$hash
            }
            $driver.DriverHash=$probes[$path];$driver.Eligible=$true;$driver.Reason='Signed driver exposes the setting; effectiveness on untested versions is unverified'
        } catch { $driver.Reason=$_.Exception.Message }
        [pscustomobject]$driver
    }
}
function Test-RmgBinding($Driver) {
    $device = Get-Item -LiteralPath ('Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\' + $Driver.InstanceId) -ErrorAction Stop
    if ($device.GetValue('Service') -ne $Driver.Service) { return $false }
    return (Get-FileHash -LiteralPath $Driver.DriverPath -Algorithm SHA256).Hash -eq $Driver.DriverHash
}
function Read-RmgRegistryValue($Service) {
    if ($Service -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid service name' }
    $path='Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\'+$Service+'\Parameters'
    $key=Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    $exists=$null -ne $key -and $key.GetValueNames() -contains $script:Setting
    [pscustomobject]@{Exists=$exists;Kind=$(if($exists){$key.GetValueKind($script:Setting).ToString()}else{$null});Value=$(if($exists){$key.GetValue($script:Setting)}else{$null})}
}
function Write-RmgRegistryValue($Service,$Exists,$Value) {
    if ($Service -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid service name' }
    $base='Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\'+$Service
    if (-not (Test-Path -LiteralPath $base)) { throw 'Driver service no longer exists' }
    $path=$base+'\Parameters'
    if ($Exists) {
        if (-not (Test-Path -LiteralPath $path)) {$null=New-Item -Path $path}
        $null=New-ItemProperty -LiteralPath $path -Name $script:Setting -PropertyType DWord -Value $Value -Force
    } elseif (Test-Path -LiteralPath $path) { Remove-ItemProperty -LiteralPath $path -Name $script:Setting -ErrorAction Stop }
}
function Invoke-RmgApply {
    [CmdletBinding(SupportsShouldProcess)]param([string]$StateRoot=$script:DefaultState)
    Assert-RmgAdmin
    if (-not $PSCmdlet.ShouldProcess('AMD display driver settings','Back up and maintain process-watcher workaround')) { return }
    Initialize-RmgStateRoot $StateRoot
    $lock = [IO.File]::Open((Join-Path $StateRoot 'state.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $state=Read-RmgState $StateRoot;$results=@()
        foreach ($driver in @(Get-RmgDrivers)) {
            $status='Configured';$detail=$driver.Reason
            if (-not $driver.Eligible) {$status='SkippedUnsupported'}
            elseif (-not (Test-RmgBinding $driver)) {$status='SkippedBindingChanged'}
            else {
                $current=Read-RmgRegistryValue $driver.Service
                if ($current.Exists -and $current.Kind -ne 'DWord') {$status='SkippedUnexpectedValueType'}
                else {
                    $record=@($state.Records | Where-Object {$_.Service -eq $driver.Service} | Select-Object -First 1)
                    if ($record.Count -eq 0) {
                        $record=@([pscustomobject]@{Service=$driver.Service;DriverHash=$driver.DriverHash;Version=$driver.Version;Original=$current;CapturedUtc=[DateTime]::UtcNow.ToString('o');LastAppliedUtc=$null;Restored=$false})
                        $state.Records=@($state.Records)+$record
                        # The durable backup precedes any registry mutation.
                        Write-RmgJson (Join-Path $StateRoot 'state.json') $state
                    }
                    if (-not $current.Exists -or $current.Value -ne 0) {
                        Write-RmgRegistryValue $driver.Service $true 0
                        $readback=Read-RmgRegistryValue $driver.Service
                        if (-not $readback.Exists -or $readback.Kind -ne 'DWord' -or $readback.Value -ne 0) { throw 'Registry readback failed' }
                        $record[0].LastAppliedUtc=[DateTime]::UtcNow.ToString('o');$record[0].Restored=$false
                        Write-RmgJson (Join-Path $StateRoot 'state.json') $state
                        $status='AppliedNeedsReload';$detail='Setting saved. A subsequent driver reload or Windows restart is needed; no restart was performed.'
                    } elseif ($record[0].LastAppliedUtc -or -not $record[0].Original.Exists -or $record[0].Original.Value -ne 0) {
                        $status='ConfiguredActivationUnverified';$detail='Setting is saved. Check activation after the driver reloads; saved state alone is not leak validation.'
                    }
                }
            }
            $results += [pscustomobject]@{Service=$driver.Service;Version=$driver.Version;DriverHash=$driver.DriverHash;Status=$status;Detail=$detail;TimeUtc=[DateTime]::UtcNow.ToString('o')}
        }
        $ssd=Invoke-RmgSsdEnforcement $StateRoot
        Write-RmgJson (Join-Path $StateRoot 'last-run.json') ([pscustomobject]@{TimeUtc=[DateTime]::UtcNow.ToString('o');Drivers=@($results);Ssd=$ssd})
        return $results
    } finally {$lock.Dispose()}
}
function Invoke-RmgRestore {
    [CmdletBinding(SupportsShouldProcess)]param([string]$StateRoot=$script:DefaultState)
    Assert-RmgAdmin
    if (-not $PSCmdlet.ShouldProcess('Recorded AMD service settings','Restore original values')) {return}
    Initialize-RmgStateRoot $StateRoot
    $lock=[IO.File]::Open((Join-Path $StateRoot 'state.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $state=Read-RmgState $StateRoot
        foreach($record in @($state.Records)) {
            if($record.Restored){continue}
            $current=Read-RmgRegistryValue $record.Service
            $status='RestoredNeedsReload'
            if(-not $current.Exists -or $current.Kind -ne 'DWord' -or $current.Value -ne 0){$status='RestoreConflict'}
            else {
                Write-RmgRegistryValue $record.Service $record.Original.Exists $record.Original.Value
                $check=Read-RmgRegistryValue $record.Service
                if($check.Exists -ne $record.Original.Exists -or ($check.Exists -and ($check.Kind -ne $record.Original.Kind -or $check.Value -ne $record.Original.Value))){throw 'Restoration readback failed'}
                $record.Restored=$true;Write-RmgJson (Join-Path $StateRoot 'state.json') $state
            }
            [pscustomobject]@{Service=$record.Service;Status=$status}
        }
    } finally {$lock.Dispose()}
}
function Read-RmgSsdPolicy($Root) {
    $path=Join-Path $Root 'ssd-policy.json'
    if(-not (Test-Path -LiteralPath $path)){return $null}
    $policy=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
    if($policy.Schema -ne 1 -or $policy.Enabled -isnot [bool] -or $policy.Restored -isnot [bool] -or $null -eq $policy.Original){throw 'Unsupported or incomplete SSD policy.'}
    $original=$policy.Original
    if($original.Start -notin @(2,3,4) -or $original.Running -isnot [bool] -or $original.DelayedExists -isnot [bool] -or $original.DelayedValue -notin @(0,1) -or ($original.Start -eq 4 -and $original.Running)){throw 'Invalid SSD service backup.'}
    $null=Get-RmgSsdMode $policy
    return $policy
}
function Get-RmgSsdMode($Policy) {
    if(-not $Policy -or -not $Policy.PSObject.Properties['Mode']){return 'Disabled'}
    if($Policy.Mode -notin @('Disabled','Ram')){throw 'Unknown SSD protection mode'}
    return $Policy.Mode
}
function Get-RmgExternalService {
    $result=[ordered]@{Name='AMD External Events Utility';Present=$false;Trusted=$false;Reason='Service not installed';State='Absent';Start=$null;DelayedExists=$false;DelayedValue=0;DriverHash='';Version=''}
    $service=Get-CimInstance Win32_Service -Filter "Name='AMD External Events Utility'" -ErrorAction Stop
    if(-not $service){return [pscustomobject]$result}
    $result.Present=$true;$result.State=[string]$service.State
    try {
        $path=[string]$service.PathName
        if($path -match '^"([^"\r\n]+)"\s*$'){$path=$Matches[1]}
        $path=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($path))
        $store=Join-Path $env:WINDIR 'System32\DriverStore\FileRepository\'
        $systemExe=Join-Path $env:WINDIR 'System32\atiesrxx.exe'
        if([IO.Path]::GetFileName($path) -ine 'atiesrxx.exe' -or (-not $path.StartsWith($store,[StringComparison]::OrdinalIgnoreCase) -and $path -ine $systemExe)){throw 'Unexpected External Events service executable'}
        Assert-RmgPlainDirectory (Split-Path $path -Parent)
        $file=Get-Item -LiteralPath $path -ErrorAction Stop
        $signature=Get-AuthenticodeSignature -LiteralPath $path
        if($signature.Status.ToString() -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=(Microsoft Windows Hardware Compatibility Publisher|Advanced Micro Devices[^,]*|AMD[^,]*),' -or $file.VersionInfo.CompanyName -notmatch '^(AMD|Advanced Micro Devices)'){throw 'A valid AMD or Microsoft hardware signature and AMD executable are required'}
        $key=Get-Item -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\AMD External Events Utility'
        if($key.GetValueKind('Start').ToString() -ne 'DWord'){throw 'Unexpected startup value type'}
        $result.Start=[int]$key.GetValue('Start')
        $result.DelayedExists=$key.GetValueNames() -contains 'DelayedAutoStart'
        if($result.DelayedExists){
            if($key.GetValueKind('DelayedAutoStart').ToString() -ne 'DWord'){throw 'Unexpected delayed-start value type'}
            $result.DelayedValue=[int]$key.GetValue('DelayedAutoStart')
        }
        if($result.Start -notin @(2,3,4) -or $result.DelayedValue -notin @(0,1) -or $result.State -notin @('Running','Stopped')){throw 'Service is transitioning or has unsupported configuration; retry when stable'}
        $result.DriverHash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $result.Version=$file.VersionInfo.FileVersion;$result.Trusted=$true;$result.Reason='Validated AMD External Events service'
    } catch {$result.Reason=$_.Exception.Message}
    return [pscustomobject]$result
}
function Set-RmgExternalService($Start,$Running,$DelayedExists,$DelayedValue) {
    if($Start -notin @(2,3,4) -or ($Start -eq 4 -and $Running)){throw 'Invalid External Events service configuration'}
    $name='AMD External Events Utility'
    # SCM updates the active configuration; preserve the exact optional registry value too.
    $startup=switch($Start){2 {if($DelayedExists -and $DelayedValue -eq 1){'delayed-auto'}else{'auto'}} 3 {'demand'} 4 {'disabled'}}
    $output=& (Join-Path $env:WINDIR 'System32\sc.exe') config $name start= $startup 2>&1
    if($LASTEXITCODE -ne 0){throw ('Service configuration failed: '+($output -join ' '))}
    $key='Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\AMD External Events Utility'
    if($DelayedExists){$null=New-ItemProperty -LiteralPath $key -Name DelayedAutoStart -PropertyType DWord -Value $DelayedValue -Force}
    else {Remove-ItemProperty -LiteralPath $key -Name DelayedAutoStart -ErrorAction SilentlyContinue}
    $controller=Get-Service -Name $name -ErrorAction Stop
    if($Running){if($controller.Status -ne 'Running'){Start-Service -Name $name -ErrorAction Stop};$controller.WaitForStatus('Running',[TimeSpan]::FromSeconds(20))}
    else {if($controller.Status -ne 'Stopped'){Stop-Service -Name $name -ErrorAction Stop};$controller.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(20))}
}
function Invoke-RmgSsdEnforcement($StateRoot) {
    # Caller owns state.lock. No service change occurs without explicit, durable opt-in.
    $policy=Read-RmgSsdPolicy $StateRoot
    if(-not $policy -or -not $policy.Enabled){return [pscustomobject]@{Status='NotOptedIn'}}
    $service=Get-RmgExternalService
    if(-not $service.Present){return [pscustomobject]@{Status='ServiceAbsent'}}
    if(-not $service.Trusted){throw ('SSD protection refused: '+$service.Reason)}
    if((Get-RmgSsdMode $policy) -eq 'Ram'){
        $cache=Get-RmgRamCacheStatus $StateRoot
        if(-not $cache.Ready){
            # A missing RAM volume must be rebuilt before AMD can write through the link.
            if($service.State -ne 'Stopped' -or $service.Start -ne 3){Set-RmgExternalService 3 $false $service.DelayedExists $service.DelayedValue}
            Initialize-RmgRamCache $StateRoot
            $cache=Get-RmgRamCacheStatus $StateRoot
            if(-not $cache.Ready){throw 'RAM cache readback failed'}
            $service=Get-RmgExternalService
        }
        if($service.Start -ne 3 -or $service.State -ne 'Running'){Set-RmgExternalService 3 $true $service.DelayedExists $service.DelayedValue}
        $check=Get-RmgExternalService
        if(-not $check.Trusted -or $check.Start -ne 3 -or $check.State -ne 'Running'){throw 'AMD service did not recover on RAM storage'}
        return [pscustomobject]@{Status='ProtectedInRam';Service=$check.Name;Startup='Manual';State=$check.State;CapacityBytes=$cache.CapacityBytes}
    }
    if($service.Start -ne 4 -or $service.State -ne 'Stopped'){
        Set-RmgExternalService 4 $false $service.DelayedExists $service.DelayedValue
        $service=Get-RmgExternalService
        if(-not $service.Trusted -or $service.Start -ne 4 -or $service.State -ne 'Stopped'){throw 'SSD protection service readback failed; original configuration remains backed up'}
    }
    return [pscustomobject]@{Status='Protected';Service=$service.Name;Startup='Disabled';State=$service.State;Version=$service.Version}
}
function Invoke-RmgProtectSsd {
    [CmdletBinding(SupportsShouldProcess)]param([string]$StateRoot=$script:DefaultState)
    Assert-RmgAdmin
    if(-not $PSCmdlet.ShouldProcess('AMD External Events Utility','Back up, disable and stop service to prevent repeated executable writes; AMD hotkeys and display-event features may be unavailable')){return}
    Initialize-RmgStateRoot $StateRoot
    $lock=[IO.File]::Open((Join-Path $StateRoot 'state.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $policy=Read-RmgSsdPolicy $StateRoot
        if($policy -and -not $policy.Enabled -and -not $policy.Restored){throw 'An earlier SSD restore is unresolved. Retry RestoreSsd or review its backup before opting in again.'}
        if($policy -and $policy.Enabled -and (Get-RmgSsdMode $policy) -eq 'Ram'){throw 'Use RestoreSsd before switching from RAM protection to service disabling'}
        if(-not $policy -or -not $policy.Enabled){
            $service=Get-RmgExternalService
            if(-not $service.Present -or -not $service.Trusted){throw ('SSD protection refused: '+$service.Reason)}
            if($service.Start -eq 4 -and $service.State -eq 'Running'){throw 'Service is disabled but still running; stop it or restore its startup configuration before opting in'}
            $policy=[pscustomobject]@{Schema=1;Enabled=$true;Restored=$false;CapturedUtc=[DateTime]::UtcNow.ToString('o');Original=[pscustomobject]@{Start=$service.Start;Running=($service.State -eq 'Running');DelayedExists=$service.DelayedExists;DelayedValue=$service.DelayedValue};DriverHash=$service.DriverHash;Version=$service.Version}
            Write-RmgJson (Join-Path $StateRoot 'ssd-policy.json') $policy
        }
        Invoke-RmgSsdEnforcement $StateRoot
    } finally {$lock.Dispose()}
}
function Invoke-RmgProtectSsdRam {
    [CmdletBinding(SupportsShouldProcess)]param([string]$StateRoot=$script:DefaultState)
    Assert-RmgAdmin
    if(-not $PSCmdlet.ShouldProcess('AMD executable cache','Redirect repeated writes into a fixed physical-memory disk and keep External Events Utility running')){return}
    Initialize-RmgStateRoot $StateRoot
    $lock=[IO.File]::Open((Join-Path $StateRoot 'state.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $policy=Read-RmgSsdPolicy $StateRoot
        if($policy -and -not $policy.Enabled -and -not $policy.Restored){throw 'An earlier SSD restore is unresolved'}
        $service=Get-RmgExternalService
        if(-not $service.Present -or -not $service.Trusted){throw ('RAM protection refused: '+$service.Reason)}
        if(-not $policy -or $policy.Restored){
            $policy=[pscustomobject]@{Schema=1;Enabled=$true;Restored=$false;CapturedUtc=[DateTime]::UtcNow.ToString('o');Original=[pscustomobject]@{Start=$service.Start;Running=($service.State -eq 'Running');DelayedExists=$service.DelayedExists;DelayedValue=$service.DelayedValue};DriverHash=$service.DriverHash;Version=$service.Version}
        }
        $policy | Add-Member -MemberType NoteProperty -Name Mode -Value Ram -Force
        $policy.Enabled=$true;$policy.Restored=$false
        Write-RmgJson (Join-Path $StateRoot 'ssd-policy.json') $policy
        Invoke-RmgSsdEnforcement $StateRoot
    } finally {$lock.Dispose()}
}
function Invoke-RmgRestoreSsd {
    [CmdletBinding(SupportsShouldProcess)]param([string]$StateRoot=$script:DefaultState)
    Assert-RmgAdmin
    if(-not $PSCmdlet.ShouldProcess('AMD External Events Utility','Disable SSD enforcement and restore saved service configuration')){return}
    Initialize-RmgStateRoot $StateRoot
    $lock=[IO.File]::Open((Join-Path $StateRoot 'state.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $policy=Read-RmgSsdPolicy $StateRoot
        if(-not $policy -or $policy.Restored){return [pscustomobject]@{Status='NotOptedIn'}}
        $service=Get-RmgExternalService
        if((Get-RmgSsdMode $policy) -eq 'Ram'){
            if(-not $service.Present -or -not $service.Trusted -or ($service.Start -eq 4 -and $service.State -eq 'Running')){return [pscustomobject]@{Status='RestoreConflict';Detail='RAM recovery maintenance retained; service identity or configuration needs review.'}}
            $original=$policy.Original
            $compatible=$service.Start -eq 3 -or ($service.Start -eq $original.Start -and $service.DelayedExists -eq $original.DelayedExists -and $service.DelayedValue -eq $original.DelayedValue)
            Set-RmgExternalService $service.Start $false $service.DelayedExists $service.DelayedValue
            Remove-RmgRamCache $StateRoot
            # Keep RAM recovery enabled until the file and volume have actually been restored.
            $policy.Enabled=$false;Write-RmgJson (Join-Path $StateRoot 'ssd-policy.json') $policy
            if(-not $compatible){
                Set-RmgExternalService $service.Start ($service.State -eq 'Running') $service.DelayedExists $service.DelayedValue
                return [pscustomobject]@{Status='RestoreConflict';Detail='RAM cache restored and released; later administrator service configuration preserved.'}
            }
        } else {
            $policy.Enabled=$false;Write-RmgJson (Join-Path $StateRoot 'ssd-policy.json') $policy
            if(-not $service.Present -or -not $service.Trusted -or $service.Start -ne 4 -or $service.State -ne 'Stopped'){return [pscustomobject]@{Status='RestoreConflict';Detail='SSD enforcement disabled; current service configuration was left unchanged.'}}
        }
        $original=$policy.Original
        Set-RmgExternalService $original.Start $original.Running $original.DelayedExists $original.DelayedValue
        $check=Get-RmgExternalService
        if(-not $check.Trusted -or $check.Start -ne $original.Start -or ($check.State -eq 'Running') -ne $original.Running -or $check.DelayedExists -ne $original.DelayedExists -or $check.DelayedValue -ne $original.DelayedValue){throw 'SSD restoration readback failed; backup is retained for retry'}
        $policy.Restored=$true;Write-RmgJson (Join-Path $StateRoot 'ssd-policy.json') $policy
        [pscustomobject]@{Status='Restored';Service=$check.Name;Start=$check.Start;State=$check.State}
    } finally {$lock.Dispose()}
}
function Get-RmgStatus {
    [CmdletBinding()]param([string]$StateRoot=$script:DefaultState)
    $drivers=@(foreach($driver in @(Get-RmgDrivers)) {
        $value=Read-RmgRegistryValue $driver.Service
        [pscustomobject]@{Name=$driver.Name;Service=$driver.Service;Version=$driver.Version;DriverHash=$driver.DriverHash;Eligible=$driver.Eligible;Reason=$driver.Reason;SettingPresent=$value.Exists;SettingValue=$value.Value;Configured=($value.Exists -and $value.Kind -eq 'DWord' -and $value.Value -eq 0)}
    })
    $task=Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    $last=$null;$lastPath=Join-Path $StateRoot 'last-run.json'
    if(Test-Path -LiteralPath $lastPath){$last=Get-Content -LiteralPath $lastPath -Raw | ConvertFrom-Json -ErrorAction Stop}
    $taskInfo=$null;if($task){$taskInfo=Get-ScheduledTaskInfo -TaskName $script:TaskName -ErrorAction SilentlyContinue}
    $policy=Read-RmgSsdPolicy $StateRoot;$service=Get-RmgExternalService
    $mode=Get-RmgSsdMode $policy;$ram=$null
    if($mode -eq 'Ram'){$ram=Get-RmgRamCacheStatus $StateRoot}
    $protected=$null -ne $policy -and $policy.Enabled -and $service.Trusted
    if($mode -eq 'Ram'){$protected=$protected -and $ram.Ready -and $service.Start -eq 3 -and $service.State -eq 'Running'}else{$protected=$protected -and $service.Start -eq 4 -and $service.State -eq 'Stopped'}
    $ssd=[pscustomobject]@{OptedIn=($null -ne $policy -and $policy.Enabled);Mode=$mode;Service=$service;RamCache=$ram;Protected=$protected}
    [pscustomobject]@{Version='0.5.1';Drivers=$drivers;Ssd=$ssd;AutomaticMaintenance=($null -ne $task -and $task.State -ne 'Disabled');LastTaskResult=$(if($taskInfo){$taskInfo.LastTaskResult}else{$null});LastMaintenance=$last;StateDirectory=$StateRoot;Activation='Configuration status only. Allocation-stack and file/disk tracing establish leak prevention and write redirection.'}
}

function Stop-RmgMaintenance {
    param([switch]$KeepRegistration)
    $task=Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    if ($task) {
        $expected=Join-Path $script:InstallRoot 'RadeonMemoryGuard.ps1'
        if ($task.Description -notlike 'JZB Apps Radeon Memory Guard*' -or @($task.Actions | Where-Object {$_.Arguments -notlike ('*"'+$expected+'"*')}).Count) { throw 'Existing task with this name is not owned by this utility.' }
        Stop-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if(-not $KeepRegistration){Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false}
    }
}
function Install-RmgMaintenance {
    [CmdletBinding(SupportsShouldProcess)]param()
    Assert-RmgAdmin
    if (-not $PSCmdlet.ShouldProcess($script:InstallRoot,'Install scheduled AMD setting maintenance')) {return}
    foreach($name in $script:PackageFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name) -PathType Leaf)) {throw "Missing package file: $name"}
    }
    $null=Read-RmgRamState $script:DefaultState
    # Stop a prior owned task only after checking that the new package is complete.
    Stop-RmgMaintenance -KeepRegistration
    Initialize-RmgStateRoot $script:InstallRoot
    Initialize-RmgStateRoot $script:DefaultState
    foreach($name in $script:PackageFiles) {
        $source=Join-Path $PSScriptRoot $name;$target=Join-Path $script:InstallRoot $name
        if ([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($target)) {Copy-Item -LiteralPath $source -Destination $target -Force}
        $null=Get-Item -LiteralPath $target
    }
    $executable=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File "'+(Join-Path $script:InstallRoot 'RadeonMemoryGuard.ps1')+'" -Action Apply -Quiet'
    $action=New-ScheduledTaskAction -Execute $executable -Argument $arguments -WorkingDirectory $script:InstallRoot
    $startup=New-ScheduledTaskTrigger -AtStartup
    $repeat=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
    $principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    $null=Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger @($startup,$repeat) -Principal $principal -Settings $settings -Force -Description 'JZB Apps Radeon Memory Guard: maintain AMD process-watcher setting and opted-in External Events mitigation; never restart devices or Windows.'
    # Let ordinary users inspect Status; only SYSTEM and Administrators can change it.
    $scheduler=New-Object -ComObject 'Schedule.Service';$scheduler.Connect()
    $registered=$scheduler.GetFolder('\').GetTask($script:TaskName)
    $registered.SetSecurityDescriptor('D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GR;;;BU)',0)
    # Register recovery before applying: a failed RAM preparation must retain startup recovery.
    $results=@(Invoke-RmgApply)
    [pscustomobject]@{Installed=$true;TaskName=$script:TaskName;InstallDirectory=$script:InstallRoot;IntervalMinutes=5;Drivers=$results}
}
function Uninstall-RmgMaintenance {
    [CmdletBinding(SupportsShouldProcess)]param([switch]$KeepSetting)
    Assert-RmgAdmin
    if (-not $PSCmdlet.ShouldProcess($script:InstallRoot,'Remove scheduled maintenance and installed utility files')) {return}
    $ssdPolicy=Read-RmgSsdPolicy $script:DefaultState
    $ramState=Read-RmgRamState $script:DefaultState
    if($KeepSetting -and (($ramState -and $ramState.Active) -or ($ssdPolicy -and $ssdPolicy.Enabled -and (Get-RmgSsdMode $ssdPolicy) -eq 'Ram'))){throw 'RAM protection requires startup maintenance. Use RestoreSsd first, or uninstall without KeepSetting to restore and release the RAM cache.'}
    $restore=@()
    if(-not $KeepSetting){
        $restore=@(Invoke-RmgRestoreSsd)
        $ramState=Read-RmgRamState $script:DefaultState
        if($ramState -and $ramState.Active){throw 'RAM restoration is incomplete; maintenance and recovery files were retained'}
    }
    $backend=Remove-RmgStorageBackend $script:DefaultState
    Stop-RmgMaintenance
    if(-not $KeepSetting){$restore+=@(Invoke-RmgRestore)}
    Assert-RmgPlainDirectory $script:InstallRoot
    # Delete only this package's known files. Keep the backup ledger and any conflicts.
    foreach($name in $script:PackageFiles) {
        $path=Join-Path $script:InstallRoot $name
        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}
    }
    if((Test-Path -LiteralPath $script:InstallRoot) -and @(Get-ChildItem -LiteralPath $script:InstallRoot -Force).Count -eq 0){[IO.Directory]::Delete($script:InstallRoot,$false)}
    [pscustomobject]@{Installed=$false;KeptSetting=[bool]$KeepSetting;Backend=$backend;Restoration=$restore;BackupDirectory=$script:DefaultState}
}
function Restore-RmgMaintenance {
    [CmdletBinding(SupportsShouldProcess)]param()
    Assert-RmgAdmin
    if($PSCmdlet.ShouldProcess('AMD workaround','Stop maintenance and restore saved values')){
        Invoke-RmgRestoreSsd
        $ramState=Read-RmgRamState $script:DefaultState
        if($ramState -and $ramState.Active){throw 'RAM restoration is incomplete; maintenance was retained'}
        Stop-RmgMaintenance
        Invoke-RmgRestore
    }
}
. (Join-Path $PSScriptRoot 'RadeonStorage.ps1')
if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'RadeonRamCache.ps1')){. (Join-Path $PSScriptRoot 'RadeonRamCache.ps1')}
Export-ModuleMember -Function Get-RmgStatus,Invoke-RmgApply,Invoke-RmgRestore,Install-RmgMaintenance,Uninstall-RmgMaintenance,Restore-RmgMaintenance,Invoke-RmgProtectSsd,Invoke-RmgRestoreSsd,Invoke-RmgProtectSsdRam,Install-RmgRamBackend
