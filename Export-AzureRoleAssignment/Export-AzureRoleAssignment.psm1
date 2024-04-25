$version = "1.0.0"

$InformationPreference = 'Continue'
$ErrorActionPreference = 'Stop'

function writelog {
    # Simple logging function with timestamp added
    Param(
        [string]$message,
        [switch]$verbose
    )
    if ($verbose) {
        Write-verbose "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))`t$message"
    }
    else {
        write-information "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))`t$message"
    }
}

class Contexts {
    # load required context data so it is easy to access by subscription name or Id
    [System.Collections.Generic.List[PSCustomObject]]$contexts = @()
    hidden [hashtable] $contextsByName = @{}
    hidden [hashtable] $contextsById = @{}
    [hashtable] $tenantsById = @{}

    Contexts() {

        foreach ($tenant in get-aztenant) {
            $this.tenantsById[$tenant.Id] = $tenant.Name
        }

        foreach ($context in Get-AzContext -ListAvailable) {
            $this.contexts.Add($context)
            $this.contextsByName[$context.Subscription.Name] = ($this.contexts.count - 1)
            $this.contextsById[$context.Subscription.Id] = ($this.contexts.count - 1)
        }

    }

    [PSCustomObject] get([string] $nameOrId) {
        if ($this.contextsByName.ContainsKey($nameOrId)) {
            return $this.contexts[$this.contextsByName[$nameOrId]]
        }
        elseif ($this.contextsById.ContainsKey($nameOrId)) {
            return  $this.contexts[$this.contextsById[$nameOrId]]
        }
        return $null
    }

    [PSCustomObject] exists([string] $nameOrId) {
        if ($this.contextsByName.ContainsKey($nameOrId)) {
            return $true
        }
        elseif ($this.contextsById.ContainsKey($nameOrId)) {
            return  $true
        }
        return $false
    }

    [PSCustomObject[]] enumerate() {
        return $this.contexts | Sort-Object { $_.subscription.name }
    }

}

enum scopeType {
    unknown = -1
    root = 0
    managementGroup = 1
    subscription = 2
    resourceGroup = 3
    resource = 4
}

enum objectType {
    group = 0
    user = 1
    servicePrincipal = 2
}

Class RoleAssignment {

    [string] $scope
    [string] $scopeType
    [string] $role
    [string] $objectName
    [string] $objectType
    [string] $filename

    RoleAssignment() {

    }

    RoleAssignment([pscustomobject] $assignment) {
        $this.scope = $assignment.scope
        $this.scopeType = $assignment.scopeType
        $this.role = $assignment.role
        $this.objectName = $assignment.objectName
        $this.objectType = $assignment.objectType
        $this.filename = $assignment.filename
    }

    RoleAssignment([string] $scope, [string] $scopeType, [string] $role, [string] $objectName, [string] $objectType, [string] $filename) {
        $this.scope = $scope
        $this.scopeType = $scopeType
        $this.role = $role
        $this.objectName = $objectName
        $this.objectType = $objectType
        $this.filename = $filename
    }

    [string] tostring() {
        return $this | convertto-json -Depth 10
    }
}

class Tag {
    [string] $filename
    [string] $scope
    [string] $scopeType
    [string] $name
    [string] $value

    Tag() {

    }

    Tag([PSCustomObject]$tag) {
        $this.filename = $tag.filename
        $this.scope = $tag.scope
        $this.scopeType = $tag.scopeType
        $this.name = $tag.name
        $this.value = $tag.value
    }

    Tag([string] $filename, [string] $scope, [string] $scopeType, [string] $name, [string] $value) {
        $this.filename = $filename
        $this.scope = $scope
        $this.scopeType = $scopeType
        $this.name = $name
        $this.value = $value
    }

}


class ResourceGroup {
    [string] $resourceGroupName
    [string] $Location
    [string] $ResourceId
}


class ResourceGroupFileData {

    ResourceGroupFileData([string] $resourceGroupName, [string] $location, $tags, [System.Collections.Generic.List[pscustomobject]] $assignments) {
        $this.resourceGroupName = $resourceGroupName
        $this.location = $location
        $this.tags = $tags
        $this.assignments = $assignments
    }

    [string] $resourceGroupName
    [string] $location
    [System.Collections.Generic.List[pscustomobject]] $assignments
    $tags
}

class FileData {

