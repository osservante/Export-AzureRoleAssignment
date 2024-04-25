# Export-AzureRoleAssignment

Export role assignments, resource groups, and resource group tags from Azure to YAML or JSON files.

> [!NOTE]  
> This module enables exporting to code which is useful for visibility and auditing of access to Azure.
> 
> The "Osservante RBAC Extension" has export, import and compare modes which enable you to easily manage all your Azure resource groups and role based access assignments (RBAC) in code.
> 
> It is available in the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=Osservante.OsservanteRBAC)

## Syntax

```PowerShell
Export-AzureRoleAssignment [[-Subscriptions] <String[]>] [[-Path] <String>] [[-Format] <String>] [<CommonParameters>]
```

## Usage

Connect to Azure.

```PowerShell
connect-azaccount
```

Import the module.

```PowerShell
Import-Module Export-AzureRoleAssignment
```

## Examples

### Example 1: Export to YAML Files

Export role assignments, for all subscriptions you have access to, to YAML files.

```PowerShell
Export-AzureRoleAssignment
```

Example output file: osx-arg-boreas-sbx.yaml

```yaml
resourceGroupName: OSX-ARG-BOREAS-SBX
location: eastus
assignments:
- role: Contributor
  objectName: sp-Boreas-sbx
  objectType: ServicePrincipal
- role: Reader
  objectName: MI-KRATOS-SBX
  objectType: ServicePrincipal
tags:
  Environment: Sand Box
```

Example output file: osx-arg-castor-sbx.yaml

```yaml
resourceGroupName: OSX-ARG-CASTOR-SBX
location: eastus
assignments:
- role: Contributor
  objectName: sp-Castor-sbx
  objectType: ServicePrincipal
tags:
  Environment: Sand Box
```

### Example 2: Export to JSON Files

Export role assignments, for all subscriptions you have access to, to JSON files.

```PowerShell
Export-AzureRoleAssignment -Format JSON
```

Example output file: osx-arg-castor-sbx.json

```json
{
    "resourceGroupName": "OSX-ARG-CASTOR-SBX",
    "location": "eastus",
    "assignments": [
        {
            "role": "Contributor",
            "objectName": "sp-Castor-sbx",
            "objectType": "ServicePrincipal"
        }
    ],
    "tags": {
        "Environment": "Sand Box"
    }
}
```

### Example 3: Export selected subscriptions

Export role assignments, for subscriptions OSX-SUB-DEV and OSX-SUB-SIT, to YAML files.

```PowerShell
Export-AzureRoleAssignment -Subscriptions OSX-SUB-DEV, OSX-SUB-SIT
```

## Parameters

### Subscriptions
Specifies the subscriptions to process.

| Item          | Value           |
| ------------- | --------------- |
| Type          | Array of String |
| Position      | Named           |
| Default value | *               |
| Required      | False           |

### Path
Specifies the path to the output folder.  
The folder will be created if it does not exist.

| Item          | Value  |
| ------------- | ------ |
| Type          | String |
| Position      | Named  |
| Default value | .      |
| Required      | False  |

### Format
Specifies the file format.

| Item          | Value      |
| ------------- | ---------- |
| Type          | String     |
| Position      | Named      |
| Valid values  | YAML, JSON |
| Default value | YAML       |
| Required      | False      |