#Requires -Version 7.0
<#
.SYNOPSIS
    Deploys the Defender TVM Snapshot Connector infrastructure to an Azure resource group.

.DESCRIPTION
    Deploys the following components in order from GitHub templates:
        1. Data Collection Endpoint (DCE)
        2. Data Collection Rule (DCR)
        3. Logic App

    After deployment the script:
        - Assigns the Logic App managed identity the Monitoring Metrics Publisher
          role on the DCR.
        - Prints the next-step instructions for assigning the Defender API app role.

    Use -Government to target Azure Government (AzureUSGovernment). Omit it for
    Azure commercial (AzureCloud).

    Prerequisites:
        - Azure CLI installed and signed in: az login
        - PowerShell 7+
        - Contributor (or equivalent) rights on the target resource group
        - Permission to create RBAC role assignments on the DCR

.PARAMETER ResourceGroup
    Name of the existing resource group to deploy into.

.PARAMETER WorkspaceResourceId
    Full resource ID of the Log Analytics workspace.
    Example: /subscriptions/<sub>/resourceGroups/<rg>/providers/microsoft.operationalinsights/workspaces/<ws>

.PARAMETER DceName
    Name for the Data Collection Endpoint. Default: DeviceTvmSnapshot

.PARAMETER DcrName
    Name for the Data Collection Rule. Default: dcr-DeviceTvmSnapshot

.PARAMETER LogicAppName
    Name for the Logic App. Default: DeviceTvmSnapshotConnector

.PARAMETER Location
    Azure region. Defaults to the resource group's region when omitted.

.PARAMETER Subscription
    Subscription name or ID. Uses the current default when omitted.

.PARAMETER Government
    Switch to target Azure Government (AzureUSGovernment cloud).

.EXAMPLE
    # Azure commercial
    .\Deploy-All.ps1 `
        -ResourceGroup      my-rg `
        -WorkspaceResourceId /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-rg/providers/microsoft.operationalinsights/workspaces/my-workspace

.EXAMPLE
    # Azure Government
    .\Deploy-All.ps1 -Government `
        -ResourceGroup      my-rg `
        -WorkspaceResourceId /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-rg/providers/microsoft.operationalinsights/workspaces/my-workspace

.EXAMPLE
    .\Deploy-All.ps1  # prompts for required values interactively
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$WorkspaceResourceId,

    [Parameter(Mandatory = $false)]
    [string]$DceName = 'DeviceTvmSnapshot',

    [Parameter(Mandatory = $false)]
    [string]$DcrName = 'dcr-DeviceTvmSnapshot',

    [Parameter(Mandatory = $false)]
    [string]$LogicAppName = 'DeviceTvmSnapshotConnector',

    [Parameter(Mandatory = $false)]
    [string]$Location,

    [Parameter(Mandatory = $false)]
    [string]$Subscription,

    [Parameter(Mandatory = $false)]
    [switch]$Government
)

$ErrorActionPreference = 'Stop'

$targetCloud = if ($Government) { 'AzureUSGovernment' } else { 'AzureCloud' }
$cloudLabel  = if ($Government) { 'Azure Government'  } else { 'Azure Commercial' }

$huntingUri      = if ($Government) { 'https://graph.microsoft.us/v1.0/security/runHuntingQuery' }   else { 'https://graph.microsoft.com/v1.0/security/runHuntingQuery' }
$huntingAudience = if ($Government) { 'https://graph.microsoft.us' }   else { 'https://graph.microsoft.com' }
$monitorAudience = if ($Government) { 'https://monitor.azure.us' }     else { 'https://monitor.azure.com' }
$graphApiBase    = if ($Government) { 'https://graph.microsoft.us' }   else { 'https://graph.microsoft.com' }
$defenderSpName  = 'WindowsDefenderATP'
$defenderAppRole = 'ThreatHunting.Read.All'

$repoOwner  = 'AndrewBlumhardt'
$repoName   = 'sentinel-defender-tvm-connector'
$repoBranch = 'main'
$tableName  = 'DeviceTvmSnapshot_CL'

# ---- Prompt for required values ------------------------------------------------

if (-not $ResourceGroup)       { $ResourceGroup       = Read-Host 'Resource group name' }
if (-not $WorkspaceResourceId) { $WorkspaceResourceId = Read-Host 'Log Analytics workspace resource ID' }
if (-not $Subscription)        { $Subscription        = Read-Host 'Subscription name or ID (leave blank for current default)' }

# ---- Preflight: Azure CLI available --------------------------------------------

$null = az --version 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI is not available. Install it from https://aka.ms/installazurecli and rerun.'
}

# ---- Cloud -----------------------------------------------------------------------

