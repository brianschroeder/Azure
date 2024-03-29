Function Invoke-BlobRehydrationManagement {
    <#
    .SYNOPSIS
    This PowerShell function assists in managing Azure blob rehydration.
    
    .DESCRIPTION
    Invoke-BlobRehydrationManagement checks whether the blobs specified in a file are in 'Archive' state, 
    and provides visibility on their rehydration status if they are. 
    If specified, it can initiate rehydration of archived blobs.
    
    .PARAMETER StorageAccountName
    The name of the Azure storage account containing the archived blobs.
    
    .PARAMETER ContainerName
    The name of the Azure storage container containing the archived blobs.
    
    .PARAMETER BlobNamesFile
    The path to the file containing the names of the blobs to be processed.
    
    .PARAMETER CheckBlobTier
    Specifies whether the function should check the blob's tier.
    
    .PARAMETER CheckArchiveStatus
    Specifies whether the function should check the blob's archive status.
    
    .PARAMETER ChangeTier
    Specifies whether the function should change the blob's tier if it's in 'Archive' state.
    
    .NOTES
    This function uses the Azure PowerShell module and requires Azure credentials with permissions 
    to read the blobs from the specified storage account and container, and change their tier if specified.
    
    .EXAMPLE
    Invoke-BlobRehydrationManagement -StorageAccountName 'YourStorageAccount' -ContainerName 'YourContainer' -BlobNamesFile 'C:\path\to\blobnames.txt' -CheckBlobTier $true -CheckArchiveStatus $true -ChangeTier $false
    This command checks the tier of each blob named in 'blobnames.txt', checks their rehydration status if they are archived, 
    and generates reports in the 'reports' directory in the current path. It does not initiate rehydration of the blobs because the '-ChangeTier' parameter is set to $false.
    
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$StorageAccountName,
    
        [Parameter(Mandatory=$true)]
        [string]$ContainerName,
    
        [Parameter(Mandatory=$true)]
        [string]$BlobNamesFile,
    
        [Parameter(Mandatory=$false)]
        [bool]$CheckBlobTier = $true,
    
        [Parameter(Mandatory=$false)]
        [bool]$CheckArchiveStatus = $true,
    
        [Parameter(Mandatory=$false)]
        [bool]$ChangeTier = $false
    )

    # Import Azure module
    Import-Module Az

    # Get the storage account context
    $context = New-AzStorageContext -StorageAccountName $StorageAccountName

    # Read the blob names from the file
    $blobNames = Get-Content $BlobNamesFile

    # Ensure Reports folder exists and create if not present
    if (!(Test-Path -Path ".\reports")) {
        New-Item -ItemType Directory -Force -Path ".\reports"
    }

    # Cleanup report folder 
    Remove-Item -Recurse '.\reports\*' -Force

    # Process each blob
    foreach($blobName in $blobNames)
    {
        $blob = Get-AzStorageBlob -Context $context -Container $ContainerName -Blob $blobName -ErrorAction SilentlyContinue

        if ($blob -ne $null) {
            if ($CheckBlobTier) {
                if ($blob.AccessTier -eq 'Archive') {
                    Add-Content -Path 'reports\archived_blobs.txt' -Value "Blob $blobName is currently in archive"

                    if ($CheckArchiveStatus) {
                        if ($blob.BlobProperties.ArchiveStatus -eq 'rehydrate-pending-to-hot') {
                            Add-Content -Path 'reports\active_rehydrating_blobs.txt' -Value "Blob $blobName is currently rehydrating to hot."
                        } elseif ($ChangeTier) {
                            $blob.ICloudBlob.SetStandardBlobTier('Hot')
                            Add-Content -Path 'reports\rehydrating_blobs_initiated.txt' -Value "Blob $blobName initiated rehdration from archive to hot."
                        }
                    }
                } else {
                    Add-Content -Path 'reports\hot_blobs.txt' -Value "Blob $blobName is currently in hot"
                }
            }
        } else {
            # Blob does not exist, write to the output file
            Add-Content -Path 'reports\blobs_not_found.txt'-Value "Blob $blobName does not exist"
        }
    }
}

