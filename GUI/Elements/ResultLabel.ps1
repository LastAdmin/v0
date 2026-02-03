$ResultLabel = New-Label
$ResultLabel.Location = Location 5 5
$ResultLabel.Size = Size 278 48
$ResultLabel.TextAlign = "MiddleCenter"
$ResultLabel.Font = FontSize 11 "Bold"
$ResultLabel.ForeColor = Color 255 255 255
$ResultLabel.Text = "Line has to be removed"

$VerificationPanel.Controls.Add($ResultLabel)