# DCR Template Validation Gate

Use this checklist before accepting any DCR template changes or replacing the source template with an exported template.

## Scope

- Source of truth: [dcr/template.json](dcr/template.json)
- Compared artifact: Azure portal export of an existing deployed DCR
- Goal: keep the repository template reusable, cloud-neutral, and deployment-safe

## Baseline Requirements (Must Stay True)

1. Parameterization
- Must include `workspaceResourceId` parameter.
- Must include `dataCollectionEndpoints_DeviceTvmSnapshot_externalid` parameter.
- Must include `location` parameter with default `[resourceGroup().location]`.

2. Cloud and region neutrality
- DCR resource `location` must be `[parameters('location')]`.
- No hardcoded region values such as `usgovvirginia` in source template.

3. Sanitization
- No hardcoded subscription-scoped ARM IDs in template defaults.
- No hardcoded tenant-specific workspace parameter names.

4. DCR transform contract
- `dataFlows[0].transformKql` must include:
  `source | extend TenantId = tostring(TenantId)`
- `outputStream` must be `Custom-DeviceTvmSnapshot_CL`.

5. Stream declaration
- Column `TenantId` type must be `string`.
- Stream column count should remain stable unless intentional schema update is made.

## Allowed Differences In Exported Templates

These differences are normal in Azure exports and should not be copied back to source templates by default:

1. Environment-specific parameter names
- Example: `workspaces_<workspaceName>_externalid`

2. Hardcoded deployment values
- Hardcoded region in `location`
- Hardcoded workspace or DCE IDs

3. Generated destination names
- Randomized destination names under `destinations.logAnalytics[].name`

## Forbidden Differences (Reject / Fix)

1. Transform regression
- `transformKql` changed from
  `source | extend TenantId = tostring(TenantId)`
  to `source`

2. Loss of portable parameter contract
- Replacing `workspaceResourceId` with workspace-specific parameter names
- Removing `location` parameterization

3. Reintroduction of hardcoded IDs
- Any real `/subscriptions/<guid>/...` values in source template

## Current Strict Diff Snapshot

Validated on 2026-05-01 against a fresh exported DCR:

1. Repo-only expected values
- `location`: `[parameters('location')]`
- `transformKql`: `source | extend TenantId = tostring(TenantId)`
- Destination name: `laDestination`
- No hardcoded subscription GUID paths

2. Export-only values (do not back-port)
- `location`: `usgovvirginia`
- `transformKql`: `source`
- Workspace parameter name: `workspaces_fedairs_externalid`
- Hardcoded subscription resource IDs present
- Generated destination name: random hash-like value

3. Matching values (good)
- `apiVersion`: `2023-03-11`
- `outputStream`: `Custom-DeviceTvmSnapshot_CL`
- `TenantId` column type: `string`
- Column count: `85`

## Quick Validation Commands

```powershell
$repo='c:\repos\sentinel-defender-tvm-connector\dcr\template.json'
$exp='c:\Users\anblumha\Downloads\ExportedTemplate-rg-sentinel\template.json'

$repoObj=Get-Content $repo -Raw | ConvertFrom-Json
$expObj=Get-Content $exp -Raw | ConvertFrom-Json

$repoRes=$repoObj.resources | Where-Object { $_.type -eq 'Microsoft.Insights/dataCollectionRules' }
$expRes=$expObj.resources | Where-Object { $_.type -eq 'Microsoft.Insights/dataCollectionRules' }

"Repo transform : $($repoRes.properties.dataFlows[0].transformKql)"
"Export transform: $($expRes.properties.dataFlows[0].transformKql)"
"Repo location  : $($repoRes.location)"
"Export location: $($expRes.location)"
"Repo workspace expr  : $($repoRes.properties.destinations.logAnalytics[0].workspaceResourceId)"
"Export workspace expr: $($expRes.properties.destinations.logAnalytics[0].workspaceResourceId)"
```