    FileData([hashtable] $tags, [System.Collections.Generic.List[pscustomobject]] $assignments) {
        $this.tags = $tags
        $this.assignments = $assignments

    }
    [hashtable] $tags
    [System.Collections.Generic.List[pscustomobject]] $assignments
}


class FilePaths {

    # Used to convert file paths from containing subscription IDs to Subscription Names and vice versa
    # e.g. "filename":  "/subscriptions/29801f9a-9479-43be-a612-a92e4dfc7b23" --> "/subscriptions/OSS-SUB-DEV"

    hidden [hashtable] $subscriptionsByName = @{}
    hidden [hashtable] $subscriptionsById = @{}

    FilePaths($azcontexts) {

        foreach ($context in $azcontexts.enumerate()) {
            $this.Add($context.Subscription.Id, $context.Subscription.Name)
        }
    }

    Add([string] $id, [string] $name) {
        $this.subscriptionsByName[$name] = $id
        $this.subscriptionsById[$id] = $name
    }

    [string] ConvertToName($filename) {

        if ($filename -match '/subscriptions/([^/]*)') {
            $subId = $matches[1]
            $subName = $this.subscriptionsById[$subId]
            return $filename.replace("/subscriptions/$subId", "/subscriptions/$subName")
        }

        return $filename

    }

    [string] ConvertToId($filename) {

        if ($filename -match '/subscriptions/([^/]*)') {
            $subName = $matches[1]
            $subId = $this.subscriptionsByName[$subName]
            return $filename.replace("/subscriptions/$subName", "/subscriptions/$subId")
        }

        return $filename

    }

}

class RoleAssignmentData {
    hidden $subscriptions
    hidden $outputFormat
    $fromAzureAssignments = [System.Collections.Generic.List[RoleAssignment]]::new()
    hidden [hashtable] $fromAzureAssignmentsHash = @{} # used to ensure no duplicates
    hidden [hashtable] $fromAzureAssignmentsfileIndex = @{}

    $fromAzureResourceGroups = @{}

    $fromAzureTags = [System.Collections.Generic.List[Tag]]::new()
    hidden [hashtable] $fromAzureTagsHash = @{} # used to ensure no duplicates
    hidden [hashtable] $fromAzureTagsfileIndex = @{}

    hidden $contexts

    hidden $FilePaths
    RoleAssignmentData($contexts) {
        $this.contexts = $contexts
        $this.FilePaths = [FilePaths]::new($this.contexts)
    }


    hidden [void] fromAzureAssignmentAdd([pscustomobject] $assignment) {

        $RoleAssignment = [RoleAssignment]::new()
        $RoleAssignment.scopeType, $RoleAssignment.fileName = $this.getScopeTypeandFileName($assignment.scope)
        $RoleAssignment.scope = $assignment.scope -replace $RoleAssignment.fileName, ""
        $RoleAssignment.role = $assignment.RoleDefinitionName
        $RoleAssignment.ObjectType = $assignment.ObjectType

        if ($assignment.ObjectType -eq "user") {
            $RoleAssignment.objectName = $assignment.SignInName
        }
        else {
            $RoleAssignment.objectName = $assignment.DisplayName
        }

        $Hash = "{0}`t{1}`t{2}`t{3}`t{4}" -f $RoleAssignment.fileName, $RoleAssignment.scope, $RoleAssignment.role, $RoleAssignment.ObjectType, $RoleAssignment.objectName

        if ($this.fromAzureAssignmentsHash.ContainsKey($Hash)) {
            # Already exists
        }
        else {
            $this.fromAzureAssignments.Add($RoleAssignment)
            $index = $this.fromAzureAssignments.count - 1

            $this.fromAzureIndexAssignmentFile($RoleAssignment.fileName, $index)
            $this.fromAzureAssignmentsHash[$hash] = 1
        }

        # $this.identities.add([AADIdentity]::new($RoleAssignment.objectName, $assignment.ObjectId, $RoleAssignment.ObjectType, [AADIdentitySource]::azure))

    }


    hidden [void] fromAzureTagAdd($rg) {

        $tags = $rg.tags

        $scope = $rg.ResourceId
        $scopeType, $fileName = $this.getScopeTypeandFileName($scope)
        $scope = $scope -replace $fileName, ""

        foreach ($key in $tags.keys) {

            $newTag = [Tag]::new($fileName, $scope, $scopeType, $key, $tags[$key])
            $Hash = "{0}`t{1}`t{2}`t{3}" -f $newTag.fileName, $newTag.scope, $newTag.scopeType, $newTag.name

            if ($this.fromAzureTagsHash.ContainsKey($Hash)) {
                # Already exists
            }
            else {
                $this.fromAzureTags.Add($newTag)
                $index = $this.fromAzureTags.count - 1

                $this.fromAzureIndexTagFile($newTag.fileName, $index)
                $this.fromAzureTagsHash[$hash] = 1
            }
        }
    }

