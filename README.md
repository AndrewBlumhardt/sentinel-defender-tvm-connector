# Defender TVM Snapshot Connector for Microsoft Sentinel

## Overview

This project provides a Logic App-based proof of concept for exporting selected Microsoft Defender Threat and Vulnerability Management (TVM) Advanced Hunting tables into a custom Log Analytics / Microsoft Sentinel table.

The goal is to enable:

- Snapshot-based TVM data retention
- Custom workbook and dashboard scenarios
- Experimental analysis of TVM data in Sentinel

This is not intended to be a fully scalable production connector. It works best for small to medium environments or targeted table exports.

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

Despite the table names including the word "Vulnerabilities" (which can imply critical must-have coverage), review of the returned data showed the value was less direct and less meaningful for this connector's core snapshot use case than expected.

These tables were removed because they accounted for most of the data volume and were a major scalability bottleneck. They can be added back if needed, but doing so significantly increases runtime and resource usage.

## Repository Layout

```text
.
|-- dce/
|   |-- template.json
|   `-- parameters.json
|-- dcr/
|   |-- template.json
|   `-- parameters.json
`-- logic app/
    |-- template.json
    |-- parameters.json
    |-- parameters.commercial.json
    `-- parameters.gov.json
```

## Deploy with Script (Recommended)

Clone the repo, then run a single PowerShell 7+ script that deploys DCE → DCR → Logic App in order, wires up the managed identity RBAC, and prints next-step instructions.

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

All parameters except `-ResourceGroup` and `-WorkspaceResourceId` have defaults and are optional. Run without arguments to be prompted interactively.

---

## Deploy To Azure (Portal Buttons)

Deploy in this order: DCE -> DCR -> Logic App.

### Azure Commercial

<p>
  <a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Fdce%2Ftemplate.json"><img src="https://aka.ms/deploytoazurebutton" alt="Deploy DCE to Azure"></a>
  <a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Fdcr%2Ftemplate.json"><img src="https://aka.ms/deploytoazurebutton" alt="Deploy DCR to Azure"></a>
  <a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Flogic%2520app%2Ftemplate.json"><img src="https://aka.ms/deploytoazurebutton" alt="Deploy Logic App to Azure"></a>
</p>

### Azure Government

<p>
  <a href="https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Fdce%2Ftemplate.json"><img src="https://aka.ms/deploytoazuregovbutton" alt="Deploy DCE to Azure Government"></a>
  <a href="https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Fdcr%2Ftemplate.json"><img src="https://aka.ms/deploytoazuregovbutton" alt="Deploy DCR to Azure Government"></a>
  <a href="https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAndrewBlumhardt%2Fsentinel-defender-tvm-connector%2Fmain%2Flogic%2520app%2Ftemplate.json"><img src="https://aka.ms/deploytoazuregovbutton" alt="Deploy Logic App to Azure Government"></a>
</p>

## Step-by-Step Deployment (Recommended)

The most reliable method is staged deployment with explicit parameter values and post-deploy validation.

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
LOCATION=<location>
WORKSPACE_RESOURCE_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-rg/providers/Microsoft.OperationalInsights/workspaces/my-workspace

DCE_NAME=DeviceTvmSnapshot
DCR_NAME=dcr-DeviceTvmSnapshot
LOGICAPP_NAME=DeviceTvmSnapshotConnector
```

### 2. Deploy DCE

```bash
az deployment group create \
  --resource-group $RG \
  --template-file dce/template.json \
  --parameters @dce/parameters.json \
  --parameters dataCollectionEndpoints_DeviceTvmSnapshot_name=$DCE_NAME location=$LOCATION