Function Confirm-AzureStorageBlob {

    <#
    .SYNOPSIS
        Confirm Blobs from Source Storage Account Container exist on the Destination Storage Account Container.  
        Can Replicate any files that exist on the Source and not the Destination if the Replicate Switch is Defined.
    .PARAMETER sourceStorageAccount
        Storage Account where the Blob list will be generated from.
    .PARAMETER destinationStorageAccount
        Storage Account where the Blobs will be confirmed if exists or not.
    .PARAMETER sourceStorageContainer
        Storage Container where the Blob list will be generated from.
    .PARAMETER destinationStorageContainer
        Storage Container where the Blobs will be confirmed if exists or not.
    .PARAMETER sourcePath
        Path within the Source Storage Container where the Blob list will be generated from.
    .PARAMETER destinationPath
        Path within the Destination Storage Container where the Blobs will be confirmed if exists or not.
    .PARAMETER replicate
        Define whether to replicate all Blobs not found in the Destination Container that exist on the Source Container.
    .EXAMPLE
        Confirm-AzureStorageBlob -sourceStorageAccount srcStorageaccount -sourceStorageContainer srcContainer -destinationStorageAccount destStorageaccount -destinationStorageContainer destContainer -sourcePath "folder1/" -destinationPath "folder2/"
    .EXAMPLE
        Confirm-AzureStorageBlob -sourceStorageAccount srcStorageaccount -sourceStorageContainer srcContainer -destinationStorageAccount destStorageaccount -destinationStorageContainer destContainer -sourcePath "folder1/" -destinationPath "folder2/" -replicate

    .NOTES
        Author: Brian Schroeder
        Date Coded: 3/8/2021
    #>

    param (
        [String]$sourceStorageAccount,
        [String]$destinationStorageAccount,
        [String]$sourceStorageContainer,
        [String]$destinationStorageContainer,
        [String]$sourcePath,
        [String]$destinationPath,
        [Switch]$replicate
    )

    $notReplicatedBlobsArray = @()
    $successfulReplication = @()
    $failedReplication = @()

    $sourceContext = New-AzStorageContext -StorageAccountName "$sourceStorageAccount" 
    $destinationContext = New-AzStorageContext -StorageAccountName "$destinationStorageAccount"

    $sourceBlobs = Get-AzStorageBlob -Context $sourceContext -Container $sourceStorageContainer -Prefix $sourcePath | Select-Object Name
    $destinationBlobs = Get-AzStorageBlob -Context $destinationContext -Container $destinationStorageContainer -Prefix $destinationPath | Select-Object Name
    
    if ($replicate) {
        Write-Host `n"The Replication Switch was passed, if any Blobs exist on $sourceStorageAccount and not on $destinationStorageAccount, the Blobs will be migrated."`n
        Start-Sleep 3
    }

    foreach ($blob in $sourceBlobs | Select-Object -Skip 1) { 

        $destinationBlobName = $blob.Name.Replace($sourcePath, $destinationPath)
        if ($destinationBlobs.Name -contains $destinationBlobName) { continue }
        else { $notReplicatedBlobsArray += $blob }

        if ($replicate) {

            try {
                "Cloning:"
                Write-Host "Source: $sourceStorageAccount/$sourceStorageContainer/$($blob.Name)"
                Write-Host "Destination: $destinationStorageAccount/$destinationStorageContainer/$destinationBlobName"
                Start-AzStorageBlobCopy -SrcBlob "$($blob.Name)" -SrcContainer "$sourceStorageContainer" -DestContainer "$destinationStorageContainer" -DestBlob "$destinationBlobName" -context $sourceContext -DestinationContext $destinationContext -Force | Out-Null
                Write-Host "Successfully Cloned" -foregroundcolor Green
                '===================================================================='
                $successfulReplication += $blob
            } catch { Write-Host `n"Failed Cloning" -foregroundcolor yellow ; $_ ; '====================================================================' ; $failedReplication += $blob }
        }
    }

    Write-Host "The following count of Blobs that exist on $sourceStorageAccount/$sourceStorageContainer/$sourcePath but not on $($destinationStorageAccount)/$($destinationStorageContainer)/$($destinationPath):" ($notReplicatedBlobsArray | Measure-Object).Count

    if ($replicate) {

        if (($successfulReplication | Measure-Object).Count -gt 0) {
            Write-Host "The following count of Blobs were successfully replicated from $sourceStorageAccount to $($destinationStorageAccount):" ($successfulReplication | Measure-Object).Count
            $successfulReplication | Out-File MAM-$destinationStorageAccount-$destinationStorageContainer-successful-replicated-blobs.csv
            Write-Host `n"Exported Report: MAM-$destinationStorageAccount-$destinationStorageContainer-successful-replicated-blobs.csv"
        }

        if (($failedReplication | Measure-Object).Count -gt 0) {
            Write-Host "The following count of Blobs failed replicating from $sourceStorageAccount to $($destinationStorageAccount):" ($failedReplication | Measure-Object).Count
            $failedReplication | Out-File MAM-$destinationStorageAccount-$destinationStorageContainer-failed-replicated-blobs.csv
            Write-Host `n"Exported Report: MAM-$destinationStorageAccount-$destinationStorageContainer-failed-replicated-blobs.csv"
        }
    }
}

Function Get-ContainerBlobs {

    <# 
    .Synopsis 
        Get all the Blob files from the requested container and export the file to an excel sheet if exportCSV switch is provided.
    .PARAMETER containerName
        Name of the Container for Blobs to be retrieved.
    .PARAMETER storageAccount
        Name of the StorageAccount for Blobs to be retrieved.
    .PARAMETER outFileName
        Name of CSV file to export with all of the Blob Names.
    .PARAMETER exportCSV
        Define exporting CSV of all Blobs vs writing them to the console.
    .PARAMETER exportCSV
        Define downloading CSV with Blob information.
    .EXAMPLE
        Get-ContainerBlobs -containerName container -storageAccount storageaccount -outFileName MAM-MigrationContainer-Blobs.csv -exportCSV
    .EXAMPLE
        Get-ContainerBlobs -containerName container-storageAccount storageaccount
    .NOTES
        Author: Brian Schroeder
        Date Coded: 08/15/2021
    #>
    
    param (
        [string] $containerName = "container",
        [string] $storageAccount = 'storageaccount',
        [string] $outFileName = "MAM-MigrationContainer-Blobs.csv",
        [switch] $exportCSV,
        [switch] $download
    )

       # Set the context of the Storage Account 
       Write-host "Setting Storage Account Context to $storageAccount"
       $context = New-AzStorageContext -StorageAccountName "$storageAccount"
   
       # Retrieve all the Blob Files, filter the names and export to xlsx.
       $blobFilesOutput = "Retrieving list of all Blobs for $containerName container"
       if ($exportCSV) { $blobFilesOutput += "and exporting to $outFileName..." } else { $blobFilesOutput += "..." }
   
       Write-Host -NoNewLine $blobFilesOutput
   
       try {
           $getBlobs = Get-AzStorageBlob -Context $context -Container $containerName | Select-Object Name, @{Name="FullPath";Expression={"https://$($storageAccount).blob.core.windows.net/$containerName/$($_.Name)"}}, @{Name="LengthGB"; Expression={"{0:N2}" -f ($_.Length / 1GB)}}
           if ($exportCSV) {
               $tempCsvPath = $outFileName -replace "\.xlsx$", ".csv"
               $getBlobs | Export-Csv -Path $tempCsvPath -NoTypeInformation
           }
           else { $getBlobs }
       }
   
       catch { Write-Host " Failed" -ForegroundColor Red; $_; break }
    
    if ($download) {

        try {
            #Downlod the file to the local host
            Write-Host -NoNewLine "Downloading $outFileName..."
            download $outFileName | Out-Null
            Write-host "Successful" -ForegroundColor Green
        }

        catch {
            Write-host  "Failed" -ForegroundColor Red ; $_ ; break
        }

        Write-Host "Successfully Completed" -ForegroundColor Green
    }
}

Function Update-AzureBlobName {

    <# 
    .SYNOPSIS
        Clone Provided Azure Blobs in CSV file with Source and Destination names and remove source blob after clone if specificed.
    .PARAMETER srcContainer
        Name of the Source Container where Blob resides.
    .PARAMETER storageAccount
        Name of the Source Storage Account where Blob resides.
    .PARAMETER destContainer
        Name of the Destination Container where Blob will be replicated.
    .PARAMETER azureBlobManifest
        Name of the CSV file containing the source and destination Azure URI paths.
    .PARAMETER cloneBlob
        Define cloning the Blob to the destination Container.
    .PARAMETER removeSrcBlob
        Define removing the Source Blob once the replication has been completed.
    .EXAMPLE
        Update-AzureBlobName -StorageAccount storageAccount -srcContainer srcContainer -destContainer destContainer -AzureBlobManifest Azure-BlobMigration.csv -cloneBlob
    .EXAMPLE
        Update-AzureBlobName -StorageAccount storageAccount -srcContainer srcContainer -destContainer destContainer -AzureBlobManifest Azure-BlobMigration.csv -cloneBlob -removeSrcBlob
    .NOTES
        Author: Brian Schroeder
        Date Coded: 08/15/2021
    #>

    param (

        [String] $srcContainer = 'srcContainer',
        [String] $storageAccount = 'storageAccount',
        [String] $destContainer = 'destContainer',
        [String] $azureBlobManifest = 'Azure-BlobMigration.csv',
        [Switch] $cloneBlob,
        [Switch] $removeSrcBlob
    )

    foreach ($blob in Get-Content $azureBlobManifest) {

        $sourceBlob = ($blob -split ',')[0] -replace "https://$($StorageAccount).blob.core.windows.net/$($srcContainer)/"
        $destinationBlob = ($blob -split ',')[1] -replace "https://$($StorageAccount).blob.core.windows.net/$($destContainer)/"
        $context = New-AzStorageContext -StorageAccountName "$StorageAccount"

        # Clone Blob to Specified Destination
        if ($cloneBlob) {

            try {
                "Cloning:" 
                Write-Host "Source: $srcContainer/$sourceBlob"  
                Write-Host "Destination: $destContainer/$destinationBlob"
                Start-AzStorageBlobCopy -SrcBlob "$sourceBlob" -SrcContainer "$srcContainer" -DestContainer "$destContainer" -DestBlob "$destinationBlob" -context $context -Force | Out-Null
                Write-Host "Successfully Cloned" -foregroundcolor Green
                '===================================================================='
            }


            catch { Write-Host `n"Failed Cloning" -foregroundcolor yellow ; $_ ; '===================================================================='}
        }

        if ($removeSrcBlob -and !$cloneBlob) { Write-Host 'Warning: Blobs must be cloned before removing the Source Blob. Pass the -CloneBlob Switch.' -foregroundcolor yellow ; break }

        # Remove Blob from Source After Blob Clone
        if ($removeSrcBlob -and $cloneBlob) {

            try {
                "Removing:" 
                Write-Host "Source: $srcContainer/$sourceBlob"  
                Remove-AzStorageBlob -Blob "$sourceBlob" -Container "$srcContainer" -context $context -Force | Out-Null
                Write-Host "Successfully Removed" -foregroundcolor Green
                '===================================================================='
            }

            catch { Write-Host `n"Failed Removing" -foregroundcolor yellow ; $_ ; '===================================================================='}
        }
    }
}
