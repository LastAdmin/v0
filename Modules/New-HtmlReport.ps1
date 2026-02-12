function New-HtmlReport {
    param(
        [string]$Technician,
        [hashtable]$Results,
        [object]$Disk,
        [int]$DiskNumber,
        [long]$DiskSize,
        [int]$TotalSamples,
        [double]$WipedPercent,
        [double]$EntropyPercent,
        [string]$OverallStatus,
        [int]$SectorSize,
        [object[]]$Leftovers = @(),
        [long]$TotalLeftoverCount = 0
    )

    $statusClass = if ($OverallStatus -like "VERIFIED*") {
        "verified"
    } elseif ($OverallStatus -like "MOSTLY*") {
        "warning"
    } else {
        "failed"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Disk Wipe Verification Report</title>
    <style>
        @media print {
            body { margin: 0; padding: 0; }
            .no-break { page-break-inside: avoid; }
        }
        @page {
            size: A4;
            margin: 15mm;
        }
        /* Removed grey background - now white with minimal margins */
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            margin: 0;
            padding: 20px 30px;
            background: white;
            font-size: 11pt;
            line-height: 1.4;
        }
        /* Removed container box styling that created the grey frame effect */
        .container {
            max-width: 100%;
            margin: 0 auto;
            background: white;
            padding: 0;
        }
        h1 {
            color: #1a1a1a;
            border-bottom: 3px solid #0078d4;
            padding-bottom: 10px;
            margin-top: 0;
            font-size: 22pt;
        }
        h2 {
            color: #333;
            margin-top: 25px;
            margin-bottom: 12px;
            font-size: 14pt;
            border-bottom: 1px solid #e0e0e0;
            padding-bottom: 5px;
        }
        .status-verified {
            background: #d4edda;
            color: #155724;
            padding: 15px;
            border-radius: 5px;
            font-size: 14pt;
            font-weight: bold;
            border-left: 5px solid #28a745;
            margin-bottom: 20px;
        }
        .status-warning {
            background: #fff3cd;
            color: #856404;
            padding: 15px;
            border-radius: 5px;
            font-size: 14pt;
            font-weight: bold;
            border-left: 5px solid #ffc107;
            margin-bottom: 20px;
        }
        .status-failed {
            background: #f8d7da;
            color: #721c24;
            padding: 15px;
            border-radius: 5px;
            font-size: 14pt;
            font-weight: bold;
            border-left: 5px solid #dc3545;
            margin-bottom: 20px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 10px 0 20px 0;
        }
        th, td {
            padding: 10px 12px;
            text-align: left;
            border: 1px solid #ddd;
            font-size: 10pt;
        }
        th {
            background: #f8f9fa;
            font-weight: 600;
            color: #333;
        }
        tr:nth-child(even) { background: #fafafa; }
        .metric {
            font-size: 28px;
            font-weight: bold;
            color: #0078d4;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 15px;
            margin: 15px 0 25px 0;
        }
        .card {
            background: #f8f9fa;
            padding: 18px;
            border-radius: 5px;
            text-align: center;
            border: 1px solid #e9ecef;
        }
        .card-label {
            font-size: 10pt;
            color: #666;
            margin-top: 5px;
        }
        .section-spacer {
            height: 30px;
        }
        .footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 2px solid #333;
            color: #333;
            font-size: 10pt;
        }
        .certification-box {
            background: #f8f9fa;
            border: 1px solid #ddd;
            padding: 15px;
            margin: 15px 0;
            border-radius: 5px;
        }
        .signature-section {
            display: flex;
            justify-content: space-between;
            margin-top: 40px;
            gap: 40px;
        }
        .signature-block {
            flex: 1;
            text-align: center;
        }
        .signature-line {
            border-top: 1px solid #333;
            margin-top: 50px;
            margin-bottom: 8px;
        }
        .signature-label {
            font-size: 10pt;
            color: #333;
        }
        .report-id {
            font-size: 9pt;
            color: #666;
            text-align: right;
            margin-bottom: 10px;
        }
        .page-break {
            page-break-before: always;
            margin-top: 40px;
        }
        .leftover-clean {
            background: #d4edda;
            color: #155724;
            padding: 15px;
            border-radius: 5px;
            border-left: 5px solid #28a745;
            margin: 10px 0 20px 0;
            font-size: 11pt;
        }
        .leftover-warning {
            background: #fff3cd;
            color: #856404;
            padding: 15px;
            border-radius: 5px;
            border-left: 5px solid #ffc107;
            margin: 10px 0 20px 0;
            font-size: 11pt;
        }
        .leftover-critical {
            background: #f8d7da;
            color: #721c24;
            padding: 15px;
            border-radius: 5px;
            border-left: 5px solid #dc3545;
            margin: 10px 0 20px 0;
            font-size: 11pt;
        }
        .hex-addr {
            font-family: 'Consolas', 'Courier New', monospace;
            font-size: 9pt;
        }
        .badge-not-wiped {
            background: #dc3545;
            color: white;
            padding: 2px 8px;
            border-radius: 3px;
            font-size: 9pt;
            font-weight: 600;
        }
        .badge-suspicious {
            background: #ffc107;
            color: #333;
            padding: 2px 8px;
            border-radius: 3px;
            font-size: 9pt;
            font-weight: 600;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="report-id">Report ID: WV-$(Get-Date -Format 'yyyyMMddHHmmss')-$([System.Guid]::NewGuid().ToString().Substring(0,8).ToUpper())</div>

        <h1>Disk Wipe Verification Report</h1>

        <div class="status-$statusClass">
            Verification Status: $OverallStatus
        </div>

        <div class="no-break">
            <h2>Disk Information</h2>
            <table>
                <tr><th style="width:35%">Property</th><th>Value</th></tr>
                <tr><td>Disk Number</td><td>$DiskNumber</td></tr>
                <tr><td>Model / Friendly Name</td><td>$($Disk.FriendlyName)</td></tr>
                <tr><td>Serial Number</td><td>$(if($Disk.SerialNumber){"$($Disk.SerialNumber)"}else{"N/A"})</td></tr>
                <tr><td>Capacity</td><td>$([math]::Round($DiskSize / 1GB, 2)) GB ($([math]::Round($DiskSize / 1TB, 3)) TB)</td></tr>
                <tr><td>Partition Style</td><td>$($Disk.PartitionStyle)</td></tr>
                <tr><td>Bus Type</td><td>$($Disk.BusType)</td></tr>
                <tr><td>Media Type</td><td>$($Disk.MediaType)</td></tr>
            </table>
        </div>

        <div class="section-spacer"></div>

        <div class="no-break">
            <h2>Analysis Summary</h2>
            <div class="grid">
                <div class="card">
                    <div class="metric">$WipedPercent%</div>
                    <div class="card-label">Sectors Verified Clean</div>
                </div>
                <div class="card">
                    <div class="metric">$TotalSamples</div>
                    <div class="card-label">Sectors Analyzed</div>
                </div>
                <div class="card">
                    <div class="metric">$EntropyPercent%</div>
                    <div class="card-label">Average Data Entropy</div>
                </div>
            </div>
        </div>

        <div class="section-spacer"></div>

        <div class="no-break">
            <h2>Detailed Sector Analysis</h2>
            <table>
                <tr><th>Category</th><th>Count</th><th>Percentage</th></tr>
                <tr><td>Wiped Sectors (Verified Clean)</td><td>$($Results.Wiped)</td><td>$WipedPercent%</td></tr>
                <tr><td>Suspicious Sectors</td><td>$($Results.Suspicious)</td><td>$([math]::Round(($Results.Suspicious / $TotalSamples) * 100, 2))%</td></tr>
                <tr><td>Not Wiped (Data Detected)</td><td>$($Results.NotWiped)</td><td>$([math]::Round(($Results.NotWiped / $TotalSamples) * 100, 2))%</td></tr>
                <tr><td>Unreadable Sectors</td><td>$($Results.Unreadable)</td><td>$([math]::Round(($Results.Unreadable / $TotalSamples) * 100, 2))%</td></tr>
            </table>
        </div>

        <div class="section-spacer"></div>

        <div class="no-break">
            <h2>Detected Wipe Patterns</h2>
            <table>
                <tr><th>Pattern Type</th><th>Occurrences</th></tr>
                $(foreach ($pattern in $Results.Patterns.GetEnumerator() | Sort-Object -Property Value -Descending) {
        "<tr><td>$($pattern.Key)</td><td>$($pattern.Value)</td></tr>"
    })
            </table>
        </div>

        <div class="section-spacer"></div>

        <div class="no-break">
            <h2>Data Leftover Analysis</h2>
$(if ($TotalLeftoverCount -eq 0) {
@"
            <div class="leftover-clean">
                <strong>No Data Leftovers Detected</strong><br>
                All analyzed sectors show wipe patterns consistent with successful data sanitization.
                No residual data, file signatures, or structured content was found. No manual review is required.
            </div>
"@
} elseif ($TotalLeftoverCount -le 50) {
@"
            <div class="leftover-warning">
                <strong>$($TotalLeftoverCount.ToString('N0')) Sector(s) With Potential Data Detected</strong><br>
                The following sectors contain data patterns that are inconsistent with a complete wipe.
                A manual review of these addresses is recommended to determine if recoverable data is present.
            </div>
"@
} else {
@"
            <div class="leftover-critical">
                <strong>$($TotalLeftoverCount.ToString('N0')) Sector(s) With Potential Data Detected</strong><br>
                A significant number of sectors contain residual data. This may indicate an incomplete wipe.
                The table below shows the first $($Leftovers.Count) findings. A full manual review is strongly recommended.
            </div>
"@
})
$(if ($TotalLeftoverCount -gt 0) {
    $tableRows = ""
    $rowNum = 0
    foreach ($entry in $Leftovers) {
        $rowNum++
        $hexOffset = "0x{0:X}" -f $entry.DiskOffset
        $statusBadge = if ($entry.Status -eq "NOT Wiped") {
            '<span class="badge-not-wiped">NOT Wiped</span>'
        } else {
            '<span class="badge-suspicious">Suspicious</span>'
        }
        $tableRows += "<tr><td>$rowNum</td><td class=`"hex-addr`">$($entry.SectorNumber.ToString('N0'))</td><td class=`"hex-addr`">$hexOffset</td><td>$statusBadge</td><td>$($entry.Pattern)</td><td>$($entry.Confidence)%</td></tr>`n"
    }
@"
            <table>
                <tr>
                    <th style="width:5%">#</th>
                    <th style="width:15%">Sector Number</th>
                    <th style="width:18%">Disk Offset</th>
                    <th style="width:12%">Status</th>
                    <th>Detected Pattern</th>
                    <th style="width:10%">Confidence</th>
                </tr>
                $tableRows
            </table>
"@
    if ($TotalLeftoverCount -gt $Leftovers.Count) {
@"
            <p style="font-size:10pt; color:#666; font-style:italic;">
                Showing $($Leftovers.Count) of $($TotalLeftoverCount.ToString('N0')) total findings.
                The remaining $( ($TotalLeftoverCount - $Leftovers.Count).ToString('N0') ) sector addresses exceeded the report detail limit.
            </p>
"@
    }
})
        </div>

        <div class="section-spacer"></div>

        <div class="no-break">
            <h2>Verification Methodology</h2>
            <table>
                <tr><th style="width:35%">Parameter</th><th>Value</th></tr>
                <tr><td>Verification Date</td><td>$(Get-Date -Format 'yyyy-MM-dd')</td></tr>
                <tr><td>Verification Time</td><td>$(Get-Date -Format 'HH:mm:ss')</td></tr>
                <tr><td>Computer Name</td><td>$env:COMPUTERNAME</td></tr>
                <tr><td>Performed By</td><td>$Technician</td></tr>
                <tr><td>Sampling Method</td><td>Statistical sampling (Start, End, Random Middle)</td></tr>
                <tr><td>Sector Size</td><td>$SectorSize bytes</td></tr>
                <tr><td>Detection Method</td><td>Shannon entropy, byte distribution, file signature analysis</td></tr>
                <tr><td>Compatible Standards</td><td>DoD 5220.22-M, NIST 800-88</td></tr>
            </table>
        </div>

        <div class="page-break"></div>

        <div class="no-break">
            <h2>Certification</h2>
            <div class="certification-box">
                <p><strong>Data Sanitization Verification Statement</strong></p>
                <p>This document certifies that the storage device identified above has been analyzed using sector-level raw disk access and statistical sampling methods. The verification process examined $TotalSamples sectors across the beginning, end, and randomly selected middle portions of the disk to determine data sanitization status.</p>
                <p>The analysis methodology is designed to detect common wipe patterns including zero-fill, one-fill, and cryptographic random data patterns (such as those produced by DoD 5220.22-M). The presence of file signatures, text content, and data structures is actively scanned to identify any recoverable information.</p>
            </div>

            <div class="signature-section">
                <div class="signature-block">
                    <div class="signature-line"></div>
                    <div class="signature-label">Technician Name (Print)</div>
                </div>
                <div class="signature-block">
                    <div class="signature-line"></div>
                    <div class="signature-label">Technician Signature</div>
                </div>
                <div class="signature-block">
                    <div class="signature-line"></div>
                    <div class="signature-label">Date</div>
                </div>
            </div>

            <!-- Changed "Witness" to "Supervisor" -->
            <div class="signature-section" style="margin-top: 30px;">
                <div class="signature-block">
                    <div class="signature-line"></div>
                    <div class="signature-label">Supervisor Name (Print)</div>
                </div>
                <div class="signature-block">
                    <div class="signature-line"></div>
                    <div class="signature-label">Supervisor Signature</div>
                </div>
                <div class="signature-block">
                    <div class="signature-line"></div>
                    <div class="signature-label">Date</div>
                </div>
            </div>
        </div>

        <div class="footer">
            <p style="text-align: center; color: #666; font-size: 9pt;">
                Generated by Disk Wipe Verification Tool v2.1 | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            </p>
        </div>
    </div>
</body>
</html>
"@

    return $html
}
