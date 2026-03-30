function Get-ShannonEntropy {
    <#
    .SYNOPSIS
        Calculates Shannon entropy for a byte array
    .DESCRIPTION
        Uses a fixed-size int array for byte frequency counting instead of hashtable.
        This is more memory efficient and faster for byte data.
    #>
    param([byte[]]$Data)

    if ($null -eq $Data -or $Data.Length -eq 0) { return 0 }

    # Use fixed-size array instead of hashtable - more memory efficient
    $frequency = New-Object 'int[]' 256
    foreach ($byte in $Data) {
        $frequency[$byte]++
    }

    $entropy = 0.0
    $length = $Data.Length
    for ($i = 0; $i -lt 256; $i++) {
        if ($frequency[$i] -gt 0) {
            $p = $frequency[$i] / $length
            $entropy -= $p * [math]::Log($p, 2)
        }
    }

    return $entropy
}

function Get-ShannonEntropyFromHistogram {
    <#
    .SYNOPSIS
        Calculates Shannon entropy from a pre-computed byte frequency histogram
    .DESCRIPTION
        Memory-efficient entropy calculation that uses running histogram totals
        instead of storing all raw bytes. Used for overall entropy calculation.
    .PARAMETER Histogram
        A 256-element long array containing byte frequency counts
    .PARAMETER TotalBytes
        Total number of bytes represented in the histogram
    #>
    param(
        [long[]]$Histogram,
        [long]$TotalBytes
    )

    if ($TotalBytes -eq 0) { return 0 }

    $entropy = 0.0
    for ($i = 0; $i -lt 256; $i++) {
        if ($Histogram[$i] -gt 0) {
            $p = $Histogram[$i] / $TotalBytes
            $entropy -= $p * [math]::Log($p, 2)
        }
    }

    return $entropy
}
