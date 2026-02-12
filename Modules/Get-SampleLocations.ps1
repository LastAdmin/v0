function Get-SampleLocations {
    <#
    .SYNOPSIS
        Generates sector locations to sample for analysis.
        Uses a HashSet for O(1) dedup and long-safe random generation.
    .PARAMETER TotalSectors
        Total number of sectors on the disk (long).
    .PARAMETER SampleSize
        Desired number of samples.
    #>
    param(
        [long]$TotalSectors,
        [int]$SampleSize
    )

    # Clamp sample size to total sectors
    if ($SampleSize -gt $TotalSectors) {
        $SampleSize = [int][math]::Min($TotalSectors, [int]::MaxValue)
    }

    # Use a HashSet<long> for O(1) deduplication instead of Select-Object -Unique
    $locationSet = New-Object 'System.Collections.Generic.HashSet[long]'

    # First 100 sectors (or fewer if disk is small)
    $headCount = [math]::Min(100, $TotalSectors)
    for ([long]$i = 0; $i -lt $headCount; $i++) {
        $locationSet.Add($i) | Out-Null
    }

    # Last 100 sectors
    $tailStart = [math]::Max(0, $TotalSectors - 100)
    for ([long]$i = $tailStart; $i -lt $TotalSectors; $i++) {
        $locationSet.Add($i) | Out-Null
    }

    # Random samples from the middle region
    $remaining = $SampleSize - $locationSet.Count
    if ($remaining -gt 0 -and $TotalSectors -gt 200) {
        $random = New-Object System.Random

        # The middle range to sample from (between head and tail)
        [long]$rangeStart = 100
        [long]$rangeEnd = $TotalSectors - 100
        [long]$rangeSize = $rangeEnd - $rangeStart

        # Safety limit: don't spin forever if range is nearly exhausted
        $maxAttempts = $remaining * 3
        $attempts = 0

        while ($locationSet.Count -lt $SampleSize -and $attempts -lt $maxAttempts) {
            # Generate a long-safe random sector number:
            # Combine two 31-bit random ints to produce a full-range [long]
            [long]$rndLong = (([long]$random.Next()) -shl 31) -bor ([long]$random.Next())
            [long]$sector = $rangeStart + ([math]::Abs($rndLong) % $rangeSize)

            $locationSet.Add($sector) | Out-Null
            $attempts++
        }
    }

    # Convert to sorted array
    $sorted = [long[]]::new($locationSet.Count)
    $locationSet.CopyTo($sorted)
    [Array]::Sort($sorted)
    return $sorted
}
