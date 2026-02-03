function Browse-Path {
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderBrowser.SelectedPath = $ReportPath.Text
    if ($FolderBrowser.ShowDialog() -eq "OK") {
        $ReportPath.Text = $FolderBrowser.SelectedPath
    }
}