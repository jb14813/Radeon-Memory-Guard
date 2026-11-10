[CmdletBinding()]
param([Parameter(Mandatory)][string]$Manifest,[Parameter(Mandatory)][string]$CertificatePath,[switch]$CheckFiles)
$ErrorActionPreference='Stop'
$certificate=New-Object Security.Cryptography.X509Certificates.X509Certificate2((Get-Item -LiteralPath $CertificatePath).FullName)
$key=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
try{$valid=$key.VerifyData([IO.File]::ReadAllBytes($Manifest),[Convert]::FromBase64String([IO.File]::ReadAllText($Manifest+'.sig')),[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)}finally{$key.Dispose()}
if(-not $valid){throw 'Release checksum manifest signature is invalid'}
$count=0
if($CheckFiles){
 $directory=Split-Path ([IO.Path]::GetFullPath($Manifest)) -Parent
 foreach($line in [IO.File]::ReadAllLines($Manifest)){
  if($line -notmatch '^([0-9a-f]{64})  ([^\\/:]+)$'){throw 'Invalid checksum manifest entry'}
  $expected=$Matches[1];$name=$Matches[2]
  if($name -eq '..' -or $name -eq '.'){throw 'Invalid checksum filename'}
  if((Get-FileHash -LiteralPath (Join-Path $directory $name)).Hash.ToLowerInvariant() -ne $expected){throw ('Release file checksum mismatch: '+$name)};$count++
 }
}
[pscustomobject]@{SignatureVerified=$true;CheckedFiles=$count;SignerThumbprint=$certificate.Thumbprint;Trust='Verify the certificate fingerprint through an independent trusted channel; this does not import certificate trust'}
