param([Parameter(Mandatory)][string]$Directory)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($Directory)
$files=@(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {$_.FullName -notlike ($root+'\.git\*')})
$forbidden=@('(?i)[A-Z0-9._%+-]+@(gmail|outlook|hotmail|yahoo)\.com','gh[pousr]_[A-Za-z0-9]{20,}','-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----')
$homePrefix='C:'+([char]92)+'Users'+([char]92)
$forbidden+=[regex]::Escape($homePrefix)
$forbidden+=('(?i)'+'Eagle'+'View')
foreach($file in $files){
 if($file.Extension -in @('.pfx','.key','.pem','.pvk','.snk','.etl','.log','.sys','.cat','.sqlite','.db')){throw ('Private/runtime artifact in public source: '+$file.Name)}
 if($file.Extension -in @('.md','.ps1','.psm1','.txt','.json','.yml','.iss','.gitignore','.gitattributes')){
  $text=[IO.File]::ReadAllText($file.FullName)
  foreach($pattern in $forbidden){if($text -match $pattern){throw ('Privacy audit failed in public source: '+$file.Name)}}
 }
}
if(-not(Test-Path (Join-Path $root 'signing\JZBApps-RadeonMemoryGuard.cer'))){throw 'Public verification certificate missing'}
[pscustomobject]@{Passed=$true;Files=$files.Count;PrivateArtifactsFound=0;PersonalDetailsFound=0}
