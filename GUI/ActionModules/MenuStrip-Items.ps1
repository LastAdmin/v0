function Debug-Mode {
    if ($DebugModeItem.Checked) {
        # Enable debug controls
        $FullDiskCheckBox.Enabled = $true
        $SampleSize.Enabled = -not $FullDiskCheckBox.Checked
        if ($SampleSize.Enabled) {
            $SampleSize.BackColor = Color 100 100 100
        }
        $MainWindow.Text = "Disk Report [DEBUG MODE]"
    }
    else {
        # Disable debug controls, force full disk scan
        $FullDiskCheckBox.Checked = $true
        $FullDiskCheckBox.Enabled = $false
        $SampleSize.Enabled = $false
        $SampleSize.BackColor = Color 15 15 15
        $MainWindow.Text = "Disk Report"
    }
    DoEvents
}