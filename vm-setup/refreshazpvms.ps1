param(
    [Parameter(Mandatory = $true)]
    [string]$SeedVhd = '',
    [Parameter(Mandatory = $true)]
    [string]$ExternalPAT = '',
    [Parameter(Mandatory = $true)]
    [string]$InternalPAT = '',
    [Parameter(Mandatory = $false)]
    [string]$AdminPassword = 'Test-Execution',
    [Parameter(Mandatory = $false)]
    [switch]$SkipSeedPrep = $false,
    [Parameter(Mandatory = $false)]
    [switch]$SkipDeleteCreate = $false
)

if (!$SkipSeedPrep) {
    .\azp_vm_setup.ps1 prepareseed -SeedVhd $SeedVhd

    write-host "Seed VHD ready. Ready to delete VMs and make new ones?"
    pause
}

if (!$SkipDeleteCreate) {
	.\azp_vm_setup.ps1 -Mode delete -PAT "$($ExternalPAT)"
	.\azp_vm_setup.ps1 -Mode delete -PAT "$($InternalPAT)" -AgentUrl "https://dev.azure.com/mscodehub" -VmsToProcess 4 -VmNamePrefix INT -AgentPool MsQuic

	.\azp_vm_setup.ps1 -Mode create -SeedVhd $SeedVhd -VmsToProcess 8
	.\azp_vm_setup.ps1 -Mode create -SeedVhd $SeedVhd -VmsToProcess 4 -VmNamePrefix INT -DebugPortBase 50020

	Write-Host "Wait for the machines to complete OOBE before continuing"
	pause
}

.\azp_vm_setup.ps1 -Mode config -PAT "$($ExternalPAT)" -VmPassword "$($AdminPassword)"
.\azp_vm_setup.ps1 -Mode config -VmsToProcess 4 -VmNamePrefix INT -DebugPortBase 50020 -VmPassword "$($AdminPassword)" -PAT "$($InternalPAT)" -AgentUrl "https://dev.azure.com/mscodehub"  -AgentPool MsQuic

Write-Host "Ensure WinSDK has finished installing on all VMs before proceeding."
pause

get-vm | restart-vm -type reboot -asjob

Write-Host "Ensure all VMs have gotten to desktop and have KD running before proceeding"
pause

$block = {
  cd c:\duonic
  & .\duonic.ps1 -uninstall
  & .\duonic.ps1 -install
}

$password = ConvertTo-SecureString "$($AdminPassword)" -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ('Administrator', $password)

get-VM | foreach{ Invoke-Command -VMName $_.Name -Credential $Credential -ScriptBlock $Block -AsJob }

