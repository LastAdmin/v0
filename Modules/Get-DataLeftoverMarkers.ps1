function Get-DataLeftoverMarker {
    <#
    .SYNOPSIS
        Creates a structured marker for a sector containing potential data leftovers.
    .DESCRIPTION
        When a sector is classified as "NOT Wiped" or "Suspicious" by Test-SectorWiped,
        this function builds a lightweight marker object containing the sector address,
        byte offset, classification details, a hex preview of the first 32 bytes, and
        an ASCII preview for manual review. These markers are collected during the scan
        and included in the final report.

        Memory considerations:
        - Each marker stores only metadata and a short preview, NOT the full sector data.
        - A 32-byte hex preview is stored per marker (64 hex characters + separators).
        - Even with 10,000 flagged sectors, total marker memory is under 5 MB.

    .PARAMETER SectorNumber
        The logical sector number on the disk.
    .PARAMETER SectorSize
        The size of a sector in bytes (typically 512 or 4096).
    .PARAMETER AnalysisResult
        The hashtable returned by Test-SectorWiped containing Status, Pattern,
        Confidence, and Details.
    .PARAMETER SectorData
        The raw byte array of the sector. Only the first 32 bytes are stored
        in the marker for preview purposes.
    .OUTPUTS
        [hashtable] A marker object with the following keys:
            SectorNumber  - [long]   Logical sector index
            ByteOffset    - [string] Hex-formatted byte offset on disk (e.g., "0x0000FA00")
            ByteOffsetDec - [long]   Decimal byte offset on disk
            Status        - [string] "NOT Wiped" or "Suspicious"
            Pattern       - [string] Detected pattern description
            Confidence    - [int]    Confidence percentage (0-100)
            Details       - [string] Analysis detail string
            HexPreview    - [string] First 32 bytes as hex (e.g., "25 50 44 46 2D ...")
            AsciiPreview  - [string] First 32 bytes as printable ASCII (non-printable replaced with ".")
    .EXAMPLE
        $marker = Get-DataLeftoverMarker -SectorNumber 4096 -SectorSize 512 `
            -AnalysisResult $analysis -SectorData $sectorData
    #>
    param(
        [long]$SectorNumber,
        [int]$SectorSize,
        [hashtable]$AnalysisResult,
        [byte[]]$SectorData
    )

    $byteOffset = [long]$SectorNumber * $SectorSize

    # Build hex preview from first 32 bytes (or fewer if sector is smaller)
    $previewLength = [math]::Min(32, $SectorData.Length)
    $hexParts = New-Object 'string[]' $previewLength
    $asciiChars = New-Object 'char[]' $previewLength

    for ($i = 0; $i -lt $previewLength; $i++) {
        $hexParts[$i] = $SectorData[$i].ToString("X2")
        # Printable ASCII range: 32 (space) to 126 (tilde)
        if ($SectorData[$i] -ge 32 -and $SectorData[$i] -le 126) {
            $asciiChars[$i] = [char]$SectorData[$i]
        } else {
            $asciiChars[$i] = '.'
        }
    }

    return @{
        SectorNumber  = $SectorNumber
        ByteOffset    = "0x{0:X}" -f $byteOffset
        ByteOffsetDec = $byteOffset
        Status        = $AnalysisResult.Status
        Pattern       = $AnalysisResult.Pattern
        Confidence    = $AnalysisResult.Confidence
        Details       = $AnalysisResult.Details
        HexPreview    = $hexParts -join " "
        AsciiPreview  = [string]::new($asciiChars)
    }
}

function New-DataLeftoverCollection {
    <#
    .SYNOPSIS
        Creates a new, empty data leftover collection with a capped maximum size.
    .DESCRIPTION
        Returns a hashtable that acts as a lightweight container for data leftover markers.
        The collection enforces a maximum marker count to prevent unbounded memory growth
        during scans of heavily non-wiped disks. When the cap is reached, new markers are
        silently dropped but the overflow count is tracked.

        Structure:
            Markers       - [System.Collections.Generic.List[hashtable]] list of marker objects
            MaxMarkers    - [int]    maximum number of markers to store
            OverflowCount - [int]    number of markers dropped because the cap was reached
            Summary       - [hashtable] aggregated counts by status and pattern

    .PARAMETER MaxMarkers
        Maximum number of individual markers to store. Defaults to 500.
        Increase for more detail at the cost of more memory; decrease for tighter environments.
    .EXAMPLE
        $leftovers = New-DataLeftoverCollection -MaxMarkers 1000
    #>
    param(
        [int]$MaxMarkers = 500
    )

    return @{
        Markers       = New-Object 'System.Collections.Generic.List[hashtable]'
        MaxMarkers    = $MaxMarkers
        OverflowCount = 0
        Summary       = @{
            TotalNotWiped   = 0
            TotalSuspicious = 0
            PatternCounts   = @{}
        }
    }
}

function Add-DataLeftoverMarker {
    <#
    .SYNOPSIS
        Adds a marker to the data leftover collection if it has not reached capacity.
    .DESCRIPTION
        Checks the collection size against its MaxMarkers cap. If under the cap, the
        marker is appended; otherwise the OverflowCount is incremented. Summary
        statistics (status counts and per-pattern counts) are always updated regardless
        of whether the individual marker is stored.
    .PARAMETER Collection
        The collection hashtable created by New-DataLeftoverCollection.
    .PARAMETER Marker
        A marker hashtable created by Get-DataLeftoverMarker.
    .EXAMPLE
        Add-DataLeftoverMarker -Collection $leftovers -Marker $marker
    #>
    param(
        [hashtable]$Collection,
        [hashtable]$Marker
    )

    # Always update summary statistics
    if ($Marker.Status -eq "NOT Wiped") {
        $Collection.Summary.TotalNotWiped++
    } elseif ($Marker.Status -eq "Suspicious") {
        $Collection.Summary.TotalSuspicious++
    }

    $pattern = $Marker.Pattern
    if (-not $Collection.Summary.PatternCounts.ContainsKey($pattern)) {
        $Collection.Summary.PatternCounts[$pattern] = 0
    }
    $Collection.Summary.PatternCounts[$pattern]++

    # Only store individual marker if under cap
    if ($Collection.Markers.Count -lt $Collection.MaxMarkers) {
        $Collection.Markers.Add($Marker)
    } else {
        $Collection.OverflowCount++
    }
}
