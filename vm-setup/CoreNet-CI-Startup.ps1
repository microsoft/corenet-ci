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
        
        # Make sure the share is available.
        Write-Host "net use $RemoteDumpDir $RemoteSharePassword /USER:VM"
        net use $RemoteDumpDir $RemoteSharePassword /USER:VM

        $RemoteDumpPath = Join-Path $RemoteDumpDir $env:computername

        # Create the folder if necessary.
        if (!(Test-Path $RemoteDumpPath)) {
            Write-Host "New-Item $RemoteDumpPath -Force"
            New-Item $RemoteDumpPath -ItemType directory -Force
        }
        
        if (Test-Path $LocalDumpCfgPath) {
            # Use the dump config to copy the dump out.
            $Description = Get-Content $LocalDumpCfgPath
            $RemoteDumpPath = Join-Path $RemoteDumpPath ($Description + ".dmp")
            
        } else {
            # No explicit dump configuration. Generate a generic one.
            $DateTime = Get-Date -Format "yyyy.dd.MM.HH.mm.ss"
            $RemoteDumpPath = Join-Path $RemoteDumpPath ("memory." + $DateTime + ".dmp")
        }
        
        # Copy the file out.
        Write-Host "Copy-Item $LocalDumpPath $RemoteDumpPath -Recurse -Force"
        Copy-Item $LocalDumpPath $RemoteDumpPath -Force
        
        # Delete the local file.
        Write-Host "Remove-Item $LocalDumpPath -Force"
        Remove-Item $LocalDumpPath -Force

    } else {
        Write-Host "$LocalDumpPath not found. Skipping."
    }

} catch {
    Write-Host "Encountered exception!"
    Write-Host $_

} finally {
    # Start AZP agent service
    Write-Host "Starting VSTS Agent Service"
    Start-Service (Get-Service vstsagent*)
}
