<#

.SYNOPSIS
This script copys out any memory dump to a well-known location and then starts
the Azure Pipeline agent service.

#>

Set-StrictMode -Version 'Latest'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

$LocalDumpPath = "C:\memory.dmp"
$LocalDumpCfgPath = "C:\dump.txt"
$RemoteDumpDir = "\\anrossi-azp\bugchecks"
$RemoteSharePassword = "VM-Test-Execution"

try {
    # Copy out any dump file.
    if (Test-Path $LocalDumpPath) {
        $RemoteDumpPath = ""
        if (Test-Path $LocalDumpCfgPath) {
            # Use the dump config to copy the dump out.
            $Description = Get-Content $LocalDumpCfgPath
            $RemoteDumpPath = Join-Path $RemoteDumpDir $env:computername ($Description + ".dmp")
            
        } else {
            # No explicit dump configuration. Generate a generic one.
            $DateTime = Get-Date -Format "yyyy.dd.MM.HH.mm.ss"
            $RemoteDumpPath = Join-Path $RemoteDumpDir $env:computername ("memory" + $DateTime + ".dmp")
        }
        
        Write-Debug "Copying $LocalDumpPath to $RemoteDumpPath"
        
        # Make sure the share is available.
        net use $RemoteDumpDir $RemoteSharePassword /USER:VM
        
        # Copy the file out.
        Copy-Item $LocalDumpPath $RemoteDumpPath -Recurse -Force
        
        # Delete the local file.
        Remove-Item $LocalDumpPath -Force
    }

} catch {
    Write-Debug "Encountered exception!"

} finally {
    # Start AZP agent service
    Start-Service (Get-Service vstsagent*)
}
