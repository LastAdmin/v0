#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Disk Wipe Verification Script - DoD 5220.22-M Compatible
.DESCRIPTION
    Analyzes raw disk sectors to verify complete data sanitization.
    Properly detects DoD 5220.22-M wipe patterns (including random final pass).
    Generates detailed HTML and/or PDF reports.
.NOTES
    Version:        3.8.0116.01
    Creation Date:  08.01.2026
    Author:         Yannick Morgenthaler
    Company:        JSW
    Contact:        yannick.morgenthaler@jsw.swiss
    Alternative
    Contacts:       yannick@n1x.ch
                    yannick@projectresilience.ch
                    yannick.morgenthaler@4058.net

    Copyright (c) 2026 Yannick Morgenthaler

    HISTORY:
    Date            By                      Comments
    ----------      ---                     ----------------------------------------------------------
    08.01.2026      Yannick Morgenthaler    Script was created initially
    11.01.2026      Yannick Morgenthaler    Further improved algorithms and Reports
    12.01.2026      Yannick Morgenthaler    Split Script into Modules for better maintenance
    03.02.2026      v0 / YM                 Memory optimization: streaming histogram instead of byte array,
                                            HashSet for sample locations, supports 100k+ sectors on 8GB RAM
    09.02.2026      v0 / YM                 Added Get-DataLeftoverMarkers module: flags sectors with potential
                                            data remnants, stores hex/ASCII previews, adds report section
    09.02.2026      v0 / YM                 Fixed critical memory crash: streaming iterator for full-disk scans,
                                            shared FileStream, eliminated array-limit errors on large sample sizes
#>

