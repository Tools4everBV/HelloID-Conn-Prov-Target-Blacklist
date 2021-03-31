#Initialize default properties
$p = $person | ConvertFrom-Json
$success = $False;
$auditMessage = "for person " + $p.DisplayName


#Change mapping here
$account = [PSCustomObject]@{
    externalId = $p.ExternalId
    mail = ""
}

if(-Not($dryRun -eq $True)) {
    #Do nothing
    Try{
        $success = $True
        $auditMessage = "Blacklist object deleted from person"
    }
    Catch{
        $auditMessage = "Blacklist object deleted from person failed"
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