$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$m = $manager | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$mRef = $managerAccountReference | ConvertFrom-Json;
$success = $false
$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Used to connect to SQL server.
$connectionString = $c.connectionString
$username = $c.username
$password = $c.password
$table = $c.table
$column = $c.column

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
        if(-not[String]::IsNullOrEmpty($Username) -and -not[String]::IsNullOrEmpty($Password)){
            # First create the PSCredential object
            $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
            $credential = [System.Management.Automation.PSCredential]::new($Username, $securePassword)
 
            # Set the password as read only
            $credential.Password.MakeReadOnly()
 
            # Create the SqlCredential object
            $sqlCredential = [System.Data.SqlClient.SqlCredential]::new($credential.username,$credential.password)
        }
        # Connect to the SQL server
        $SqlConnection = [System.Data.SqlClient.SqlConnection]::new()
        $SqlConnection.ConnectionString = “$ConnectionString”
        if(-not[String]::IsNullOrEmpty($sqlCredential)){
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

try {
    # Query current data in database
    Write-Verbose "Querying table '$($table)', column '$($column)'"
    $querySelect = "
    SELECT
        $column 
    FROM
        $table"

    $querySelectResult = [System.Collections.ArrayList]::new()
    $querySelectSplatParams = @{
        ConnectionString = $connectionString
        SqlQuery = $querySelect
    }

    Invoke-SQLQuery @querySelectSplatParams -Data ([ref]$querySelectResult)
    Write-Verbose "Successfully performed SQL query. Returned rows: $($querySelectResult.Rows.Count)"

    # Get current values and generate random value that doesn't exist yet
    $currentValues = $querySelectResult."$($column)" | Sort-Object 

    # Define range of allowed numbers
    $inputRange = 40000..49999
    $excludeRange = $currentValues
    $randomRange = $inputRange | Where-Object { $excludeRange -notcontains $_ }
    if($randomRange -eq $null){
        throw "Error generating random value: No more values allowed. Please adjust the range. Current range: $($inputRange | Select-Object -First 1) to $($inputRange | Select-Object -Last 1)"
    }
    $uniqueValue = Get-Random -InputObject $randomRange

    # Update Database with new row
    Write-Verbose "Upating table '$($table)', column '$($column)' with value '$($uniqueValue)'"
    $queryInsert = "
    INSERT INTO $table
        ($column)
    VALUES
        ('$uniqueValue')"

    $queryInsertResult = [System.Collections.ArrayList]::new()
    $queryInsertSplatParams = @{
        ConnectionString = $connectionString
        SqlQuery = $queryInsert
    }

    Invoke-SQLQuery @queryInsertSplatParams -Data ([ref]$queryInsertResult)

    # Set aRef object for use in futher actions
    $aRef = $uniqueValue

    $auditLogs.Add([PSCustomObject]@{
        Action = "CreateAccount"
        Message = "Successfully updated table '$($table)', column '$($column)' with value '$($uniqueValue)'"
        IsError = $false;
    });

    $success = $true;      
}
catch {
    $auditLogs.Add([PSCustomObject]@{
        Action = "CreateAccount"
        Message = "Error updating table '$($table)', column '$($column)' with value '$($uniqueValue)': $_"
        IsError = $true;
    });

    $success = $true;   

    Write-Error $_
}

# Send results
$result = [PSCustomObject]@{
	Success= $success;
	AccountReference= $aRef;
	AuditLogs = $auditLogs;
    Account = $account;

    # Optionally return data for use in other systems
    ExportData = [PSCustomObject]@{
        uniqueValue = $aRef
    };    
};

Write-Output $result | ConvertTo-Json -Depth 10;