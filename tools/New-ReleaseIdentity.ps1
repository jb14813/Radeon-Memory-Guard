[CmdletBinding()]
param([switch]$TrustForCurrentUser)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$directory=Join-Path $root 'signing';$null=New-Item -ItemType Directory -Path $directory -Force
$publicPath=Join-Path $directory 'JZBApps-RadeonMemoryGuard.cer'
$subject='CN=JZB Apps Radeon Memory Guard Experimental'
if(Test-Path -LiteralPath $publicPath){
 $public=New-Object Security.Cryptography.X509Certificates.X509Certificate2($publicPath)
 $certificate=Get-Item -LiteralPath ('Cert:\CurrentUser\My\'+$public.Thumbprint) -ErrorAction Stop
 if($certificate.Subject -ne $subject -or -not $certificate.HasPrivateKey){throw 'The dedicated project identity is not available with its private key'}
}else{
 $certificate=New-SelfSignedCertificate -Type CodeSigningCert -Subject $subject -FriendlyName 'JZB Apps Radeon Memory Guard release integrity' -CertStoreLocation Cert:\CurrentUser\My -Provider 'Microsoft Software Key Storage Provider' -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 -KeyUsage DigitalSignature -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(3)
 $null=Export-Certificate -Cert $certificate -FilePath $publicPath -Type CERT
}
if($certificate.Issuer -ne $certificate.Subject -or $certificate.Subject -ne $subject){throw 'Refusing a non-project certificate'}
if($TrustForCurrentUser){
 foreach($store in @('Root','TrustedPublisher')){
  if(-not(Test-Path -LiteralPath ('Cert:\CurrentUser\'+$store+'\'+$certificate.Thumbprint))){$null=Import-Certificate -FilePath $publicPath -CertStoreLocation ('Cert:\CurrentUser\'+$store)}
 }
}
$metadata=[ordered]@{Subject=$subject;Thumbprint=$certificate.Thumbprint;CertificateSha256=(Get-FileHash -LiteralPath $publicPath -Algorithm SHA256).Hash.ToLowerInvariant();ExpiresUtc=$certificate.NotAfter.ToUniversalTime().ToString('o');SelfSigned=$true;PublicWindowsTrust=$false;KeyExportable=$false}
$metadata | ConvertTo-Json | Set-Content (Join-Path $directory 'identity.json') -Encoding UTF8
[pscustomobject]@{PublicCertificate=$publicPath;Thumbprint=$certificate.Thumbprint;TrustedForCurrentUser=[bool]$TrustForCurrentUser;PrivateKey='Nonexportable in CurrentUser My; never bundled'}
