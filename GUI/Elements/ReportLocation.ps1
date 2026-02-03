$ReportPathLabel = New-Label
$ReportPathLabel.Location = Location 15 345
$ReportPathLabel.Size = Size 120 20
$ReportPathLabel.Text = "Report Location:"
$ReportPathLabel.ForeColor = Color 255 255 255

$ReportPath = New-TextBox
$ReportPath.Location = Location 15 365
$ReportPath.Size = Size 250 25
$ReportPath.Text = "$env:USERPROFILE\Documents\WipeReports"
$ReportPath.BackColor = Color 100 100 100
$ReportPath.ForeColor = Color 255 255 255

$ReportPathButton = New-Button
$ReportPathButton.Location = Location 270 365
$ReportPathButton.Size = Size 35 20
$ReportPathButton.Text = "..."
$ReportPathButton.FlatStyle = "Flat"
$ReportPathButton.BackColor = Color 100 100 100
$ReportPathButton.ForeColor = Color 255 255 255

$LeftPanel.Controls.Add($ReportPathLabel)
$LeftPanel.Controls.Add($ReportPath)
$LeftPanel.Controls.Add($ReportPathButton)