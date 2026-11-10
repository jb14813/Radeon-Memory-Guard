# Headless controller for the original signed Arsenal miniport and AWEAlloc.
# Protocol reference: Arsenal Image Mounter c5c1415, Unmanaged Source/phdskmnt/inc/common.h.
function Initialize-RmgStorageNative {
 if('RmgStorageNative' -as [type]){return}
 Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public sealed class RmgStorageInstallResult {
 public string InstanceId;
 public bool RebootRequired;
}
public static class RmgStorageNative {
 const uint Capacity=67108864, AllDevices=0x00FFFFFF;
 static readonly Guid ClassGuid=new Guid("4D36E97B-E325-11CE-BFC1-08002BE10318");
 [StructLayout(LayoutKind.Sequential)] struct DevInfo {public int Size;public Guid ClassGuid;public uint DevInst;public UIntPtr Reserved;}
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct InstallParams {
  public int Size;public uint Flags,FlagsEx;public IntPtr Parent,Callback,CallbackContext,FileQueue;public UIntPtr ClassReserved;public uint Reserved;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)] public string DriverPath;
 }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string p,uint a,uint s,IntPtr sa,uint c,uint f,IntPtr t);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool DeviceIoControl(SafeFileHandle h,uint c,byte[] i,int il,byte[] o,int ol,out int r,IntPtr over);
 [DllImport("setupapi.dll",SetLastError=true)] static extern IntPtr SetupDiCreateDeviceInfoList(ref Guid g,IntPtr w);
 [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetupDiCreateDeviceInfo(IntPtr s,string name,ref Guid g,string desc,IntPtr w,uint flags,ref DevInfo d);
 [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetupDiSetDeviceRegistryProperty(IntPtr s,ref DevInfo d,uint p,byte[] b,uint len);
 [DllImport("setupapi.dll",SetLastError=true)] static extern bool SetupDiCallClassInstaller(uint f,IntPtr s,ref DevInfo d);
 [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetupDiGetDeviceInstanceId(IntPtr s,ref DevInfo d,StringBuilder b,int len,out int required);
 [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetupDiOpenDeviceInfo(IntPtr s,string id,IntPtr w,uint flags,ref DevInfo d);
 [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetupDiGetDeviceRegistryProperty(IntPtr s,ref DevInfo d,uint property,out uint type,byte[] buffer,uint length,out uint required);
 [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetupDiGetDeviceInstallParams(IntPtr s,ref DevInfo d,ref InstallParams p);
 [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetupDiSetDeviceInstallParams(IntPtr s,ref DevInfo d,ref InstallParams p);
 [DllImport("setupapi.dll",SetLastError=true)] static extern bool SetupDiBuildDriverInfoList(IntPtr s,ref DevInfo d,uint type);
 [DllImport("setupapi.dll",SetLastError=true)] static extern bool SetupDiSelectBestCompatDrv(IntPtr s,ref DevInfo d);
 [DllImport("setupapi.dll",SetLastError=true)] static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);

 static void Put(byte[] b,int offset,uint value){Buffer.BlockCopy(BitConverter.GetBytes(value),0,b,offset,4);}
 static void Port(int port){if(port<0||port>254)throw new ArgumentOutOfRangeException("port");}
 static void Unit(uint unit){if(unit>=AllDevices)throw new ArgumentOutOfRangeException("unit","A specific LUN is required");}
 static byte[] Header(uint code,int payload){
  byte[] b=new byte[28+payload];Put(b,0,28);Buffer.BlockCopy(Encoding.ASCII.GetBytes("PhDskMnt"),0,b,4,8);
  Put(b,12,30);Put(b,16,code);Put(b,24,(uint)payload);return b;
 }
 public static byte[] CreatePacket(long size){
  if(size!=Capacity)throw new ArgumentOutOfRangeException("size");
  byte[] name=Encoding.Unicode.GetBytes(@"\Device\AWEAlloc");
  byte[] b=Header(0x83730801,34+name.Length);Put(b,28,AllDevices);
  Buffer.BlockCopy(BitConverter.GetBytes(size),0,b,32,8);Put(b,40,512);Put(b,56,0x1110);
  Buffer.BlockCopy(BitConverter.GetBytes((ushort)name.Length),0,b,60,2);Buffer.BlockCopy(name,0,b,62,name.Length);return b;
 }
 public static bool ValidatePhysical(byte[] b,uint unit){
  if(b==null||b.Length<62||unit>=AllDevices)return false;
  int length=BitConverter.ToUInt16(b,60);
  if(length!=32||62+length>b.Length||BitConverter.ToUInt32(b,28)!=unit||BitConverter.ToInt64(b,32)!=Capacity||BitConverter.ToUInt32(b,40)!=512)return false;
  uint flags=BitConverter.ToUInt32(b,56);
  return (flags&~0x10000u)==0x1110 && Encoding.Unicode.GetString(b,62,length).Equals(@"\Device\AWEAlloc",StringComparison.OrdinalIgnoreCase);
 }
 static byte[] Control(int port,byte[] b,bool version){
  Port(port);
  using(var h=CreateFile(@"\\.\Scsi"+port+":",0xc0000000,3,IntPtr.Zero,3,0,IntPtr.Zero)){
   if(h.IsInvalid)throw new Win32Exception();int count;
   if(!DeviceIoControl(h,0x4d008,b,b.Length,b,b.Length,out count,IntPtr.Zero))throw new Win32Exception();
   if(count<28||count>b.Length)throw new Exception("Invalid miniport response length");
   uint status=BitConverter.ToUInt32(b,20);
   if(version){if(status!=0x0101)throw new Exception("Unsupported miniport protocol version");}
   else if((status&0x80000000)!=0)throw new Exception("Miniport status 0x"+status.ToString("X"));
   if(count!=b.Length)Array.Resize(ref b,count);return b;
  }
 }
 public static void CheckAdapter(int port){Control(port,Header(0x83730800,4),true);}
 public static uint Create(int port){
  Port(port);CheckAdapter(port);byte[] b=Control(port,CreatePacket(Capacity),false);
  if(b.Length<32)throw new Exception("Truncated create reply");uint unit=BitConverter.ToUInt32(b,28);Unit(unit);
  return unit; // Persist this identity before querying/formatting the newly created device.
 }
 public static byte[] Query(int port,uint unit){Port(port);Unit(unit);byte[] b=Header(0x83730802,2048);Put(b,28,unit);return Control(port,b,false);}
 public static bool IsPhysicalMemory(int port,uint unit){
  return ValidatePhysical(Query(port,unit),unit);
 }
 public static void Remove(int port,uint unit){
  Port(port);Unit(unit);if(!IsPhysicalMemory(port,unit))throw new Exception("Refusing removal of an unexpected storage device");
  byte[] b=Header(0x83730806,4);Put(b,28,unit);Control(port,b,false);
 }
 public static RmgStorageInstallResult InstallRoot(string inf){return InstallRoot(inf,null);}
 public static RmgStorageInstallResult InstallRoot(string inf,Action<string> registeredCallback){
  if(!System.IO.Path.IsPathRooted(inf)||!System.IO.Path.GetFileName(inf).Equals("phdskmnt.inf",StringComparison.OrdinalIgnoreCase)||!System.IO.File.Exists(inf))throw new ArgumentException("Original INF path required");
  object deleteFlag=Microsoft.Win32.Registry.GetValue(@"HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\phdskmnt","DeleteFlag",null);
  if(deleteFlag!=null&&Convert.ToInt32(deleteFlag)!=0)throw new InvalidOperationException("The miniport service is pending deletion. Wait for a normal Windows restart; no device was installed.");
  Guid guid=ClassGuid;IntPtr set=SetupDiCreateDeviceInfoList(ref guid,IntPtr.Zero);
  if(set==new IntPtr(-1))throw new Win32Exception();
  DevInfo info=new DevInfo();info.Size=Marshal.SizeOf(typeof(DevInfo));bool registered=false,installed=false;
  try {
   if(!SetupDiCreateDeviceInfo(set,"SCSIAdapter",ref guid,"Arsenal Image Mounter",IntPtr.Zero,1,ref info))throw new Win32Exception();
   byte[] id=Encoding.Unicode.GetBytes("ROOT\\PhDskMnt\0\0");
   if(!SetupDiSetDeviceRegistryProperty(set,ref info,1,id,(uint)id.Length)||!SetupDiCallClassInstaller(0x19,set,ref info))throw new Win32Exception();
   registered=true;StringBuilder instance=new StringBuilder(512);int required;
   if(!SetupDiGetDeviceInstanceId(set,ref info,instance,instance.Capacity,out required))throw new Win32Exception();
   if(registeredCallback!=null)registeredCallback(instance.ToString());
   InstallParams p=new InstallParams();p.Size=Marshal.SizeOf(typeof(InstallParams));
   if(!SetupDiGetDeviceInstallParams(set,ref info,ref p))throw new Win32Exception();
   p.Flags|=0x810000;p.DriverPath=inf;
   if(!SetupDiSetDeviceInstallParams(set,ref info,ref p)||!SetupDiBuildDriverInfoList(set,ref info,2)||!SetupDiSelectBestCompatDrv(set,ref info)||!SetupDiCallClassInstaller(2,set,ref info))throw new Win32Exception();
   if(!SetupDiGetDeviceInstallParams(set,ref info,ref p))throw new Win32Exception();
   installed=true;return new RmgStorageInstallResult{InstanceId=instance.ToString(),RebootRequired=(p.Flags&0x180)!=0};
  } finally {if(registered&&!installed)SetupDiCallClassInstaller(5,set,ref info);SetupDiDestroyDeviceInfoList(set);}
 }
 public static bool RemoveRoot(string instance){
  if(instance==null||!instance.StartsWith(@"ROOT\SCSIADAPTER\",StringComparison.OrdinalIgnoreCase))throw new ArgumentException("Owned SCSI root device required");
  Guid guid=ClassGuid;IntPtr set=SetupDiCreateDeviceInfoList(ref guid,IntPtr.Zero);
  if(set==new IntPtr(-1))throw new Win32Exception();
  try {
   DevInfo info=new DevInfo();info.Size=Marshal.SizeOf(typeof(DevInfo));
   if(!SetupDiOpenDeviceInfo(set,instance,IntPtr.Zero,0,ref info))throw new Win32Exception();
   byte[] property=new byte[4096];uint type,required;
   if(!SetupDiGetDeviceRegistryProperty(set,ref info,1,out type,property,(uint)property.Length,out required)||required>property.Length)throw new Win32Exception();
   string[] ids=Encoding.Unicode.GetString(property,0,(int)required).TrimEnd('\0').Split('\0');bool match=false;
   foreach(string id in ids)if(id.Equals(@"ROOT\PhDskMnt",StringComparison.OrdinalIgnoreCase))match=true;
   if(!match)throw new InvalidOperationException("Refusing removal of an unrelated root device");
   bool bound=SetupDiGetDeviceRegistryProperty(set,ref info,4,out type,property,(uint)property.Length,out required);
   if(!bound){int error=Marshal.GetLastWin32Error();if(error!=13)throw new Win32Exception(error);}
   else {
    if(required>property.Length)throw new Exception("Invalid service property length");
    string service=Encoding.Unicode.GetString(property,0,(int)required).TrimEnd('\0');
    if(service.Length!=0&&!service.Equals("phdskmnt",StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Unexpected storage service binding");
   }
   if(!SetupDiCallClassInstaller(5,set,ref info))throw new Win32Exception();
   InstallParams p=new InstallParams();p.Size=Marshal.SizeOf(typeof(InstallParams));
   if(!SetupDiGetDeviceInstallParams(set,ref info,ref p))throw new Win32Exception();
   return (p.Flags&0x180)!=0;
  }finally{SetupDiDestroyDeviceInfoList(set);}
 }
}
'@
}

$script:StorageHashes=@{
 phdskmnt='C18A61E9B248FCF68421A72A706F7FDD41BE5929B62DD50F33BD19ABA0A1EE69'
 AWEAlloc='80424CE40FCDA4C41FDF3DBCF90B4C5C8156E4A635BFD86153E7F161B19180FE'
 aimwrfltr='D74EC91FE8CC58BD09084274D81B7A2767151165AB751B8F7E384556D5D3353D'
 vhdaccess='8FC4BC1DA1DF272179067C73DC6AA95200B7BFEBCBFB06E8FF5552A18E3E0EE0'
 deviodrv='24F345428C57C02207EACB6583B7B555DEE7047494D36162490650013B030B56'
 deviosvc='3BDCDDDE741CBD92DD32E4314399FC14893F7180D6FF6AE1B0F71D5D2A2CAED9'
}
function Read-RmgStorageState($Root) {
 $path=Join-Path $Root 'storage-backend.json'
 if(-not (Test-Path -LiteralPath $path)){return $null}
 $state=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
 if($state.Schema -ne 1 -or $state.Provider -ne 'Arsenal' -or $state.RootOwned -isnot [bool] -or $state.MiniportOwned -isnot [bool] -or $state.AweOwned -isnot [bool] -or $state.PackageOwned -isnot [bool] -or $state.Staging -isnot [bool]){throw 'Invalid storage ownership ledger'}
 if($state.DeviceInstanceId -and $state.DeviceInstanceId -notmatch '^ROOT\\SCSIADAPTER\\[0-9A-F]{4}$'){throw 'Unexpected storage device identity'}
 if($state.RootOwned -and -not $state.DeviceInstanceId){throw 'Owned controller identity is missing'}
 if($state.PublishedInf -and $state.PublishedInf -notmatch '^oem[0-9]+\.inf$'){throw 'Unexpected published driver package'}
 foreach($name in @($state.AuxiliaryOwned)){if($name -notin @('aimwrfltr','vhdaccess','deviodrv','deviosvc')){throw 'Unexpected auxiliary ownership claim'}}
 foreach($inf in @($state.PriorPublishedInfs)){if($inf -notmatch '^oem[0-9]+\.inf$'){throw 'Unexpected staging inventory'}}
 if($state.AweOriginal -and ($state.AweOriginal.Start -notin @(0,1,2,3,4) -or -not $state.AweOriginal.ImagePath)){throw 'Invalid allocator configuration backup'}
 return $state
}
function Get-RmgStorageDriver([ValidateSet('phdskmnt','AWEAlloc')]$Name) {
 $driver=Get-CimInstance Win32_SystemDriver -Filter ("Name='"+$Name+"'")
 if(-not $driver){throw ('Missing signed storage driver: '+$Name)}
 $path=([string]$driver.PathName).Trim('"') -replace '^\\\?\?\\',''
 if($path.StartsWith('\SystemRoot\',[StringComparison]::OrdinalIgnoreCase)){$path=Join-Path $env:WINDIR $path.Substring(12)}
 $path=[Environment]::ExpandEnvironmentVariables($path)
 $allowed=Join-Path $env:WINDIR 'System32\'
 if(-not $path.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($path) -ine ($Name+'.sys')){throw 'Unexpected storage driver path'}
 if((Get-FileHash -LiteralPath $path).Hash -ne $script:StorageHashes[$Name]){throw ('Untested or changed storage driver: '+$Name)}
 $signature=Get-AuthenticodeSignature -LiteralPath $path
 if($signature.Status.ToString() -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '^CN=Microsoft Windows Hardware Compatibility Publisher,'){throw 'A valid Microsoft hardware signature is required'}
 return $driver
}
function Invoke-RmgStorageAdapterCheck($Port){[RmgStorageNative]::CheckAdapter($Port)}
function Get-RmgStoragePorts {
 Initialize-RmgStorageNative
 foreach($key in @(Get-ChildItem -LiteralPath 'HKLM:\HARDWARE\DEVICEMAP\Scsi')){
  if((Get-ItemProperty -LiteralPath $key.PSPath).Driver -eq 'phdskmnt'){
   $port=[int]($key.PSChildName -replace '\D','')
   try{Invoke-RmgStorageAdapterCheck $port;$port}catch{
    $cause=$_.Exception;while($cause.InnerException){$cause=$cause.InnerException}
    if($cause -is [ComponentModel.Win32Exception] -and $cause.NativeErrorCode -in @(2,3,1167)){continue}
    throw
   }
  }
 }
}
function Assert-RmgRamProvider {
 $miniport=Get-RmgStorageDriver phdskmnt
 if($miniport.State -ne 'Running'){throw 'The signed Arsenal PnP controller is not running; no legacy load was attempted'}
 $awe=Get-RmgStorageDriver AWEAlloc
 if($awe.State -ne 'Running'){Start-Service -Name AWEAlloc -ErrorAction Stop}
 $ports=@(Get-RmgStoragePorts)
 if($ports.Count -eq 0){throw 'No signed Arsenal PnP storage adapter is available'}
 [pscustomobject]@{Provider='Arsenal';Allocator='AWEAlloc';Port=[int]$ports[0]}
}
function Get-RmgBackendPackage {
 param([string]$Root,[string]$PayloadRoot,[ValidateSet('Arsenal-DriverFiles.zip')][string]$Name='Arsenal-DriverFiles.zip',[switch]$Offline)
 Initialize-RmgStateRoot $Root
 $target=Join-Path $Root $Name
 if($Offline){
  if(-not $PayloadRoot -or -not [IO.File]::Exists((Join-Path $PayloadRoot $Name))){throw 'Bundled offline driver payload is missing'}
  $source=Join-Path $PayloadRoot $Name
  if([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($target)){Copy-Item -LiteralPath $source -Destination $target -Force}
 }elseif(-not [IO.File]::Exists($target)){
  Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/ArsenalRecon/Arsenal-Image-Mounter/c5c1415f91dbca4bdd7413a29d46e0acf74907a2/DriverSetup/DriverFiles.zip' -OutFile $target
 }
 if((Get-FileHash -LiteralPath $target).Hash -ne 'DE8A919F69F6FD91E3730270ADBB7FA7FE56AD1BF1C535479F3345102C3253E9'){throw 'Driver payload checksum mismatch'}
 return $target
}
function Install-RmgStorageRoot($Inf,$Registered) {
 Initialize-RmgStorageNative
 [RmgStorageNative]::InstallRoot($Inf,$Registered)
}
function New-RmgStorageRegistrationCallback($State,$Path) {
 $ownerModule=$ExecutionContext.SessionState.Module
 $callback=[Action[string]]{
  param($id)
  & $ownerModule {param($s,$p,$instance) $s.DeviceInstanceId=$instance;$s.RootOwned=$true;$s.Phase='Registered';Write-RmgJson $p $s} $State $Path $id
 }.GetNewClosure()
 return $callback
}
function Get-RmgOwnedStorageServicePath($Name) {
 if($Name -notin @('phdskmnt','AWEAlloc','aimwrfltr','vhdaccess','deviodrv','deviosvc')){throw 'Unexpected storage service removal'}
 $key='HKLM:\SYSTEM\CurrentControlSet\Services\'+$Name
 if(-not (Test-Path -LiteralPath $key)){return}
 $path=([string](Get-ItemProperty -LiteralPath $key).ImagePath).Trim('"') -replace '^\\\?\?\\',''
 if($path.StartsWith('\SystemRoot\',[StringComparison]::OrdinalIgnoreCase)){$path=Join-Path $env:WINDIR $path.Substring(12)}
 $path=[Environment]::ExpandEnvironmentVariables($path)
 $extension=if($Name -eq 'deviosvc'){'.exe'}else{'.sys'}
 if(-not $path.StartsWith((Join-Path $env:WINDIR 'System32\'),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($path) -ine ($Name+$extension) -or (Get-FileHash -LiteralPath $path).Hash -ne $script:StorageHashes[$Name]){throw ('Storage service was changed; retained: '+$Name)}
 return $path
}
function Remove-RmgOwnedStorageService($Name) {
 if(-not (Get-RmgOwnedStorageServicePath $Name)){return}
 $svc=Get-Service -Name $Name -ErrorAction SilentlyContinue
 if($svc){try{$stopped=($svc.Status -eq 'Stopped')}finally{$svc.Dispose()};if(-not $stopped){throw ('Storage service remains active: '+$Name)}}
 $out=& "$env:WINDIR\System32\sc.exe" delete $Name
 if($LASTEXITCODE -ne 0){throw ('Storage service removal failed: '+$Name)}
}
function Restore-RmgAweConfiguration($Original) {
 $key='HKLM:\SYSTEM\CurrentControlSet\Services\AWEAlloc'
 Set-ItemProperty -LiteralPath $key -Name Start -Value $Original.Start
 Set-ItemProperty -LiteralPath $key -Name ImagePath -Value $Original.ImagePath
 $check=Get-ItemProperty -LiteralPath $key
 if($check.Start -ne $Original.Start -or $check.ImagePath -ine $Original.ImagePath){throw 'Shared allocator configuration restoration failed'}
}
function Repair-RmgStorageAuxiliary($Root,$State) {
 $path=Join-Path $Root 'storage-backend.json';$errors=@()
 foreach($name in @($State.AuxiliaryOwned)){
  try{
   Remove-RmgOwnedStorageService $name
   $State.AuxiliaryOwned=@($State.AuxiliaryOwned|Where-Object{$_ -ne $name});Write-RmgJson $path $State
  }catch{
   $errors+=$_.Exception.Message
   # Prevent newly introduced optional components from starting on a later boot.
   try{if(Get-RmgOwnedStorageServicePath $name){Set-Service -Name $name -StartupType Disabled -ErrorAction Stop}}catch{}
  }
 }
 if($State.AweOriginal){
  try{Restore-RmgAweConfiguration $State.AweOriginal;$State.AweOriginal=$null;Write-RmgJson $path $State}catch{$errors+=$_.Exception.Message}
 }
 if($errors.Count){throw ($errors -join '; ')}
}
function Get-RmgPinnedStoragePackages {
 foreach($package in @(Get-WindowsDriver -Online|Where-Object{$_.OriginalFileName -like '*\phdskmnt.inf'})){
  $inf=[Environment]::ExpandEnvironmentVariables($package.OriginalFileName)
  if((Get-FileHash -LiteralPath $inf).Hash -ne '155F55BEF8B4F27581382A0C88B1A81382AF332917C7EA66276BFBD5D8903EED'){continue}
  $directory=Split-Path $inf -Parent
  if((Get-FileHash -LiteralPath (Join-Path $directory 'x64\phdskmnt.sys')).Hash -eq $script:StorageHashes.phdskmnt -and (Get-FileHash -LiteralPath (Join-Path $directory 'x64\awealloc.sys')).Hash -eq $script:StorageHashes.AWEAlloc){$package}
 }
}
function Recover-RmgStorageStaging($Root,$State) {
 if(-not $State.Staging){return}
 $pinned=@(Get-RmgPinnedStoragePackages)
 if($pinned.Count -gt 1){throw 'Ambiguous pinned driver package inventory'}
 if($pinned.Count -eq 1){
  $alreadyOwned=($State.PackageOwned -and $State.PublishedInf -eq $pinned[0].Driver)
  $State.PublishedInf=$pinned[0].Driver;$State.PackageOwned=($alreadyOwned -or $pinned[0].Driver -notin @($State.PriorPublishedInfs))
 }
 $State.Staging=$false;Write-RmgJson (Join-Path $Root 'storage-backend.json') $State
}
function Assert-RmgStorageRegistrationAvailable($State) {
 if($State.RootOwned -and (Get-PnpDevice -InstanceId $State.DeviceInstanceId -ErrorAction SilentlyContinue)){throw 'A previously registered owned controller is not ready. Restore/uninstall that registration before retrying; no new controller was created'}
}
function Remove-RmgOwnedDriverPackage($Inf) {
 if($Inf -notmatch '^oem[0-9]+\.inf$'){throw 'Invalid owned driver package'}
 if(-not (Test-Path -LiteralPath (Join-Path $env:WINDIR ('INF\'+$Inf)))){return}
 if($Inf -notin @(Get-RmgPinnedStoragePackages|Select-Object -ExpandProperty Driver)){throw 'Published driver package identity changed; package retained'}
 $out=& "$env:WINDIR\System32\pnputil.exe" /delete-driver $Inf
 if($LASTEXITCODE -ne 0){throw 'Shared driver package retained by Windows'}
}
function Install-RmgStoragePackage($Zip,$Root) {
 $ledgerPath=Join-Path $Root 'storage-backend.json'
 $state=Read-RmgStorageState $Root
 if(-not $state){
  $state=[pscustomobject]@{Schema=1;Provider='Arsenal';RootOwned=$false;MiniportOwned=$false;AweOwned=$false;PackageOwned=$false;DeviceInstanceId='';PublishedInf='';Phase='Preparing';AuxiliaryOwned=@();AweOriginal=$null;Staging=$false;PriorPublishedInfs=@();CapturedUtc=[DateTime]::UtcNow.ToString('o')}
  Write-RmgJson $ledgerPath $state
 }
 Recover-RmgStorageStaging $Root $state
 Repair-RmgStorageAuxiliary $Root $state
 $ports=@(Get-RmgStoragePorts)
 if($ports.Count -gt 0){$null=Assert-RmgRamProvider;$state.Phase='Ready';Write-RmgJson $ledgerPath $state;return}
 Assert-RmgStorageRegistrationAvailable $state
 $services=@(Get-CimInstance Win32_SystemDriver|Where-Object{$_.Name -in @('phdskmnt','AWEAlloc','aimwrfltr','vhdaccess','deviodrv')})
 if(@($services|Where-Object{$_.Name -eq 'phdskmnt'}).Count){throw 'An existing Arsenal controller is not ready; its registration was left unchanged'}
 if(@($services|Where-Object{$_.Name -in @('aimwrfltr','vhdaccess','deviodrv')}).Count -or (Get-Service -Name deviosvc -ErrorAction SilentlyContinue)){throw 'Existing Arsenal auxiliary components were left unchanged; prepare the shared controller separately'}
 $aweKey='HKLM:\SYSTEM\CurrentControlSet\Services\AWEAlloc'
 if(Test-Path -LiteralPath $aweKey){
  $aweBefore=Get-ItemProperty -LiteralPath $aweKey;$null=Get-RmgStorageDriver AWEAlloc
  $state.AweOriginal=[pscustomobject]@{Start=$aweBefore.Start;ImagePath=$aweBefore.ImagePath}
 }else{$state.AweOwned=$true}
 $dest=Join-Path $Root ('storage-package-'+[guid]::NewGuid().ToString('N'))
 Expand-Archive -LiteralPath $Zip -DestinationPath $dest
 $package=Join-Path $dest 'Win10'
 $cat=Get-AuthenticodeSignature -LiteralPath (Join-Path $package 'phdskmnt.cat')
 if($cat.Status.ToString() -ne 'Valid' -or $cat.SignerCertificate.Subject -notmatch '^CN=Microsoft Windows Hardware Compatibility Publisher,'){throw 'Original Microsoft-signed storage catalog required'}
 foreach($name in @('phdskmnt','AWEAlloc')){if((Get-FileHash -LiteralPath (Join-Path $package ('x64\'+$name+'.sys'))).Hash -ne $script:StorageHashes[$name]){throw 'Unexpected storage driver payload'}}
 $state.PriorPublishedInfs=@(Get-WindowsDriver -Online|Where-Object{$_.OriginalFileName -like '*\phdskmnt.inf'}|Select-Object -ExpandProperty Driver)
 $state.Staging=$true;Write-RmgJson $ledgerPath $state
 $output=& "$env:WINDIR\System32\pnputil.exe" /add-driver (Join-Path $package 'phdskmnt.inf')
 $stagingExit=$LASTEXITCODE
 Recover-RmgStorageStaging $Root $state
 if($stagingExit -ne 0){throw ('Original driver package staging failed: '+($output -join ' '))}
 if(-not $state.PublishedInf){throw 'Pinned driver package was not found after staging'}
 # All four were verified absent before the unmodified INF may register them.
 $state.AuxiliaryOwned=@('aimwrfltr','vhdaccess','deviodrv','deviosvc');$state.MiniportOwned=$true
 Write-RmgJson $ledgerPath $state
 $registered=New-RmgStorageRegistrationCallback $state $ledgerPath
 try {
  $installed=Install-RmgStorageRoot (Join-Path $package 'phdskmnt.inf') $registered
  if($installed.RebootRequired){throw 'Windows deferred storage activation; no reboot was requested and existing protection was retained'}
 }finally{Repair-RmgStorageAuxiliary $Root $state}
 $null=Assert-RmgRamProvider;$state.Phase='Ready';Write-RmgJson $ledgerPath $state
}
function Install-RmgRamBackend {
 [CmdletBinding(SupportsShouldProcess)]param([string]$StateRoot=$script:DefaultState,[string]$PayloadRoot,[switch]$Offline)
 Assert-RmgAdmin
 if(-not $PSCmdlet.ShouldProcess('Signed RAM storage drivers','Prepare headless Arsenal/AWEAlloc backend without rebooting')){return}
 Initialize-RmgStateRoot $StateRoot
 $root=Join-Path $StateRoot 'ram-backend-downloads';Initialize-RmgStateRoot $root
 $zip=Get-RmgBackendPackage -Root $root -PayloadRoot $PayloadRoot -Offline:$Offline
 Install-RmgStoragePackage $zip $StateRoot
 $provider=Assert-RmgRamProvider
 [pscustomobject]@{Ready=$true;Offline=[bool]$Offline;Provider=$provider.Provider;Allocator='AWEAlloc';RebootRequested=$false;DownloadDirectory=$root}
}
function Remove-RmgStorageBackend($StateRoot) {
 $ram=Read-RmgRamState $StateRoot
 if($ram -and $ram.Active){throw 'Restore and release the RAM disk before removing its backend'}
 $state=Read-RmgStorageState $StateRoot
 if(-not $state){return [pscustomobject]@{Status='PreservedShared'}}
 $path=Join-Path $StateRoot 'storage-backend.json'
 Recover-RmgStorageStaging $StateRoot $state
 Repair-RmgStorageAuxiliary $StateRoot $state
 if(-not $state.RootOwned -and -not $state.MiniportOwned -and -not $state.AweOwned -and -not $state.PackageOwned){return [pscustomobject]@{Status='PreservedShared'}}
 $ports=@(Get-RmgStoragePorts)
 $remaining=@(Get-CimInstance Win32_DiskDrive|Where-Object{$_.SCSIPort -in $ports})
 if($remaining.Count){return [pscustomobject]@{Status='PreservedInUse';Reason='Other storage disks use the shared controller'}}
 $retained=@()
 if($state.RootOwned){
  try{
   $device=Get-PnpDevice -InstanceId $state.DeviceInstanceId -ErrorAction SilentlyContinue
   if($device){Initialize-RmgStorageNative;if([RmgStorageNative]::RemoveRoot($state.DeviceInstanceId)){throw 'Windows deferred controller removal'}}
   $state.RootOwned=$false;$state.DeviceInstanceId='';Write-RmgJson $path $state
  }catch{$retained+=$_.Exception.Message}
 }
 if($state.MiniportOwned -and -not $state.RootOwned){
  try{Remove-RmgOwnedStorageService phdskmnt;$state.MiniportOwned=$false;Write-RmgJson $path $state}catch{$retained+=$_.Exception.Message}
 }
 if($state.AweOwned -and -not $state.RootOwned -and -not $state.MiniportOwned){
  try{
   $driver=Get-CimInstance Win32_SystemDriver -Filter "Name='AWEAlloc'"
   if($driver -and $driver.State -eq 'Running'){$null=Get-RmgStorageDriver AWEAlloc;Stop-Service -Name AWEAlloc -ErrorAction Stop}
   Remove-RmgOwnedStorageService AWEAlloc;$state.AweOwned=$false;Write-RmgJson $path $state
  }catch{$retained+=$_.Exception.Message}
 }
 if($state.PackageOwned -and -not $state.RootOwned -and -not $state.MiniportOwned -and -not $state.AweOwned){
  try{Remove-RmgOwnedDriverPackage $state.PublishedInf;$state.PackageOwned=$false;Write-RmgJson $path $state}catch{$retained+=$_.Exception.Message}
 }
 $state.Phase=$(if($retained.Count){'Retained'}else{'Removed'});Write-RmgJson $path $state
 [pscustomobject]@{Status=$(if($retained.Count){'BackendRetained'}else{'RemovedOwned'});Details=$retained}
}
