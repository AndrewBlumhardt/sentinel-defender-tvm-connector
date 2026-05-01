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
5. Data lands in a custom table (for example: `DeviceTvmSnapshot_CL`).

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

These were removed because they accounted for the majority of data volume while providing limited additional value. They can be added back if needed, but doing so significantly impacts scalability.

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
    `-- parameters.json
```

## Deployment

Deploy in this order:

1. DCE template
2. DCR template
3. Logic App template

Example with Azure CLI:

```bash
# 1) Deploy DCE
az deployment group create \
  --resource-group <resource-group> \
  --template-file dce/template.json \
  --parameters @dce/parameters.json \
  --parameters dataCollectionEndpoints_DeviceTvmSnapshot_name=<dce-name> location=<location>

# 2) Deploy DCR
az deployment group create \
  --resource-group <resource-group> \
  --template-file dcr/template.json \
  --parameters @dcr/parameters.json \
  --parameters \
      dataCollectionRules_dcr_DeviceTvmSnapshot_name=<dcr-name> \
      dataCollectionEndpoints_DeviceTvmSnapshot_externalid=<dce-resource-id> \
      workspaceResourceId=<workspace-resource-id> \
      location=<location>

# 3) Deploy Logic App
az deployment group create \
  --resource-group <resource-group> \
  --template-file "logic app/template.json" \
  --parameters @"logic app/parameters.json" \
  --parameters \
      workflows_QueryGraphAPI_name=<logic-app-name> \
      location=<location> \
      logsIngestionUri=<logs-ingestion-uri>
```

## Required Configuration

### 1. Azure Permissions (Ingestion)

Assign the Logic App managed identity:

```text
Monitoring Metrics Publisher
```

Scope:

```text
Data Collection Rule (DCR)
```

### 2. Defender Advanced Hunting API Permissions

This connector does not use Azure RBAC for Defender data access.

You must assign API permissions (for example):

```text
AdvancedQuery.Read.All
or
ThreatHunting.Read.All
```

to the Logic App managed identity service principal.

This requires:

- App role assignment
- Admin consent

### 3. Managed Identity API Permission (CLI/Graph)

Assign API permissions to the managed identity using Microsoft Graph.

High-level steps:

1. Get the Logic App managed identity service principal ID
2. Get the Microsoft Graph service principal ID
3. Locate the app role ID for `AdvancedQuery.Read.All` or `ThreatHunting.Read.All`
4. Assign the app role to the Logic App service principal
5. Grant admin consent

Placeholder:

```text
# Insert environment-specific CLI or Graph command here for assigning API permission to managed identity
```

### 4. Values to Update After Deployment

You may need to update:

```text
DCE endpoint
DCR immutable ID
Stream name
Custom table name
Workspace ID
Advanced Hunting endpoint
Batch size
Parallelism
Schedule
```

## Environment Endpoints

Default template values target Azure Government:

- `advancedHuntingUri`: `https://graph.microsoft.us/v1.0/security/runHuntingQuery`
- `advancedHuntingAudience`: `https://graph.microsoft.us`
- `logsIngestionAudience`: `https://monitor.azure.us`

For Azure commercial cloud, typically use:

- `advancedHuntingUri`: `https://graph.microsoft.com/v1.0/security/runHuntingQuery`
- `advancedHuntingAudience`: `https://graph.microsoft.com`
- `logsIngestionAudience`: `https://monitor.azure.com`

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

## Known Limitations

- Not a transactional export (data may change during execution)
- Possible duplicate or missed records
- Advanced Hunting API throttling (~45 calls/min)
- Logs Ingestion API ~1 MB payload limit
- Logic App debugging becomes difficult at scale
- Not suitable for large-scale full TVM ingestion

## Troubleshooting

Common fixes:

- Payload too large -> reduce batch size (250 -> 200)
- 429 errors -> reduce parallelism (40 -> 20)
- Missing table -> wait for initial ingestion to complete
- DCR errors -> verify stream name and schema
- Permission errors -> confirm API permissions and DCR role assignment

## Summary

This connector demonstrates that TVM data can be exported into Sentinel, but it also highlights why a native connector likely does not exist today.

Best use cases:

- Small environments
- Targeted table export
- Experimentation and learning

Not recommended for:

- Full TVM ingestion at scale
- Enterprise-wide daily ingestion