$currentCloud = (az cloud show --query name -o tsv 2>$null)
if ($currentCloud -ne $targetCloud) {
    Write-Host "Switching Azure CLI from '$currentCloud' to '$targetCloud'." -ForegroundColor Yellow
    az cloud set --name $targetCloud
    if ($LASTEXITCODE -ne 0) { throw "Failed to switch Azure CLI to $targetCloud." }
}

# ---- Login check ----------------------------------------------------------------

$accountJson = az account show -o json 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($accountJson)) {
    $loginHint = if ($Government) { 'az login --environment AzureUSGovernment' } else { 'az login' }
    throw "Not logged in to Azure CLI. Run '$loginHint' and rerun the script."
}

if (-not [string]::IsNullOrWhiteSpace($Subscription)) {
    az account set --subscription $Subscription
    if ($LASTEXITCODE -ne 0) { throw "Unable to select subscription '$Subscription'." }
    $accountJson = az account show -o json
}

$account = $accountJson | ConvertFrom-Json
Write-Host "`nCloud: $cloudLabel | Subscription: $($account.name) ($($account.id))" -ForegroundColor DarkCyan

$enabledSubscriptions = az account list --query "[?state=='Enabled'] | length(@)" -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($enabledSubscriptions) -or [int]$enabledSubscriptions -lt 1) {
    $tenantHint = if ($Government) {
        'No enabled subscriptions found in AzureUSGovernment. Verify tenant/directory access and run: az login --environment AzureUSGovernment'
    }
    else {
        'No enabled subscriptions found in AzureCloud. Verify tenant/directory access and run: az login'
    }
    throw $tenantHint
}

# ---- Resolve location -----------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($Location)) {
    $Location = az group show --name $ResourceGroup --query location -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Location)) {
        throw "Resource group '$ResourceGroup' not found in subscription $($account.id)."
    }
    Write-Host "Location not specified; using resource group location: $Location" -ForegroundColor DarkCyan
}

