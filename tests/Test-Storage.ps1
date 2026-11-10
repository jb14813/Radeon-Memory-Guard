$ErrorActionPreference='Stop'
$script:passed=0
function Assert($Value,$Message){if(-not $Value){throw $Message};$script:passed++}
$source=Join-Path $PSScriptRoot '..\RadeonStorage.ps1'
Assert (Test-Path -LiteralPath $source -PathType Leaf) 'The native storage controller is missing.'
. $source
Assert ((Get-Content -LiteralPath $source -Raw) -notmatch 'UpdateDriverForPlugAndPlayDevices') 'Installer can update unrelated existing Arsenal controllers.'
Initialize-RmgStorageNative
$packet=[RmgStorageNative]::CreatePacket(67108864)
Assert ($packet.Length -eq 94) 'Wrong miniport create packet size.'
Assert ([BitConverter]::ToUInt32($packet,0) -eq 28) 'Wrong SRB header size.'
Assert ([Text.Encoding]::ASCII.GetString($packet,4,8) -eq 'PhDskMnt') 'Request targets the wrong storage driver.'
Assert ([BitConverter]::ToUInt32($packet,16).ToString('X8') -eq '83730801') 'Wrong create control code.'
Assert ([BitConverter]::ToUInt32($packet,28) -eq 0xFFFFFF) 'Creation did not request a new LUN.'
Assert ([BitConverter]::ToInt64($packet,32) -eq 67108864) 'RAM capacity is not fixed at 64 MiB.'
Assert ([BitConverter]::ToUInt32($packet,40) -eq 512) 'Unexpected sector size.'
Assert ([BitConverter]::ToUInt32($packet,56) -eq 0x1110) 'Backing is not physical AWE memory.'
Assert ([Text.Encoding]::Unicode.GetString($packet,62,32) -eq '\Device\AWEAlloc') 'A file or pageable-memory backend was requested.'
$query=$packet.Clone();[BitConverter]::GetBytes([uint32]0x101).CopyTo($query,28)
Assert ([RmgStorageNative]::ValidatePhysical($query,0x101)) 'A valid physical-memory reply was rejected.'
[BitConverter]::GetBytes([uint32]0x210).CopyTo($query,56)
Assert (-not [RmgStorageNative]::ValidatePhysical($query,0x101)) 'A pageable virtual-memory disk was accepted.'
$query=$packet.Clone();[BitConverter]::GetBytes([uint32]0x101).CopyTo($query,28);[BitConverter]::GetBytes([long]134217728).CopyTo($query,32)
Assert (-not [RmgStorageNative]::ValidatePhysical($query,0x101)) 'An unexpected disk size was accepted.'
$query=$packet.Clone();[BitConverter]::GetBytes([uint32]0x101).CopyTo($query,28)
Assert (-not [RmgStorageNative]::ValidatePhysical($query,0x102)) 'A different LUN was accepted.'
Assert (-not [RmgStorageNative]::ValidatePhysical((New-Object byte[] 30),0x101)) 'A truncated driver response was accepted.'
foreach($unit in @([uint32]0xFFFFFF,[uint32]::MaxValue)){
 $failed=$false;try{[RmgStorageNative]::Remove(0,$unit)}catch{$failed=$true}
 Assert $failed 'An all-device removal sentinel reached the kernel.'
}
$failed=$false;try{[RmgStorageNative]::Create(999)}catch{$failed=$true}
Assert $failed 'An invalid adapter reached the kernel.'
$failed=$false;try{[RmgStorageNative]::CreatePacket(134217728)}catch{$failed=$true}
Assert $failed 'An unexpected allocation size was allowed.'
foreach($id in @('ROOT\UNRELATED\0000','PCI\VEN_1002')){
 $failed=$false;try{[RmgStorageNative]::RemoveRoot($id)}catch{$failed=$true}
 Assert $failed 'An unrelated device reached the removal API.'
}
Write-Output "Passed $script:passed storage assertions; no real storage requests were issued."
