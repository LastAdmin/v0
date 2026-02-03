$ProgressLabel = New-Label
$ProgressLabel.Location = Location 15 505
$ProgressLabel.Size = Size 290 20
$ProgressLabel.Text = "0%"
$ProgressLabel.TextAlign = "MiddleCenter"
$ProgressLabel.ForeColor = Color 255 255 255

$LeftPanel.Controls.Add($ProgressLabel)