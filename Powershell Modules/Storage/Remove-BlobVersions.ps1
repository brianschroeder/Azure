Import-Module Az.Storage

$storageAccountName = "saName"
$storageAccountKey = "saKey"
$containerName = "container"
$prefix = "prefix"
"Gathering versions for prefix $($prefix) in $storageAccountName/$containerName"

Select-AzSubscription -SubscriptionId "Subscription" | Out-Null

$context = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
$blobs = Get-AzStorageBlob -Container $containerName -Prefix $prefix -Context $context -IncludeVersion

$blobVersionCount = 0

foreach ($blob in $blobs) {

    if ($blob.Name -match [regex]::Escape($prefix))

        {

        $blobVersionCount += 1
        Remove-AzStorageBlob -Blob $blob.Name -Container $containerName -Context $context -Force -VersionId $blob.VersionId 

        }
}

"$blobVersionCount total versions removed."