DCE_ID=$(az monitor data-collection endpoint show -g $RG -n $DCE_NAME --query id -o tsv)
```

### 3. Deploy DCR

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

### 4. Build Logs Ingestion URI (DCE + DCR Immutable ID)

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

### 5. Deploy Logic App

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

### 6. Assign Managed Identity Role on DCR (Ingestion)

`Monitoring Metrics Publisher` on the DCR is required for Logs Ingestion API writes. There is no broader Sentinel role, including Sentinel Contributor, that substitutes for this requirement.

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

### 7. Assign Defender API App Role to Managed Identity

This connector uses the Defender Advanced Hunting API. The Logic App managed identity must be granted the `ThreatHunting.Read.All` app role on the Defender for Endpoint Enterprise application (`WindowsDefenderATP`).

This must be assigned with Azure CLI / Microsoft Graph as an app role assignment on the managed identity object. This connector does not use a separate app registration or client secret.

The Azure portal UI does not provide a reliable path to assign this app role to managed identities. Use CLI/Graph for this step. No Azure RBAC/Entra role assignment can replace it.

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

### 8. Update/Verify Ingestion URI in Logic App

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

### 9. Test End-to-End

1. Trigger the Logic App manually once from the portal (Run Trigger on `Recurrence`) for immediate validation.
2. Confirm run status is Succeeded.
3. If you just assigned credentials or permissions, wait 10 to 15 minutes for them to propagate before running the Logic App.
4. If the Logic App run completes successfully, wait at least 30 minutes before assuming the solution is not working. New tables and fresh data can take time to appear in the Log Analytics and Sentinel user interfaces.

> [!IMPORTANT]
> If the Logic App run succeeds, be patient before troubleshooting missing data. It can take 30 minutes or more for a newly created table and its records to become visible in the UI.

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

Assign Logic App managed identity to:

```text
Monitoring Metrics Publisher
```

Scope:

```text
Data Collection Rule (DCR)
```

`Monitoring Metrics Publisher` is the required role for this DCR ingestion path. There is no equivalent broader Sentinel role that replaces it.

Assignment can be done by CLI or manually in Azure portal (DCR -> Access control (IAM)).

### Defender Advanced Hunting API Permission

Assign managed identity app role:

```text
ThreatHunting.Read.All
```

This app role must be assigned via CLI/Graph to the managed identity object. No Azure/Sentinel RBAC role is an equivalent substitute.

Service principal-based API authentication is also supported if preferred.

## Environment Endpoints

Azure Government defaults:

- `advancedHuntingUri`: `https://graph.microsoft.us/v1.0/security/runHuntingQuery`
- `advancedHuntingAudience`: `https://graph.microsoft.us`
- `logsIngestionAudience`: `https://monitor.azure.us`

Azure Commercial defaults:

- `advancedHuntingUri`: `https://graph.microsoft.com/v1.0/security/runHuntingQuery`
- `advancedHuntingAudience`: `https://graph.microsoft.com`
- `logsIngestionAudience`: `https://monitor.azure.com`

## Recommended Methods (Research Notes)

- Use staged IaC deployment (DCE -> DCR -> Logic App), not one giant template, for easier troubleshooting and safer retries.
- Keep DCR and workspace in the same region.
- Use least privilege RBAC (`Monitoring Metrics Publisher`) at DCR scope only.
- Prefer managed identity and app role assignment for Defender API access.
- Use DCR ingestion endpoint where possible; keep DCE path when private link or existing architecture requires it.

## Default Tuning

Recommended starting values:

```text
WriteBatchSize = 250
Parallelism = 40
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

For environments with more than 5,000 devices, each run may take several hours.

## Known Limitations

- Not a transactional export (data may change during execution)
- Possible duplicate or missed records
- Advanced Hunting API throttling (~45 calls/min)
- Logs Ingestion API ~1 MB payload limit
- Logic App debugging becomes difficult at scale
- Not suitable for large-scale full TVM ingestion

## Troubleshooting

Common fixes:

- Most issues are basic setup or propagation problems: missing configuration, incorrect audiences, incomplete permission assignment, or running the Logic App too soon after granting access.
- After assigning API permissions or RBAC, wait 10 to 15 minutes before running the Logic App.
- If the Logic App run succeeds but you do not see data yet, wait at least 30 minutes before assuming failure. Missing tables usually means the new table has not appeared in the UI yet, not that one specific TVM table was skipped.
- If the entire Logic App run fails, the most likely cause is authentication or configuration: wrong audience, missing `ThreatHunting.Read.All`, missing `Monitoring Metrics Publisher`, incorrect `logsIngestionUri`, or another skipped setup step.
- If the Logic App run is only partially successful, such as one or more loop iterations failing, the most likely cause is scale pressure: batch size is too large, parallelism is too high, or Advanced Hunting API throttling is being hit.
- If you are making other Defender Advanced Hunting API calls in parallel, those calls can contribute to throttling and reduce success rates for this workflow.
- Payload too large -> reduce batch size (250 -> 200)
- 429 errors or intermittent loop failures -> reduce parallelism (40 -> 20) and account for other API activity
- DCR errors -> verify stream name, schema, and ingestion URI
- Permission errors -> confirm API permissions, DCR role assignment, and correct cloud-specific audiences
- If you add or remove TVM tables from this solution, update both Advanced Hunting queries in the Logic App template: the count query outside the loop (`HTTP-Count`) and the paged query inside the loop (`QueryAdvancedHunting`).

## Summary

This connector demonstrates that TVM data can be exported into Sentinel, but it also highlights why a native connector likely does not exist today.

Best use cases:

- Small environments
- Targeted table export
- Experimentation and learning

Not recommended for:

- Full TVM ingestion at scale
- Enterprise-wide daily ingestion
