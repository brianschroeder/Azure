Function Add-KeyVaultAccess {

    <#
    .SYNOPSIS
        Adds access for the defined Users to the specified KeyVaults.
    .PARAMETER AllowedIP
        IP address that will be granted access to the specified KeyVaults.
    .PARAMETER KeyVaults
        Array of KeyVaults for Permissions to be added.   
    .PARAMETER SecretPermissions
        Permissions to be set on the KeyVault for Secrets.    
    .PARAMETER Identity
        Email/ID of the Identities to be added to the KeyVaults. 
    .EXAMPLE
        Add-KeyVaultAccess -Identity <Identity> -KeyVaults <KeyVaults> -SecretPermissions Get,List -AllowedIP <AllowedIP>
    .EXAMPLE
        Add-KeyVaultAccess -Identity <Identity> -KeyVaults <KeyVaults> -SecretPermissions Get,List
    .NOTES
        Author: Brian Schroeder
        Date Coded: 10/12/2021
    #>

    param (
        [String]$AllowedIP,
        [Array]$Identity,
        [Array]$KeyVaults,
        [Array]$SecretPermissions
    )

    if ($KeyVaults -match ':') { $SetContext = $True }
    Write-Host `n'Attempting to add Permissions to KeyVaults...'

    foreach ($ID in $Identity) {

        if ($ID -match '@') { $UserID = (Get-AzAdUser -UserPrincipalName $ID).ID }
        else { $UserID = $ID }
    
        foreach ($KeyVault in $KeyVaults) {

            if ($SetContext -eq $True) {

                $BaseKeyVault = $KeyVault -split ':' ; $KeyVault = $BaseKeyVault[0] ; $SubscriptionName = $BaseKeyVault[1]
                try { Set-AzContext -SubscriptionName "$SubscriptionName" -ErrorAction Stop | Out-Null }
                catch { Write-Host -NoNewLine "Failed: " -Foregroundcolor Red ; Write-Host "Unable to set context for '$SubscriptionName'" ; Write-Host $_ ; continue } 
            
            }

            if ($AllowedIP -ne $null -and $AllowedIP -ne 0) { 
                try { Add-AzKeyVaultNetworkRule -VaultName $KeyVault -IpAddressRange "$AllowedIP/32" -ErrorAction Stop }
                catch { Write-Host -NoNewLine "Failed: " -Foregroundcolor Red ; Write-Host "Adding network access for $AllowedIP on '$KeyVault'" ; Write-Host $_  ; continue } 
                Write-Host -NoNewLine "Success: " -Foregroundcolor Green ; Write-Host "Added network access for $AllowedIP on '$KeyVault'"
            }

            try { Set-AzKeyVaultAccessPolicy -VaultName $KeyVault -ObjectId $UserID -PermissionsToSecrets $SecretPermissions -ErrorAction Stop }
            catch { Write-Host -NoNewLine "Failed: " -Foregroundcolor Red ; Write-Host "Adding access for $ID to KeyVault '$KeyVault' with '$SecretPermissions' permissions" ;  Write-Host $_  ; continue } 
            Write-Host -NoNewLine "Success: " -Foregroundcolor Green ; Write-Host "Added $ID to '$KeyVault' with '$SecretPermissions' permissions"
        }
    }
}

Function Remove-KeyVaultAccess {

    <#
    .SYNOPSIS
        Removes access for the defined Users to the specified KeyVaults.
    .PARAMETER GetTenantKeyVaults
        Switch to define retrieving all Key Vaults in the Tenant
    .PARAMETER Identity
        Email/ID of the Identities to be Removed from the KeyVaults. 
    .PARAMETER KeyVaults
        Array of KeyVaults for Permissions to be removed.   
    .PARAMETER RemoveIP
        IP address that currently has access to the KeyVault that will be removed.
    .EXAMPLE
        Remove-KeyVaultAccess -SetContext -Identity <Identity> -KeyVaults 'examplekv:examplesub','examplekv:examplesub' -RemoveIP 40.112.54.40
    .EXAMPLE
        Remove-KeyVaultAccess -Identity <Identity> -KeyVaults 'examplekv:examplesub','examplekv:examplesub'
    .NOTES
        Author: Brian Schroeder
        Date Coded: 10/12/2021
    #>

    param (
        [Array]$Identity,
        [Switch]$GetTenantKeyVaults,
        [Array]$KeyVaults,
        [String]$RemoveIP
    )

    Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"
    if ($GetTenantKeyVaults) { $KeyVaults = Get-TenantKeyVaults }
    if ($KeyVaults -match ':') { $SetContext = $True }
    Write-Host 'Attempting to remove Permissions from KeyVaults...'

    foreach ($ID in $Identity) {

        if ($ID -match '@') { $UserID = (Get-AzAdUser -UserPrincipalName $ID).ID }
        else { $UserID = $ID }
    
        foreach ($KeyVault in $KeyVaults) {

            if ($SetContext -eq $True) {

                $BaseKeyVault = $KeyVault -split ':' ; $KeyVault = $BaseKeyVault[0] ; $SubscriptionName = $BaseKeyVault[1]
                try { Set-AzContext -SubscriptionName "$SubscriptionName" -ErrorAction Stop | Out-Null }
                catch { Write-Host -NoNewLine "Failed: " -Foregroundcolor Red ; Write-Host "Unable to set context for '$SubscriptionName'" ; Write-Host $_ ; continue } 
            
            }

            if ($RemoveIP -ne $null -and $RemoveIP -ne 0) { 
                try { Remove-AzKeyVaultNetworkRule -VaultName $KeyVault -IpAddressRange "$RemoveIP/32" -ErrorAction Stop }
                catch { Write-Host -NoNewLine "Failed: " -Foregroundcolor Red ; Write-Host "Removing network access for $RemoveIP on '$KeyVault'" ;  Write-Host $_  ; continue } 
                Write-Host -NoNewLine "Success: " -Foregroundcolor Green ; Write-Host "Removed network access for $RemoveIP on '$KeyVault'"
            }

            try { Remove-AzKeyVaultAccessPolicy -VaultName $KeyVault -ObjectId $UserID -ErrorAction Stop ; Write-Host -NoNewLine "Success: " -Foregroundcolor Green ;  Write-Host "Removed $ID from '$KeyVault'"  }
            catch { Write-Host -NoNewLine "Failed: " -Foregroundcolor Red ; Write-Host "Removing access for $ID from KeyVault '$KeyVault'" ; Write-Host $_  } 
        }
    }
}


Function Get-KeyVaultSubscriptions {

    <#
    .SYNOPSIS
        Retrieve the Subscription the provided Key Vaults exist in.
    .PARAMETER KeyVaults
        Array of KeyVaults for Subscriptions to be fetched.  
    .EXAMPLE
        Get-KeyVaultSubscriptions -KeyVaults examplekv1,examplekv2
    .NOTES
        Author: Brian Schroeder
        Date Coded: 10/13/2021
    #>

    param ([Array]$KeyVaults)

    $Subscriptions = (Get-AzSubscription).Name
    $KeyVaultSubscriptionArray = @()

    Write-Host "Retrieving Subscription names for KeyVaults..."

    foreach ($KeyVault in $KeyVaults) {
        $SubscriptionFound = $False
        
        foreach ($Subscription in $Subscriptions) {

            if ($SubscriptionFound -eq $True) { break }
            Set-AzContext -SubscriptionName $Subscription | Out-Null
            if (Get-AzKeyVault -VaultName $KeyVault) { $KeyVaultSubscriptionArray += "$($KeyVault):$($Subscription)"  ; $SubscriptionFound = $True } 
        
        }
    }

    return $KeyVaultSubscriptionArray 
}

Function Get-TenantKeyVaults {

    <#
    .SYNOPSIS
        Retrieve all of the Keyvaults in each Subscription for a Tenant.
    .EXAMPLE
        Get-TenantKeyVaults
    .NOTES
        Author: Brian Schroeder
        Date Coded: 11/17/2021
    #>

    $keyVaultsArray = New-Object System.Collections.ArrayList
    $subscriptions = (Get-AzSubscription).Name

     Write-Host `n'Retrieving Azure Key Vaults...'`n

    foreach ($subscription in $subscriptions) {

        try { Set-AzContext -SubscriptionName $Subscription -WarningAction SilentlyContinue | Out-Null } 
        catch { Write-Host -NoNewLine "Failed: " -Foregroundcolor Red ; Write-Host "Unable to set context for '$Subscription'" ; Write-Host $_ ; continue } 
        
        try { $keyVaults = Get-AZResource -ResourceType Microsoft.KeyVault/vaults } 
        catch { Write-Host -NoNewLine "Failed: " -Foregroundcolor Red ; Write-Host "Unable to reteive Key Vaults for '$Subscription'" ; Write-Host $_ ; continue } 

        foreach($keyVault in $KeyVaults.Name) {
            $keyVaultsArray.add("$($keyVault):$subscription") | Out-Null
        }
    }

    return $keyVaultsArray
    
}
