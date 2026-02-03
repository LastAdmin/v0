$CancelScan = New-Button
$CancelScan.Location = Location 165 610
$CancelScan.Size = Size 140 40
$CancelScan.Text = "Cancel"
$CancelScan.BackColor = Color 100 100 100
$CancelScan.ForeColor = Color 255 255 255
$CancelScan.FlatStyle = "Flat"
$CancelScan.Font = FontSize 10
$CancelScan.Enabled = $false

$LeftPanel.Controls.Add($CancelScan)