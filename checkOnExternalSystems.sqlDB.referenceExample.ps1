#####################################################
# HelloID-Conn-Prov-Target-Blacklist-Check-On-External-Systems-SQLDB
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

# Used to connect to SQL server.
$connectionString = $c.connectionString
$username = $c.username
$password = $c.password
$table = $c.table



#region Change mapping here
$valuesToCheck = [PSCustomObject]@{
    'SamAccountName'    = [PSCustomObject]@{
        accountValue = $a.samaccountname
        databaseColumn    = 'SamAccountName' # Please make sure the database columns match the HelloID attribute name
    }
    'UserPrincipalName' = [PSCustomObject]@{
        accountValue = $a.AdditionalFields.userPrincipalName
        databaseColumn    = 'AdditionalFields.userPrincipalName' # Please make sure the database columns match the HelloID attribute name
    }
    'MailNickName'      = [PSCustomObject]@{
        accountValue = $a.AdditionalFields.mailNickName
        databaseColumn    = 'SamAccountName' # Please make sure the database columns match the HelloID attribute name
    }
}
#endregion Change mapping here

# Troubleshooting
# $account = [PSCustomObject]@{
#     'SamAccountName'                     = 'test1'
#     'AdditionalFields.userPrincipalName' = 'test1@test.nl'
# }

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

function Invoke-SQLQuery {
    param(
        [parameter(Mandatory = $true)]
        $ConnectionString,

        [parameter(Mandatory = $false)]
        $Username,

        [parameter(Mandatory = $false)]
        $Password,

        [parameter(Mandatory = $true)]
        $SqlQuery,

        [parameter(Mandatory = $true)]
        [ref]$Data
    )
    try {
        $Data.value = $null

        # Initialize connection and execute query
        if (-not[String]::IsNullOrEmpty($Username) -and -not[String]::IsNullOrEmpty($Password)) {
            # First create the PSCredential object
            $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
            $credential = [System.Management.Automation.PSCredential]::new($Username, $securePassword)
 
            # Set the password as read only
            $credential.Password.MakeReadOnly()
 
            # Create the SqlCredential object
            $sqlCredential = [System.Data.SqlClient.SqlCredential]::new($credential.username, $credential.password)
        }
        # Connect to the SQL server
        $SqlConnection = [System.Data.SqlClient.SqlConnection]::new()
        $SqlConnection.ConnectionString = “$ConnectionString”
        if (-not[String]::IsNullOrEmpty($sqlCredential)) {
            $SqlConnection.Credential = $sqlCredential
        }
        $SqlConnection.Open()
        Write-Verbose "Successfully connected to SQL database" 

        # Set the query
        $SqlCmd = [System.Data.SqlClient.SqlCommand]::new()
        $SqlCmd.Connection = $SqlConnection
        $SqlCmd.CommandText = $SqlQuery

        # Set the data adapter
        $SqlAdapter = [System.Data.SqlClient.SqlDataAdapter]::new()
        $SqlAdapter.SelectCommand = $SqlCmd

        # Set the output with returned data
        $DataSet = [System.Data.DataSet]::new()
        $null = $SqlAdapter.Fill($DataSet)

        # Set the output with returned data
        $Data.value = $DataSet.Tables[0] | Select-Object -Property * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors
    }
    catch {
        $Data.Value = $null
        Write-Error $_
    }
    finally {
        if ($SqlConnection.State -eq "Open") {
            $SqlConnection.close()
        }
        Write-Verbose "Successfully disconnected from SQL database"
    }
}
#endregion functions

try {
    # Query current data in database
    try {
        # Create list of properties to query
        [System.Collections.ArrayList]$queryInsertProperties = @()
        foreach ($property in $valuesToCheck.PSObject.Properties) {
            # Enclose Name with brackets []
            $null = $queryInsertProperties.Add("[$($property.Name)]")
        }

        $querySelect = "
        SELECT
            $($queryInsertProperties -join ',')
        FROM
            $table"

        Write-Verbose "Querying data from table '$($table)'. Query: $($querySelect)"

        $querySelectResult = [System.Collections.ArrayList]::new()
        $querySelectSplatParams = @{
            ConnectionString = $connectionString
            SqlQuery         = $querySelect
            ErrorAction      = 'Stop'
        }

        Invoke-SQLQuery @querySelectSplatParams -Data ([ref]$querySelectResult)

        Write-Information "Successfully queried data from table '$($table)'. Returned rows: $($querySelectResult.Rows.Count)"
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        $auditLogs.Add([PSCustomObject]@{
                Message = "Error querying data from table '$($table)'. Query: $($querySelect). Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $True
            })
    }

    # Check values against database data
    Try {
        foreach ($valueToCheck in $valuesToCheck.PsObject.Properties) {
            if ($valueToCheck.Value.accountValue -in $querySelectResult."$($valueToCheck.Value.databaseColumn)") {
                Write-Warning "$($valueToCheck.Name) value '$($valueToCheck.Value.accountValue)' is NOT unique in database column '$($valueToCheck.Value.databaseColumn)'"
                [void]$NonUniqueFields.Add("$($valueToCheck.Name)")
            }
            else {
                Write-Verbose "$($valueToCheck.Name) value '$($valueToCheck.Value.accountValue)' is unique in database column '$($valueToCheck.Value.databaseColumn)'"
            }
        }
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        $auditLogs.Add([PSCustomObject]@{
                Message = "Error checking values against database data. Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $True
            })

        throw "Error checking values against database data. Error Message: $($errorMessage.AuditErrorMessage)"
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