$StartScan = New-Button
$StartScan.Location = Location 15 610
$StartScan.Size = Size 140 40
$StartScan.Text = "Start Scan"
$StartScan.BackColor = Color 200 0 0
$StartScan.ForeColor = Color 255 255 255
$StartScan.FlatStyle = "Flat"
$StartScan.Font = FontSize 10 "Bold"

$LeftPanel.Controls.Add($StartScan)