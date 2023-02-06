#####################################################
# HelloID-Conn-Prov-Target-Blacklist-Check-On-External-Systems-Csv
#
# Version: 1.0.0
#####################################################
# Initialize default values
$p = $person | ConvertFrom-Json
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
    'SamAccountName'    = [PSCustomObject]@{
        accountValue = $a.samaccountname
        csvColumn    = 'SamAccountName' # Please make sure the CSV headers match the HelloID attribute name
    }
    'UserPrincipalName' = [PSCustomObject]@{
        accountValue = $a.AdditionalFields.userPrincipalName
        csvColumn    = 'AdditionalFields.userPrincipalName' # Please make sure the CSV headers match the HelloID attribute name
    }
    'MailNickName'      = [PSCustomObject]@{
        accountValue = $a.AdditionalFields.mailNickName
        csvColumn    = 'SamAccountName' # Please make sure the CSV headers match the HelloID attribute name
    }
}
#endregion Change mapping here

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}

function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if ( $($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage

            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
    }
}
#endregion functions

try {
    # Get CSV data
    try {
        Write-Verbose "Querying data from CSV '$($csvPath)'"

        $csvContent = Import-Csv -Path $csvPath -Delimiter $csvDelimiter -Encoding $csvEncoding

        Write-Verbose "Successfully queried data from CSV '$($csvPath)'. Result Count: $($csvContent.Rows.Count)"
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        $auditLogs.Add([PSCustomObject]@{
                Message = "Error querying data from CSV '$($csvPath)'. Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $True
            })

        throw "Error querying data from CSV '$($csvPath)'. Error Message: $($errorMessage.AuditErrorMessage)"
    }

    # Check values against CSV data
    Try {
        foreach ($valueToCheck in $valuesToCheck.PsObject.Properties) {
            if ($valueToCheck.Value.accountValue -in $csvContent."$($valueToCheck.Value.csvColumn)") {
                Write-Warning "$($valueToCheck.Name) value '$($valueToCheck.Value.accountValue)' is NOT unique in CSV column '$($valueToCheck.Value.csvColumn)'"
                [void]$NonUniqueFields.Add("$($valueToCheck.Name)")
            }
            else {
                Write-Verbose "$($valueToCheck.Name) value '$($valueToCheck.Value.accountValue)' is unique in CSV column '$($valueToCheck.Value.csvColumn)'"
            }
        }
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        $auditLogs.Add([PSCustomObject]@{
                Message = "Error checking values against CSV data. Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $True
            })

        throw "Error checking values against CSV data. Error Message: $($errorMessage.AuditErrorMessage)"
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