    hidden [void] fromAzureIndexAssignmentFile($fileName, $index) {
        if (-not $this.fromAzureAssignmentsfileIndex.ContainsKey($fileName)) {
            $indexList = [System.Collections.Generic.List[int]]::new()
            $indexList.Add($index)
            $this.fromAzureAssignmentsfileIndex[$fileName] = $indexList
        }
        else {
            $this.fromAzureAssignmentsfileIndex[$fileName].Add($index)
        }
    }

    hidden [void] fromAzureIndexTagFile($fileName, $index) {
        if (-not $this.fromAzureTagsfileIndex.ContainsKey($fileName)) {
            $indexList = [System.Collections.Generic.List[int]]::new()
            $indexList.Add($index)
            $this.fromAzureTagsfileIndex[$fileName] = $indexList
        }
        else {
            $this.fromAzureTagsfileIndex[$fileName].Add($index)
        }
    }

    hidden [array] getScopeTypeandFileName($scope) {
        # return scopetype, filename

        if ($scope -match '/subscriptions/([^/]*)/resourceGroups/([^/]*)$') {
            return @([scopetype]::resourceGroup, $scope)
        }
        elseif ($scope -match '(/subscriptions/([^/]*)/resourceGroups/([^/]*))/providers/(.*)$') {
            return @([scopetype]::resource, $Matches[1])
        }
        elseif ($scope -match '/providers/Microsoft.Management/managementGroups/(.*)$') {
            return @([scopetype]::managementGroup, "/managementGroups/$($Matches[1])")
        }
        elseif ($scope -match '/subscriptions/([^/]*)$') {
            return @([scopetype]::subscription, $scope)
        }
        elseif ($scope -eq '/') {
            return @([scopetype]::root, "/root")
        }
        else {
            return @([scopetype]::unknown, $scope)
        }
    }


    hidden [System.Collections.Generic.List[RoleAssignment]] FromAzureGetAssignmentsForFile($fileName) {

        $FromAzureGetAssignmentsForFile = [System.Collections.Generic.List[RoleAssignment]]::new()
        foreach ($assignmentIndex in $this.fromAzureAssignmentsfileIndex[$fileName]) {
            $FromAzureGetAssignmentsForFile.Add($this.fromAzureAssignments[$assignmentIndex])
        }
        return $FromAzureGetAssignmentsForFile
    }

    hidden [System.Collections.Generic.List[pscustomobject]] MinimiseAssignments($assignments) {
        # to minimise json file size/compexity this removes scope if blank and scopeType (as known from file location)
        $MinimisedAssigments = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach ($assignment in $assignments) {
            if ( $assignment.scope -eq "") {
                $MinimisedAssigments.Add( ($assignment | Select-Object -Property role, objectName, objectType) )
            }
            else {
                $MinimisedAssigments.Add( ($assignment | Select-Object -Property role, objectName, objectType, scope) )
            }
        }

        return $MinimisedAssigments
    }

    hidden [System.Collections.Generic.List[Tag]] FromAzureGetTagsForFile($fileName) {

        $FromAzureGetTagsForFile = [System.Collections.Generic.List[Tag]]::new()
        foreach ($tagIndex in $this.fromAzureTagsfileIndex[$fileName]) {
            $FromAzureGetTagsForFile.Add($this.fromAzureTags[$tagIndex])
        }
        return $FromAzureGetTagsForFile
    }

    [void] getData($subscriptions) {

        if ($subscriptions[0] -eq "*") {
            $this.subscriptions = $this.contexts.enumerate().subscription.name
        }
        else {
            $this.subscriptions = $subscriptions
        }

        foreach ($sub in $this.subscriptions) {
            writelog "Processing $sub"
            $context = $this.contexts.get($sub)
            if (!$context) {
                throw "Subscription not found: $sub"
            }
            $this.getRoleAssignments($context)
            $this.getResourceGroupsAndTags($context)
        }

    }

