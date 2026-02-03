function Disk-List {
    #change variable names
    if ($DiskList.SelectedItem -and $DiskList.SelectedItem -match "Disk (\d+)") {
        $diskNum = [int]$Matches[1]
        $disk = Get-Disk -Number $diskNum -ErrorAction SilentlyContinue
        if ($disk) {
            $totalSectors = [math]::Floor($disk.Size / [int]$SectorSize.SelectedItem)
            $SectorInfoLabel.Text = "Total sectors: $($totalSectors.ToString('N0'))"
            if ($FullDiskCheckBox.Checked) {
                $SampleSize.Maximum = $totalSectors
                $SampleSize.Value = $totalSectors
            }
        }
    }
}