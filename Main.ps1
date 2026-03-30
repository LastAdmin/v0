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
            . .\Modules\New-HtmlReport.ps1
            . .\Modules\Convert-HtmlToPdf.ps1
            # Load compiled C# analysis engine for high-performance scanning
            . .\Modules\DiskAnalysisEngine.ps1
            Write-Console "Modules Successfully Loaded!" "SpringGreen"
        }
        catch {
            Write-Console "ERROR: could not load modules: $_" "Red"
            exit 1
        }

        # Load file signatures into compiled engine
        Write-Console "Load File Signatures..." "Yellow"
        $StatusLabel.Text = "Status: Load File Signatures..."
        DoEvents
        $FileSignatures = @{
            "PDF"      = [byte[]]@(0x25, 0x50, 0x44, 0x46, 0x2D)       # %PDF- (5 bytes)
            "ZIP/DOCX" = [byte[]]@(0x50, 0x4B, 0x03, 0x04)             # PK.. (4 bytes)
            "JPEG"     = [byte[]]@(0xFF, 0xD8, 0xFF, 0xE0)             # JPEG with JFIF (4 bytes)
            "PNG"      = [byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A) # .PNG\r\n (6 bytes)
            "GIF87"    = [byte[]]@(0x47, 0x49, 0x46, 0x38, 0x37, 0x61) # GIF87a (6 bytes)
            "GIF89"    = [byte[]]@(0x47, 0x49, 0x46, 0x38, 0x39, 0x61) # GIF89a (6 bytes)
            "RAR"      = [byte[]]@(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07) # Rar!.. (6 bytes)
            "7Z"       = [byte[]]@(0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C) # 7z.... (6 bytes)
            "SQLite"   = [byte[]]@(0x53, 0x51, 0x4C, 0x69, 0x74, 0x65) # SQLite (6 bytes)
            "NTFS"     = [byte[]]@(0xEB, 0x52, 0x90, 0x4E, 0x54, 0x46, 0x53) # NTFS boot sector (7 bytes)
            "EXE"      = [byte[]]@(0x4D, 0x5A, 0x90, 0x00)             # MZ with valid header (4 bytes)
        }

        # Pass signatures to the compiled C# engine
        $sigNames = [string[]]($FileSignatures.Keys)
        $sigBytesArr = [byte[][]]($sigNames | ForEach-Object { ,$FileSignatures[$_] })
        [DiskAnalysisEngine]::SetSignatures($sigBytesArr, $sigNames)

        Write-Console "Loaded File Signatures:" "Magenta"
        Write-Console "$($sigNames -join ', ')" "Info"

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

        # Determine if this is a full disk scan (sequential) or sample scan (random)
        $isFullDiskScan = $FullDiskCheckBox.Checked

        if ($isFullDiskScan) {
            Write-Console "Full Disk Scan: scanning all $($totalSectors.ToString('N0')) sectors sequentially..." "Yellow"
            $StatusLabel.Text = "Status: Full Disk Scan - sequential read..."
            DoEvents
            $totalSamples = $totalSectors
        } else {
            Write-Console "Build Sample Locations..." "Yellow"
            $StatusLabel.Text = "Status: Build Sample Locations..."
            DoEvents
            $sampleLocations = Get-SampleLocations -TotalSectors $totalSectors -SampleSize $sampleSize
            $totalSamples = $sampleLocations.Count
            Write-Console "Sampling $totalSamples sectors..." "Yellow"
        }

        # Initialize results and compiled engine counters
        Write-Console "Initialize Analysis Engine..." "Yellow"
        $StatusLabel.Text = "Status: Initialize Analysis Engine..."
        DoEvents

        [DiskAnalysisEngine]::ResetGlobalCounters()
        $patternCounts = New-Object 'System.Collections.Generic.Dictionary[string,int]'

        $results = @{
            Wiped = 0
            NotWiped = 0
            Suspicious = 0
            Unreadable = 0
        }

        Write-Console "Analyzing $($totalSamples.ToString('N0')) sectors..." "Yellow"

        # Open the disk stream once for the entire scan
        # Note: .NET FileStream blocks device paths (\\.\PhysicalDrive), so we use
        # the RawDiskAccess helper which calls Win32 CreateFile directly via P/Invoke
        $diskStream = $null
        try {
            $diskStream = [RawDiskAccess]::OpenDisk($diskPath)
        }
        catch {
            Write-Console "ERROR: Could not open disk stream: $_" "Red"
            Write-Console "Make sure you are running as Administrator." "Yellow"
            throw
        }

        # I/O buffer: 2048 sectors per chunk = 1MB at 512-byte sectors
        # This is the sweet spot for sequential disk reads
        $chunkSectors = 2048
        $chunkBuffer = New-Object byte[] ($SectorSize * $chunkSectors)

        # Reusable buffer for single-sector reads (sample mode)
        $readBuffer = New-Object byte[] $SectorSize

        $progress = [long]0
        $lastUiUpdate = [System.Diagnostics.Stopwatch]::StartNew()
        $scanTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $uiUpdateIntervalMs = 250  # Refresh UI every 250ms

        if ($isFullDiskScan) {
            # ===== FULL DISK: read sequential 1MB chunks, process entirely in C# =====
            $sectorIndex = [long]0
            while ($sectorIndex -lt $totalSectors) {
                if ($script:cancelRequested) {
                    Write-Console "Scan cancelled by user." "Red"
                    $StatusLabel.Text = "Status: Scan cancelled by user."
                    break
                }

                # Calculate chunk size
                $remainingSectors = $totalSectors - $sectorIndex
                $currentChunkSectors = [math]::Min($chunkSectors, $remainingSectors)
                $bytesToRead = [int]($currentChunkSectors * $SectorSize)

                # Single I/O read for the entire chunk (sequential = no seek needed)
                try {
                    $bytesRead = $diskStream.Read($chunkBuffer, 0, $bytesToRead)
                }
                catch {
                    $bytesRead = 0
                }

                if ($bytesRead -le 0) {
                    # End of readable area
                    $results.Unreadable += $currentChunkSectors
                    $sectorIndex += $currentChunkSectors
                    $progress += $currentChunkSectors
                    continue
                }

                # Adjust actual sector count if a partial read occurred at the end of the disk
                $actualSectorsRead = [math]::Floor($bytesRead / $SectorSize)
                if ($actualSectorsRead -le 0) {
                    $results.Unreadable += $currentChunkSectors
                    $sectorIndex += $currentChunkSectors
                    $progress += $currentChunkSectors
                    continue
                }
                $unreadableInChunk = $currentChunkSectors - $actualSectorsRead
                if ($unreadableInChunk -gt 0) { $results.Unreadable += $unreadableInChunk }

                # Process only the bytes that were actually read
                $chunkStats = [DiskAnalysisEngine]::AnalyzeChunk($chunkBuffer, [int]($actualSectorsRead * $SectorSize), $SectorSize, $patternCounts, [long]$sectorIndex)

                $results.Wiped      += $chunkStats.Wiped
                $results.NotWiped   += $chunkStats.NotWiped
                $results.Suspicious += $chunkStats.Suspicious
                $results.Unreadable += $chunkStats.Unreadable

                $progress += $currentChunkSectors
                $sectorIndex += $currentChunkSectors

                # Throttled UI update
                if ($lastUiUpdate.ElapsedMilliseconds -ge $uiUpdateIntervalMs) {
                    $percent = [math]::Round(($progress / $totalSamples) * 100, 1)
                    $ScanProgress.Value = [math]::Min([int]$percent, 100)
                    $ProgressLabel.Text = "$percent%"

                    # Calculate speed and ETA
                    $elapsedSec = $scanTimer.Elapsed.TotalSeconds
                    if ($elapsedSec -gt 0) {
                        $sectorsPerSec = [math]::Round($progress / $elapsedSec)
                        $mbPerSec = [math]::Round(($sectorsPerSec * $SectorSize) / 1MB, 1)
                        $remainSectors = $totalSamples - $progress
                        $etaSec = if ($sectorsPerSec -gt 0) { [math]::Round($remainSectors / $sectorsPerSec) } else { 0 }
                        $eta = [TimeSpan]::FromSeconds($etaSec)
                        $StatusLabel.Text = "Status: $($sectorIndex.ToString('N0'))/$($totalSectors.ToString('N0')) | ${mbPerSec} MB/s | ETA: $($eta.ToString('hh\:mm\:ss'))"
                    }

                    DoEvents
                    $lastUiUpdate.Restart()
                }
            }
        } else {
            # ===== SAMPLE SCAN: read individual sectors, analyze each in C# =====
            foreach ($sectorNum in $sampleLocations) {
                if ($script:cancelRequested) {
                    Write-Console "Scan cancelled by user." "Red"
                    $StatusLabel.Text = "Status: Scan cancelled by user."
                    break
                }

                $progress++

                $offset = [long]$sectorNum * $SectorSize

                # Guard: skip sectors beyond the readable stream length
                try {
                    $diskStream.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $bytesRead = $diskStream.Read($readBuffer, 0, $SectorSize)
                }
                catch {
                    $bytesRead = 0
                }

                if ($bytesRead -lt $SectorSize) {
                    $results.Unreadable++
                    if (-not $patternCounts.ContainsKey("N/A")) { $patternCounts["N/A"] = 0 }
                    $patternCounts["N/A"]++
                    continue
                }

                # Analyze single sector in compiled C#
                $sectorResult = [DiskAnalysisEngine]::AnalyzeSector($readBuffer, 0, $SectorSize)

                switch ($sectorResult.Status) {
                    0 { $results.Wiped++ }
                    1 {
                        $results.NotWiped++
                        [DiskAnalysisEngine]::RecordLeftover([long]$sectorNum, $SectorSize, $sectorResult)
                    }
                    2 {
                        $results.Suspicious++
                        [DiskAnalysisEngine]::RecordLeftover([long]$sectorNum, $SectorSize, $sectorResult)
                    }
                    3 { $results.Unreadable++ }
                }

                if ($patternCounts.ContainsKey($sectorResult.Pattern)) {
                    $patternCounts[$sectorResult.Pattern]++
                } else {
                    $patternCounts[$sectorResult.Pattern] = 1
                }

                # Throttled UI update
                if ($lastUiUpdate.ElapsedMilliseconds -ge $uiUpdateIntervalMs) {
                    $percent = [math]::Round(($progress / $totalSamples) * 100, 1)
                    $ScanProgress.Value = [math]::Min([int]$percent, 100)
                    $ProgressLabel.Text = "$percent%"

                    $elapsedSec = $scanTimer.Elapsed.TotalSeconds
                    if ($elapsedSec -gt 0) {
                        $sectorsPerSec = [math]::Round($progress / $elapsedSec)
                        $remainSectors = $totalSamples - $progress
                        $etaSec = if ($sectorsPerSec -gt 0) { [math]::Round($remainSectors / $sectorsPerSec) } else { 0 }
                        $eta = [TimeSpan]::FromSeconds($etaSec)
                        $StatusLabel.Text = "Status: Sector $sectorNum | $sectorsPerSec sectors/s | ETA: $($eta.ToString('hh\:mm\:ss'))"
                    }

                    DoEvents
                    $lastUiUpdate.Restart()
                }
            }
        }

        # Close the disk stream
        if ($diskStream) {
            $diskStream.Close()
            $diskStream.Dispose()
            $diskStream = $null
        }

        # Final UI update to 100%
        $ScanProgress.Value = 100
        $ProgressLabel.Text = "100%"
        $scanElapsed = $scanTimer.Elapsed
        Write-Console "Sector Scan Completed in $($scanElapsed.ToString('hh\:mm\:ss'))" "SpringGreen"
        $StatusLabel.Text = "Status: Sector Scan Completed in $($scanElapsed.ToString('hh\:mm\:ss'))"
        DoEvents

        # Calculate overall entropy from the compiled engine's global counters
        Write-Console "Calculate overall entropy..." "Yellow"
        $StatusLabel.Text = "Status: Calculate overall entropy..."
        DoEvents
        $overallEntropy = [DiskAnalysisEngine]::ComputeGlobalEntropy()
        $entropyPercent = [math]::Round(($overallEntropy / 8) * 100, 2)

        # Convert pattern counts dictionary to hashtable for report compatibility
        $results.Patterns = @{}
        foreach ($kv in $patternCounts.GetEnumerator()) {
            $results.Patterns[$kv.Key] = $kv.Value
        }

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

        $statusColor = if ($overallStatus -like "VERIFIED*") {
            "SpringGreen"
        } elseif ($overallStatus -like "MOSTLY*") {
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

        # Retrieve leftover data from the compiled engine
        $leftovers = [DiskAnalysisEngine]::GetLeftovers()
        $totalLeftoverCount = [DiskAnalysisEngine]::GetTotalLeftoverCount()

        Write-Console "Leftover sectors with potential data: $($totalLeftoverCount.ToString('N0'))" $(if($totalLeftoverCount -gt 0){"Yellow"}else{"SpringGreen"})

        #Retrieve HardwareInfo for SerialNumber
        Write-Console "_____________________________________________________" "Gray"
        Write-Console "Retrieve Hardware Info..." "Yellow"
        $StatusLabel.Text = "Status: Retrieve Hardware Info..."
        DoEvents
        $HardwareInfo = Get-HardwareInfo

        # Generate Reports
        Write-Console "_____________________________________________________" "Gray"
        Write-Console "Generating Report(s)..." "Yellow"
        $StatusLabel.Text = "Status: Generating Report(s)..."
        DoEvents

        $htmlContent = New-HtmlReport -Technician $Technician -Results $results -Disk $disk -DiskNumber $DiskNumber `
    -DiskSize $diskSize -TotalSamples $totalSamples -WipedPercent $wipedPercent `
    -EntropyPercent $entropyPercent -OverallStatus $overallStatus -SectorSize $SectorSize `
    -Leftovers $leftovers -TotalLeftoverCount $totalLeftoverCount -ComputerSerial $HardwareInfo.BiosSN

        $htmlPath = "$ReportFile.html"
        $pdfPath = "$ReportFile.pdf"

        if (-not (Test-Path $ReportPath)) {
            mkdir $ReportPath | Out-Null
        }

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
        # Ensure disk stream is always closed
        if ($diskStream) {
            try {
                $diskStream.Close()
                $diskStream.Dispose()
            } catch { }
            $diskStream = $null
        }

        # Re-enable UI
        $StartScan.Enabled = $true
        $CancelScan.Enabled = $false
        $DiskList.Enabled = $true
    }
}
