function Get-ByteDistributionScore {
    param([byte[]]$Data)

    if ($null -eq $Data -or $Data.Length -eq 0) { return 0 }

    # Use fixed-size array instead of hashtable - faster and more memory efficient
    $frequency = New-Object 'int[]' 256
    foreach ($byte in $Data) { $frequency[$byte]++ }

    $expected = $Data.Length / 256.0
    $chiSquare = 0.0
    for ($i = 0; $i -lt 256; $i++) {
        $diff = $frequency[$i] - $expected
        $chiSquare += ($diff * $diff) / $expected
    }

    $maxChiSquare = $Data.Length * 255
    $normalizedScore = 1 - ($chiSquare / $maxChiSquare)

    return [math]::Max(0, [math]::Min(1, $normalizedScore))
}
