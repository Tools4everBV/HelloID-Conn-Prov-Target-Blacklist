#Initialize default properties
$personObject = ConvertFrom-Json $person
$success = $False;
$auditMessage = "for person " + $p.DisplayName
$config = $configuration | ConvertFrom-Json


#Change mapping here
$account = [PSCustomObject]@{
    displayName = $personObject.DisplayName
    userName = $personObject.Accounts.MicrosoftActiveDirectory.sAMAccountName
    externalId = $account_guid
    samAccountName = $personObject.Accounts.MicrosoftActiveDirectory.sAMAccountName
    userPrincipalName = $personObject.Accounts.MicrosoftActiveDirectory.userPrincipalName
}

#Default variables for blacklist
$Path = $config.path
$db = $Path + $config.filename;
$success = $False;

#$db = "C:\Database\UniqueDB.db";


if(-Not($dryRun -eq $True)) {
    #Add libs
    Add-type -Path "C:\Program Files\System.Data.SQLite\2015\bin\System.Data.SQLite.dll"; #Moet deze configurabel?
    Try{
     
      # Append SQL table
        $sAMAccountName = "$($account.samAccountName)"
        Write-Verbose "$sAMAccountName" -verbose

        If (Test-Path $db) {
		    $conn = New-Object -TypeName System.Data.SQLite.SQLiteConnection
			$conn.ConnectionString = "Data Source=$db"
			$conn.Open()
            $sql = "INSERT INTO [Values] (Value) VALUES ('$sAMAccountName')";
			$cmd = $conn.CreateCommand()
            $cmd.CommandText = $sql
            $dataAdapter = New-Object -TypeName System.Data.SQLite.SQLiteDataAdapter $cmd
            $dataset = New-Object System.Data.DataSet
            [void]$dataAdapter.Fill($dataset)
            
			$cmd.Dispose()
			$conn.Close()

            $Success = $True
            $auditMessage = "Succes";
            Write-Verbose -Verbose "$ValueToCheck added to SQLLite db!"
        }   
    }
    Catch{
        $auditMessage = "Blacklist appending failed"
    }


} else {
    Write-Verbose -Verbose "Dry mode: $output"
}


#build up result
$result = [PSCustomObject]@{ 
	Success = $success
	AccountReference = $account.externalId
	AuditDetails = $auditMessage
    Account = $account

    # Optionally return data for use in other systems
    ExportData = [PSCustomObject]@{}
};

#send result back
Write-Output $result | ConvertTo-Json -Depth 10