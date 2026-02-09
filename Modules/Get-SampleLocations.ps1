function Get-SampleLocations {
    <#
    .SYNOPSIS
        Generates sector locations to sample for analysis (memory-optimized, streaming)
    .DESCRIPTION
        Returns a lightweight iterator object instead of a full array. The iterator
        yields sector numbers on demand so that even full-disk scans with billions
        of sectors use only a few KB of RAM for the location list itself.

        For SAMPLED scans (SampleSize < TotalSectors):
          - First 100 sectors, last 100 sectors, plus random middle sectors are
            pre-generated into a sorted array (typical max: a few hundred KB).

        For FULL scans (SampleSize >= TotalSectors):
          - Returns a sequential counter object that yields 0, 1, 2, ... without
            allocating any array at all. Memory usage: ~100 bytes.

    .PARAMETER TotalSectors
        Total number of sectors on the disk
    .PARAMETER SampleSize
        Desired number of samples. If >= TotalSectors, a full sequential scan is used.
    .OUTPUTS
        [hashtable] with keys:
            Count       - [long] total number of sectors to scan
            GetEnumerator - [scriptblock] returns an enumerator over sector numbers
            IsFullScan  - [bool] true if scanning every sector sequentially
    #>
    param(
        [long]$TotalSectors,
        [long]$SampleSize
    )

    # FULL DISK SCAN: sequential counter, zero array allocation
    if ($SampleSize -ge $TotalSectors) {
        return @{
            Count = $TotalSectors
            IsFullScan = $true
            # Returns a simple range enumerator - no array stored in memory
            GetEnumerator = {
                param([long]$total)
                $i = [long]0
                while ($i -lt $total) {
                    $i  # yield
                    $i++
                }
            }.GetNewClosure()
            _totalForEnum = $TotalSectors
        }
    }

    # SAMPLED SCAN: build a sorted array of selected sector numbers
    # For typical sample sizes (1,000 - 500,000), this uses < 4 MB of RAM
    $locationSet = New-Object 'System.Collections.Generic.HashSet[long]'

    # First 100 sectors
    $firstCount = [math]::Min(100, $TotalSectors)
    for ($i = [long]0; $i -lt $firstCount; $i++) {
        [void]$locationSet.Add($i)
    }

    # Last 100 sectors (avoid overlap with first 100)
    if ($TotalSectors -gt 100) {
        $endStart = [math]::Max(100, $TotalSectors - 100)
        for ($i = $endStart; $i -lt $TotalSectors; $i++) {
            [void]$locationSet.Add($i)
        }
    }

    # Random samples from middle section
    $remaining = $SampleSize - $locationSet.Count
    if ($remaining -gt 0 -and $TotalSectors -gt 200) {
        $random = New-Object System.Random
        $middleStart = [long]100
        $middleEnd = $TotalSectors - 100
        $middleRange = $middleEnd - $middleStart

        # Limit attempts to avoid infinite loop when range is nearly exhausted
        $maxAttempts = [long]$remaining * 3
        $attempts = [long]0

        while ($locationSet.Count -lt $SampleSize -and $attempts -lt $maxAttempts) {
            if ($middleRange -gt [int]::MaxValue) {
                $randomOffset = [long]($random.NextDouble() * $middleRange)
            } else {
                $randomOffset = [long]$random.Next(0, [int]$middleRange)
            }
            $sector = $middleStart + $randomOffset
            [void]$locationSet.Add($sector)
            $attempts++
        }
    }

    # Convert to sorted array
    $sortedArray = New-Object 'long[]' $locationSet.Count
    $locationSet.CopyTo($sortedArray)
    [Array]::Sort($sortedArray)

    # Clear the HashSet immediately - we only need the sorted array from here
    $locationSet.Clear()
    $locationSet = $null

    return @{
        Count = [long]$sortedArray.Length
        IsFullScan = $false
        _array = $sortedArray
    }
}