    [void] getRoleAssignments($context) {

        $result = Get-AzRoleAssignment -DefaultProfile $context -WarningAction SilentlyContinue
        foreach ($assignment in $result) {
            $this.fromAzureAssignmentAdd($assignment)
        }

        writelog "    $($this.fromAzureAssignments.count) Role Assignments loaded from Azure"

    }

    hidden [void] getResourceGroupsAndTags($context) {

        $result = (Get-AzResourceGroup -DefaultProfile $context | Where-Object ManagedBy -eq $null)

        foreach ($rg in $result) {

            $rgnew = [ResourceGroup]::new()
            $rgnew.resourceGroupName = $rg.ResourceGroupName
            $rgnew.location = $rg.Location
            $rgnew.ResourceId = $rg.ResourceId

            $this.fromAzureResourceGroups.Add($rgnew.ResourceId, $rgnew)
            $this.fromAzureTagAdd($rg)
        }

        writelog "    $($this.fromAzureResourceGroups.Count) Resource Groups loaded from Azure"
        writelog "    $($this.fromAzureTags.count) Resource Group Tags loaded from Azure"

    }

    [void] fromAzureCreateFiles($rootFolder, $outputFormat) {

        $this.outputFormat = $outputFormat

        $filesToCreate = @{}

        # Create files for any detected assignments
        foreach ($fileName in $this.fromAzureAssignmentsfileIndex.keys) {
            $filesToCreate[$fileName] = 1
        }

        # need to also create files for resource groups that have no assignments
        foreach ($fileName in $this.FromAzureResourceGroups.Keys) {
            $filesToCreate[$fileName] = 1
        }

        # need to also create files for subscriptions that have no assignments
        Foreach ($sub in $this.subscriptions) {
            $subid = $this.Contexts.get($sub).subscription.id
            $filesToCreate["/subscriptions/$subid"] = 1
        }

        foreach ($fileName in $filesToCreate.keys | sort-object) {
            $parent = split-Path -Path $this.FilePaths.ConvertToName("$rootFolder$fileName") -Parent

            if (-not (Test-Path "$parent")) {
                mkdir "$parent"
            }

            $assignments = ($this.FromAzureGetAssignmentsForFile($fileName) |
                select-object -Property scope, scopeType, role, objectName, objectType |
                Sort-Object filename, scope, scopeType, role, objectName, objectType)

            $tags = @{}
            $tags = [ordered]@{}
            ($this.FromAzureGetTagsForFile($fileName) |
            select-object -Property name, value |
            Sort-Object filename, name, value) | ForEach-Object { $tags.Add($_.name, $_.value) }

            if ($fileName -like '*/resourceGroups/*') {

                # remove scope and scopetype from resource group assignments
                $minAssignments = $this.MinimiseAssignments($assignments)

                $rg = $this.FromAzureResourceGroups[$fileName]
                $rgFileData = [ResourceGroupFileData]::new($rg.resourceGroupName, $rg.location, $tags, $minAssignments)
                $this.writeToFile($rgFileData, "$rootFolder$fileName")
            }
            else {

                # set name of the file for subscription, managementgroup, or root
                $name = 'subscription.$($this.fileextension)'
                Switch -Wildcard ($fileName) {
                    '/root' {
                        $name = 'root'
                        break
                    }
                    '/managementGroups/*' {
                        $name = 'managementgroup'
                        break
                    }
                    '/subscriptions/*' {
                        $name = 'subscription'
                        break
                    }
                }

                # TODO
                if (-not (Test-Path $this.FilePaths.ConvertToName("$rootFolder$fileName"))) {
                    mkdir $this.FilePaths.ConvertToName("$rootFolder$fileName")
                }


                $minAssignments = $this.MinimiseAssignments($assignments)
                $FileData = [FileData]::new($tags, $minAssignments)
                $this.writeToFile($FileData, "$rootFolder$fileName/$name")
            }

        }

    }

    [string] formatJson([pscustomobject]$object) {
        return $this.formatJson([string]($object |  ConvertTo-Json -Depth 100))
    }

