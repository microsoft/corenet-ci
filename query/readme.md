# Setup

The [dpt.ps1](./dpt.ps1) PowerShell script was created because there doesn't seem to be any standard way to run queries across different ADO and GitHub projects, so we've created thos to leverage each's CLI. The following instructions will help you get set up.

## Install

You can use [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/) to install the dependencies:

- [GitHub CLI](https://cli.github.com/): `winget install -e --id Microsoft.AzureCLI`
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/): `winget install -e --id GitHub.cli`

> **Note:** Restart your terminal afterwards.

## Login

To log in to each CLI, run in a normal (**NOT Administrator**) Windows Terminal:

- **GitHub CLI**: `gh auth login` (then walk through the wizard)
- **Azure CLI**: `az login` (then go through and accept all defaults)

## Validate

To validate things are correctly installed and working run:

- **GitHub CLI**: `gh issue list -R microsoft/msquic`
- **Azure CLI**: `az boards query --org https://dev.azure.com/microsoft --project OS --wiql "SELECT Title FROM workitems WHERE Tags Contains 'QUIC'"`

> **Note:** For ADO, you likely will have to approve installation of a dependency first.

# Execution

### Count of Work Items by origin (repository)

```PowerShell
> $items = .\dpt.ps1

> $items | Group-Object -Property origin | Select-Object Count,Name | Sort-Object Count -Descending

Count Name
----- ----
  660 os
  149 msquic
   61 xdp
   19 net-offloads
    9 netperf
    7 ntttcp
    3 cxplat
    3 etl2pcapng
    3 win-net-test
    2 latte
```

### Table of Work Items

```PowerShell
> $items = .\dpt.ps1

> $items | Format-Table -AutoSize

origin       state     number   priority assignee                   title
------       -----     ------   -------- --------                   -----
msquic       active    4375                                         test.ps1
msquic       active    4370                                         msquic missing from packages.microsoft.com for ama…
msquic       active    4367                                         packages for Ubuntu 24 seems to be missing on pack…
msquic       active    4361                                         Ubuntu 22.04+ perf issue
msquic       active    4360                                         Expose RttVariance statistic
msquic       active    4347                                         spinquic assert failure during cleanup phase
msquic       active    4338                                         Windows DataPathTest/DataPathTest.TcpConnect/4 ass…
msquic       active    4330                                         Basic/WithRebindPaddingArgs.RebindAddrPadded faile…
msquic       active    4328                                         Handshake/WithHandshakeArgs4.RandomLoss/23 fail
msquic       active    4326                                         Misc/WithCidUpdateArgs.CidUpdate/5 faliure
...
```

### Table of Work Items for Assignee

```PowerShell
> $items | Where-Object { $_.assignee -eq 'Matt Olson' } | Select-Object origin,number,priority,title | Format-Table -AutoSize

origin number   priority title
------ ------   -------- -----
msquic 763               Support BBR Congestion Control
os     8133782           .....
os     8187966           .....
os     10367971          .....
```
