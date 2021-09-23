param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("prepareseed", "create", "config", "delete", "launchdebug")]
    [string]$Mode,

    [Parameter(Mandatory = $false)]
    [string]$SeedVhdLocation = 'c:\SeedVHDs',

    [Parameter(Mandatory = $false)]
    [string]$SeedVhd = '',

    [Parameter(Mandatory = $false)]
    [string]$VhdLocation = 'c:\users\public\documents\Hyper-V\Virtual hard disks',

    [Parameter(Mandatory = $false)]
    [long]$VhdSize = 40GB,

    [Parameter(Mandatory = $false)]
    [string]$UnattendLocation = "$($PSScriptRoot)",

    [Parameter(Mandatory = $false)]
    [string]$PAT = '',

    [Parameter(Mandatory = $false)]
    [long]$VmCores = 4,

    [Parameter(Mandatory = $false)]
    [long]$MaximumVmMemory = 4096,

    [Parameter(Mandatory = $false)]
    [long]$VmsToProcess = 8,

    [Parameter(Mandatory = $false)]
    [long]$VmNumberStart = 1,

    [Parameter(Mandatory = $false)]
    [string]$VmNamePrefix = "AZP",

    [Parameter(Mandatory = $false)]
    [string]$VmPassword = "Test-Execution",

    [Parameter(Mandatory = $false)]
    [ValidateSet('MsQuic-Win-Latest', 'MsQuic')]
    [string]$AgentPool = 'MsQuic-Win-Latest',

    [Parameter(Mandatory = $false)]
    [ValidateSet('https://dev.azure.com/ms', 'https://dev.azure.com/mscodehub')]
    [string]$AgentUrl = 'https://dev.azure.com/ms',

    [Parameter(Mandatory = $false)]
    [long]$DebugPortBase = 50000
)

$ProgressPreference = 'SilentlyContinue'

$AzpDebugKey = "my.azp.vm.key"

function ExecuteScriptWithMountedVhd($vhd, $scriptblock)
{
    $vhdname = (Split-Path $vhd -Leaf).substring(0,8)
    $vhdmountdir = "$($Env:Temp)\vhdmount\$vhdname"
    if (Test-Path $vhdmountdir) {
        throw "VHD mount path already exists."
    }
    mkdir $vhdmountdir > $null
    dism.exe /mount-image /ImageFile:$vhd /index:1 /mountdir:$vhdmountdir
    & $scriptblock
    dism.exe /unmount-image /mountdir:$vhdmountdir /commit
    Remove-Item -Path $vhdmountdir -Force > $null
}

function AddUnattendFile($vhd, $unattendfile)
{
    ExecuteScriptWithMountedVhd $vhd {
        dism.exe /image:$vhdmountdir /apply-unattend:$unattendfile
        Copy-Item $unattendfile $vhdmountdir
    }
}

function CreateVM($VmName, $VmNumber)
{
    $VhdExtension = $SeedVhd.split('.')[-1]
    $VhdPath = "$(Join-Path $VhdLocation $VmName).$($VhdExtension)"

    if (-not (Test-Path $VhdPath)) {
        New-VHD -Path $VhdPath -ParentPath (Join-Path $SeedVhdLocation $SeedVhd) -Differencing
    }

    $VMGeneration = 1
    if ($VhdExtension.Contains("vhdx")) {
        $VmGeneration = 2
    }

    New-Vm -Name $VmName -VHDPath $VhdPath -Generation $VMGeneration -SwitchName "ExternalSwitch"

    Set-VMProcessor -VMName $VmName -Count $VmCores

    Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $true -MinimumBytes (512 * 1024 * 1024) -StartupBytes (1024 *1024 * 1024) -MaximumBytes ($MaximumVmMemory * 1024 * 1024)

    if ($VMGeneration -eq 2) {
        Set-VMFirmware -VMName $VmName -FirstBootDevice (Get-VMHardDiskDrive -VMName $VmName) -EnableSecureBoot Off
    }

    Start-VM $VmName -AsJob

    # Wait for VM to start - never gets to "Healthy"
    # while ((Get-VM -Name $VmName).HeartBeat -ne  'OkApplicationsHealthy') {
    #     Write-Host "VM state is: $((Get-VM -Name $VmName).HeartBeat) Sleeping 5 seconds..."
    #     Start-Sleep -Seconds 5
    # }
}