    [string] formatJson([string]$json) {

        $IndentStack = [system.collections.stack]::new()
        [string] $output = ""

        [bool] $inString = $false

        foreach ($line in $json -split '\n') {

            $SOLIndent = $IndentStack.Count

            # loop through each character icrementing or decrementing
            $lastChar = ''
            foreach ($i in $line.ToCharArray()) {

                if ($IndentStack.Count -gt 0 -and $IndentStack.Peek() -eq '"') {
                    $inString = $true
                }
                else {
                    $inString = $false
                }

                if ($i -eq '[' -and -not $inString) {
                    $IndentStack.Push($i)
                }
                elseif ($i -eq '{' -and -not $inString ) {
                    $IndentStack.Push($i)
                }
                elseif ($i -eq '"' -and -not $inString) {
                    $IndentStack.Push($i)
                }
                elseif ($i -eq ']' -and -not $inString) {
                    $null = $IndentStack.Pop()
                }
                elseif ($i -eq '}' -and -not $inString) {
                    $null = $IndentStack.Pop()
                }
                elseif ($i -eq '"' -and $lastChar -ne '\') {
                    $null = $IndentStack.Pop()
                }
                $lastChar = $i
            }

            $EOLIndent = $IndentStack.Count

            if ($EOLIndent -lt $SOLIndent) {
                $line = ' ' * $EOLIndent * 4 + $line.Trim().Replace(':  ', ': ').Replace('\u0027', "'").Replace('\u003c', "<").Replace('\u003e', ">").Replace('\u0026', "&")
            }
            else {
                $line = ' ' * $SOLIndent * 4 + $line.Trim().Replace(':  ', ': ').Replace('\u0027', "'").Replace('\u003c', "<").Replace('\u003e', ">").Replace('\u0026', "&")
            }
            if ($line.Trim() -ne "") { $output += "$line`n" }

        }
        return $output.Substring(0, $output.Length - 1)
    }

    [void] writeToFile([pscustomobject]$object, [string] $filename) {

        $jsonData = $this.formatJson($object)
        $outputFileName = $this.FilePaths.ConvertToName("$filename")

        if ($this.outputFormat -eq "YAML") {
            $yamldata = ($jsonData | ConvertFrom-Json | ConvertTo-yaml)
            writelog "    Creating file ${outputFileName}.yaml" -verbose
            $yamldata | Out-File $this.FilePaths.ConvertToName("$filename.yaml") -NoNewline
        }
        else {
            writelog "    Creating file ${outputFileName}.json" -verbose
            $jsonData | Out-File $this.FilePaths.ConvertToName("$filename.json") -NoNewline
        }

    }

}

<#
.SYNOPSIS
    Export role assignments, resource groups, and resource group tags from Azure to YAML or JSON files.

.DESCRIPTION
    Loops through subscriptions, exporting role assignments, resource groups, and resource group tags, and creates a separate YAML or JSON file for each resource group, subscription, or management group.

    Use connect-azaccount to logon first.

.PARAMETER Subscriptions
    Specifies the subscriptions to process.
    Defaults to '*'

.PARAMETER Path
    Specifies the path to the output folder.
    The folder will be created if it does not exist.
    Defaults to '.\output'

.PARAMETER Format
    Specifies the file format.
    YAML or JSON.
    Defaults to YAML.

.EXAMPLE
    PS>  Export-AzureRoleAssignment
    Export role assignments, for all subscriptions you have access to, to YAML files.

.EXAMPLE
    PS>  Export-AzureRoleAssignment -Format JSON
    Export role assignments, for all subscriptions you have access to, to JSON files.

.EXAMPLE
    PS>  Export-AzureRoleAssignment -Subscriptions OSX-SUB-DEV, OSX-SUB-SIT
    Export role assignments, for subscriptions OSX-SUB-DEV and OSX-SUB-SIT, to YAML files.

.EXAMPLE
    PS>  Export-AzureRoleAssignment -Format JSON
    Export role assignments, for all subscriptions you have access to, to JSON files.
#>
function Export-AzureRoleAssignment {
    [cmdletbinding()]
    param (
        [string[]] $Subscriptions = @("*"),
        [string] $Path = ".\output",
        [ValidateSet("JSON", "YAML")]
        [string] $Format = "YAML"
    )

    writelog "Export-AzureRoleAssignment started ($version)" -verbose

    # get required context (subscription) data
    $contexts = [Contexts]::new()

    # get role assignment data for each subscription
    $roleAssignmentData = [RoleAssignmentData]::new($contexts)
    $roleAssignmentData.getData($Subscriptions)

    writelog "Write data to file: $path"
    $roleAssignmentData.fromAzureCreateFiles($Path, $Format)

    writelog "Export-AzureRoleAssignment completed ($version)" -verbose
}


Export-ModuleMember -function Export-AzureRoleAssignment