function Get-SampleLocations {
    <#
    .SYNOPSIS
        Generates sector locations to sample for analysis (memory-optimized)
    .DESCRIPTION
        Uses a HashSet for O(1) lookups and pre-allocated collections to minimize
        memory allocations. Suitable for sample sizes of 100,000+ sectors.
    .PARAMETER TotalSectors
        Total number of sectors on the disk
    .PARAMETER SampleSize
        Desired number of samples
    #>
    param(
        [long]$TotalSectors,
        [int]$SampleSize
    )

    # Use HashSet for O(1) duplicate checking - much more memory efficient
    $locationSet = New-Object 'System.Collections.Generic.HashSet[long]'

    # First 100 sectors (or fewer if disk is smaller)
    $firstCount = [math]::Min(100, $TotalSectors)
    for ($i = 0; $i -lt $firstCount; $i++) {
        $locationSet.Add($i) | Out-Null
    }

    # Last 100 sectors (avoid overlap with first 100)
    if ($TotalSectors -gt 100) {
        $endStart = [math]::Max(100, $TotalSectors - 100)
        for ($i = $endStart; $i -lt $TotalSectors; $i++) {
            $locationSet.Add($i) | Out-Null
        }
    }

    # Random samples from middle section
    $remaining = $SampleSize - $locationSet.Count
    if ($remaining -gt 0 -and $TotalSectors -gt 200) {
        $random = New-Object System.Random
        $middleStart = 100
        $middleEnd = $TotalSectors - 100
        $middleRange = $middleEnd - $middleStart
        
        # Limit attempts to avoid infinite loop if range is small
        $maxAttempts = $remaining * 3
        $attempts = 0
        
        while ($locationSet.Count -lt $SampleSize -and $attempts -lt $maxAttempts) {
            # Use NextInt64 for large disk support, fallback for smaller ranges
            if ($middleRange -gt [int]::MaxValue) {
                $randomOffset = [long]($random.NextDouble() * $middleRange)
            } else {
                $randomOffset = $random.Next(0, [int]$middleRange)
            }
            $sector = $middleStart + $randomOffset
            $locationSet.Add($sector) | Out-Null
            $attempts++
        }
    }

    # Convert to sorted array - List<T> is more memory efficient than ArrayList
    $sortedList = New-Object 'System.Collections.Generic.List[long]' $locationSet
    $sortedList.Sort()
    
    return $sortedList.ToArray()
}