function ConfigureVM($VmName, $VmNumber)
{
    $block = {
        param($Port, $HostIP, $VmName, $Token, $DebugKey, $Password, $PoolName, $URL)
        Set-MpPreference -DisableRealtimeMonitoring $true
        certutil.exe -addstore -f "Root" "c:\testroot-sha2.cer"
        Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI"
        bcdedit.exe /set testsigning on
        bcdedit.exe /dbgsettings NET HOSTIPV6:$HostIP PORT:$Port KEY:$DebugKey /noumex
        # bcdedit.exe /debug on
        # Configure dump file collection.
        reg add HKLM\SYSTEM\CurrentControlSet\Control\CrashControl /v DumpFile /t REG_EXPAND_SZ /d C:\memory.dmp /f
        reg add HKLM\SYSTEM\CurrentControlSet\Control\CrashControl /v CrashDumpEnabled /t REG_DWORD /d 1 /f
        reg add HKLM\SYSTEM\CurrentControlSet\Control\CrashControl /v Overwrite /t REG_DWORD /d 1 /f
        reg add HKLM\SYSTEM\CurrentControlSet\Control\CrashControl /v AlwaysKeepMemoryDump /t REG_DWORD /d 1 /f
        # Enable driver verifier.
        verifier.exe /standard /driver fndis.sys msquicpriv.sys msquictestpriv.sys xdp.sys xdpfnmp.sys xdpmp.sys
        # Install DuoNic
        pushd c:\duonic
        & C:\duonic\duonic.ps1 -Install
        popd
        # Install VS build tools
        c:\vs_buildtools.exe --add Microsoft.VisualStudio.Workload.MSBuildTools --add Microsoft.VisualStudio.Workload.VCTools --IncludeRecommended --passive --force --wait
        # Add agent to pool
        c:\a\config.cmd --unattended --URL "$($URL)" --auth pat --token "$($Token)" --pool "$($PoolName)" --agent "$($VmName)" --replace --work "c:\a\w" --runAsService
        # Enable services to run as Administrator
        secedit.exe /export /cfg "$($Env:Temp)\secconfig.cfg"
        (Get-Content "$($Env:Temp)\secconfig.cfg") -replace 'SeServiceLogonRight = (?<SIDs>.*)', 'SeServiceLogonRight = Administrator,$1' | Set-Content "$($Env:Temp)\secconfig.cfg"
        secedit.exe /configure /db c:\windows\security\local.sdb /cfg "$($Env:Temp)\secconfig.cfg" /areas USER_RIGHTS
        # Set AZP service to run as Administrator
        #$cred = New-Object System.Management.Automation.PSCredential ('Administrator', (ConvertTo-SecureString $Password -AsPlainText -Force))
        #& "C:\Program Files\Powershell\7\pwsh.exe" -Command Set-Service -Name "vsts*" -Credential (New-Object System.Management.Automation.PSCredential ('Administrator', (ConvertTo-SecureString $Password -AsPlainText -Force)))
        #Get-Service vsts* | Restart-Service
        $ServiceName = (get-service vsts*).name
        $WmiObject = Get-WMIObject Win32_Service -filter "name='$ServiceName'"
        $StopStatus = $WmiObject.StopService()
        If ($StopStatus.ReturnValue -eq "0") {
            Write-host "The service '$ServiceName' Stopped successfully"
        }
        $ChangeStatus = $WmiObject.change($null,$null,$null,$null,$null,$null,'.\Administrator',$Password,$null,$null,$null)
        If ($ChangeStatus.ReturnValue -eq "0") {
            Write-host "Set User Name sucessfully for the service '$ServiceName'"
        }
        # Create start up job to copy dump files and start Azure Pipeline agent service.
        $Trigger = New-ScheduledTaskTrigger -AtStartup
        $Action = New-ScheduledTaskAction -Execute 'pwsh' -Argument C:\CoreNet-CI-Startup.ps1
        Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName CoreNet-CI-Startup -Description "Copy Dumps and Start VSTS Service" -User Administrator -Password Test-Execution
        Set-Service $ServiceName -StartupType Manual
        # Start the service back up.
        Start-Sleep 5
        $StartStatus = $WmiObject.StartService()
        If ($StartStatus.ReturnValue -eq "0") {
            Write-host "The service '$ServiceName' Started successfully"
        }
        Start-Process c:\OpenCppCoverageSetup-x64-0.9.9.0.exe -Wait -ArgumentList {"/silent"} -NoNewWindow
        # Visual studio installer doesn't respect the --wait parameter, so we can't automatically reboot
        # Wait for Visual Studio to finish installing to copy this
        Start-Sleep 300
        Copy-Item "c:\sdk\*" "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x86\"
    }

    $DebugPort = $DebugPortBase + $VmNumber
    $HostIP =  (get-netipaddress -AddressFamily IPv6 -AddressState Preferred -InterfaceAlias "vEthernet (ExternalSwitch)" -ValidLifetime ([TimeSpan]::MaxValue)).IPAddress.Split('%')[0]

    $password = ConvertTo-SecureString $VmPassword -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ('Administrator', $password)

    #start up WinDbgX
    # windbgx.exe -y c:\symbols -k net:port=$DebugPort,key=$AzpDebugKey

    #Configure VM
    return Invoke-Command -VmName $VmName -Credential $credential -ScriptBlock $block -ArgumentList $DebugPort,$HostIP,$VmName,$PAT, $AzpDebugKey,$VmPassword,$AgentPool,$AgentUrl -AsJob
}

