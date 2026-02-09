function Get-Parameters {
    $timestamp = Get-Date -Format "yyyMMdd_HHmmss"
    @{
        technician = $TechnicianName.Text
        diskNumber = $diskNumber
        sampleSize = [long]$SampleSize.Value
        sectorSize = [int]$SectorSize.SelectedItem
        reportFormat = $ReportFormat.SelectedItem
        reportPath = $ReportPath.Text
        timestamp = Get-Date -Format "yyyMMdd_HHmmss"
        reportFile = Join-Path $ReportPath.Text "\DiskWipeReport_$timestamp"
    }
}