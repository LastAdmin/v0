function Start-Scan {
    # Validate disk selection
    if ($DiskList.SelectedIndex -lt 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select a disk to scan.", "No Disk Selected", "OK", "Warning")
        return
    }

    # Validate Technician name input
    if ($TechnicianName.Text -eq "") {
        [System.Windows.Forms.MessageBox]::Show("Please enter your name.", "No Name entered", "OK", "Warning")
        return
    }

    # Get disk number
    $selectedDisk = $DiskList.SelectedItem
    if ($selectedDisk -notmatch "Disk (\d+)") {
        [System.Windows.Forms.MessageBox]::Show("Invalid disk selection.", "Error", "OK", "Error")
        return
    }
    $diskNumber = [int]$Matches[1]

    # Confirm scan
    $confirm = [System.Windows.Forms.MessageBox]::Show(
            "You are about to scan Disk $diskNumber.`n`nThis is a READ-ONLY operation and will not modify the disk.`n`nContinue?",
            "Confirm Scan",
            "YesNo",
            "Question"
    )

    if ($confirm -ne "Yes") {
        Write-Console "Analysis cancelled." "Orange"
        return
    }

    # Reset UI
    $script:cancelRequested = $false
    $StartScan.Enabled = $false
    $CancelScan.Enabled = $true
    $DiskList.Enabled = $false
    $ScanProgress.Value = 0
    $ProgressLabel.Text = "0%"
    $VerificationPanel.Visible = $false
    $VerificationPanel.BackColor = Color 100 100 100
    $ResultLabel.ForeColor = Color 255 255 255
    $ResultLabel.Text = ""
    $Console.Clear()

    # Get Parameters
    $P = Get-Parameters

    Write-Console "=====================================================" "Magenta"
    Write-Console "     DISK WIPE VERIFICATION SCAN" "Info"
    Write-Console "=====================================================" "Magenta"
    Write-Console "Parameters:" "Info"
    Write-Console "   Technician: $($P.technician)" "Info"
    Write-Console "   Disk Number: $($P.diskNumber)" "Info"
    Write-Console "   Sample Size: $($P.sampleSize.ToString('N0')) sectors" "Info"
    Write-Console "   Sector Size: $($P.sectorSize) bytes" "Info"
    Write-Console "   Report Format: $($P.reportFormat)" "Info"
    Write-Console "   Report Path: $($P.reportPath)" "Info"
    Write-Console "   Report File: $($P.reportFile)" "Info"
    Write-Console "=====================================================" "Magenta"

    $StatusLabel.Text = "Status: Initializing..."
    DoEvents

    Main-Process
}
