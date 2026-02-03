function Get-AvailableDisks {
    Get-Disk | Select-Object Number, FriendlyName, Size, PartitionStyle, OperationalStatus |
            Format-Table -AutoSize
}