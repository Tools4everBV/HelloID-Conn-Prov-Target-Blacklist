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

#region Change mapping here
$valuesToCheck = [PSCustomObject]@{
    'SamAccountName'    = [PSCustomObject]@{
        accountValue = $a.samaccountname
    }
    'UserPrincipalName' = [PSCustomObject]@{
        accountValue = $a.AdditionalFields.userPrincipalName
    }
    'MailNickName'      = [PSCustomObject]@{
        accountValue = $a.AdditionalFields.mailNickName
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
    # Get AD users in scope
    try {
        Write-Verbose "Querying AD users"

        $adUsers = Get-ADUser -Filter * -Properties (@("employeeID") + $valuesToCheck.PsObject.Properties.Name)
        $adUsersGrouped = $adUsers | Group-Object -Property employeeID -AsString -AsHashTable

        Write-Information "Successfully queried AD users. Result count: $(($adUsers | Measure-Object).Count)"
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        throw "Error querying AD users. Error Message: $($errorMessage.AuditErrorMessage)"
    }

    Try {
        foreach ($valueToCheck in $valuesToCheck.PsObject.Properties) {
            $personADUser = $adUsersGrouped[$p.ExternalId]
            # If AD account is found for person, check in entire AD and check it is not used by current account
            if ($null -ne $personADUser) {
                if ($valueToCheck.Value.accountValue -in $adUsers."$($valueToCheck.Name)" -and $valueToCheck.Value.accountValue.ToLower() -ne $personADUser."$($valueToCheck.Name)".ToLower()) {
                    Write-Warning "$($valueToCheck.Name) value '$($valueToCheck.Value.accountValue)' is NOT unique in AD"
                    [void]$NonUniqueFields.Add("$($valueToCheck.Name)")
                }
                else {
                    Write-Verbose "$($valueToCheck.Name) value '$($valueToCheck.Value.accountValue)' is unique in AD"
                }
            }
            # If AD account is  NOT found for person, check in entire AD
            else {
                if ($valueToCheck.Value.accountValue -in $adUsers."$($valueToCheck.Name)") {
                    Write-Warning "$($valueToCheck.Name) value '$($valueToCheck.Value.accountValue)' is NOT unique in AD"
                    [void]$NonUniqueFields.Add("$($valueToCheck.Name)")
                }
                else {
                    Write-Verbose "$($valueToCheck.Name) value '$($valueToCheck.Value.accountValue)' is unique in AD"
                }                
            }

        }
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        $auditLogs.Add([PSCustomObject]@{
                Message = "Error checking values against AD data. Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $True
            })

        throw "Error checking values against AD data. Error Message: $($errorMessage.AuditErrorMessage)"
    }
    #endregion Custom - Additionally check against AD  
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
