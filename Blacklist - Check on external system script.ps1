# Initialize default properties
$a = $account | ConvertFrom-Json;
# Use SQLite on server
Add-type -Path "C:\Program Files\System.Data.SQLite\2015\bin\System.Data.SQLite.dll";
#Params
$db = "C:\HelloID\UniqueDB.db";
$success = $False;
$ValueToCheck = $a.sAMAccountName;
$NonUniqueFields = @()
$dryrun = $False
Try {
    If (Test-Path $db) {
        if($dryRun -eq $False) {
            $conn = New-Object -TypeName System.Data.SQLite.SQLiteConnection
            $conn.ConnectionString = "Data Source=$db"
            $conn.Open()
            $sql = "SELECT * FROM [Values] WHERE [Value] = '$ValueToCheck' COLLATE NOCASE";
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $sql
            $dataAdapter = New-Object -TypeName System.Data.SQLite.SQLiteDataAdapter $cmd
            $dataset = New-Object System.Data.DataSet
            [void]$dataAdapter.Fill($dataset)
            $res = $($dataset.Tables.rows) | fl
            $cmd.ExecuteNonQuery() | Out-Null
            $cmd.Dispose()
            $conn.Close()
            if ($res.count -gt 0) {
                $auditMessage = "Failed!"
                $NonUniqueFields = @("sAMAccountName")
                Write-Verbose -Verbose "$ValueToCheck is NOT unique!"
                } else {
                $auditMessage = "Succes";
                Write-Verbose -Verbose "$ValueToCheck is unique!"
            }
            $success = $True;
        }
    }
    
} catch {
        $auditMessage = "Failed!";
        Write-Verbose -Verbose "Error checking value in DB"
}

# Build up result
$result = [PSCustomObject]@{
    Success = $success;
    # Add field name as string when field is not unique
    NonUniqueFields = $NonUniqueFields
}
# Send result back
Write-Output $result | ConvertTo-Json -Depth 2
