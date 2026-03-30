function Get-DiskStatus {
    .\Crystal\DiskInfo64.exe /CopyExit
    Start-Sleep -Seconds 5
    $CrystalReportPath = Test-Path .\Crystal\DiskInfo.txt
    if ($CrystalReportPath -eq $true) {
        $CrystalReport = Get-Content .\Crystal\DiskInfo.txt
    }
    else {
        Start-Sleep -Seconds 5
        $CrystalReportPath = Test-Path .\Crystal\DiskInfo.txt
        if ($CrystalReportPath -eq $true) {
            $CrystalReport = Get-Content .\Crystal\DiskInfo.txt
        }
        else {
            Write-Console "ERROR: Crystal Report not created or found" "Red"
            $StatusLabel.Text = "Status: ERROR"
            $VerificationPanel.BackColor = Color 255 0 0
            $ResultLabel.Text = "HW Report Failed"
            $ResultLabel.ForeColor = Color 0 0 0
            DoEvents
            $ReportStatus = $false
            return $ReportStatus
        }
    }
}