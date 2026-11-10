param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference='Stop'
$verify=Join-Path $PSScriptRoot '..\tools\Verify-Release.ps1'
if(-not(Test-Path -LiteralPath $verify)){throw 'Release integrity verification is not implemented.'}
$result=& $verify -Path $Path
if(-not $result.IntegrityVerified){throw 'Original signed release failed verification'}
$copy=Join-Path $PSScriptRoot ('..\build\tamper-test-'+[guid]::NewGuid().ToString('N')+'.exe')
Copy-Item -LiteralPath $Path -Destination $copy
$stream=[IO.File]::Open($copy,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite)
try{$stream.Position=4096;$old=$stream.ReadByte();$stream.Position=4096;$stream.WriteByte($old -bxor 1)}finally{$stream.Dispose()}
$rejected=$false;try{& $verify -Path $copy | Out-Null}catch{$rejected=$true}
if(-not $rejected){throw 'An altered executable passed integrity verification'}
$rejected=$false;try{& $verify -Path $Path -ExpectedSha256 ('0'*64) | Out-Null}catch{$rejected=$true}
if(-not $rejected){throw 'An incorrect final-file checksum was accepted'}
Write-Output 'Passed signed-release integrity, modified-file rejection, and wrong-checksum rejection.'