function DeleteVM($VmName)
{
    if ((Get-VM -Name $VmName).State -eq 'Running') {

        $block = {
            param($Token)
            C:\a\config.cmd remove --unattended --auth pat --token "$($Token)"
        }

        $password = ConvertTo-SecureString $VmPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ('Administrator', $password)

        Invoke-Command -VmName $VmName -Credential $credential -ScriptBlock $block -ArgumentList $PAT

        # Turn off running VM
        Stop-VM -Name $VmName -TurnOff -Force
    }
   # Remove VHDs (and snapshot VHDs) before the VM
   Remove-Item -Path "$(Join-Path $VhdLocation $VmName)*" -Force
   Remove-VM -Name $VmName -Force
}

#
# Actually run the script
#

if ($Mode -eq "prepareseed") {
    $Vhd = Join-Path $SeedVhdLocation $SeedVhd
    if ((Get-VHD $Vhd).Size -lt $VhdSize) {
        Resize-VHD -Path $Vhd -SizeBytes $VhdSize
    }
    AddUnattendFile $Vhd "$($UnattendLocation)\unattend.xml"
    ExecuteScriptWithMountedVhd $Vhd {
        Invoke-WebRequest -Uri "https://vstsagentpackage.azureedge.net/agent/2.192.0/vsts-agent-win-x64-2.192.0.zip" -OutFile "$($vhdmountdir)\vsts-agent-win-x64-2.192.0.zip"
        Invoke-WebRequest -Uri "https://github.com/OpenCppCoverage/OpenCppCoverage/releases/download/release-0.9.9.0/OpenCppCoverageSetup-x64-0.9.9.0.exe" -OutFile "$($vhdmountdir)\OpenCppCoverageSetup-x64-0.9.9.0.exe"
        Expand-Archive -Path "$($vhdmountdir)\vsts-agent-win-x64-2.172.2.zip" -DestinationPath "$($vhdmountdir)\a" -Force
        Copy-Item "vs_buildtools.exe" "$($vhdmountdir)\vs_buildtools.exe"
        Copy-Item "sfpcopy.exe" "$($vhdmountdir)\Windows\System32\sfpcopy.exe"
        Copy-Item "testroot-sha2.cer" "$($vhdmountdir)"
        Copy-Item "dswdevice.exe" "$($vhdmountdir)"
        Copy-Item "notmyfault64.exe" "$($vhdmountdir)"
        Copy-Item "CoreNet-CI-Startup.ps1" "$($vhdmountdir)"
        Copy-Item -Recurse "duonic" "$($vhdmountdir)"
        Copy-Item -Recurse "sdk" "$($vhdmountdir)"
    }
} else {
    $Jobs = @()
    for ($i = $VmNumberStart; $i -le $VmsToProcess; $i++) {
        if ($Mode -eq "create") {
            CreateVM "$($VmNamePrefix)-$($i)" $i
        } elseif ($Mode -eq "config") {
            $Jobs += ConfigureVM "$($VmNamePrefix)-$($i)" $i
        } elseif ($Mode -eq "delete") {
             $VmName = "$($VmNamePrefix)-$($i)"
             DeleteVm $VmName
        } elseif ($Mode -eq "launchdebug") {
            $DebugPort = $DebugPortBase + $i
            windbgx.exe -y c:\symbols -k net:port=$DebugPort,key=$AzpDebugKey
        }
    }

    foreach ($Job in $Jobs) {
        Receive-Job -Job $Job -Wait
    }
}
