[CmdletBinding()]
param([Parameter(Mandatory)][string]$Directory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$public=New-Object Security.Cryptography.X509Certificates.X509Certificate2((Join-Path $root 'signing\JZBApps-RadeonMemoryGuard.cer'))
$identity=Get-Item -LiteralPath ('Cert:\CurrentUser\My\'+$public.Thumbprint)
if($identity.Subject -ne 'CN=JZB Apps Radeon Memory Guard Experimental' -or -not $identity.HasPrivateKey){throw 'Dedicated project signing key required'}
$files=@(Get-ChildItem -LiteralPath $Directory -File | Where-Object {$_.Name -notmatch '^SHA256SUMS' -and $_.Name -notlike '*.sha256'} | Sort-Object Name)
$lines=@($files | ForEach-Object {((Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant())+'  '+$_.Name})
$manifest=Join-Path $Directory 'SHA256SUMS'
[IO.File]::WriteAllText($manifest,($lines -join "`n")+"`n",(New-Object Text.UTF8Encoding($false)))
$key=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($identity)
try{$signature=$key.SignData([IO.File]::ReadAllBytes($manifest),[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)}finally{$key.Dispose()}
[IO.File]::WriteAllText(($manifest+'.sig'),[Convert]::ToBase64String($signature),(New-Object Text.UTF8Encoding($false)))
[pscustomobject]@{Manifest=$manifest;Files=$files.Count;SignerThumbprint=$public.Thumbprint}
