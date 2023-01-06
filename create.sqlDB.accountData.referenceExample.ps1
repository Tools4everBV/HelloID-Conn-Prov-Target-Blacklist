#####################################################
# HelloID-Conn-Prov-Target-Blacklist-Create-SQLDB
#
# Version: 1.0.0
#####################################################
# Initialize default values
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false # Set to false at start, at the end, only when no error occurs it is set to true
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"
$WarningPreference = "Continue"

# Used to connect to SQL server.
$connectionString = $c.connectionString
$username = $c.username
$password = $c.password
$table = $c.table

#region Change mapping here
$account = [PSCustomObject]@{
    'SamAccountName'                     = $p.Accounts.MicrosoftActiveDirectory.samaccountname # Please make sure the DB columns match the HelloID attribute name
    'AdditionalFields.userPrincipalName' = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName # Please make sure the DB columns match the HelloID attribute name
}
#endregion Change mapping here

# # Troubleshooting
# $account = [PSCustomObject]@{
#     'SamAccountName'                     = 'test1'
#     'AdditionalFields.userPrincipalName' = 'test1@test.nl'
# }
# $dryRun = $false

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
    # Export data to database
    try {
        # Create list of property names and values
        [System.Collections.ArrayList]$queryInsertProperties = @()
        [System.Collections.ArrayList]$queryInsertValues = @()
        foreach ($property in $account.PSObject.Properties) {
            # Enclose Name with brackets []
            $null = $queryInsertProperties.Add("[$($property.Name)]")
            # Enclose Value with single quotes ''
            $null = $queryInsertValues.Add("'$($property.Value)'")
        }

        $queryInsert = "
        INSERT INTO $table
            ($($queryInsertProperties -join ','))
        VALUES
            ($($queryInsertValues -join ','))"
    
        Write-Verbose "Inserting data in table '$($table)'. Query: $($queryInsert)"

        $queryInsertResult = [System.Collections.ArrayList]::new()
        $queryInsertSplatParams = @{
            ConnectionString = $connectionString
            SqlQuery         = $queryInsert
            ErrorAction      = 'Stop'
        }
        Invoke-SQLQuery @queryInsertSplatParams -Data ([ref]$queryInsertResult)

        Write-Information "Successfully inserted data in table '$($table)'. Query: $($queryInsert)"

        $auditLogs.Add([PSCustomObject]@{
                Message = "Successfully inserted data in table '$($table)'. Query: $($queryInsert)"
                IsError = $false;
            });   
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
                Message = "Error inserting data in table '$($table)'. Query: $($queryInsert). Error Message: $auditErrorMessage"
                IsError = $True
            })
    }
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($auditLogs.IsError -contains $true)) {
        $success = $true
    }

    # Send results
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $aRef
        AuditLogs        = $auditLogs
        Account          = $account

        # Optionally return data for use in other systems
        ExportData       = [PSCustomObject]@{
            SamAccountName    = $account.'SamAccountName' 
            UserPrincipalName = $account.'AdditionalFields.userPrincipalName'
        }
    }

    Write-Output ($result | ConvertTo-Json -Depth 10)
}