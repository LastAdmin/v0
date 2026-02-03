$DiskTable = New-DataGridView
$DiskTableColumn1 = New-DataGridViewColumn
$DiskTableColumn2 = New-DataGridViewColumn
$DiskTableColumn3 = New-DataGridViewColumn

#$DiskTable.Location = New-Object System.Drawing.Point(510, 20)
$DiskTable.Location = New-Object System.Drawing.Point(5, 10)
#$DiskTable.Size = New-Object System.Drawing.Size(470, 180)
$DiskTable.Size = New-Object System.Drawing.Size(460, 180)
$DiskTable.Name = "Disk Table"
$DiskTable.ReadOnly = $true

$DiskTableColumn1.HeaderText = "Number"
$DiskTableColumn1.Name = "DiskNumber"
$DiskTableColumn1.Width = 50

$DiskTableColumn2.HeaderText = "Friendly Name"
$DiskTableColumn2.Name = "FriendlyName"
$DiskTableColumn2.Width = 215

$DiskTableColumn3.HeaderText = "Size"
$DiskTableColumn3.Name = "Size"
$DiskTableColumn3.Width = 150

$DiskTable.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::AutoSize
$DiskTable.Columns.AddRange(
    $DiskTableColumn1,
    $DiskTableColumn2,
    $DiskTableColumn3
)

$DiskTable.Add_DoubleClick ({
    DataGridView-DoubleClick
})

#$MainWindow.Controls.Add($DiskTable)
$GroupBoxR.Controls.Add($DiskTable)