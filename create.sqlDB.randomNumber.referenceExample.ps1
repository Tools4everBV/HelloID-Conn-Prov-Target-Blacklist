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
$column = $c.column

#region Change mapping here
# Define range of allowed numbers
$inputRange = 40000..49999
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
        $SqlCmd = [System.Data.SqlClient.SqlCommand]::new();
        $SqlCmd.Connection = $SqlConnection;
        $SqlCmd.CommandText = $SqlQuery;

        # Set the data adapter
        $SqlAdapter = [System.Data.SqlClient.SqlDataAdapter]::new();
        $SqlAdapter.SelectCommand = $SqlCmd;

        # Set the output with returned data
        $DataSet = [System.Data.DataSet]::new();
        $null = $SqlAdapter.Fill($DataSet)

        # Set the output with returned data
        $Data.value = $DataSet.Tables[0] | Select-Object -Property * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors;
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
#end region functions

try {
    # Query current data in database
    try {
        $querySelect = "
        SELECT
            $column 
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

    # Get current values and generate random value that doesn't exist yet
    try {
        $currentValues = $querySelectResult."$($column)" | Sort-Object 
        $excludeRange = $currentValues
        $randomRange = $inputRange | Where-Object { $excludeRange -notcontains $_ }
        if ($null -eq $randomRange) {
            throw "Error generating random value: No more values allowed. Please adjust the range. Current range: $($inputRange | Select-Object -First 1) to $($inputRange | Select-Object -Last 1)"
        }
        $uniqueValue = Get-Random -InputObject $randomRange

        # Update Database with new row
        $queryInsert = "
        INSERT INTO $table
            ($column)
        VALUES
            ('$uniqueValue')"
    
        Write-Verbose "Inserting data in table '$($table)'. Query: $($queryInsert)"

        $queryInsertResult = [System.Collections.ArrayList]::new()
        $queryInsertSplatParams = @{
            ConnectionString = $connectionString
            SqlQuery         = $queryInsert
            ErrorAction      = 'Stop'
        }
        Invoke-SQLQuery @queryInsertSplatParams -Data ([ref]$queryInsertResult)

        # Set aRef object for use in futher actions
        $aRef = $uniqueValue

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
            UniqueValue = $aRef
        }
    }

    Write-Output ($result | ConvertTo-Json -Depth 10)
}