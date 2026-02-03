function Get-PrintableAsciiRatio {
    param([byte[]]$Data)

    if ($null -eq $Data -or $Data.Length -eq 0) { return 0 }

    $printable = 0
    foreach ($byte in $Data) {
        if (($byte -ge 32 -and $byte -le 126) -or $byte -eq 9 -or $byte -eq 10 -or $byte -eq 13) {
            $printable++
        }
    }

    return $printable / $Data.Length
}