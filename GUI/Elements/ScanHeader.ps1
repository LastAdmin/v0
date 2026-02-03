$ScanHeader = New-Label
$ScanHeader.Location = Location 15 420
$ScanHeader.Size = Size 290 25
$ScanHeader.Text = "Scan Progress"
$ScanHeader.Font = FontSize 12 "Bold"
$ScanHeader.ForeColor = Color 255 255 255

$LeftPanel.Controls.Add($ScanHeader)