
param (
    [Parameter(Mandatory = $false)]
    [switch]$NoHyperLinks = $false,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeInactive = $false,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeWatson = $false,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeFullTree = $false
)

if (!$NoHyperLinks -and ($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) -and -not $Env:WT_SESSION) {
    Write-Error "This script requires PowerShell 6 or later. Please install the latest PowerShell Core."
    exit 1
}

if (!"$(gh auth status)".Contains('Logged in')) {
    gh auth login
}

#az login

function Start-GitHubQuery {
    param([string]$repo, $name = $null)
    if (!$name) { $name = $repo.Split('/')[1] }
    Start-Job -ScriptBlock {
        param($repo)
        function ConvertTo-Priority {
            param($labels)
            $priority = ""
            $labels | ForEach-Object {
                switch ($_.name) {
                    'P0' { $priority = '0'; break }
                    'P1' { $priority = '1'; break }
                    'P2' { $priority = '2'; break }
                    'P3' { $priority = '3'; break }
                }
            }
            return $priority
        }

        function ConvertTo-NumberOutput {
            param($repo, $number)
            if ($using:NoHyperLinks) { $number }
            else { "`e]8;;https://github.com/$repo/issues/$number`e\$number`e]8;;`e\" }
        }

        function ConvertTo-Name {
            param($name)
            $name = $name -replace ' \(.*?\)', ''
            $words = $name -split ' '
            $camelCase = $words | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() }
            return $camelCase -join ' '
        }

        $query = `
            gh issue list -R $repo `
            -L 9999 `
            --json number,title,assignees,state,labels
        $query | ConvertFrom-Json | ForEach-Object {
            try {
                $issue = [PSCustomObject]@{
                    origin = $using:name
                    state = $_.state.Tolower().Replace('open', 'active')
                    number = ConvertTo-NumberOutput $repo $_.number
                    priority = ConvertTo-Priority $_.labels
                    assignee = ''
                    title = $_.title
                }
                try { $issue.assignee = ConvertTo-Name $_.assignees[0].name } catch {}
                $issue
            } catch { }
        }
    } -ArgumentList $repo
}

function Start-AzureDevOpsQuery {
    param([string]$path)
    Start-Job -ScriptBlock {
        param([string]$path)
        function ConvertTo-Priority {
            param($field)
            if ($null -eq $field) { "" }
            else { $field.ToString() }
        }

        function ConvertTo-NumberOutput {
            param($number)
            if ($using:NoHyperLinks) { $number }
            else { "`e]8;;https://microsoft.visualstudio.com/OS/_workitems/edit/$number`e\$number`e]8;;`e\" }
        }

        function ConvertTo-Name {
            param($name)
            $name = $name -replace ' \(.*?\)', ''
            if ($name -match '^(.*), (.*)') {
                return "$($matches[2]) $($matches[1])"
            }
            return $name
        }

        $osSelect = "Title,Tags,Priority,Severity,State,[Assigned To]"
        $osWhere = "[Area Path] Under '$path'"
        $osWhere += " AND [Work Item Type] <> 'Test Plan'"
        $osWhere += " AND [Work Item Type] <> 'Test Case'"
        $osWhere += " AND [Product Family] <> 'Windows Servicing'"
        if (!$using:IncludeInactive) {
            $osWhere += " AND (State == 'Active' OR State == 'Proposed' OR State == 'Committed')"
        }
        if (!$using:IncludeWatson) {
            $osWhere += " AND [Assigned To] <> 'Telemetry Bug Tracker (microsoft)'"
            #$osWhere += " AND Product <> 'Watson'"
        }
        if (!$using:IncludeFullTree) {
            $osWhere += " AND [Work Item Type] <> 'Objective'"
            $osWhere += " AND [Work Item Type] <> 'Key Result'"
            $osWhere += " AND [Work Item Type] <> 'Measure'"
            $osWhere += " AND [Work Item Type] <> 'Scenario'"
        }
        $query = `
            az boards query `
            --org https://dev.azure.com/microsoft `
            --project OS `
            --wiql "SELECT $osSelect FROM workitems WHERE $osWhere" `
            --only-show-errors
        $query | ConvertFrom-Json | ForEach-Object {
            try {
                $item = [PSCustomObject]@{
                    origin = 'os'
                    state = $_.fields.'System.State'.Tolower()
                    number = ConvertTo-NumberOutput $_.id
                    priority = ConvertTo-Priority $_.fields.'Microsoft.VSTS.Common.Priority'
                    assignee =  ConvertTo-Name $_.fields.'System.AssignedTo'.displayName.Replace('Closed', '')
                    title = $_.fields.'System.Title'
                }
                $item
            } catch { }
        }
    } -ArgumentList $path
}

$jobs = @()
$jobs += Start-GitHubQuery microsoft/msquic
$jobs += Start-GitHubQuery microsoft/xdp-for-windows xdp
$jobs += Start-GitHubQuery microsoft/win-net-test
$jobs += Start-GitHubQuery microsoft/cxplat
$jobs += Start-GitHubQuery microsoft/netperf
$jobs += Start-GitHubQuery microsoft/etl2pcapng
$jobs += Start-GitHubQuery microsoft/ntttcp
$jobs += Start-GitHubQuery microsoft/latte
$jobs += Start-GitHubQuery microsoft/quicreach
$jobs += Start-GitHubQuery microsoft/net-offloads
#$jobs += Start-GitHubQuery microsoft/ebpf-for-windows ebpf
$jobs += Start-AzureDevOpsQuery 'OS\Core\IO Fabrics\Transports Security and SDN\DPT-Data Path and Transports'
$jobs += Start-AzureDevOpsQuery 'OS\Core\IO Fabrics\Transports Security and SDN\NDX - Network Developer Experience'
$jobs += Start-AzureDevOpsQuery 'OS\Core\IO Fabrics\Transports Security and SDN\Time'

$items = $jobs | Wait-Job | Receive-Job
$empty = $jobs | Remove-Job

$items | Select-Object -Property origin, state, number, priority, assignee, title