function Main-Process {
    try {
        #param(
        #    [Parameter(Mandatory=$false)]
        #    [int]$DiskNumber,
        #
        #    [Parameter(Mandatory=$false)]
        #    [int]$SampleSize = 1000,
        #
        #    [Parameter(Mandatory=$false)]
        #    [int]$SectorSize = 512,
        #
        #    [Parameter(Mandatory=$false)]
        #    [ValidateSet("HTML", "PDF", "Both")]
        #    [string]$ReportFormat = "Both",
        #
        #    [Parameter(Mandatory=$false)]
        #    [string]$ReportPath = "$env:USERPROFILE\Documents\GitHub\JSW\WipeReports\DiskWipeReport_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        #)

        # ========== MAIN EXECUTION ==========

        Write-Console "=====================================================" "Magenta"
        Write-Console "       DISK WIPE VERIFICATION TOOL v2.1" "Info"
        Write-Console "       DoD 5220.22-M Compatible Analysis" "Info"
        Write-Console "=====================================================" "Magenta"
        Write-Console "This tool verifies complete data sanitization by analyzing`n raw disk sectors and detecting wipe patterns." "Info"
        Write-Console "_____________________________________________________" "Gray"

        # Get Params
        Write-Console "Get Parameters..." "Yellow"
        $StatusLabel.Text = "Status: Get Parameters..."
        DoEvents
        $P = Get-Parameters

        # Set Params
        Write-Console "Set Parameters..." "Yellow"
        $StatusLabel.Text = "Status: Set Parameters..."
        DoEvents
        $Technician = $P.technician
        $DiskNumber = $P.diskNumber
        $SampleSize = $P.sampleSize
        $SectorSize = $P.sectorSize
        $ReportFormat = $P.reportFormat
        $ReportPath = $P.reportPath
        $ReportFile = $P.reportFile

        $ErrorActionPreference = "Stop"

        Write-Console "Load Modules..." "Yellow"
        $StatusLabel.Text = "Status: Load Modules..."
        DoEvents
        # Load Modules
        try {
            . .\Modules\Get-AvailableDisks.ps1
            . .\Modules\Read-DiskSector.ps1
            . .\Modules\Get-ShannonEntropy.ps1
            . .\Modules\Get-ByteDistributionScore.ps1
            . .\Modules\Test-FileSignatures.ps1
            . .\Modules\Get-PrintableAsciiRatio.ps1
            . .\Modules\Test-SectorWiped.ps1
            . .\Modules\Get-ByteHistogram.ps1
            . .\Modules\Get-DataLeftoverMarkers.ps1
            . .\Modules\New-HtmlReport.ps1
            . .\Modules\Convert-HtmlToPdf.ps1
            Write-Console "Modules Successfully Loaded!" "SpringGreen"
        }
        catch {
            Write-Console "ERROR: could not load modules!" "Red"
            exit 1
        }

        # Removed short signatures like MZ (2 bytes) that cause false positives with random data
        Write-Console "Load File Signatures..." "Yellow"
        $StatusLabel.Text = "Status: Load File Signatures..."
        DoEvents
        $FileSignatures = @{
            "PDF"      = @(0x25, 0x50, 0x44, 0x46, 0x2D)       # %PDF- (5 bytes)
            "ZIP/DOCX" = @(0x50, 0x4B, 0x03, 0x04)             # PK.. (4 bytes)
            "JPEG"     = @(0xFF, 0xD8, 0xFF, 0xE0)             # JPEG with JFIF (4 bytes)
            "PNG"      = @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A) # .PNG\r\n (6 bytes)
            "GIF87"    = @(0x47, 0x49, 0x46, 0x38, 0x37, 0x61) # GIF87a (6 bytes)
            "GIF89"    = @(0x47, 0x49, 0x46, 0x38, 0x39, 0x61) # GIF89a (6 bytes)
            "RAR"      = @(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07) # Rar!.. (6 bytes)
            "7Z"       = @(0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C) # 7z.... (6 bytes)
            "SQLite"   = @(0x53, 0x51, 0x4C, 0x69, 0x74, 0x65) # SQLite (6 bytes)
            "NTFS"     = @(0xEB, 0x52, 0x90, 0x4E, 0x54, 0x46, 0x53) # NTFS boot sector (7 bytes)
            "EXE"      = @(0x4D, 0x5A, 0x90, 0x00)             # MZ with valid header (4 bytes)
        }
        $sigs = $FileSignatures.Keys
        Write-Console "Loaded File Signatures:" "Magenta"
        Write-Console "$sigs" "Info"

        ##########################################################
        # NOT NEEDED ANYMORE
        # List available disks if no disk specified
        #if (-not $PSBoundParameters.ContainsKey('DiskNumber')) {
        #    Write-Console "Available Disks:" Yellow
        #    Get-AvailableDisks
        #    $DiskNumber = [int](Read-Host "Enter disk number to analyze")
        #}
        ##########################################################

        # Validate disk exists
        Write-Console "Validate Disk..." "Yellow"
        $StatusLabel.Text = "Status: Validate Disk..."
        DoEvents
        $disk = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
        if (-not $disk) {
            Write-Console "ERROR: Disk $DiskNumber not found!" "Red"
            exit 1
        }

        $diskPath = "\\.\PhysicalDrive$DiskNumber"
        $diskSize = $disk.Size
        $totalSectors = [math]::Floor($diskSize / $SectorSize)

        Write-Console "_____________________________________________________" "Gray"
        Write-Console "=====================================================" "Magenta"
        Write-Console "Target Disk Information:" "SpringGreen"
        Write-Console "  Disk Number    : $DiskNumber" "Info"
        Write-Console "  Model          : $($disk.FriendlyName)" "Info"
        Write-Console "  Serial         : $(if($disk.SerialNumber){$disk.SerialNumber}else{'N/A'})" "Info"
        Write-Console "  Size           : $([math]::Round($diskSize / 1GB, 2)) GB" "Info"
        Write-Console "  Total Sectors  : $($totalSectors.ToString('N0'))" "Info"
        Write-Console "  Sample Size    : $SampleSize sectors" "Info"
        Write-Console "  Report Format  : $ReportFormat" "Info"
        Write-Console "=====================================================" "Magenta"
        Write-Console "_____________________________________________________" "Gray"

        ##########################################################
        # CONFIRMATION IS DONE IN START-SCAN
        # Confirmation
        #$confirm = Read-Host "Proceed with analysis? (Y/N)"
        #if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        #    Write-Console "Analysis cancelled." "Yellow"
        #    exit 0
        #}
        ##########################################################

        # Build sample locations
        Write-Console "Build Sample Locations..." "Yellow"
        $StatusLabel.Text = "Status: Build Sample Locations..."
        DoEvents
        $sampleLocations = Get-SampleLocations -TotalSectors $totalSectors -SampleSize $sampleSize

        # Initialize results
        Write-Console "Initialize Results..." "Yellow"
        $StatusLabel.Text = "Status: Initialize Results..."
        DoEvents
        $results = @{
            Wiped = 0
            NotWiped = 0
            Suspicious = 0
            Unreadable = 0
            Patterns = @{}
        }

        $totalSamples = $sampleLocations.Count
        
        # MEMORY OPTIMIZATION: Use running histogram instead of storing all bytes
        # This uses only 2KB (256 * 8 bytes) instead of potentially hundreds of MB
        $runningHistogram = New-Object 'long[]' 256
        $totalBytesRead = [long]0

        # Data leftover collection for flagged sectors (NOT Wiped / Suspicious)
        # Stores up to 500 individual markers with hex previews for the report
        $dataLeftovers = New-DataLeftoverCollection -MaxMarkers 500

        Write-Console "Analyzing $($totalSamples.ToString('N0')) sectors$(if($sampleLocations.IsFullScan){' (full disk scan)'}else{' (sampled)'})..." "Yellow"

        # PERFORMANCE OPTIMIZATION: Open disk stream ONCE for the entire scan
        # instead of opening/closing per sector (eliminates 100,000+ file operations)
        $diskStream = $null
        $buffer = New-Object byte[] $SectorSize
        try {
            $diskStream = [System.IO.File]::Open($diskPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        }
        catch {
            Write-Console "ERROR: Cannot open disk for reading: $_" "Red"
            $StatusLabel.Text = "Status: ERROR - Cannot open disk"
            DoEvents
            return
        }

        $progress = [long]0
        $lastPercent = -1

        # TIME-BASED UI REFRESH: call DoEvents at least every 200ms so the GUI
        # stays responsive (cancel button, window drag, etc.) even when each 1%
        # represents thousands of sectors.
        $uiTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $uiIntervalMs = 200

        # Iterate based on scan type - full scan uses counter, sampled uses array
        if ($sampleLocations.IsFullScan) {
            # FULL SCAN: sequential iteration with no array allocation
            $sectorNum = [long]0
            while ($sectorNum -lt $totalSamples) {
                if ($script:cancelRequested) {
                    Write-Console "Scan cancelled by user." "Red"
                    $StatusLabel.Text = "Status: Scan cancelled by user."
                    break
                }

                $progress++
                $percent = [int][math]::Floor(($progress / $totalSamples) * 100)

                # Update UI on percent change OR on a 200ms timer - whichever comes first
                if ($percent -ne $lastPercent) {
                    $StatusLabel.Text = "Status: Scanning Sector: $($sectorNum.ToString('N0')) ($percent%)"
                    $ScanProgress.Value = [math]::Min($percent, 100)
                    $ProgressLabel.Text = "$percent%"
                    DoEvents
                    $lastPercent = $percent
                    $uiTimer.Restart()
                } elseif ($uiTimer.ElapsedMilliseconds -ge $uiIntervalMs) {
                    $StatusLabel.Text = "Status: Scanning Sector: $($sectorNum.ToString('N0')) ($percent%)"
                    DoEvents
                    $uiTimer.Restart()
                }

                # Read sector using the shared stream
                $sectorData = $null
                try {
                    $offset = $sectorNum * $SectorSize
                    [void]$diskStream.Seek($offset, [System.IO.SeekOrigin]::Begin)
                    $bytesRead = $diskStream.Read($buffer, 0, $SectorSize)
                    if ($bytesRead -gt 0) {
                        # Copy buffer so analysis functions get their own copy
                        $sectorData = New-Object byte[] $bytesRead
                        [System.Buffer]::BlockCopy($buffer, 0, $sectorData, 0, $bytesRead)
                    }
                }
                catch {
                    $sectorData = $null
                }

                $analysis = Test-SectorWiped -SectorData $sectorData

                switch ($analysis.Status) {
                    "Wiped" { $results.Wiped++ }
                    "NOT Wiped" { $results.NotWiped++ }
                    "Suspicious" { $results.Suspicious++ }
                    "Unreadable" { $results.Unreadable++ }
                }

                if (-not $results.Patterns.ContainsKey($analysis.Pattern)) {
                    $results.Patterns[$analysis.Pattern] = 0
                }
                $results.Patterns[$analysis.Pattern]++

                if ($sectorData -and ($analysis.Status -eq "NOT Wiped" -or $analysis.Status -eq "Suspicious")) {
                    $marker = Get-DataLeftoverMarker -SectorNumber $sectorNum -SectorSize $SectorSize `
                        -AnalysisResult $analysis -SectorData $sectorData
                    Add-DataLeftoverMarker -Collection $dataLeftovers -Marker $marker
                }

                if ($sectorData) {
                    foreach ($byte in $sectorData) {
                        $runningHistogram[$byte]++
                    }
                    $totalBytesRead += $sectorData.Length
                }

                $sectorNum++
            }
        }
        else {
            # SAMPLED SCAN: iterate over pre-built sorted array
            $uiTimer.Restart()
            foreach ($sectorNum in $sampleLocations._array) {
                if ($script:cancelRequested) {
                    Write-Console "Scan cancelled by user." "Red"
                    $StatusLabel.Text = "Status: Scan cancelled by user."
                    break
                }

                $progress++
                $percent = [int][math]::Floor(($progress / $totalSamples) * 100)

                if ($percent -ne $lastPercent) {
                    $StatusLabel.Text = "Status: Scanning Sector: $($sectorNum.ToString('N0')) ($percent%)"
                    $ScanProgress.Value = [math]::Min($percent, 100)
                    $ProgressLabel.Text = "$percent%"
                    DoEvents
                    $lastPercent = $percent
                    $uiTimer.Restart()
                } elseif ($uiTimer.ElapsedMilliseconds -ge $uiIntervalMs) {
                    $StatusLabel.Text = "Status: Scanning Sector: $($sectorNum.ToString('N0')) ($percent%)"
                    DoEvents
                    $uiTimer.Restart()
                }

                # Read sector using the shared stream
                $sectorData = $null
                try {
                    $offset = [long]$sectorNum * $SectorSize
                    [void]$diskStream.Seek($offset, [System.IO.SeekOrigin]::Begin)
                    $bytesRead = $diskStream.Read($buffer, 0, $SectorSize)
                    if ($bytesRead -gt 0) {
                        $sectorData = New-Object byte[] $bytesRead
                        [System.Buffer]::BlockCopy($buffer, 0, $sectorData, 0, $bytesRead)
                    }
                }
                catch {
                    $sectorData = $null
                }

                $analysis = Test-SectorWiped -SectorData $sectorData

                switch ($analysis.Status) {
                    "Wiped" { $results.Wiped++ }
                    "NOT Wiped" { $results.NotWiped++ }
                    "Suspicious" { $results.Suspicious++ }
                    "Unreadable" { $results.Unreadable++ }
                }

                if (-not $results.Patterns.ContainsKey($analysis.Pattern)) {
                    $results.Patterns[$analysis.Pattern] = 0
                }
                $results.Patterns[$analysis.Pattern]++

                if ($sectorData -and ($analysis.Status -eq "NOT Wiped" -or $analysis.Status -eq "Suspicious")) {
                    $marker = Get-DataLeftoverMarker -SectorNumber $sectorNum -SectorSize $SectorSize `
                        -AnalysisResult $analysis -SectorData $sectorData
                    Add-DataLeftoverMarker -Collection $dataLeftovers -Marker $marker
                }

                if ($sectorData) {
                    foreach ($byte in $sectorData) {
                        $runningHistogram[$byte]++
                    }
                    $totalBytesRead += $sectorData.Length
                }
            }

            # Free the sample array now that we are done iterating
            $sampleLocations._array = $null
        }

        # Close the shared disk stream
        if ($diskStream) {
            $diskStream.Close()
            $diskStream.Dispose()
            $diskStream = $null
        }

        #Write-Progress -Activity "Scanning Disk Sectors" -Completed
        Write-Console "Sector Scan Completed" "SpringGreen"
        $StatusLabel.Text = "Status: Sector Scan Completed"
        DoEvents

        # Calculate overall entropy from running histogram (memory-efficient)
        Write-Console "Calculate overall entropy..." "Yellow"
        $StatusLabel.Text = "Status: Calculate overall entropy..."
        DoEvents
        $overallEntropy = Get-ShannonEntropyFromHistogram -Histogram $runningHistogram -TotalBytes $totalBytesRead
        $entropyPercent = [math]::Round(($overallEntropy / 8) * 100, 2)

        # Calculate wiped percentage
        Write-Console "Calculate wiped percentage..." "Yellow"
        $StatusLabel.Text = "Status: Calculate wiped percentage..."
        DoEvents
        $wipedPercent = [math]::Round(($results.Wiped / $totalSamples) * 100, 2)

        # Determine overall status
        Write-Console "Determine overall status..." "Yellow"
        $StatusLabel.Text = "Status: Determine overall status..."
        DoEvents
        $overallStatus = if ($wipedPercent -ge 99.5) {
            "VERIFIED CLEAN - Disk Successfully Wiped"
        }
        elseif ($wipedPercent -ge 95) {
            "MOSTLY CLEAN - Manual Review Recommended"
        }
        else {
            "NOT VERIFIED - Recoverable Data Detected"
        }

        $statusColor = if ($OverallStatus -eq "VERIFIED*") {
            "SpringGreen"
        } elseif ($OverallStatus -eq "MOSTLY*") {
            "Yellow"
        } else {
            "Red"
        }

        # Console Output
        Write-Console "=====================================================" "Magenta"
        Write-Console "                 ANALYSIS RESULTS"
        Write-Console "=====================================================" "Magenta"
        Write-Console "Overall Status: $overallStatus" "$statusColor"

        Write-Console "Sector Analysis:" "SpringGreen"
        Write-Console "  Wiped Sectors      : $($results.Wiped) ($wipedPercent%)" "SpringGreen"
        Write-Console "  Suspicious Sectors : $($results.Suspicious)" "Yellow"
        Write-Console "  Not Wiped          : $($results.NotWiped)" $(if($results.NotWiped -gt 0){"Red"}else{"White"})
        Write-Console "  Unreadable         : $($results.Unreadable)" "Orange"

        Write-Console "Data Entropy: $entropyPercent% (100% = perfectly random)"

        Write-Console "Detected Patterns:" "SpringGreen"
        foreach ($pattern in $results.Patterns.GetEnumerator() | Sort-Object -Property Value -Descending) {
            Write-Console "  $($pattern.Key): $($pattern.Value) sectors" "Info"
        }

        # Data Leftover Summary
        $leftoverTotal = $dataLeftovers.Summary.TotalNotWiped + $dataLeftovers.Summary.TotalSuspicious
        if ($leftoverTotal -gt 0) {
            Write-Console "" "Info"
            Write-Console "Data Leftover Markers:" $(if($leftoverTotal -gt 0){"Red"}else{"SpringGreen"})
            Write-Console "  NOT Wiped sectors   : $($dataLeftovers.Summary.TotalNotWiped)" "Red"
            Write-Console "  Suspicious sectors  : $($dataLeftovers.Summary.TotalSuspicious)" "Yellow"
            Write-Console "  Markers stored      : $($dataLeftovers.Markers.Count)" "Info"
            if ($dataLeftovers.OverflowCount -gt 0) {
                Write-Console "  Overflow (not stored): $($dataLeftovers.OverflowCount)" "Orange"
            }
            Write-Console "  >> See report for sector addresses and hex previews <<" "Yellow"
        } else {
            Write-Console "" "Info"
            Write-Console "Data Leftover Markers: None - All sampled sectors are clean!" "SpringGreen"
        }

        # Generate Reports
        Write-Console "_____________________________________________________" "Gray"
        Write-Console "Generating Report(s)..." "Yellow"
        $StatusLabel.Text = "Status: Generating Report(s)..."
        DoEvents

        $htmlContent = New-HtmlReport -Technician $Technician -Results $results -Disk $disk -DiskNumber $DiskNumber `
    -DiskSize $diskSize -TotalSamples $totalSamples -WipedPercent $wipedPercent `
    -EntropyPercent $entropyPercent -OverallStatus $overallStatus -SectorSize $SectorSize `
    -DataLeftovers $dataLeftovers

        $htmlPath = "$ReportFile.html"
        $pdfPath = "$ReportFile.pdf"

        if ($ReportFormat -eq "HTML" -or $ReportFormat -eq "Both") {
            $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
            Write-Console "  HTML Report: $htmlPath" "Info"
        }

        if ($ReportFormat -eq "PDF" -or $ReportFormat -eq "Both") {
            # Always save HTML first for PDF conversion
            $tempHtml = if ($ReportFormat -eq "PDF") {
                $tempPath = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.html'
                $htmlContent | Out-File -FilePath $tempPath -Encoding UTF8
                $tempPath
            } else {
                $htmlPath
            }

            $pdfSuccess = Convert-HtmlToPdf -HtmlPath $tempHtml -PdfPath $pdfPath

            if ($pdfSuccess) {
                Write-Console "  PDF Report : $pdfPath" "SpringGreen"
            } else {
                Write-Console "  PDF generation failed. HTML report available instead." "Red"
                if ($ReportFormat -eq "PDF") {
                    # Move temp HTML to final location if PDF-only was requested but failed
                    Move-Item -Path $tempHtml -Destination $htmlPath -Force
                    Write-Console "  HTML Report: $htmlPath" "SpringGreen"
                }
            }

            # Clean up temp file if PDF-only and not moved
            if ($ReportFormat -eq "PDF" -and $pdfSuccess -and (Test-Path $tempHtml)) {
                Remove-Item -Path $tempHtml -Force
            }
        }

        Write-Console "_____________________________________________________" "Gray"

        ##########################################################
        # NOT NEEDED. WAS FOR OPENING REPORTS. CONSOLE INPUT -> NEW IS IN MSG BOX
        # Offer to open report
        #$openReport = Read-Host "Open report now? (Y/N)"
        #if ($openReport -eq 'Y' -or $openReport -eq 'y') {
        #    if ($ReportFormat -eq "PDF" -and (Test-Path $pdfPath)) {
        #        Start-Process $pdfPath
        #    } elseif (Test-Path $htmlPath) {
        #        Start-Process $htmlPath
        #    }
        #}
        ##########################################################
        # Offer to open report new
        $openReport = [System.Windows.Forms.MessageBox]::Show(
                "Scan complete!`n`nStatus: $overallStatus`n`nOpen the report now?",
                "Scan Complete",
                "YesNo",
                "Information"
        )

        if ($openReport -eq "Yes") {
            if ($reportFormat -eq "PDF" -or $reportFormat -eq "Both") {
                Start-Process "$reportFile.pdf"
            }
            else {
                Start-Process "$reportFile.html"
            }
        }

        Write-Console "Verification complete." "SpringGreen"
        $StatusLabel.Text = "Status: Verification Complete!"
        $VerificationPanel.Visible = $true
        $VerificationPanel.BackColor = Color 0 255 00
        $ResultLabel.Text = "Verification Complete"
        $ResultLabel.ForeColor = Color 0 0 0
        DoEvents
    }
    catch {
        Write-Console "ERROR: $_" "Red"
        $StatusLabel.Text = "Status: ERROR"
        $VerificationPanel.Visible = $true
        $VerificationPanel.BackColor = Color 255 0 0
        $ResultLabel.Text = "ERROR"
        $ResultLabel.ForeColor = Color 0 0 0
        DoEvents
        [System.Windows.Forms.MessageBox]::Show("An error occurred: $_", "Error", "OK", "Error")
    }
    finally {
        # Ensure disk stream is always closed, even on error/cancel
        if ($diskStream) {
            try { $diskStream.Close(); $diskStream.Dispose() } catch {}
            $diskStream = $null
        }
        # Re-enable UI
        $StartScan.Enabled = $true
        $CancelScan.Enabled = $false
        $DiskList.Enabled = $true
    }
}
