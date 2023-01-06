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
    'SamAccountName'                     = $a.samaccountname # Please make sure the database columns match the HelloID attribute name
    'AdditionalFields.userPrincipalName' = $a.AdditionalFields.userPrincipalName # Please make sure the database columns match the HelloID attribute name
}
#endregion Change mapping here

# Troubleshooting
# $account = [PSCustomObject]@{
#     'SamAccountName'                     = 'test1'
#     'AdditionalFields.userPrincipalName' = 'test1@test.nl'
# }

#region functions
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
                Message = "Error querying data from table '$($table)'. Query: $($querySelect). Error Message: $auditErrorMessage"
                IsError = $True
            })
    }

    # Check values against database data
    Try {
        # Write-Warning ($querySelectResult | convertto-json)
        foreach ($valueToCheck in $valuesToCheck.PsObject.Properties) {
            if ($valueToCheck.Value -in $querySelectResult."$($valueToCheck.Name)") {
                Write-Warning "Value '$($valueToCheck.Value)' is NOT unique in database column '$($valueToCheck.Name)'"
                [void]$NonUniqueFields.Add("$($valueToCheck.Name)")
            }
            else {
                Write-Information "Value '$($valueToCheck.Value)' is unique in database column '$($valueToCheck.Name)'"
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
                Message = "Error checking values against database data. Error Message: $auditErrorMessage"
                IsError = $True
            })

        throw "Error checking values against database data. Error Message: $auditErrorMessage"
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