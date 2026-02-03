function Write-Console($Message, $Color) {
    if ($Color -eq $null) {
        $Color = "White"
    }

    $timestamp = Get-Date -Format "HH:mm:ss"
    $Console.SelectionStart = $Console.Text.Length
    $Console.SelectionColor = $Color
    $Console.AppendText("[$timestamp] $Message`r`n")
    $Console.ScrollToCaret()
    DoEvents
}