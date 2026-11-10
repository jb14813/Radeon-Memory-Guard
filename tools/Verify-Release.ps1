[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path,[string]$CertificatePath=(Join-Path $PSScriptRoot '..\signing\JZBApps-RadeonMemoryGuard.cer'),[string]$ExpectedSha256)
$ErrorActionPreference='Stop'
$file=(Get-Item -LiteralPath $Path).FullName
$expected=New-Object Security.Cryptography.X509Certificates.X509Certificate2((Get-Item -LiteralPath $CertificatePath).FullName)
Add-Type -AssemblyName System.Security
if(-not ('RmgReleaseIntegrity' -as [type])){
 $references=@('System.Security')
 if($PSVersionTable.PSEdition -eq 'Core'){$references+=@([Security.Cryptography.Pkcs.SignedCms].Assembly.Location,[Security.Cryptography.X509Certificates.X509Certificate2].Assembly.Location)}
 Add-Type -ReferencedAssemblies $references -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography.Pkcs;
using System.Security.Cryptography.X509Certificates;
public static class RmgReleaseIntegrity {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct FileInfo {public uint Size;[MarshalAs(UnmanagedType.LPWStr)]public string Path;public IntPtr Handle,Subject;}
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct TrustData {public uint Size;public IntPtr Policy,Sip;public uint Ui,Revocation,Choice;public IntPtr File;public uint State;public IntPtr StateData,Url;public uint Flags,Context;public IntPtr Signature;}
 [StructLayout(LayoutKind.Sequential)] struct SignatureSettings {public uint Size,Index,Flags,SecondaryCount,VerifiedIndex;public IntPtr CryptoPolicy;}
 [StructLayout(LayoutKind.Sequential)] struct ProviderSignerPrefix {public uint Size;public System.Runtime.InteropServices.ComTypes.FILETIME Time;public uint CertificateCount;public IntPtr Certificates;}
 [StructLayout(LayoutKind.Sequential)] struct ProviderCertificatePrefix {public uint Size;public IntPtr Certificate;}
 [DllImport("wintrust.dll",ExactSpelling=true,CharSet=CharSet.Unicode)] static extern int WinVerifyTrust(IntPtr window,ref Guid action,ref TrustData data);
 [DllImport("wintrust.dll",ExactSpelling=true)] static extern IntPtr WTHelperProvDataFromStateData(IntPtr state);
 [DllImport("wintrust.dll",ExactSpelling=true)] static extern IntPtr WTHelperGetProvSignerFromChain(IntPtr provider,uint index,[MarshalAs(UnmanagedType.Bool)]bool counter,uint counterIndex);
 public static string Verify(string path) {
  // Check the PKCS#7 signature without installing or trusting its certificate.
  byte[] bytes=System.IO.File.ReadAllBytes(path);int pe=BitConverter.ToInt32(bytes,60);int opt=pe+24;
  int directory=opt+(BitConverter.ToUInt16(bytes,opt)==0x20b?112:96)+32;
  int offset=BitConverter.ToInt32(bytes,directory),size=BitConverter.ToInt32(bytes,directory+4);
  if(offset<=0||size<8||offset>bytes.Length-size)throw new InvalidDataException("Missing Authenticode signature");
  int length=BitConverter.ToInt32(bytes,offset)-8;
  if(length<=0||length>size-8)throw new InvalidDataException("Invalid Authenticode signature size");
  byte[] message=new byte[length];Buffer.BlockCopy(bytes,offset+8,message,0,length);
  var cms=new SignedCms();cms.Decode(message);cms.CheckSignature(true);
  if(cms.SignerInfos.Count!=1||cms.SignerInfos[0].Certificate==null)throw new InvalidDataException("Exactly one signer is required");
  string thumbprint=cms.SignerInfos[0].Certificate.Thumbprint;
  // Ask Windows to verify the actual PE image digest, cache-only, with no trust import.
  var info=new FileInfo{Size=(uint)Marshal.SizeOf(typeof(FileInfo)),Path=path};
  IntPtr pointer=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(FileInfo)));Marshal.StructureToPtr(info,pointer,false);
  var settings=new SignatureSettings{Size=(uint)Marshal.SizeOf(typeof(SignatureSettings)),Index=0,Flags=1};
  IntPtr settingsPointer=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SignatureSettings)));Marshal.StructureToPtr(settings,settingsPointer,false);
  var data=new TrustData{Size=(uint)Marshal.SizeOf(typeof(TrustData)),Ui=2,Choice=1,File=pointer,State=1,Flags=0x200|0x1000|0x10,Signature=settingsPointer};
  var action=new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
  try{
   int result=WinVerifyTrust(new IntPtr(-1),ref action,ref data);if(result!=0)throw new InvalidDataException("Windows image-digest verification failed: 0x"+result.ToString("X8"));
   settings=(SignatureSettings)Marshal.PtrToStructure(settingsPointer,typeof(SignatureSettings));
   if(settings.VerifiedIndex!=0)throw new InvalidDataException("Windows verified an unexpected signature index");
   IntPtr signerPointer=WTHelperGetProvSignerFromChain(WTHelperProvDataFromStateData(data.StateData),0,false,0);
   if(signerPointer==IntPtr.Zero)throw new InvalidDataException("Windows did not expose the verified signer");
   var signer=(ProviderSignerPrefix)Marshal.PtrToStructure(signerPointer,typeof(ProviderSignerPrefix));
   if(signer.CertificateCount==0||signer.Certificates==IntPtr.Zero)throw new InvalidDataException("Verified signer has no certificate");
   var context=(ProviderCertificatePrefix)Marshal.PtrToStructure(signer.Certificates,typeof(ProviderCertificatePrefix));
   using(var verified=new X509Certificate2(context.Certificate)){if(verified.Thumbprint!=thumbprint)throw new InvalidDataException("CMS signer and Windows-verified image signer differ");}
  }
  finally{data.State=2;WinVerifyTrust(new IntPtr(-1),ref action,ref data);Marshal.DestroyStructure(pointer,typeof(FileInfo));Marshal.FreeHGlobal(pointer);Marshal.FreeHGlobal(settingsPointer);}
  return thumbprint;
 }
}
'@
}
$actual=[RmgReleaseIntegrity]::Verify($file)
if($actual -ne $expected.Thumbprint){throw 'Executable signer differs from the independently obtained JZB Apps public certificate'}
$hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
if($ExpectedSha256 -and $hash -ne $ExpectedSha256.ToLowerInvariant()){throw 'Final-file SHA-256 mismatch'}
[pscustomobject]@{Path=$file;IntegrityVerified=$true;SignerThumbprint=$actual;Sha256=$hash;Trust='Pinned self-signed key; no public Windows publisher trust is implied'}
