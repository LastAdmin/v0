$ReportFormatLabel = New-Label
$ReportFormatLabel.Location = Location 15 285
$ReportFormatLabel.Size = Size 120 20
$ReportFormatLabel.Text = "Report Format:"
$ReportFormatLabel.ForeColor = Color 255 255 255

$ReportFormat = New-ComboBox
$ReportFormat.Location = Location 15 305
$ReportFormat.Size = Size 290 25
$ReportFormat.DropDownStyle = "DropDownList"
$ReportFormat.Items.AddRange(@("HTML", "PDF", "Both"))
$ReportFormat.SelectedIndex = 2
$ReportFormat.BackColor = Color 100 100 100
$ReportFormat.ForeColor = Color 255 255 255

$LeftPanel.Controls.Add($ReportFormatLabel)
$LeftPanel.Controls.Add($ReportFormat)