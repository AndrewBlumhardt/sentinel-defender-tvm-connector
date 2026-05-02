# Defender TVM Snapshot Connector for Microsoft Sentinel

## Overview

This project is a **Logic App-based proof of concept** for exporting selected Microsoft Defender Threat and Vulnerability Management (TVM) Advanced Hunting tables into a custom Log Analytics / Microsoft Sentinel table.

The goal is to enable:

- Snapshot-based TVM data retention
- Custom workbook and dashboard scenarios
- Experimental analysis of TVM data in Sentinel

This is **not intended to be a fully scalable production connector**. It works best for **small to medium environments** or **targeted table exports**.

For a full walkthrough and background, see the blog post: <a href="https://www.techchat.blog/2026/05/01/sentinel-tvm-snapshot-data-connector/" target="_blank">Sentinel TVM Snapshot Data Connector</a>

## Architecture

The workflow follows a simple pattern:

1. A Logic App runs on a scheduled trigger.
2. It queries Defender Advanced Hunting for selected TVM tables.
3. Results are paged using row number batching.
4. Data is written to Log Analytics using the Logs Ingestion API (DCR/DCE pipeline).
5. The data lands in a single table called `DeviceTvmSnapshot_CL`.

Core components:

- Logic App (with system-assigned managed identity)
- Data Collection Endpoint (DCE)
- Data Collection Rule (DCR)
- Log Analytics workspace
- Defender Advanced Hunting API

## Included Tables

Included tables:

```text
DeviceTvmInfoGathering
DeviceTvmInfoGatheringKB
DeviceTvmSoftwareEvidenceBeta
DeviceTvmCertificateInfo
DeviceTvmSecureConfigurationAssessment
DeviceTvmBrowserExtensions
DeviceTvmBrowserExtensionsKB
DeviceTvmHardwareFirmware
DeviceTvmSoftwareInventory
DeviceTvmSecureConfigurationAssessmentKB
```

Excluded tables:

```text
DeviceTvmSoftwareVulnerabilitiesKB
DeviceTvmSoftwareVulnerabilities
```

- `DeviceTvmSoftwareVulnerabilitiesKB` is a global dataset (~300K records) and does not scale per device.
- `DeviceTvmSoftwareVulnerabilities` represents similar data scoped to device software.

Despite the word "Vulnerabilities" in the names, review of the returned data showed the value was **less direct and less meaningful** for this connector's core snapshot use case than expected.

These tables were removed because they accounted for **most of the data volume** and were a **major scalability bottleneck**. They can be added back if needed, but doing so significantly increases runtime and resource usage.

## Repository Layout

```text
.
|-- dce/
|   |-- template.json
|   `-- parameters.json
|-- dcr/
|   |-- template.json
|   `-- parameters.json
|-- table/
|   |-- template.json
|   `-- parameters.json
`-- logic app/
    |-- template.json
    |-- parameters.json
    |-- parameters.commercial.json
    `-- parameters.gov.json
```

## Pre-Deploy Data Collection (Required)

Capture these values before running any deployment option (script, portal button, or CLI):

- Sentinel workspace name
- Subscription ID
- Workspace ARM resource ID
- Workspace (Sentinel) region

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
WORKSPACE_NAME=<workspace-name>
WORKSPACE_RG=<workspace-resource-group>

WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace show \
  --resource-group $WORKSPACE_RG \
  --workspace-name $WORKSPACE_NAME \
  --query id -o tsv)

WORKSPACE_REGION=$(az monitor log-analytics workspace show \
  --resource-group $WORKSPACE_RG \
  --workspace-name $WORKSPACE_NAME \
  --query location -o tsv)

echo "Subscription       : $SUBSCRIPTION_ID"
echo "Workspace name     : $WORKSPACE_NAME"
echo "Workspace ARM ID   : $WORKSPACE_RESOURCE_ID"
echo "Workspace region   : $WORKSPACE_REGION"
```

> [!IMPORTANT]
> **DCE, DCR, and Log Analytics workspace must all be in the same region.** Set your deployment `LOCATION` to the workspace region.

ARM ID examples (fully qualified):

```text
Workspace ARM ID:
/subscriptions/<subscription-id>/resourceGroups/<workspace-rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>

DCE ARM ID (this is the value for dataCollectionEndpointId / dataCollectionEndpoints_DeviceTvmSnapshot_externalid):
/subscriptions/<subscription-id>/resourceGroups/<dce-rg>/providers/Microsoft.Insights/dataCollectionEndpoints/<dce-name>
```

