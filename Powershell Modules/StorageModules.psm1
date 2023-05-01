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
        Confirm-AzureStorageBlob -sourceStorageAccount stmambridgemam2086 -sourceStorageContainer qa-normal-flow -destinationStorageAccount nbaqamediaingest01 -destinationStorageContainer qa-normal-flow -sourcePath "folder1/" -destinationPath "folder2/"
    .EXAMPLE
        Confirm-AzureStorageBlob -sourceStorageAccount stmambridgemam2086 -sourceStorageContainer qa-normal-flow -destinationStorageAccount nbaqamediaingest01 -destinationStorageContainer qa-normal-flow -sourcePath "folder1/" -destinationPath "folder2/" -replicate

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
        Get-ContainerBlobs -containerName migration -storageAccount stmaminputmam1776 -outFileName MAM-MigrationContainer-Blobs.csv -exportCSV
    .EXAMPLE
        Get-ContainerBlobs -containerName migration -storageAccount stmaminputmam1776
    .NOTES
        Author: Brian Schroeder
        Date Coded: 08/15/2021
    #>
    
    param (
        [string] $containerName = "migration",
        [string] $storageAccount = 'stmaminputmam1776',
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
