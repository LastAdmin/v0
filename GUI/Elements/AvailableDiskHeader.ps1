$DiskHeader = New-Label
$DiskHeader.Location = Location 15 15
$DiskHeader.Size = Size 400 25
$DiskHeader.Text = "Available Disks"
$DiskHeader.Font = FontSize 12 "Bold"
$DiskHeader.ForeColor = Color 255 255 255

$RightPanel.Controls.Add($DiskHeader)