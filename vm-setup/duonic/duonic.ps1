#
# Setup script for duonic, up to 4 pairs.
#
# NB: this doesn't support all possible configurations for
# duonic. Currently it is mainly used for RDQ configuration.
# See duonic readme for instructions on manual configuration.
#

param (

    [Parameter(Mandatory = $false, ParameterSetName='GatherDeps')]
    [switch]$GatherDeps = $false,

    [Parameter(Mandatory = $false, ParameterSetName='GatherDeps')]
    [string]$BuildPath = "",

    [Parameter(Mandatory = $false, ParameterSetName='Install')]
    [switch]$Install = $false,

    [Parameter(Mandatory = $false, ParameterSetName='Uninstall')]
    [switch]$Uninstall = $false,

    [Parameter(Mandatory = $false, ParameterSetName='Install')]
    [Parameter(ParameterSetName='Uninstall')]
    [switch]$DriverPreinstalled = $false,

    [Parameter(Mandatory = $false, ParameterSetName='Install')]
    [ValidateRange(1, 4)]
    [Int32]$NumNicPairs = 1,

    [Parameter(Mandatory = $false, ParameterSetName='Install')]
    [Parameter(ParameterSetName='Uninstall')]
    [switch]$NoFirewallRules = $false,

    [Parameter(Mandatory = $false, ParameterSetName='RdqDisable')]
    [switch]$RdqDisable = $false,

    [Parameter(Mandatory = $false, ParameterSetName='Rdq')]
    [switch]$Rdq = $false,

    [Parameter(Mandatory = $true, ParameterSetName='Rdq')]
    [Int32]$RttMs = 0,

    [Parameter(Mandatory = $true, ParameterSetName='Rdq')]
    [Int32]$BottleneckMbps = 0,

    [Parameter(Mandatory = $true, ParameterSetName='Rdq')]
    [Int32]$BottleneckBufferPackets = 0,

    [Parameter(Mandatory = $false, ParameterSetName='Rdq')]
    [Int32]$RandomLossDenominator = 0, # N>0: drop 1/N of packets. N==0: no random loss.

    [Parameter(Mandatory = $false, ParameterSetName='Rdq')]
    [Int32]$ReorderDelayDeltaMs = 0, # Extra delay (in ms) applied to reordered packets.

    [Parameter(Mandatory = $false, ParameterSetName='Rdq')]
    [Int32]$RandomReorderDenominator = 0,  # N>0: Switch between delay queues with probability 1/N.
                                           # N==0: no reordering.
    [Parameter(Mandatory = $false, ParameterSetName='Rdq')]
    [Int32]$MaxDelayJitterMs = 0, # max delay jitter (in ms).

    [Parameter(Mandatory = $false, ParameterSetName='Rdq')]
    [Int32]$RandomDelayJitterDenominator = 0, # N>0: the probability of delay jitter event per packet is 1/N.
                                              # N==0: no delay jitter.

    [Parameter(Mandatory = $false, ParameterSetName='Rdq')]
    [string]$RandomSeed = "",   # Empty string, use system RNG for seed.
                                # Non-empty string, hex values seed for random loss/reorder/jitter RNG.

    [Parameter(Mandatory = $false, ParameterSetName='Rdq')]
    [Int32]$REDUpper = 0,      # N>0: at this average queue size, the marking probability is maximal.
                               # N==0: ignore packets for RED.
    [Parameter(Mandatory = $false, ParameterSetName='Rdq')]
    [Int32]$REDLower = 0,      # N>0: average queue size at which marking becomes a possibility.
                               # N==0: ignore packets for RED.
    [Parameter(Mandatory = $false, ParameterSetName='Rdq')]
    [Int32]$REDMaxProb = 0,    # N>0: maximum probability for marking in percentage.
                               # N==0: ignore packets for RED.
    [Parameter(Mandatory = $false, ParameterSetName='Rdq')]
    [Int32]$REDQWeightPercent = 0,  # N>0: RED uses exponential weighted moving average (EWMA) queue length, AvgQ.
                                    # AvgQ = (100% - REDQWeightPercent) * Q + REDQWeightPercent * AvgQ where Q is
                                    # the instaneuous queue length.
                                    # N==0: always use instantaneous queue length for RED.
    [Parameter(Mandatory = $false, ParameterSetName='Rdq')]
    [switch]$REDDrop                # If set, drop packets rather than mark them for RED.
)

if ($GatherDeps) {
    if ($BuildPath -eq "") {
        $Build = ((gci "hklm:\software\microsoft\windows NT" | gp).BuildLabEx).Split(".")
        $BuildPath = "\\winbuilds\release\" + $Build[3] + "\" + $Build[0] + "." + $Build[1] + "." + $Build[4] + "\" + $Build[2]
    }
    net use $BuildPath
    if (!(Test-Path $BuildPath)) {
        echo ("Path for this build doesn't exist: " + $BuildPath)
        exit
    }
    cp ($BuildPath + "\bin\idw\dswdevice.exe")
    cp ($BuildPath + "\bin\idw\devcon.exe")
    cp ($BuildPath + "\test_automation_bins\net\test\duonic\duonic.*")
}

