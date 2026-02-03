$VerificationPanel = New-Panel
$VerificationPanel.Location = Location 15 535
$VerificationPanel.Size = Size 290 60
$VerificationPanel.BorderStyle = "FixedSingle"
$VerificationPanel.BackColor = Color 100 100 100
$VerificationPanel.Visible = $true #has to be false

$LeftPanel.Controls.Add($VerificationPanel)