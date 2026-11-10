[CmdletBinding()]
param([string]$CompilerPath,[switch]$SelfSign,[switch]$Offline=$true,[string]$SignToolPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid version'}
if(-not $CompilerPath){
    $CompilerPath=Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
    if(-not (Test-Path -LiteralPath $CompilerPath -PathType Leaf)){
        $command=Get-Command ISCC.exe -ErrorAction SilentlyContinue
        if($command){$CompilerPath=$command.Source}
    }
}
if(-not $CompilerPath -or -not (Test-Path -LiteralPath $CompilerPath -PathType Leaf)){throw 'Install Inno Setup 6, or provide -CompilerPath to ISCC.exe'}
$build=Join-Path $root 'build'
$null=New-Item -ItemType Directory -Path $build -Force
$arguments=@('/Qp',('/DAppVersion='+$version),('/DSourceRoot='+$root),('/DBuildRoot='+$build))
if($Offline){
    $payload=& (Join-Path $PSScriptRoot 'Prepare-OfflinePayload.ps1')
    $arguments+=('/DOfflinePayloadDir='+$payload.Path)
}
if($SelfSign){
    $public=New-Object Security.Cryptography.X509Certificates.X509Certificate2((Join-Path $root 'signing\JZBApps-RadeonMemoryGuard.cer'))
    $certificate=Get-Item -LiteralPath ('Cert:\CurrentUser\My\'+$public.Thumbprint)
    if(-not $certificate.HasPrivateKey -or $certificate.Subject -ne 'CN=JZB Apps Radeon Memory Guard Experimental' -or $certificate.Issuer -ne $certificate.Subject){throw 'Only the dedicated self-signed JZB Apps project identity may sign this build'}
    if(-not $SignToolPath){$SignToolPath='C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'}
    if(-not(Test-Path -LiteralPath $SignToolPath -PathType Leaf)){throw 'Provide -SignToolPath to a Windows SDK SignTool.exe'}
    $command='$q'+$SignToolPath+'$q sign /fd SHA256 /td SHA256 /tr http://timestamp.digicert.com /s My /sha1 '+$public.Thumbprint+' $f'
    $arguments+='/DSelfSign';$arguments+=('/SJzbOwn='+$command)
}
$arguments+=(Join-Path $root 'installer\RadeonMemoryGuard.iss')
$output=& $CompilerPath @arguments 2>&1
if($LASTEXITCODE -ne 0){throw ('Inno Setup failed: '+($output -join [Environment]::NewLine))}
$prefix='RadeonMemoryGuard-Setup-'
$exe=Join-Path $build ($prefix+$version+'.exe')
if(-not (Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Compiler did not produce the installer'}
if($SelfSign){$null=& (Join-Path $PSScriptRoot 'Verify-Release.ps1') -Path $exe}
elseif((Get-AuthenticodeSignature -LiteralPath $exe).Status.ToString() -ne 'NotSigned'){throw 'Unsigned build unexpectedly uses a signing certificate'}
$hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
($hash+'  '+[IO.Path]::GetFileName($exe)) | Set-Content -LiteralPath ($exe+'.sha256') -Encoding ASCII
[pscustomobject]@{Path=$exe;Sha256=$hash;Offline=[bool]$Offline;SelfSigned=[bool]$SelfSign}
