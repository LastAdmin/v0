$StatusLabel = New-Label
$StatusLabel.Location = Location 15 450
$StatusLabel.Size = Size 290 25
$StatusLabel.Text = "Status: Ready"
$StatusLabel.ForeColor = Color 255 255 255

$LeftPanel.Controls.Add($StatusLabel)