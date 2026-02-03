function Get-SampleLocations {
    <#
    .SYNOPSIS
        Generates sector locations to sample for analysis
    .PARAMETER TotalSectors
        Total number of sectors on the disk
    .PARAMETER SampleSize
        Desired number of samples
    #>
    param(
        [long]$TotalSectors,
        [int]$SampleSize
    )

    $sampleLocations = @()

    # First 100 sectors
    $sampleLocations += 0..([math]::Min(99, $TotalSectors - 1))

    # Last 100 sectors
    $endStart = [math]::Max(0, $TotalSectors - 100)
    $sampleLocations += $endStart..($TotalSectors - 1)

    # Random samples from middle
    $remaining = $SampleSize - $sampleLocations.Count
    if ($remaining -gt 0 -and $TotalSectors -gt 200) {
        $random = New-Object System.Random
        for ($i = 0; $i -lt $remaining; $i++) {
            $sampleLocations += $random.Next(100, $TotalSectors - 100)
        }
    }

    return $sampleLocations | Select-Object -Unique | Sort-Object
}