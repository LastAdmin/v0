$ConsoleHeader = New-Label
$ConsoleHeader.Location = Location 15 210
$ConsoleHeader.Size = Size 490 25
$ConsoleHeader.Text = "Console Output"
$ConsoleHeader.Font = FontSize 12 "Bold"
$ConsoleHeader.ForeColor = Color 255 255 255

$RightPanel.Controls.Add($ConsoleHeader)