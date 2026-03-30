function Create-HardwareReport {
    $VerificationPanel.Visible = $true
    $VerificationPanel.BackColor = Color 255 255 0
    $ResultLabel.Text = "Create HW Report..."
    $ResultLabel.ForeColor = Color 0 0 0
    DoEvents

    Write-Console "Getting Hardware Information..." "Yellow"
    $StatusLabel.Text = "Status: Get HW Info"
    DoEvents
    $HardwareInfo = Get-HardwareInfo

    Write-Console "Getting Disk Health Status..." "Yellow"
    $StatusLabel.Text = "Status: Get Disk Health Status"
    DoEvents
    $DiskStatus = Get-DiskStatus
    if ($DiskStatus -eq $false) {
        break
    }

    Write-Console "Generate Report..." "Yellow"
    $StatusLabel.Text = "Status: Generate Report..."
    DoEvents
    Create-HTMLReport
}