if ($Install) {
    if (-not $DriverPreinstalled) {
        # The driver might have already been previously installed via another method. This might
        # have been done if pnputil is not available on the machine, which is the case for
        # OneCore-based images.
        pnputil.exe /install /add-driver duonic.inf
    }

    for ($i = 1; $i -le $NumNicPairs * 2; $i++) {
        echo "Creating device for NIC $i"
        .\dswdevice.exe -i duonic_svc$i ms_duonic
    }

    Start-Sleep 3 # give some time for devices to start

    for ($i = 1; $i -le $NumNicPairs * 2; $i++) {
        echo "Setting up NIC $i"
        $nicDescription = if ($i -eq 1) { "duonic" } else { "duonic #$i" }
        Rename-NetAdapter -InterfaceDescription $nicDescription duo$i
        Set-NetAdapterAdvancedProperty duo$i -DisplayName linkprocindex -RegistryValue 999 -NoRestart # no proc affinity
        Set-NetAdapterAdvancedProperty duo$i -DisplayName maclastbyte -RegistryValue $i -NoRestart
    }

    echo "Restarting NICs"
    Restart-NetAdapter duo?
    Start-Sleep 10 # wait for duonic(s) to restart

    # Configure each pair separately with its own hard-coded subnet, ie 192.168.x.0/24.
    for ($i = 1; $i -le $NumNicPairs; $i++) {
        echo "Plumbing IP config for pair $i"

        # Generate the "ID" of the NICs, eg 1 and 2 for the first pair, 3 and 4 for the second...
        $nic1 = $i * 2 - 1
        $nic2 = $nic1 + 1

        netsh int ipv4 add address name=duo$nic1 address=192.168.$i.11/24
        netsh int ipv4 add address name=duo$nic2 address=192.168.$i.12/24

        netsh int ipv6 add address interface=duo$nic1 address=fc00::$i`:11/112
        netsh int ipv6 add address interface=duo$nic2 address=fc00::$i`:12/112

        # Create static neighbor entries so layer 4 tests don't see an inconsistent first RTT measurement from Neighbor Discovery.
        netsh int ipv4 add neighbor interface=duo$nic1 address=192.168.$i.12 neighbor=22-22-22-22-00-0$nic2
        netsh int ipv4 add neighbor interface=duo$nic2 address=192.168.$i.11 neighbor=22-22-22-22-00-0$nic1

        netsh int ipv6 add neighbor interface=duo$nic1 address=fc00::$i`:12 neighbor=22-22-22-22-00-0$nic2
        netsh int ipv6 add neighbor interface=duo$nic2 address=fc00::$i`:11 neighbor=22-22-22-22-00-0$nic1

        # Create routing rules to ensure traffic destined for the test addresses goes through duonic.
        # Without these routing rules, applications would have to explicitly bind to a source address.
        netsh int ipv4 add route prefix=192.168.$i.12/32 interface=duo$nic1 nexthop=0.0.0.0 metric=0
        netsh int ipv4 add route prefix=192.168.$i.11/32 interface=duo$nic2 nexthop=0.0.0.0 metric=0

        netsh int ipv6 add route prefix=fc00::$i`:12/128 interface=duo$nic1 nexthop=:: metric=0
        netsh int ipv6 add route prefix=fc00::$i`:11/128 interface=duo$nic2 nexthop=:: metric=0

        if (-not $NoFirewallRules) {
            netsh advfirewall firewall add rule name=AllowDuonic$i dir=in action=allow protocol=any remoteip=192.168.$i.0/24
            netsh advfirewall firewall add rule name=AllowDuonic$i`v6 dir=in action=allow protocol=any remoteip=fc00::$i`:0/112
        }
    }

    Start-Sleep 5 # give some time for IP addresses to be ready
}

