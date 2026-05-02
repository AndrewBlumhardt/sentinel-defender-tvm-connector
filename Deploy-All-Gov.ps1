#Requires -Version 7.0
<#
.SYNOPSIS
    Convenience wrapper that runs Deploy-All.ps1 targeting Azure Government.

.DESCRIPTION
    Identical to calling:
        .\Deploy-All.ps1 -Government @PSBoundParameters

    See Deploy-All.ps1 for full parameter documentation.

.EXAMPLE
    .\Deploy-All-Gov.ps1 `
        -ResourceGroup      my-rg `
        -WorkspaceResourceId /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-rg/providers/microsoft.operationalinsights/workspaces/my-workspace
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)] [string]$ResourceGroup,
    [Parameter(Mandatory = $false)] [string]$WorkspaceResourceId,
    [Parameter(Mandatory = $false)] [string]$DceName       = 'DeviceTvmSnapshot',
    [Parameter(Mandatory = $false)] [string]$DcrName       = 'dcr-DeviceTvmSnapshot',
    [Parameter(Mandatory = $false)] [string]$LogicAppName  = 'DeviceTvmSnapshotConnector',
    [Parameter(Mandatory = $false)] [string]$Location,
    [Parameter(Mandatory = $false)] [string]$Subscription,
    [Parameter(Mandatory = $false)] [int]$RbacAssignmentTimeoutSeconds = 90
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$scriptDir\Deploy-All.ps1" @PSBoundParameters -Government
