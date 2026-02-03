$TechnicianNameLabel = New-Label
$TechnicianNameLabel.Location = Location 15 55
$TechnicianNameLabel.Size = Size 120 20
$TechnicianNameLabel.Text = "Technician Name"
$TechnicianNameLabel.ForeColor = Color 255 255 255

$TechnicianName = New-TextBox
$TechnicianName.Location = Location 15 75
$TechnicianName.Size = Size 290 25
$TechnicianName.Text = ""
$TechnicianName.BackColor = Color 100 100 100
$TechnicianName.ForeColor = Color 255 255 255

$LeftPanel.Controls.Add($TechnicianNameLabel)
$LeftPanel.Controls.Add($TechnicianName)