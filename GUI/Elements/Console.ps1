$Console = New-RichTextBox
$Console.Location = Location 15 240
$Console.Size = Size 580 400
$Console.Multiline = $true
$Console.ScrollBars = "Vertical"
$Console.ReadOnly = $true
$Console.BackColor = Color 5 5 5
$Console.ForeColor = Color 200 200 200
$Console.Font = FontSize 9 "" "Consolas"

$RightPanel.Controls.Add($Console)