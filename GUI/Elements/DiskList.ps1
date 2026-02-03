$DiskList = New-ListBox
$DiskList.Location = Location 15 50
$DiskList.Size = Size 580 150
$DiskList.Font = FontSize 9 "" "Consolas"

$RightPanel.Controls.Add($DiskList)