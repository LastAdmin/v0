$FullDiskCheckBox = New-CheckBox
$FullDiskCheckBox.Location = Location 15 170
$FullDiskCheckBox.Size = Size 290 25
$FullDiskCheckBox.Text = "Full Disk Scan (all sectors)"
$FullDiskCheckBox.ForeColor = Color 255 255 255
$FullDiskCheckBox.Checked = $true
$FullDiskCheckBox.Enabled = $false

$LeftPanel.Controls.Add($FullDiskCheckBox)
