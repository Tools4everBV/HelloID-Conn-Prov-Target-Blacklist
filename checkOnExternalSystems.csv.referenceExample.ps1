#####################################################
# HelloID-Conn-Prov-Target-Blacklist-Check-On-External-Systems-Csv
#
# Version: 1.0.0
#####################################################
# Initialize default values
$success = $false # Set to false at start, at the end, only when no error occurs it is set to true
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()
$NonUniqueFields = [System.Collections.Generic.List[PSCustomObject]]::new()

# The entitlementContext contains the configuration
# - configuration: The configuration that is set in the Custom PowerShell configuration
$eRef = $entitlementContext | ConvertFrom-Json
$c = $eRef.configuration

# The account object contains the account mapping that is configured
$a = $account | ConvertFrom-Json;

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Used to connect to the blacklist CSV
$csvPath = $c.csvPath
$csvDelimiter = $c.csvDelimiter
$csvEncoding = $c.csvEncoding

#region Change mapping here
$valuesToCheck = [PSCustomObject]@{
    'samAccountName'                     = $a.samaccountname # Please make sure the CSV headers match the HelloID attribute name
    'AdditionalFields.userPrincipalName' = $a.AdditionalFields.userPrincipalName # Please make sure the CSV headers match the HelloID attribute name
}
#endregion Change mapping here

# # Troubleshooting
# $csvPath = "C:\HelloID\blacklist.csv"
# $csvDelimiter = ";"
# $csvEncoding = "UTF8"
# $valuesToCheck = [PSCustomObject]@{
#     'samAccountName'                     = 'test1'
#     'AdditionalFields.userPrincipalName' = 'test1@test.nl'
# }

try {
    # Get CSV data
    try {
        Write-Verbose "Querying data from CSV '$($csvPath)'"

        $csvContent = Import-Csv -Path $csvPath -Delimiter $csvDelimiter -Encoding $csvEncoding

        Write-Information "Successfully queried data from CSV '$($csvPath)'. Result Count: $($csvContent.Rows.Count)"
    }
    catch {
        # Clean up error variables
        $verboseErrorMessage = $null
        $auditErrorMessage = $null

        $ex = $PSItem
        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
            $verboseErrorMessage = $ex.Exception.Message
        }
        if ([String]::IsNullOrEmpty($auditErrorMessage)) {
            $auditErrorMessage = $ex.Exception.Message
        }

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"

        $auditLogs.Add([PSCustomObject]@{
                Message = "Error querying data from CSV '$($csvPath)'. Error Message: $auditErrorMessage"
                IsError = $True
            })

        throw "Error querying data from CSV '$($csvPath)'. Error Message: $auditErrorMessage"
    }

    # Check values against CSV data
    Try {
        foreach ($valueToCheck in $valuesToCheck.PsObject.Properties) {
            if ($valueToCheck.Value -in $csvContent."$($valueToCheck.Name)") {
                Write-Warning "Value '$($valueToCheck.Value)' is NOT unique in CSV column '$($valueToCheck.Name)'"
                [void]$NonUniqueFields.Add("$($valueToCheck.Name)")
            }
            else {
                Write-Information "Value '$($valueToCheck.Value)' is unique in CSV column '$($valueToCheck.Name)'"
            }
        }
    }
    catch {
        # Clean up error variables
        $verboseErrorMessage = $null
        $auditErrorMessage = $null

        $ex = $PSItem
        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
            $verboseErrorMessage = $ex.Exception.Message
        }
        if ([String]::IsNullOrEmpty($auditErrorMessage)) {
            $auditErrorMessage = $ex.Exception.Message
        }

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"

        $auditLogs.Add([PSCustomObject]@{
                Message = "Error checking values against CSV data. Error Message: $auditErrorMessage"
                IsError = $True
            })

        throw "Error checking values against CSV data. Error Message: $auditErrorMessage"
    }
}
catch {
    Write-Warning $_
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($auditLogs.IsError -contains $true)) {
        $success = $true
    }

    # Send results
    $result = [PSCustomObject]@{
        Success         = $success
        # AuditLogs        = $auditLogs # Not available in check on external system
        # Account          = $account # Not available in check on external system

        # Add field name as string when field is not unique
        NonUniqueFields = $NonUniqueFields
    }

    Write-Output ($result | ConvertTo-Json -Depth 10)
}