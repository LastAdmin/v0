function Full-DiskScan {
    $SampleSize.Enabled = -not $FullDiskCheckBox.Checked
    if (!$SampleSize.Enabled) {
        $SampleSize.BackColor = Color 15 15 15
        DoEvents
    }
    if ($SampleSize.Enabled) {
        $SampleSize.BackColor = Color 100 100 100
        DoEvents
    }
    if ($FullDiskCheckBox.Checked) {
        $selectedDisk = $DiskList.SelectedItem
        if ($selectedDisk -and $selectedDisk -match "Disk (\d+)") {
            $diskNum = [int]$Matches[1]
            $disk = Get-Disk -Number $diskNum -ErrorAction SilentlyContinue
            if ($disk) {
                $totalSectors = [math]::Floor($disk.Size / $SectorSize.SelectedItem)
                $SampleSize.Maximum = $totalSectors
                $SampleSize.Value = $totalSectors
                $SectorInfoLabel.Text = "Total sectors: $($totalSectors.ToString('N0'))"
            }
        }
    }
}