## Deployment Options

This repo supports three deployment paths:

1. Scripted deployment (recommended): one-command PowerShell flow via `Deploy-All.ps1` or `Deploy-All-Gov.ps1`.
2. Portal button deployment: click-through ARM deployments for each component (`Table -> DCE -> DCR -> Logic App`).
3. Manual CLI walkthrough: staged `az` commands with explicit variables and validation checks.

## Deploy with Script (Recommended)

Clone the repo, then run a single PowerShell 7+ script that deploys **Table -> DCE -> DCR -> Logic App** in order, wires up the managed identity RBAC, and prints next-step instructions.

```powershell
# Azure Commercial
.\Deploy-All.ps1 `
    -ResourceGroup      <rg-name> `
  -WorkspaceResourceId /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<ws>

# Azure Government
.\Deploy-All-Gov.ps1 `
    -ResourceGroup      <rg-name> `
  -WorkspaceResourceId /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<ws>
```

Only `-ResourceGroup` and `-WorkspaceResourceId` are typically required. All other parameters have defaults. Run without arguments to be prompted interactively.

---

## Deploy To Azure (Portal Buttons)

Deploy in this order: Table -> DCE -> DCR -> Logic App.

| Cloud | Table | DCE | DCR | Logic App |
| --- | --- | --- | --- | --- |
| Azure Commercial | <a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Ftable%2Ftemplate.json"><img src="https://aka.ms/deploytoazurebutton" alt="Deploy Table to Azure"></a> | <a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Fdce%2Ftemplate.json"><img src="https://aka.ms/deploytoazurebutton" alt="Deploy DCE to Azure"></a> | <a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Fdcr%2Ftemplate.json"><img src="https://aka.ms/deploytoazurebutton" alt="Deploy DCR to Azure"></a> | <a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Flogic%2520app%2Ftemplate.json"><img src="https://aka.ms/deploytoazurebutton" alt="Deploy Logic App to Azure"></a> |
| Azure Government | <a href="https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Ftable%2Ftemplate.json"><img src="https://aka.ms/deploytoazuregovbutton" alt="Deploy Table to Azure Government"></a> | <a href="https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Fdce%2Ftemplate.json"><img src="https://aka.ms/deploytoazuregovbutton" alt="Deploy DCE to Azure Government"></a> | <a href="https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Fdcr%2Ftemplate.json"><img src="https://aka.ms/deploytoazuregovbutton" alt="Deploy DCR to Azure Government"></a> | <a href="https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Flogic%2520app%2Ftemplate.json"><img src="https://aka.ms/deploytoazuregovbutton" alt="Deploy Logic App to Azure Government"></a> |

> [!IMPORTANT]
> If the subscription dropdown is empty in the deploy blade, you are usually signed into the wrong cloud or directory for that button. Use `portal.azure.com` for commercial and `portal.azure.us` for government, then switch to the correct directory/tenant and retry.

## Manual CLI Walkthrough (Step-by-Step)

The most reliable method is **staged deployment with explicit parameter values** and **post-deploy validation**.

### 0. Prerequisites

- Contributor (or higher) on target resource group.
- Permission to assign RBAC on the DCR.
- Permission to assign app roles in Microsoft Entra ID (admin consent path).
- Existing Log Analytics workspace.
- Azure CLI login to the correct cloud.

```bash
# Commercial
az cloud set --name AzureCloud
az login

# Government
az cloud set --name AzureUSGovernment
az login
```

### 1. Set Variables

```bash
RG=<resource-group>
LOCATION=$WORKSPACE_REGION
WORKSPACE_RESOURCE_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-rg/providers/Microsoft.OperationalInsights/workspaces/my-workspace

DCE_NAME=DeviceTvmSnapshot
DCR_NAME=dcr-DeviceTvmSnapshot
LOGICAPP_NAME=DeviceTvmSnapshotConnector
```

### 2. Create or Verify Custom Table (Required Before DCR)

The DCR deployment validates that `DeviceTvmSnapshot_CL` already exists in the target Log Analytics workspace.

If this table does not exist yet, create it before deploying DCR:

```bash
# Option A: Deploy ARM template in workspace resource group
az deployment group create \
  --resource-group $WORKSPACE_RG \
  --template-file table/template.json \
  --parameters @table/parameters.json \
  --parameters workspaceName=$WORKSPACE_NAME tableName=DeviceTvmSnapshot_CL

# Option B: Create table directly with CLI
az monitor log-analytics workspace table create \
  --resource-group $WORKSPACE_RG \
  --workspace-name $WORKSPACE_NAME \
  --name DeviceTvmSnapshot_CL \
  --columns TimeGenerated=datetime TableName=string
```

Verify table exists:

```bash
az monitor log-analytics workspace table show \
  --resource-group $WORKSPACE_RG \
  --workspace-name $WORKSPACE_NAME \
  --name DeviceTvmSnapshot_CL \
  --query "{name:name, provisioningState:provisioningState}" -o table
```

> [!IMPORTANT]
> If DCR deployment fails with `InvalidOutputTable` for `Custom-DeviceTvmSnapshot_CL`, the custom table is missing (or not fully provisioned yet) in the destination workspace.

### 3. Deploy DCE

```bash
az deployment group create \
  --resource-group $RG \
  --template-file dce/template.json \
  --parameters @dce/parameters.json \
  --parameters dataCollectionEndpoints_DeviceTvmSnapshot_name=$DCE_NAME location=$LOCATION

DCE_ID=$(az monitor data-collection endpoint show -g $RG -n $DCE_NAME --query id -o tsv)
```

### 4. Deploy DCR

```bash
az deployment group create \
  --resource-group $RG \
  --template-file dcr/template.json \
  --parameters @dcr/parameters.json \
  --parameters \
    dataCollectionRules_dcr_DeviceTvmSnapshot_name=$DCR_NAME \
    dataCollectionEndpoints_DeviceTvmSnapshot_externalid=$DCE_ID \
    workspaceResourceId=$WORKSPACE_RESOURCE_ID \
    location=$LOCATION

DCR_ID=$(az monitor data-collection rule show -g $RG -n $DCR_NAME --query id -o tsv)
```

### 5. Build Logs Ingestion URI (DCE + DCR Immutable ID)

```bash
DCR_IMMUTABLE_ID=$(az monitor data-collection rule show -g $RG -n $DCR_NAME --query immutableId -o tsv)

# Fallback for older CLI schemas:
# DCR_IMMUTABLE_ID=$(az monitor data-collection rule show -g $RG -n $DCR_NAME --query properties.immutableId -o tsv)

DCE_INGEST_ENDPOINT=$(az monitor data-collection endpoint show -g $RG -n $DCE_NAME --query logsIngestion.endpoint -o tsv)

# Fallback for older CLI schemas:
# DCE_INGEST_ENDPOINT=$(az monitor data-collection endpoint show -g $RG -n $DCE_NAME --query properties.logsIngestion.endpoint -o tsv)

LOGS_INGEST_URI="${DCE_INGEST_ENDPOINT}dataCollectionRules/${DCR_IMMUTABLE_ID}/streams/Custom-DeviceTvmSnapshot_CL?api-version=2023-01-01"
echo $LOGS_INGEST_URI
```

### 6. Deploy Logic App

Use the cloud-specific sample parameters and pass the computed `logsIngestionUri`.

> [!IMPORTANT]
> If you configure or adjust the Logic App HTTP actions manually in the portal, verify the Managed Identity authentication audience values for your cloud. This is easy to overlook and will cause authentication failures.
> - Commercial: `advancedHuntingAudience=https://graph.microsoft.com`, `logsIngestionAudience=https://monitor.azure.com`
> - Government: `advancedHuntingAudience=https://graph.microsoft.us`, `logsIngestionAudience=https://monitor.azure.us`

```bash
# Commercial
az deployment group create \
  --resource-group $RG \
  --template-file "logic app/template.json" \
  --parameters @"logic app/parameters.commercial.json" \
  --parameters workflows_QueryGraphAPI_name=$LOGICAPP_NAME location=$LOCATION logsIngestionUri="$LOGS_INGEST_URI"

# Government
az deployment group create \
  --resource-group $RG \
  --template-file "logic app/template.json" \
  --parameters @"logic app/parameters.gov.json" \
  --parameters workflows_QueryGraphAPI_name=$LOGICAPP_NAME location=$LOCATION logsIngestionUri="$LOGS_INGEST_URI"
```

### 7. Assign Managed Identity Role on DCR (Ingestion)

`Monitoring Metrics Publisher` on the DCR is required for Logs Ingestion API writes. **No broader Sentinel role, including Sentinel Contributor, substitutes for this requirement.**