$workspaceMatch = [regex]::Match(
    $WorkspaceResourceId,
    '^/subscriptions/[^/]+/resourceGroups/([^/]+)/providers/Microsoft\.OperationalInsights/workspaces/([^/]+)$',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

if (-not $workspaceMatch.Success) {
    throw "WorkspaceResourceId is not a valid Log Analytics workspace ARM ID: $WorkspaceResourceId"
}

$workspaceRg   = $workspaceMatch.Groups[1].Value
$workspaceName = $workspaceMatch.Groups[2].Value

$timestamp = Get-Date -Format 'yyyyMMddHHmmss'
$results   = [System.Collections.Generic.List[pscustomobject]]::new()

function Invoke-Step {
    param([string]$Label, [scriptblock]$Action)
    Write-Host "`n[DEPLOY] $Label" -ForegroundColor Cyan
    if ($WhatIfPreference) {
        Write-Host '  WhatIf: skipping actual deployment.' -ForegroundColor DarkYellow
        $results.Add([pscustomobject]@{ Step = $Label; Status = 'WhatIf' })
        return $true
    }
    try {
        & $Action
        if ($LASTEXITCODE -ne 0) { throw "Exit code $LASTEXITCODE" }
        $results.Add([pscustomobject]@{ Step = $Label; Status = 'OK' })
        return $true
    }
    catch {
        Write-Host "  FAILED: $_" -ForegroundColor Red
        $results.Add([pscustomobject]@{ Step = $Label; Status = "Failed: $_" })
        return $false
    }
}

# ---- 1. Create/validate custom workspace table ----------------------------------

Write-Host "`n[CHECK] Workspace table '$tableName' in workspace '$workspaceName'..." -ForegroundColor Cyan
$tableJson = az monitor log-analytics workspace table show `
    --resource-group $workspaceRg `
    --workspace-name $workspaceName `
    --name $tableName `
    -o json 2>$null

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($tableJson)) {
    Write-Host "  Table already exists." -ForegroundColor Green
    $results.Add([pscustomobject]@{ Step = 'Workspace table (DeviceTvmSnapshot_CL)'; Status = 'Exists' })
}
else {
    $tableTemplateUri = "https://raw.githubusercontent.com/$repoOwner/$repoName/$repoBranch/table/template.json"
    $ok = Invoke-Step 'Workspace table (DeviceTvmSnapshot_CL)' {
        az deployment group create `
            --resource-group $workspaceRg `
            --name "table-$timestamp" `
            --template-uri $tableTemplateUri `
            --parameters workspaceName=$workspaceName tableName=$tableName `
            --output table
    }
    if (-not $ok) { throw 'Workspace table deployment failed. Aborting.' }

    $tableJson = az monitor log-analytics workspace table show `
        --resource-group $workspaceRg `
        --workspace-name $workspaceName `
        --name $tableName `
        -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tableJson)) {
        throw "Workspace table '$tableName' was not found after deployment in workspace '$workspaceName' ($workspaceRg)."
    }
}

# ---- 2. Deploy DCE ---------------------------------------------------------------

$dceTemplatUri = "https://raw.githubusercontent.com/$repoOwner/$repoName/$repoBranch/dce/template.json"

$ok = Invoke-Step 'Data Collection Endpoint (DCE)' {
    az deployment group create `
        --resource-group $ResourceGroup `
        --name "dce-$timestamp" `
        --template-uri $dceTemplatUri `
        --parameters dataCollectionEndpoints_DeviceTvmSnapshot_name=$DceName location=$Location `
        --output table
}
if (-not $ok) { throw 'DCE deployment failed. Aborting.' }

$dceId             = az monitor data-collection endpoint show -g $ResourceGroup -n $DceName --query id                          -o tsv 2>$null
$dceIngestEndpoint = az monitor data-collection endpoint show -g $ResourceGroup -n $DceName --query logsIngestion.endpoint       -o tsv 2>$null

if ([string]::IsNullOrWhiteSpace($dceId) -or [string]::IsNullOrWhiteSpace($dceIngestEndpoint)) {
    # Fallback for CLI versions that nest properties differently
    $dceJson           = az monitor data-collection endpoint show -g $ResourceGroup -n $DceName -o json | ConvertFrom-Json
    $dceId             = $dceJson.id
    $dceIngestEndpoint = $dceJson.properties.logsIngestion.endpoint
}

Write-Host "  DCE resource ID    : $dceId"             -ForegroundColor DarkGray
Write-Host "  DCE ingest endpoint: $dceIngestEndpoint" -ForegroundColor DarkGray

# ---- 3. Deploy DCR ---------------------------------------------------------------

$dcrTemplateUri = "https://raw.githubusercontent.com/$repoOwner/$repoName/$repoBranch/dcr/template.json"

$ok = Invoke-Step 'Data Collection Rule (DCR)' {
    az deployment group create `
        --resource-group $ResourceGroup `
        --name "dcr-$timestamp" `
        --template-uri $dcrTemplateUri `
        --parameters `
            dataCollectionRules_dcr_DeviceTvmSnapshot_name=$DcrName `
            dataCollectionEndpoints_DeviceTvmSnapshot_externalid=$dceId `
            workspaceResourceId=$WorkspaceResourceId `
            location=$Location `
        --output table
}
if (-not $ok) { throw 'DCR deployment failed. Aborting.' }

$dcrId          = az monitor data-collection rule show -g $ResourceGroup -n $DcrName --query id          -o tsv 2>$null
$dcrImmutableId = az monitor data-collection rule show -g $ResourceGroup -n $DcrName --query immutableId  -o tsv 2>$null

if ([string]::IsNullOrWhiteSpace($dcrImmutableId)) {
    $dcrJson        = az monitor data-collection rule show -g $ResourceGroup -n $DcrName -o json | ConvertFrom-Json
    $dcrId          = $dcrJson.id
    $dcrImmutableId = $dcrJson.properties.immutableId
}

Write-Host "  DCR resource ID  : $dcrId"          -ForegroundColor DarkGray
Write-Host "  DCR immutable ID : $dcrImmutableId" -ForegroundColor DarkGray

# ---- 4. Build ingestion URI ------------------------------------------------------

# Normalize endpoint (ensure trailing /)
if (-not $dceIngestEndpoint.EndsWith('/')) { $dceIngestEndpoint += '/' }
$logsIngestionUri = "${dceIngestEndpoint}dataCollectionRules/${dcrImmutableId}/streams/Custom-DeviceTvmSnapshot_CL?api-version=2023-01-01"
Write-Host "  Logs ingestion URI: $logsIngestionUri" -ForegroundColor DarkGray

# ---- 5. Deploy Logic App ---------------------------------------------------------

$laTemplateUri = "https://raw.githubusercontent.com/$repoOwner/$repoName/$repoBranch/logic%20app/template.json"

$ok = Invoke-Step 'Logic App' {
    az deployment group create `
        --resource-group $ResourceGroup `
        --name "logicapp-$timestamp" `
        --template-uri $laTemplateUri `
        --parameters `
            workflows_QueryGraphAPI_name=$LogicAppName `
            location=$Location `
            logsIngestionUri=$logsIngestionUri `
            advancedHuntingUri=$huntingUri `
            advancedHuntingAudience=$huntingAudience `
            logsIngestionAudience=$monitorAudience `
        --output table
}
if (-not $ok) { throw 'Logic App deployment failed. Aborting.' }

# ---- 6. Assign Monitoring Metrics Publisher on DCR --------------------------------

Write-Host "`n[RBAC] Assigning Monitoring Metrics Publisher on DCR..." -ForegroundColor Cyan
$laJson        = az logic workflow show -g $ResourceGroup -n $LogicAppName -o json | ConvertFrom-Json
$miPrincipalId = $laJson.identity.principalId

if ([string]::IsNullOrWhiteSpace($miPrincipalId)) {
    Write-Host '  WARNING: Could not retrieve Logic App managed identity. Assign Monitoring Metrics Publisher on the DCR manually.' -ForegroundColor Yellow
    $results.Add([pscustomobject]@{ Step = 'RBAC: Monitoring Metrics Publisher'; Status = 'Skipped (MI not found)' })
}
else {
    az role assignment create `
        --assignee-object-id $miPrincipalId `
        --assignee-principal-type ServicePrincipal `
        --role 'Monitoring Metrics Publisher' `
        --scope $dcrId `
        --output none 2>$null

    if ($LASTEXITCODE -eq 0) {
        Write-Host '  Role assigned successfully.' -ForegroundColor Green
        $results.Add([pscustomobject]@{ Step = 'RBAC: Monitoring Metrics Publisher'; Status = 'OK' })
    }
    else {
        Write-Host '  WARNING: Role assignment failed. Assign Monitoring Metrics Publisher on the DCR manually.' -ForegroundColor Yellow
        $results.Add([pscustomobject]@{ Step = 'RBAC: Monitoring Metrics Publisher'; Status = 'Failed - assign manually' })
    }
}

# ---- Summary -------------------------------------------------------------------

Write-Host "`n--- Deployment Summary ($cloudLabel) ---" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$failed = @($results | Where-Object { $_.Status -notmatch '^(OK|WhatIf|Skipped)' })
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) step(s) failed. Review the output above." -ForegroundColor Red
    exit 1
}

