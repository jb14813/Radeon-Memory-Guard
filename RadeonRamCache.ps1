# Private RAM-cache backend. The caller holds Radeon Memory Guard's state.lock.
$script:RamSource=Join-Path $env:WINDIR 'System32\config\systemprofile\AppData\Local\AMD\atieclxx.exe'
$script:RamBackup=$script:RamSource+'.rmg-original'
$script:RamCapacity=64MB
function Initialize-RmgRamNative {
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
 static byte[] Control(int port,uint code,uint device,int length){
  if(port<0||port>255||device==uint.MaxValue)throw new ArgumentException("Invalid RAM device identity");
  byte[] b=new byte[28+length];Buffer.BlockCopy(BitConverter.GetBytes(28),0,b,0,4);Buffer.BlockCopy(Encoding.ASCII.GetBytes("PassMark"),0,b,4,8);Buffer.BlockCopy(BitConverter.GetBytes(10),0,b,12,4);Buffer.BlockCopy(BitConverter.GetBytes(code),0,b,16,4);Buffer.BlockCopy(BitConverter.GetBytes(length),0,b,24,4);Buffer.BlockCopy(BitConverter.GetBytes(device),0,b,code==0x83730802?32:28,4);
  using(var h=CreateFile(@"\\.\Scsi"+port+":",0xc0000000,3,IntPtr.Zero,3,0,IntPtr.Zero)){
   if(h.IsInvalid)throw new Win32Exception();int r;
   if(!DeviceIoControl(h,0x4d008,b,b.Length,b,b.Length,out r,IntPtr.Zero))throw new Win32Exception();
   uint status=BitConverter.ToUInt32(b,20);if(status!=0)throw new Exception("RAM miniport status 0x"+status.ToString("X"));return b;
  }
 }
 public static string BackendPath(int port,uint device){var b=Control(port,0x83730802,device,0x44c);int length=BitConverter.ToUInt16(b,78);if(length<=0||(length&1)!=0||80+length>b.Length)throw new Exception("Invalid RAM backing path");return Encoding.Unicode.GetString(b,80,length).TrimEnd('\0');}
 public static bool IsPhysicalMemory(int port,uint device){string p=BackendPath(port,device);return p.Equals(@"\??\AWEAlloc",StringComparison.OrdinalIgnoreCase)||p.Equals(@"\Device\AWEAlloc",StringComparison.OrdinalIgnoreCase)||p.Equals(@"\\.\AWEAlloc",StringComparison.OrdinalIgnoreCase);}
 public static void Remove(int port,uint device){if(!IsPhysicalMemory(port,device))throw new Exception("Refusing to remove storage without the physical-memory backend");Control(port,0x83730806,device,4);}
}
'@
}
function Read-RmgRamState($Root) {
    $path=Join-Path $Root 'ram-cache.json'
    if(-not (Test-Path -LiteralPath $path)){return $null}
    $state=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
    if($state.Schema -ne 1 -or $state.Source -ine $script:RamSource -or $state.Backup -ine $script:RamBackup -or $state.CapacityBytes -ne $script:RamCapacity -or $state.Id -notmatch '^[a-f0-9]{32}$' -or $state.OriginalExists -isnot [bool] -or $state.Active -isnot [bool]){throw 'Invalid RAM-cache ledger; no cache or disk was changed'}
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
        $disks=@(Get-Disk | Where-Object {$_.Number -eq $State.DiskNumber -and $_.UniqueId -eq $State.DiskUniqueId -and $_.Signature -eq $State.DiskSignature -and $_.Size -eq $script:RamCapacity -and $_.FriendlyName -eq 'PassMark osfdisk'})
    }
    if($disks.Count -eq 0){return $null}
    if($disks.Count -ne 1){throw 'Ambiguous RAM disk identity'}
    $disk=$disks[0]
    if($disk.FriendlyName -ne 'PassMark osfdisk' -or $disk.Size -ne $script:RamCapacity -or $disk.UniqueId -ne $State.DiskUniqueId){throw 'RAM volume identity changed'}
    if($disk.Signature -ne $State.DiskSignature){throw 'RAM partition signature changed'}
    $physical=Get-CimInstance Win32_DiskDrive -Filter ('Index='+$disk.Number)
    if(-not $physical -or $physical.Model -ne 'PassMark osfdisk SCSI Disk Device'){throw 'Unexpected RAM storage device'}
    if($physical.SCSIBus -ne 0 -or $physical.SCSILogicalUnit -ne 0){throw 'Unsupported RAM provider SCSI addressing'}
    $unit=[uint32]$physical.SCSITargetId -shl 16
    Initialize-RmgRamNative
    if(-not [RmgRamNative]::IsPhysicalMemory($physical.SCSIPort,$unit)){throw 'RAM volume is not backed by locked physical memory'}
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
function Assert-RmgRamProvider {
    $tool=Join-Path $env:ProgramFiles 'OSFMount\OSFMount.com'
    Assert-RmgPlainDirectory (Split-Path $tool -Parent)
    $signature=Get-AuthenticodeSignature -LiteralPath $tool
    if($signature.Status.ToString() -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '^CN=PassMark Software Pty Ltd,'){throw 'Install the official signed OSFMount provider before selecting RAM mode'}
    $version=[string](Get-Item -LiteralPath (Join-Path (Split-Path $tool -Parent) 'OSFMount.exe')).VersionInfo.FileVersion
    if($version.Trim() -notmatch '^3\.3\.1000(?:\.0)?$'){throw 'RAM mode currently supports the reviewed OSFMount 3.3.1000 interface'}
    $awe=Get-CimInstance Win32_SystemDriver -Filter "Name='AWEAlloc'"
    if(-not $awe){throw 'RAM mode requires the official signed AWEAlloc physical-memory allocator'}
    $path=$awe.PathName -replace '^\\\?\?\\',''
    $allowed=Join-Path $env:WINDIR 'System32\DriverStore\FileRepository\'
    if(-not $path.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($path) -ine 'awealloc.sys'){throw 'Unexpected AWEAlloc driver path'}
    $sig=Get-AuthenticodeSignature -LiteralPath $path
    if($sig.Status.ToString() -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Windows Hardware Compatibility Publisher|Arsenal Consulting|LTR Data'){throw 'A valid allocator driver signature is required'}
    if($awe.State -ne 'Running'){Start-Service -Name AWEAlloc -ErrorAction Stop}
    return $tool
}
function Invoke-RmgRamTool($Tool,$Arguments) {
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$Tool;$psi.Arguments=$Arguments;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process;$process.StartInfo=$psi
    try {
        $null=$process.Start();$process.StandardInput.Close()
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(30000)){$process.Kill();throw 'RAM provider timed out; inspect the retained creation ledger before retrying'}
        $output=$stdout.GetAwaiter().GetResult();$errorText=$stderr.GetAwaiter().GetResult()
        if($process.ExitCode -ne 0){throw ('RAM provider failed: '+$errorText+' '+$output)}
    }finally{$process.Dispose()}
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
    $tool=Assert-RmgRamProvider;$seed=Get-RmgRamSeed
    $state=Read-RmgRamState $StateRoot
    if(-not $state -or -not $state.Active){
        $link=[RmgRamNative]::ReadLink($script:RamSource)
        if($link -or [IO.File]::Exists($script:RamBackup)){throw 'Existing cache link or backup is not owned by a new RAM installation'}
        $exists=[IO.File]::Exists($script:RamSource)
        if($exists -and (Get-FileHash -LiteralPath $script:RamSource).Hash -ne (Get-FileHash -LiteralPath $seed).Hash){throw 'Current cache is not the official AMD executable'}
        $state=[pscustomobject]@{Schema=1;Id=[guid]::NewGuid().ToString('N');Source=$script:RamSource;Backup=$script:RamBackup;OriginalExists=$exists;OriginalHash=$(if($exists){(Get-FileHash -LiteralPath $script:RamSource).Hash}else{''});Active=$true;CapacityBytes=$script:RamCapacity;Phase='Captured';VolumeRoot='';Target='';PreviousTarget='';DiskNumber=-1;DiskUniqueId='';DiskSignature=0;CapturedUtc=[DateTime]::UtcNow.ToString('o')}
        Write-RmgJson (Join-Path $StateRoot 'ram-cache.json') $state
    }
    $device=Get-RmgRamDisk $state
    if(-not $device){
        if($state.Phase -in @('Creating','Created')){throw 'An interrupted RAM creation needs review; refusing to allocate another disk'}
        $state.Phase='Creating';Write-RmgJson (Join-Path $StateRoot 'ram-cache.json') $state
        $before=@(Get-Disk | Select-Object -ExpandProperty Number)
        Invoke-RmgRamTool $tool '-a -t file -f \\.\AWEAlloc -s 64M -o rw,physical'
        $new=@(Get-Disk | Where-Object {$_.Number -notin $before})
        if($new.Count -ne 1 -or $new[0].FriendlyName -ne 'PassMark osfdisk' -or $new[0].Size -ne $script:RamCapacity -or $new[0].PartitionStyle -ne 'RAW'){throw 'Unexpected new RAM storage; no disk was formatted'}
        $physical=Get-CimInstance Win32_DiskDrive -Filter ('Index='+$new[0].Number)
        if($physical.SCSIBus -ne 0 -or $physical.SCSILogicalUnit -ne 0){throw 'Unsupported new RAM provider SCSI addressing'}
        $unit=[uint32]$physical.SCSITargetId -shl 16
        if(-not [RmgRamNative]::IsPhysicalMemory($physical.SCSIPort,$unit)){throw 'New storage is not the requested physical-memory backend; no disk was formatted'}
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
        [RmgRamNative]::Remove($device.Port,$device.Unit)
        for($n=0;$n -lt 20;$n++){
            if(-not @(Get-Disk | Where-Object {$_.Path -eq $device.Disk.Path}).Count){break}
            Start-Sleep -Milliseconds 100
        }
        if(@(Get-Disk | Where-Object {$_.Path -eq $device.Disk.Path}).Count){throw 'RAM detach is pending; retained ledger allows cleanup retry'}
    }
    $state.Active=$false;$state.Phase='Restored';Write-RmgJson (Join-Path $StateRoot 'ram-cache.json') $state
}
function Get-RmgBackendPackage {
    param([string]$Root,[string]$PayloadRoot,[ValidateSet('osfmount-3.3.1000.exe','Arsenal-DriverFiles.zip')][string]$Name,[switch]$Offline)
    Initialize-RmgStateRoot $Root
    $items=@{
        'osfmount-3.3.1000.exe'=@{Hash='5986BEBD3F4954580B5EC910749712E533438A5EF4589C17562F6B07F386CB76';Url='https://www.osforensics.com/downloads/osfmount.exe'}
        'Arsenal-DriverFiles.zip'=@{Hash='DE8A919F69F6FD91E3730270ADBB7FA7FE56AD1BF1C535479F3345102C3253E9';Url='https://raw.githubusercontent.com/ArsenalRecon/Arsenal-Image-Mounter/c5c1415f91dbca4bdd7413a29d46e0acf74907a2/DriverSetup/DriverFiles.zip'}
    }
    $target=Join-Path $Root $Name
    if($Offline){
        if(-not $PayloadRoot -or -not [IO.File]::Exists((Join-Path $PayloadRoot $Name))){throw ('Bundled offline payload is missing: '+$Name)}
        $source=Join-Path $PayloadRoot $Name
        if([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($target)){Copy-Item -LiteralPath $source -Destination $target -Force}
    }elseif(-not [IO.File]::Exists($target)){
        Invoke-WebRequest -UseBasicParsing -Uri $items[$Name].Url -OutFile $target
    }
    if((Get-FileHash -LiteralPath $target).Hash -ne $items[$Name].Hash){throw ('Dependency checksum mismatch: '+$Name)}
    return $target
}
function Install-RmgOsfMount {
    param([string]$Setup)
    $signature=Get-AuthenticodeSignature -LiteralPath $Setup
    if($signature.Status.ToString() -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '^CN=PassMark Software Pty Ltd,'){throw 'Invalid OSFMount installer signature'}
    $before=@(Get-Process -Name OSFMount -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$Setup
    $psi.Arguments='/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $process=New-Object Diagnostics.Process;$process.StartInfo=$psi
    try{$null=$process.Start();if(-not $process.WaitForExit(55000)){throw 'OSFMount setup timed out; inspect installation before retrying'};if($process.ExitCode -ne 0){throw ('OSFMount setup returned '+$process.ExitCode+'; no reboot was requested')}}finally{$process.Dispose()}
    foreach($gui in @(Get-Process -Name OSFMount -ErrorAction SilentlyContinue)){
        if($gui.Id -notin $before -and $gui.Path -ieq (Join-Path $env:ProgramFiles 'OSFMount\OSFMount.exe')){$null=$gui.CloseMainWindow()}
    }
}
function Install-RmgAweAllocPackage {
    param([string]$Zip,[string]$Root)
    # Always expand the just-verified archive, not a leftover extraction directory.
    $dest=Join-Path $Root ('arsenal-drivers-'+[guid]::NewGuid().ToString('N'))
    Expand-Archive -LiteralPath $Zip -DestinationPath $dest
    $package=Join-Path $dest 'Win10'
    $cat=Get-AuthenticodeSignature -LiteralPath (Join-Path $package 'phdskmnt.cat')
    if($cat.Status.ToString() -ne 'Valid' -or $cat.SignerCertificate.Subject -notmatch 'CN=Microsoft Windows Hardware Compatibility Publisher,'){throw 'A Microsoft hardware catalog is required for the allocator package'}
    $output=& "$env:WINDIR\System32\pnputil.exe" /add-driver (Join-Path $package 'phdskmnt.inf')
    if($LASTEXITCODE -ne 0){throw ('Signed allocator package staging failed: '+($output -join ' '))}
    $hash=(Get-FileHash -LiteralPath (Join-Path $package 'x64\awealloc.sys')).Hash
    $matches=@(Get-ChildItem -LiteralPath "$env:WINDIR\System32\DriverStore\FileRepository" -Directory -Filter 'phdskmnt.inf_amd64_*' | ForEach-Object {Join-Path $_.FullName 'x64\awealloc.sys'} | Where-Object {[IO.File]::Exists($_) -and (Get-FileHash -LiteralPath $_).Hash -eq $hash})
    if($matches.Count -ne 1){throw 'Unable to identify the staged allocator binary uniquely'}
    $output=& "$env:WINDIR\System32\sc.exe" create AWEAlloc type= kernel start= demand binPath= $matches[0] DisplayName= 'AWE Allocation Driver'
    if($LASTEXITCODE -ne 0){throw ('Allocator service registration failed: '+($output -join ' '))}
}
function Install-RmgRamBackend {
    [CmdletBinding(SupportsShouldProcess)]param([string]$StateRoot=$script:DefaultState,[string]$PayloadRoot,[switch]$Offline)
    Assert-RmgAdmin
    if(-not $PSCmdlet.ShouldProcess('OSFMount and AWEAlloc','Install verified signed RAM-storage dependencies without restarting Windows')){return}
    Initialize-RmgStateRoot $StateRoot
    $root=Join-Path $StateRoot 'ram-backend-downloads';Initialize-RmgStateRoot $root
    $setup=$null;$zip=$null
    # Offline setup requires a complete bundle and never falls back to a download.
    if($Offline){
        $setup=Get-RmgBackendPackage -Root $root -PayloadRoot $PayloadRoot -Name 'osfmount-3.3.1000.exe' -Offline
        $zip=Get-RmgBackendPackage -Root $root -PayloadRoot $PayloadRoot -Name 'Arsenal-DriverFiles.zip' -Offline
    }
    if(-not [IO.File]::Exists((Join-Path $env:ProgramFiles 'OSFMount\OSFMount.com'))){
        if(-not $setup){$setup=Get-RmgBackendPackage -Root $root -Name 'osfmount-3.3.1000.exe'}
        Install-RmgOsfMount $setup
    }
    if(-not (Get-CimInstance Win32_SystemDriver -Filter "Name='AWEAlloc'")){
        if(-not $zip){$zip=Get-RmgBackendPackage -Root $root -Name 'Arsenal-DriverFiles.zip'}
        Install-RmgAweAllocPackage $zip $root
    }
    $null=Assert-RmgRamProvider
    [pscustomobject]@{Ready=$true;Offline=[bool]$Offline;Provider='OSFMount';Allocator='AWEAlloc';RebootRequested=$false;DownloadDirectory=$root}
}
