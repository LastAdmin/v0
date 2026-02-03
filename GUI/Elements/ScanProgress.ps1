$ScanProgress = New-ProgressBar
$ScanProgress.Location = Location 15 475
$ScanProgress.Size = Size 290 25
$ScanProgress.Style = "Continuous"

$LeftPanel.Controls.Add($ScanProgress)