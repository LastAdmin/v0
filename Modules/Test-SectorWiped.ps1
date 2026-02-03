function Test-SectorWiped {
    param(
        [byte[]]$SectorData
    )

    if ($null -eq $SectorData -or $SectorData.Length -eq 0) {
        return @{
            Status = "Unreadable"
            Pattern = "N/A"
            Confidence = 0
            Details = "Could not read sector"
        }
    }

    # Check for zero-fill (fastest check)
    $allZeros = $true
    foreach ($byte in $SectorData) {
        if ($byte -ne 0x00) {
            $allZeros = $false; break
        }
    }
    if ($allZeros) {
        return @{
            Status = "Wiped"
            Pattern = "Zero-filled (0x00)"
            Confidence = 100
            Details = "All bytes are 0x00 - standard wipe pattern"
        }
    }

    # Check for one-fill
    $allOnes = $true
    foreach ($byte in $SectorData) {
        if ($byte -ne 0xFF) {
            $allOnes = $false; break
        }
    }
    if ($allOnes) {
        return @{
            Status = "Wiped"
            Pattern = "One-filled (0xFF)"
            Confidence = 100
            Details = "All bytes are 0xFF - standard wipe pattern"
        }
    }

    # Calculate entropy and distribution FIRST (before signature check)
    $entropy = Get-ShannonEntropy -Data $SectorData
    $distribution = Get-ByteDistributionScore -Data $SectorData
    $asciiRatio = Get-PrintableAsciiRatio -Data $SectorData

    # HIGH ENTROPY PATH: DoD 5220.22-M random pass detection
    # True random data has: high entropy (>7.0), reasonable distribution (>0.80)
    # We check this BEFORE file signatures because random data may accidentally match signatures
    if ($entropy -gt 7.0) {
        # Very high entropy - almost certainly random wipe data
        if ($entropy -gt 7.5 -and $distribution -gt 0.80) {
            $confidence = [math]::Round((($entropy / 8) * 60) + ($distribution * 40))
            return @{
                Status = "Wiped"
                Pattern = "Random data (DoD 5220.22-M)"
                Confidence = $confidence
                Details = "Entropy: $([math]::Round($entropy, 2))/8.0, Distribution: $([math]::Round($distribution * 100, 1))%"
            }
        }

        # High entropy with good distribution - likely random
        if ($distribution -gt 0.75 -and $asciiRatio -lt 0.5) {
            $confidence = [math]::Round((($entropy / 8) * 50) + ($distribution * 50))
            return @{
                Status = "Wiped"
                Pattern = "Random data (cryptographic wipe)"
                Confidence = $confidence
                Details = "Entropy: $([math]::Round($entropy, 2))/8.0, Distribution: $([math]::Round($distribution * 100, 1))%"
            }
        }

        # High entropy but high ASCII ratio - could be compressed text
        if ($asciiRatio -gt 0.7) {
            return @{
                Status = "NOT Wiped"
                Pattern = "Text content detected"
                Confidence = 75
                Details = "High ASCII ratio ($([math]::Round($asciiRatio * 100, 1))%) indicates text data"
            }
        }

        # High entropy, moderate distribution - likely still random wipe
        if ($distribution -gt 0.70) {
            return @{
                Status = "Wiped"
                Pattern = "Random data (probable wipe)"
                Confidence = [math]::Round($entropy / 8 * 100)
                Details = "Entropy: $([math]::Round($entropy, 2))/8.0 - consistent with random wipe"
            }
        }
    }

    # LOW/MEDIUM ENTROPY PATH: Check for file signatures (real data is more likely here)
    # Only check signatures when entropy is lower, reducing false positives
    if ($entropy -lt 7.0) {
        $fileType = Test-FileSignatures -Data $SectorData
        if ($fileType) {
            return @{
                Status = "NOT Wiped"
                Pattern = "File signature: $fileType"
                Confidence = 95
                Details = "Found $fileType file header - recoverable data present"
            }
        }
    }

    # Medium entropy analysis
    if ($entropy -gt 5.0 -and $entropy -le 7.0) {
        # Check if it looks like compressed/encrypted data
        if ($asciiRatio -lt 0.3 -and $distribution -gt 0.6) {
            return @{
                Status = "Suspicious"
                Pattern = "Compressed/encrypted data possible"
                Confidence = 60
                Details = "Medium entropy ($([math]::Round($entropy, 2))) - may be compressed files"
            }
        }

        # Could be partially overwritten
        return @{
            Status = "NOT Wiped"
            Pattern = "Residual data likely"
            Confidence = 65
            Details = "Entropy: $([math]::Round($entropy, 2)) - does not match wipe patterns"
        }
    }

    # Low entropy - definitely contains structured data
    if ($entropy -le 5.0) {
        return @{
            Status = "NOT Wiped"
            Pattern = "Structured data detected"
            Confidence = 85
            Details = "Low entropy ($([math]::Round($entropy, 2))) indicates organized/recoverable data"
        }
    }

    # Fallback
    return @{
        Status = "NOT Wiped"
        Pattern = "Unknown data pattern"
        Confidence = 50
        Details = "Entropy: $([math]::Round($entropy, 2)), unable to classify"
    }
}