# ---- Next Steps ----------------------------------------------------------------

$updateLogicAppCommand = @(
    'az deployment group create',
    "  --resource-group $ResourceGroup",
    '  --template-file "logic app/template.json"',
    (if ($Government) { '  --parameters @"logic app/parameters.gov.json"' } else { '  --parameters @"logic app/parameters.commercial.json"' }),
    "  --parameters workflows_QueryGraphAPI_name=$LogicAppName location=$Location logsIngestionUri='$logsIngestionUri'"
) -join "`n"

$defenderCliCommands = @(
    "$([Environment]::NewLine)# Resolve the Defender for Endpoint Enterprise application object",
    "MDE_RESOURCE_SP_ID=`$(az ad sp list --display-name \"$defenderSpName\" --query \"[0].id\" -o tsv)",
    "$([Environment]::NewLine)# Resolve the Threat Hunting app role ID",
    "APP_ROLE_ID=`$(az ad sp show --id `$MDE_RESOURCE_SP_ID --query \"appRoles[?value=='$defenderAppRole' && contains(allowedMemberTypes, 'Application')].id | [0]\" -o tsv)",
    "$([Environment]::NewLine)# Assign the app role to the Logic App managed identity",
    "az rest --method POST --url \"$graphApiBase/v1.0/servicePrincipals/$miPrincipalId/appRoleAssignments\" --headers \"Content-Type=application/json\" --body '{\"principalId\":\"$miPrincipalId\",\"resourceId\":\"'\"`$MDE_RESOURCE_SP_ID\"'\",\"appRoleId\":\"'\"`$APP_ROLE_ID\"'\"}'"
) -join "`n"

Write-Host @"

--- Next Steps ---

1. Assign Defender API app role to the Logic App managed identity (requires admin consent):

     Logic App MI principal ID : $miPrincipalId
    Required app role         : $defenderAppRole
    Defender enterprise app   : $defenderSpName

    This connector uses managed identity only. No separate app registration or client secret is required.
    This is an app role assignment to the managed identity object via CLI/Graph, not an Entra directory role.
    Azure portal UI does not reliably expose this assignment path for managed identities.
     Use Azure CLI / Microsoft Graph. Example:

$defenderCliCommands

2. Update or verify the Logic App ingestion URI by recomputing it from the deployed DCE/DCR values:

         $logsIngestionUri

     If you need to redeploy the Logic App with the current URI, run:

$updateLogicAppCommand

3. Test: trigger the Logic App manually in the portal (Run Trigger on Recurrence),
   then validate data in Log Analytics:

     DeviceTvmSnapshot_CL
     | summarize Rows=count(), Latest=max(TimeGenerated)

"@ -ForegroundColor DarkCyan
