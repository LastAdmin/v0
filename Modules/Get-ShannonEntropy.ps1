function Get-ShannonEntropy {
    param([byte[]]$Data)

    if ($null -eq $Data -or $Data.Length -eq 0) { return 0 }

    $frequency = @{}
    foreach ($byte in $Data) {
        if ($frequency.ContainsKey($byte)) {
            $frequency[$byte]++
        } else {
            $frequency[$byte] = 1
        }
    }

    $entropy = 0.0
    $length = $Data.Length
    foreach ($count in $frequency.Values) {
        $p = $count / $length
        if ($p -gt 0) {
            $entropy -= $p * [math]::Log($p, 2)
        }
    }

    return $entropy
}