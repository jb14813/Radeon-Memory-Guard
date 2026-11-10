#Requires -Version 5.1
<##
.SYNOPSIS
Maintains AMD's existing process-watcher workaround across driver service changes.
.EXAMPLE
.\RadeonMemoryGuard.ps1 -Action Status -Json
.EXAMPLE
.\RadeonMemoryGuard.ps1 -Action Install
##>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Status','Apply','Install','Restore','Uninstall','ProtectSsd','RestoreSsd','ProtectSsdRam','InstallRamBackend')][string]$Action='Status',
    [switch]$Json,
    [switch]$Quiet,
    [switch]$KeepSetting,
    [string]$PayloadRoot,
    [switch]$Offline
)
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'RadeonMemoryGuard.psm1') -Force
    $result=switch($Action){
        Status {Get-RmgStatus}
        Apply {Invoke-RmgApply -WhatIf:$WhatIfPreference}
        Install {Install-RmgMaintenance -WhatIf:$WhatIfPreference}
        ProtectSsd {Invoke-RmgProtectSsd -WhatIf:$WhatIfPreference}
        ProtectSsdRam {Invoke-RmgProtectSsdRam -WhatIf:$WhatIfPreference}
        InstallRamBackend {Install-RmgRamBackend -PayloadRoot $PayloadRoot -Offline:$Offline -WhatIf:$WhatIfPreference}
        RestoreSsd {Invoke-RmgRestoreSsd -WhatIf:$WhatIfPreference}
        Restore {Restore-RmgMaintenance -WhatIf:$WhatIfPreference}
        Uninstall {Uninstall-RmgMaintenance -KeepSetting:$KeepSetting -WhatIf:$WhatIfPreference}
    }
    if(-not $Quiet){if($Json){$result | ConvertTo-Json -Depth 10}else{$result | Format-List}}
} catch {
    try {
        $errorPath=Join-Path $env:ProgramData 'JZBApps-RadeonMemoryGuard\last-error.json'
        if(Test-Path -LiteralPath (Split-Path $errorPath -Parent)) {
            [pscustomobject]@{TimeUtc=[DateTime]::UtcNow.ToString('o');Action=$Action;Message=$_.Exception.Message;Stack=$_.ScriptStackTrace} | ConvertTo-Json | Set-Content -LiteralPath $errorPath -Encoding UTF8
        }
    } catch {}
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
exit 0