> [!IMPORTANT]
> `Monitoring Metrics Publisher` on the DCR is mandatory for this connector's ingestion path. No broader Sentinel role is an equivalent substitute.

You can assign this role either with Azure CLI (example below) or manually in the Azure portal on the DCR IAM blade.

```bash
LA_MI_PRINCIPAL_ID=$(az logic workflow show -g $RG -n $LOGICAPP_NAME --query identity.principalId -o tsv)

az role assignment create \
  --assignee-object-id $LA_MI_PRINCIPAL_ID \
  --assignee-principal-type ServicePrincipal \
  --role "Monitoring Metrics Publisher" \
  --scope $DCR_ID
```

### 8. Assign Defender API App Role to Managed Identity

This connector uses the Defender Advanced Hunting API. The Logic App managed identity must be granted the `ThreatHunting.Read.All` app role on the Defender for Endpoint Enterprise application (`WindowsDefenderATP`).

This is assigned with **Azure CLI / Microsoft Graph** as an app role assignment on the managed identity object. This connector does **not** use a separate app registration or client secret.

The Azure portal UI does not provide a reliable path to assign this app role to managed identities. **Use CLI/Graph for this step. No Azure RBAC or Entra role assignment can replace it.**

> [!NOTE]
> This repository defaults to managed identity and secretless auth. If preferred, this API permission can also be granted to a service principal.

Example (Microsoft Graph app role assignment flow):

```bash
# Defender for Endpoint Enterprise application object (varies by tenant/cloud naming)
MDE_RESOURCE_SP_ID=$(az ad sp list --display-name "WindowsDefenderATP" --query "[0].id" -o tsv)

APP_ROLE_ID=$(az ad sp show --id $MDE_RESOURCE_SP_ID --query "appRoles[?value=='ThreatHunting.Read.All' && contains(allowedMemberTypes, 'Application')].id | [0]" -o tsv)

az rest --method POST \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/$LA_MI_PRINCIPAL_ID/appRoleAssignments" \
  --headers "Content-Type=application/json" \
  --body "{\"principalId\":\"$LA_MI_PRINCIPAL_ID\",\"resourceId\":\"$MDE_RESOURCE_SP_ID\",\"appRoleId\":\"$APP_ROLE_ID\"}"
```

> [!IMPORTANT]
> Admin consent and directory permissions are required for this step.

### 9. Update/Verify Ingestion URI in Logic App

The deployment script already constructs this value from the deployed DCE ingest endpoint and DCR immutable ID, then passes it into the Logic App deployment automatically.

If DCR or DCE values change later, recompute the URI from variables and redeploy the Logic App with the updated `logsIngestionUri` value instead of editing the workflow manually.

```bash
DCR_IMMUTABLE_ID=$(az monitor data-collection rule show -g $RG -n $DCR_NAME --query immutableId -o tsv)
DCE_INGEST_ENDPOINT=$(az monitor data-collection endpoint show -g $RG -n $DCE_NAME --query logsIngestion.endpoint -o tsv)

LOGS_INGEST_URI="${DCE_INGEST_ENDPOINT}dataCollectionRules/${DCR_IMMUTABLE_ID}/streams/Custom-DeviceTvmSnapshot_CL?api-version=2023-01-01"

az deployment group create \
  --resource-group $RG \
  --template-file "logic app/template.json" \
  --parameters @"logic app/parameters.commercial.json" \
  --parameters workflows_QueryGraphAPI_name=$LOGICAPP_NAME location=$LOCATION logsIngestionUri="$LOGS_INGEST_URI"
```

Expected format:

```text
{DCE_INGEST_ENDPOINT}dataCollectionRules/{DCR_IMMUTABLE_ID}/streams/Custom-DeviceTvmSnapshot_CL?api-version=2023-01-01
```

### 10. Test End-to-End

1. Trigger the Logic App manually once from the portal (Run Trigger on `Recurrence`) for immediate validation.
2. Confirm run status is Succeeded.
3. If you just assigned credentials or permissions, **wait 10 to 15 minutes** for them to propagate before running the Logic App.
4. If the Logic App run completes successfully, **wait at least 30 minutes** before assuming the solution is not working. New tables and fresh data can take time to appear in the Log Analytics and Sentinel user interfaces.

> [!IMPORTANT]
> If the Logic App run succeeds, be patient before troubleshooting missing data. It can take **30 minutes or more** for a newly created table and its records to become visible in the UI.

5. Validate data landed in Log Analytics:

```kusto
DeviceTvmSnapshot_CL
| summarize Rows=count(), Latest=max(TimeGenerated)
```

6. Validate table coverage:

```kusto
DeviceTvmSnapshot_CL
| summarize Rows=count() by TableName
| order by Rows desc
```

## Required Configuration Summary

### Ingestion RBAC

- **Role:** `Monitoring Metrics Publisher`
- **Scope:** `Data Collection Rule (DCR)`
- **Assignment method:** Azure CLI or Azure portal (`DCR -> Access control (IAM)`)
- **Important:** No broader Sentinel role is an equivalent substitute.

### Defender Advanced Hunting API Permission

- **App role:** `ThreatHunting.Read.All`
- **Assignment method:** Azure CLI / Microsoft Graph
- **Important:** No Azure or Sentinel RBAC role is an equivalent substitute.
- **Alternative:** Service principal-based API authentication is also supported if preferred.

## Environment Endpoints

Azure Government defaults:

- `advancedHuntingUri`: `https://graph.microsoft.us/v1.0/security/runHuntingQuery`
- `advancedHuntingAudience`: `https://graph.microsoft.us`
- `logsIngestionAudience`: `https://monitor.azure.us`

Azure Commercial defaults:

- `advancedHuntingUri`: `https://graph.microsoft.com/v1.0/security/runHuntingQuery`
- `advancedHuntingAudience`: `https://graph.microsoft.com`
- `logsIngestionAudience`: `https://monitor.azure.com`

## Default Tuning

Recommended starting values:

```text
WriteBatchSize = 250
Parallelism = 40
```

Default schedule:

```text
Recurrence = Once per day
```

Because this solution captures periodic snapshots, you may choose to run it less frequently to reduce cost and data volume.

Recommended schedule range:

```text
Every 3 days to every 7 days
```

That is usually feasible without materially affecting reporting for this use case.

```text
Do not run this more than once per day.
```

If errors occur:

```text
WriteBatchSize = 200
Parallelism = 20
```

## Performance Observations

From testing (300-device lab):

- ~112,000 records processed in under 5 minutes
- ~1.3 million records per hour sustained

Estimated scaling:

- 3,000 devices -> ~50 minutes
- 10,000 devices -> ~3 hours

Practical limit:

```text
~5,000 devices before runtime becomes multi-hour
```

For environments with more than **5,000 devices**, each run may take **several hours**.

## Known Limitations

- Not a transactional export (data may change during execution)
- Possible duplicate or missed records
- Advanced Hunting API throttling (~45 calls/min)
- Logs Ingestion API ~1 MB payload limit
- Logic App debugging becomes difficult at scale
- Not suitable for large-scale full TVM ingestion

## Troubleshooting

Common fixes:

- **Most issues are setup or propagation issues:** missing configuration, incorrect audiences, incomplete permission assignment, or running the Logic App too soon after granting access.
- **After assigning API permissions or RBAC, wait 10 to 15 minutes** before running the Logic App.
- **If the Logic App run succeeds but you do not see data yet, wait at least 30 minutes** before assuming failure. Missing tables usually means the new table has not appeared in the UI yet, not that one specific TVM table was skipped.
- **Complete run failure** usually means authentication or configuration problems: wrong audience, missing `ThreatHunting.Read.All`, missing `Monitoring Metrics Publisher`, incorrect `logsIngestionUri`, or another skipped setup step.
- **Partial loop failures** usually mean scale pressure: batch size is too large, parallelism is too high, or Advanced Hunting API throttling is being hit.
- If you are making other Defender Advanced Hunting API calls in parallel, those calls can contribute to throttling and reduce success rates for this workflow.
- Payload too large: reduce batch size from `250` to `200`.
- `429` errors or intermittent loop failures: reduce parallelism from `40` to `20` and account for other API activity.
- DCR errors: verify stream name, schema, and ingestion URI.
- Permission errors: confirm API permissions, DCR role assignment, and correct cloud-specific audiences.
- If you add or remove TVM tables from this solution, update **both** Advanced Hunting queries in the Logic App template: the count query outside the loop (`HTTP-Count`) and the paged query inside the loop (`QueryAdvancedHunting`).

## Summary

This connector demonstrates that TVM data can be exported into Sentinel, but it also highlights why a native connector likely does not exist today.

Best use cases:

- Small environments
- Targeted table export
- Experimentation and learning

Not recommended for:

- Full TVM ingestion at scale
- Enterprise-wide daily ingestion
