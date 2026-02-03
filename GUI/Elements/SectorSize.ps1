$SectorSizeLabel = New-Label
$SectorSizeLabel.Location = Location 15 225
$SectorSizeLabel.Size = Size 120 20
$SectorSizeLabel.Text = "Sector Size (bytes):"
$SectorSizeLabel.ForeColor = Color 255 255 255

$SectorSize = New-ComboBox
$SectorSize.Location = Location 15 245
$SectorSize.Size = Size 290 25
$SectorSize.DropDownStyle = "DropDownList"
$SectorSize.Items.AddRange(@("512", "4096"))
$SectorSize.SelectedIndex = 0
$SectorSize.BackColor = Color 100 100 100
$SectorSize.ForeColor = Color 255 255 255

$LeftPanel.Controls.Add($SectorSizeLabel)
$LeftPanel.Controls.Add($SectorSize)