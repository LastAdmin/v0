function Load-Disks {
    $DiskList.Items.Clear()
    Write-Console "Loading available disks..." "Yellow"

    try {
        $disks = Get-Disk
        foreach ($disk in $disks) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 2)
            $status = $disk.OperationalStatus
            $entry = "Disk $($disk.Number) | $($disk.FriendlyName) | $sizeGB GB | $status"
            $DiskList.Items.Add($entry)
        }
        Write-Console "Found $($disks.Count) disk(s)" "Orange"

        if ($DiskList.Items.Count -gt 0) {
            $DiskList.SelectedIndex = 0
        }
    }
    catch {
        Write-Console "Error loading disks: $_"
    }
}