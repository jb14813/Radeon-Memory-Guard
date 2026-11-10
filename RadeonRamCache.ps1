# Private RAM-cache backend. The caller holds Radeon Memory Guard's state.lock.
$script:RamSource=Join-Path $env:WINDIR 'System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe'
$script:RamBackup=$script:RamSource+'.rmg-original'
$script:RamCapacity=64MB
function Initialize-RmgRamNative {
    Initialize-RmgStorageNative
    if('RmgRamNative' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
public static class RmgRamNative {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string p,uint a,uint s,IntPtr sa,uint c,uint f,IntPtr t);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool DeviceIoControl(SafeFileHandle h,uint c,byte[] i,int il,byte[] o,int ol,out int r,IntPtr over);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateSymbolicLink(string link,string target,int flags);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool DeleteFile(string path);
 public static void Link(string source,string target){if(!CreateSymbolicLink(source,target,0))throw new Win32Exception();}
 public static void DeleteLink(string source){if(!DeleteFile(source))throw new Win32Exception();}
 public static string ReadLink(string source){
  using(var h=CreateFile(source,0,7,IntPtr.Zero,3,0x02200000,IntPtr.Zero)){
   if(h.IsInvalid){int e=Marshal.GetLastWin32Error();if(e==2||e==3)return null;throw new Win32Exception(e);}
   byte[] b=new byte[16384];int r;
   if(!DeviceIoControl(h,0x900a8,null,0,b,b.Length,out r,IntPtr.Zero)){int e=Marshal.GetLastWin32Error();if(e==4390)return null;throw new Win32Exception(e);}
   if(r<20||BitConverter.ToUInt32(b,0)!=0xa000000c||BitConverter.ToUInt32(b,16)!=0)throw new Exception("Unexpected cache reparse point");
   int offset=BitConverter.ToUInt16(b,8),length=BitConverter.ToUInt16(b,10);
   if(20+offset+length>r)throw new Exception("Invalid cache link data");
   string p=Encoding.Unicode.GetString(b,20+offset,length);
   return p.StartsWith(@"\??\",StringComparison.Ordinal)?@"\\?\"+p.Substring(4):p;
  }
 }

}
'@
}
function Read-RmgRamState($Root) {
    $path=Join-Path $Root 'ram-cache.json'
    if(-not (Test-Path -LiteralPath $path)){return $null}
    $state=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
    if($state.Schema -ne 2 -or $state.Provider -ne 'Arsenal' -or $state.Source -ine $script:RamSource -or $state.Backup -ine $script:RamBackup -or $state.CapacityBytes -ne $script:RamCapacity -or $state.Id -notmatch '^[a-f0-9]{32}$' -or $state.OriginalExists -isnot [bool] -or $state.Active -isnot [bool]){throw 'Unsupported RAM-cache ledger. Restore and uninstall the prior backend and archive its inactive ledger before installing this version; no cache or disk was changed'}
    foreach($target in @($state.Target,$state.PreviousTarget)){
        if($target -and $target -notmatch '^\\\\\?\\Volume\{[0-9a-f-]{36}\}\\atieclxx\.exe$'){throw 'Unexpected RAM-cache target in ledger'}
    }
    return $state
}
function Get-RmgRamDisk($State) {
    if(-not $State.VolumeRoot){return $null}
    $volumes=@(Get-Volume -ErrorAction Stop | Where-Object {$_.Path -ieq $State.VolumeRoot})
    if($volumes.Count -gt 1){throw 'Ambiguous RAM volume identity'}
    $volume=$null;$disks=@()
    if($volumes.Count -eq 1){$volume=$volumes[0];$disks=@($volume | Get-Partition -ErrorAction SilentlyContinue | Get-Disk -ErrorAction SilentlyContinue)}
    if($disks.Count -eq 0){
        # An offline volume disappears from Get-Volume. Match its saved MBR signature too.
        $disks=@(Get-Disk | Where-Object {$_.Number -eq $State.DiskNumber -and $_.UniqueId -eq $State.DiskUniqueId -and $_.Signature -eq $State.DiskSignature -and $_.Size -eq $script:RamCapacity -and $_.FriendlyName -eq 'Arsenal Virtual'})
    }
    if($disks.Count -eq 0){return $null}
    if($disks.Count -ne 1){throw 'Ambiguous RAM disk identity'}
    $disk=$disks[0]
    if($disk.FriendlyName -ne 'Arsenal Virtual' -or $disk.Size -ne $script:RamCapacity -or $disk.UniqueId -ne $State.DiskUniqueId){throw 'RAM volume identity changed'}
    if($disk.Signature -ne $State.DiskSignature){throw 'RAM partition signature changed'}
    $physical=Get-CimInstance Win32_DiskDrive -Filter ('Index='+$disk.Number)
    if(-not $physical -or $physical.SCSIPort -notin @(Get-RmgStoragePorts)){throw 'Unexpected RAM storage controller'}
    $unit=[uint32]$physical.SCSIBus -bor ([uint32]$physical.SCSITargetId -shl 8) -bor ([uint32]$physical.SCSILogicalUnit -shl 16)
    if($physical.SCSIPort -ne $State.AdapterPort -or $unit -ne $State.DeviceNumber){throw 'RAM controller or LUN identity changed'}
    Initialize-RmgRamNative
    if(-not [RmgStorageNative]::IsPhysicalMemory($physical.SCSIPort,$unit)){throw 'RAM volume is not backed by locked physical memory'}
    [pscustomobject]@{Disk=$disk;Volume=$volume;Port=[int]$physical.SCSIPort;Unit=$unit}
}
function Get-RmgRamCacheStatus($StateRoot) {
    try {
        $state=Read-RmgRamState $StateRoot
        if(-not $state -or -not $state.Active){return [pscustomobject]@{Ready=$false;CapacityBytes=$script:RamCapacity;Reason='RAM redirection is not installed'}}
        $device=Get-RmgRamDisk $state
        if(-not $device -or -not $device.Volume -or $device.Disk.IsOffline){return [pscustomobject]@{Ready=$false;CapacityBytes=$script:RamCapacity;Reason='RAM volume must be prepared or recreated'}}
        $cookie=Get-Content -LiteralPath (Join-Path $state.VolumeRoot 'rmg-volume.json') -Raw | ConvertFrom-Json -ErrorAction Stop
        if($cookie.Id -ne $state.Id){throw 'RAM ownership marker changed'}
        $owner=(Get-Acl -LiteralPath $state.VolumeRoot).GetOwner([Security.Principal.SecurityIdentifier]).Value
        if($owner -notin @('S-1-5-18','S-1-5-32-544')){throw 'RAM root owner changed'}
        $link=[RmgRamNative]::ReadLink($script:RamSource)
        [pscustomobject]@{Ready=($link -ieq $state.Target -and [IO.File]::Exists($state.Target));CapacityBytes=$script:RamCapacity;AvailableBytes=$device.Volume.SizeRemaining;VolumeRoot=$state.VolumeRoot;DiskNumber=$device.Disk.Number;Reason='Physical-memory backing and link inspected; administrator access is required'}
    }catch{[pscustomobject]@{Ready=$false;CapacityBytes=$script:RamCapacity;Reason=$_.Exception.Message}}
}
function Get-RmgRamSeed {
    $service=Get-CimInstance Win32_Service -Filter "Name='AMD External Events Utility'"
    $path=([string]$service.PathName).Trim('"')
    $seed=Join-Path (Split-Path $path -Parent) 'atieclxx.exe'
    $store=Join-Path $env:WINDIR 'System32\DriverStore\FileRepository\'
    if(-not $seed.StartsWith($store,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected AMD cache source'}
    $sig=Get-AuthenticodeSignature -LiteralPath $seed
    if($sig.Status.ToString() -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Windows Hardware Compatibility Publisher|Advanced Micro Devices|AMD,'){throw 'AMD cache source signature is invalid'}
    return $seed
}
function Initialize-RmgRamCache($StateRoot) {
    Initialize-RmgRamNative
    $provider=Assert-RmgRamProvider;$seed=Get-RmgRamSeed
    $state=Read-RmgRamState $StateRoot
    if(-not $state -or -not $state.Active){
        $link=[RmgRamNative]::ReadLink($script:RamSource)
        if($link -or [IO.File]::Exists($script:RamBackup)){throw 'Existing cache link or backup is not owned by a new RAM installation'}
        $exists=[IO.File]::Exists($script:RamSource)
        if($exists -and (Get-FileHash -LiteralPath $script:RamSource).Hash -ne (Get-FileHash -LiteralPath $seed).Hash){throw 'Current cache is not the official AMD executable'}
        $state=[pscustomobject]@{Schema=2;Provider='Arsenal';AdapterPort=-1;DeviceNumber=-1;Id=[guid]::NewGuid().ToString('N');Source=$script:RamSource;Backup=$script:RamBackup;OriginalExists=$exists;OriginalHash=$(if($exists){(Get-FileHash -LiteralPath $script:RamSource).Hash}else{''});Active=$true;CapacityBytes=$script:RamCapacity;Phase='Captured';VolumeRoot='';Target='';PreviousTarget='';DiskNumber=-1;DiskUniqueId='';DiskSignature=0;CapturedUtc=[DateTime]::UtcNow.ToString('o')}
        Write-RmgJson (Join-Path $StateRoot 'ram-cache.json') $state
    }
    $device=Get-RmgRamDisk $state
    if(-not $device){
        if($state.Phase -in @('Creating','Created')){throw 'An interrupted RAM creation needs review; refusing to allocate another disk'}
        $state.Phase='Creating';Write-RmgJson (Join-Path $StateRoot 'ram-cache.json') $state
        $unit=[RmgStorageNative]::Create($provider.Port)
        $state.AdapterPort=$provider.Port;$state.DeviceNumber=$unit
        Write-RmgJson (Join-Path $StateRoot 'ram-cache.json') $state
        Update-HostStorageCache
        $new=@()
        for($attempt=0;$attempt -lt 40;$attempt++){
            $physical=@(Get-CimInstance Win32_DiskDrive | Where-Object {$_.SCSIPort -eq $provider.Port -and ([uint32]$_.SCSIBus -bor ([uint32]$_.SCSITargetId -shl 8) -bor ([uint32]$_.SCSILogicalUnit -shl 16)) -eq $unit})
            if($physical.Count -eq 1){$new=@(Get-Disk -Number $physical[0].Index);break}
            Start-Sleep -Milliseconds 200
        }
        if($new.Count -ne 1 -or $new[0].FriendlyName -ne 'Arsenal Virtual' -or $new[0].Size -ne $script:RamCapacity -or $new[0].PartitionStyle -ne 'RAW' -or $new[0].IsSystem -or $new[0].IsBoot){throw 'Unexpected new RAM storage; no disk was formatted'}
        if(-not [RmgStorageNative]::IsPhysicalMemory($provider.Port,$unit)){throw 'New storage is not the requested physical-memory backend; no disk was formatted'}
        $state.DiskNumber=$new[0].Number;$state.DiskUniqueId=$new[0].UniqueId;$state.Phase='Created'
        Write-RmgJson (Join-Path $StateRoot 'ram-cache.json') $state
        $part=$new[0] | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -UseMaximumSize -AssignDriveLetter
        $volume=$part | Format-Volume -FileSystem NTFS -NewFileSystemLabel ('RMG-'+$state.Id.Substring(0,8)) -Confirm:$false
        $formattedDisk=$part | Get-Disk
        $state.DiskUniqueId=$formattedDisk.UniqueId;$state.DiskSignature=$formattedDisk.Signature
        $state.PreviousTarget=$state.Target;$state.VolumeRoot=$volume.Path;$state.Target=Join-Path $volume.Path 'atieclxx.exe';$state.Phase='VolumeReady'
        Write-RmgJson (Join-Path $StateRoot 'ram-cache.json') $state
        # New NTFS volumes initially belong to their creator. Set the protected ACL immediately.
        Set-Acl -LiteralPath $state.VolumeRoot -AclObject (Get-Acl -LiteralPath $StateRoot)
        Write-RmgJson (Join-Path $state.VolumeRoot 'rmg-volume.json') ([pscustomobject]@{Id=$state.Id;CapacityBytes=$state.CapacityBytes})
    } else {
        if($device.Disk.IsOffline){$null=$device.Disk | Set-Disk -IsOffline $false}
        $cookie=Get-Content -LiteralPath (Join-Path $state.VolumeRoot 'rmg-volume.json') -Raw | ConvertFrom-Json
        if($cookie.Id -ne $state.Id){throw 'RAM volume ownership marker changed'}
        $owner=(Get-Acl -LiteralPath $state.VolumeRoot).GetOwner([Security.Principal.SecurityIdentifier]).Value
        if($owner -notin @('S-1-5-18','S-1-5-32-544')){throw 'RAM root owner changed'}
    }
    Copy-Item -LiteralPath $seed -Destination $state.Target -Force
    if((Get-FileHash -LiteralPath $state.Target).Hash -ne (Get-FileHash -LiteralPath $seed).Hash){throw 'RAM seed readback failed'}
    $current=[RmgRamNative]::ReadLink($script:RamSource)
    if($current -and $current -ine $state.Target -and $current -ine $state.PreviousTarget){throw 'Cache link belongs to another configuration'}
    if($current){[RmgRamNative]::DeleteLink($script:RamSource)}
    elseif([IO.File]::Exists($script:RamSource)){
        if(-not [IO.File]::Exists($state.Backup)){
            if(-not $state.OriginalExists -or (Get-FileHash -LiteralPath $script:RamSource).Hash -ne $state.OriginalHash){throw 'Cache changed before backup'}
            [IO.File]::Move($script:RamSource,$state.Backup)
        }else{
            # A driver update can replace the link with a new generated cache copy.
            if((Get-FileHash -LiteralPath $script:RamSource).Hash -ne (Get-FileHash -LiteralPath $seed).Hash){throw 'Replacement cache is not the current official AMD executable'}
            [IO.File]::Delete($script:RamSource)
        }
    }
    if($state.OriginalExists -and (-not [IO.File]::Exists($state.Backup) -or (Get-FileHash -LiteralPath $state.Backup).Hash -ne $state.OriginalHash)){throw 'Original cache backup is missing or changed'}
    [RmgRamNative]::Link($script:RamSource,$state.Target)
    $state.Phase='Linked';Write-RmgJson (Join-Path $StateRoot 'ram-cache.json') $state
}
function Remove-RmgRamCache($StateRoot) {
    Initialize-RmgRamNative
    $state=Read-RmgRamState $StateRoot
    if(-not $state -or -not $state.Active){return}
    if($state.Phase -in @('Creating','Created')){throw 'Interrupted RAM creation requires review of the retained disk identity before cleanup'}
    $device=Get-RmgRamDisk $state
    $link=[RmgRamNative]::ReadLink($script:RamSource)
    if($link -and $link -ine $state.Target -and $link -ine $state.PreviousTarget){throw 'Restore conflict: cache link was changed; original backup retained'}
    if($state.OriginalExists -and [IO.File]::Exists($state.Backup)){
        if((Get-FileHash -LiteralPath $state.Backup).Hash -ne $state.OriginalHash){throw 'Restore conflict: original cache backup changed'}
        if(-not $link -and [IO.File]::Exists($script:RamSource)){throw 'Restore conflict: original cache location was replaced'}
        if($link){[RmgRamNative]::DeleteLink($script:RamSource)}
        [IO.File]::Move($state.Backup,$script:RamSource)
    }elseif($link){
        if($state.OriginalExists){throw 'Original cache backup is missing'}
        [RmgRamNative]::DeleteLink($script:RamSource)
    }elseif($state.OriginalExists -and (-not [IO.File]::Exists($script:RamSource) -or (Get-FileHash -LiteralPath $script:RamSource).Hash -ne $state.OriginalHash)){throw 'Original cache restoration cannot be verified'}
    $state.Phase='Restoring';Write-RmgJson (Join-Path $StateRoot 'ram-cache.json') $state
    if($device){
        # Address only the identified AWE-backed LUN, never all devices on its adapter.
        $null=$device.Disk | Set-Disk -IsOffline $true
        [RmgStorageNative]::Remove($device.Port,$device.Unit)
        for($n=0;$n -lt 20;$n++){
            if(-not @(Get-Disk | Where-Object {$_.Path -eq $device.Disk.Path}).Count){break}
            Start-Sleep -Milliseconds 100
        }
        if(@(Get-Disk | Where-Object {$_.Path -eq $device.Disk.Path}).Count){throw 'RAM detach is pending; retained ledger allows cleanup retry'}
    }
    $state.Active=$false;$state.Phase='Restored';Write-RmgJson (Join-Path $StateRoot 'ram-cache.json') $state
}
