#####################################################
# HelloID-Conn-Prov-Target-Blacklist-Create-Csv
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

# Used to connect to the blacklist CSV
$csvPath = $c.csvPath
$csvDelimiter = $c.csvDelimiter
$csvEncoding = $c.csvEncoding

#region Change mapping here
$account = [PSCustomObject]@{
    'SamAccountName'                     = $p.Accounts.MicrosoftActiveDirectory.samaccountname # Please make sure the CSV headers match the HelloID attribute name
    'AdditionalFields.userPrincipalName' = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName # Please make sure the CSV headers match the HelloID attribute name
}
#endregion Change mapping here

# # Troubleshooting
# $account = [PSCustomObject]@{
#     'SamAccountName'                     = 'test1'
#     'AdditionalFields.userPrincipalName' = 'test1@test.nl'
# }
# $dryRun = $false

try {
    # Export data to CSV
    try {
        if (-Not($dryRun -eq $True)) {
            Write-Verbose "Exporting data to CSV '$($csvPath)'. Account object: $($account|ConvertTo-Json)"

            $account | Export-Csv -Path $csvPath -Delimiter $csvDelimiter -Encoding $csvEncoding -NoTypeInformation -Append -Force -Confirm:$false

            $auditLogs.Add([PSCustomObject]@{
                    Message = "Successfully exported data to CSV '$($csvPath)'. Account object: $($account|ConvertTo-Json)"
                    IsError = $false
                })
        }
        else {
            Write-Warning "DryRun: Would export data to CSV '$($csvPath)'. Account object: $($account|ConvertTo-Json)."
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
                Message = "Error exporting data to CSV '$($csvPath)'. Account object: $($account|ConvertTo-Json). Error Message: $auditErrorMessage"
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