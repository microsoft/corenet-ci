
param (
    [Parameter(Mandatory = $false)]
    [switch]$IncludeWatson = $false,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeFullTree = $false,

    [Parameter(Mandatory = $false)]
    [string]$User = ""
)

Write-Host "`n[$(Get-Date)] Running query..."
$items = ./dpt.ps1 -IncludeWatson:$IncludeWatson -IncludeFullTree:$IncludeFullTree

if ($User -eq "") {
    Write-Host "[$(Get-Date)] Query complete! Total items: $($items.Count)"

    Write-Host "`nItems by Origin"
    $items | Group-Object origin | Select-Object Count,Name | Sort-Object Count -Descending | Format-Table -AutoSize

    Write-Host "`nItems by Assignee"
    $items | Group-Object assignee | Select-Object Count,Name | Sort-Object Count -Descending | Format-Table -AutoSize

    Write-Host "`nItems by Priority"
    $items | Group-Object priority | Select-Object Count,Name | Sort-Object Count -Descending | Format-Table -AutoSize

} else {
    $items = $items | Where-Object { $_.assignee -eq $User }
    Write-Host "[$(Get-Date)] Query complete! Total items: $($items.Count)"

    $items | Select-Object origin,number,priority,title | Sort-Object number | Format-Table -AutoSize
}
