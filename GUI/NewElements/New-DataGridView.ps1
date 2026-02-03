function New-DataGridView {
    $DataGridView = New-Object System.Windows.Forms.DataGridView
    return $DataGridView
}

function New-DataGridViewColumn {
    $DataGridViewColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    return $DataGridViewColumn
}