if ($Rdq) {
    Set-NetAdapterAdvancedProperty duo? -DisplayName RdqEnabled -RegistryValue 1 -NoRestart

    # The RDQ buffer limit is by packets and not bytes, so turn off LSO to
    # avoid strange behavior. This makes RDQ behave more like a real middlebox
    # on the network (such a middlebox would only see packets after LSO sends
    # are split into MTU-sized packets).
    Set-NetAdapterLso duo? -IPv4Enabled $false -IPv6Enabled $false -NoRestart
    Set-NetAdapterUso duo? -IPv4Enabled $false -IPv6Enabled $false -NoRestart

    Set-NetAdapterAdvancedProperty duo? -DisplayName DelayMs -RegistryValue ([convert]::ToInt32($RttMs/2)) -NoRestart
    Set-NetAdapterAdvancedProperty duo? -DisplayName RateLimitMbps -RegistryValue $BottleneckMbps -NoRestart
    Set-NetAdapterAdvancedProperty duo? -DisplayName QueueLimitPackets -RegistryValue $BottleneckBufferPackets -NoRestart
    Set-NetAdapterAdvancedProperty duo? -DisplayName RandomLossDenominator -RegistryValue $RandomLossDenominator -NoRestart
    Set-NetAdapterAdvancedProperty duo? -DisplayName ReorderDelayDeltaMs -RegistryValue $ReorderDelayDeltaMs -NoRestart
    Set-NetAdapterAdvancedProperty duo? -DisplayName RandomReorderDenominator -RegistryValue $RandomReorderDenominator -NoRestart
    Set-NetAdapterAdvancedProperty duo? -DisplayName MaxDelayJitterMs -RegistryValue $MaxDelayJitterMs -NoRestart
    Set-NetAdapterAdvancedProperty duo? -DisplayName RandomDelayJitterDenominator -RegistryValue $RandomDelayJitterDenominator -NoRestart
    Set-NetAdapterAdvancedProperty duo? -DisplayName REDUpper -RegistryValue $REDUpper -NoRestart
    Set-NetAdapterAdvancedProperty duo? -DisplayName REDLower -RegistryValue $REDLower -NoRestart
    Set-NetAdapterAdvancedProperty duo? -DisplayName REDMaxProb -RegistryValue $REDMaxProb -NoRestart
    Set-NetAdapterAdvancedProperty duo? -DisplayName REDQWeightPercent -RegistryValue $REDQWeightPercent -NoRestart
    if ($REDDrop) {
        Set-NetAdapterAdvancedProperty duo? -DisplayName REDDrop -RegistryValue 1 -NoRestart
    } else {
        Set-NetAdapterAdvancedProperty duo? -DisplayName REDDrop -RegistryValue 0 -NoRestart
    }
    if ($RandomSeed -ne "") {
        Set-NetAdapterAdvancedProperty duo? -DisplayName RandomSeed -RegistryValue $RandomSeed -NoRestart
    } else {
        Reset-NetAdapterAdvancedProperty duo? -DisplayName RandomSeed -NoRestart
    }

    Restart-NetAdapter duo?
    Start-Sleep 10 # (wait for duonic to restart)
    Get-NetAdapterAdvancedProperty duo? | Select-Object Name,DisplayName,DisplayValue
    echo "Done."
}

if ($RdqDisable) {
    Set-NetAdapterAdvancedProperty duo? -DisplayName RdqEnabled -RegistryValue 0 -NoRestart
    Set-NetAdapterLso duo? -IPv4Enabled $true -IPv6Enabled $true -NoRestart
    Restart-NetAdapter duo?
    Start-Sleep 10 # (wait for duonic to restart)
    echo "Done."
}

if ($Uninstall) {
    # Uninstall all possible duonic pairs.
    for ($i = 1; $i -le 4; $i++) {
        $nic1 = $i * 2 - 1
        $nic2 = $nic1 + 1

        .\dswdevice.exe -u duonic_svc$nic1 > $null
        .\dswdevice.exe -u duonic_svc$nic2 > $null

        if (-not $NoFirewallRules) {
            netsh advfirewall firewall del rule name=AllowDuonic$i
            netsh advfirewall firewall del rule name=AllowDuonic$i`v6
        }
    }

    # The driver might have already been previously installed via another method. This might
    # have been done if pnputil or Get-WindowsDriver is not available on the machine, which is
    # the case for OneCore-based images.
    if (-not $DriverPreinstalled) {
        sc.exe delete duonic
        # There are some cases where pnputil is used to install the driver, but
        # Get-WindowsDriver is not available, eg RS 1.8x. In that case, fall back to parsing pnputil
        # enum output.
        try {
            $duonicDriverFile = (Get-WindowsDriver -Online | where {$_.OriginalFileName -like "*duonic.inf" }).Driver
        } catch {
            # Expected pnputil enum output is:
            #   Published Name: oem##.inf
            #   Original Name:  duonic.inf
            #   ...
            $driversInstalled = pnputil /enum-drivers
            $duonicDriverFile = ""
            foreach ($line in $driversInstalled) {
                if ($line -match "Published Name") {
                    $duonicDriverFile = $($line -split ":")[1]
                }

                if ($line -match "Original Name") {
                    $infName = $($line -split ":")[1]
                    if ($infName -match "duonic.inf") {
                        break
                    }

                    $duonicDriverFile = ""
                }
            }

            if ($duonicDriverFile -eq "") {
                echo "Couldn't find duonic in driver list."
            }
        }

        # In older OS versions, pnputil was not capable of uninstalling a driver from any devices
        # using it. Fall back to using devcon.
        pnputil /uninstall /delete-driver $duonicDriverFile 2> $null
        if ($LASTEXITCODE -ne 0) {
            .\devcon.exe remove duonic.inf ms_duonic 2> $null
            pnputil /delete-driver $duonicDriverFile /force 2> $null
        }
    }
}
