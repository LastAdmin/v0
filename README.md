# Disk Wipe Verification Tool

A PowerShell-based tool for verifying complete data sanitization of storage devices. Validates wipe operations against DoD 5220.22-M and NIST 800-88 standards by analyzing raw disk sectors and generating professional verification reports.

## Requirements

- **Operating System:** Windows 10/11 or Windows Server 2016+
- **PowerShell:** Version 5.1 or later
- **Privileges:** Administrator (Run as Administrator required)
- **PDF Export (optional):** Microsoft Edge, Google Chrome, Brave, wkhtmltopdf, or Microsoft Word

## Quick Start

1. Right-click `EXE.ps1` and select **Run with PowerShell**, or open an elevated PowerShell terminal and run:
   ```powershell
   Set-Location "C:\Path\To\DiskWipeVerification"
   .\EXE.ps1
   ```

2. In the GUI:
   - Enter your **Technician Name**
   - Select the **target disk** from the list on the right
   - Set your desired **Sample Size** (number of random sectors to check) or enable **Full Disk Scan**
   - Choose the **Sector Size** (512 bytes default)
   - Select the **Report Format** (HTML, PDF, or Both)
   - Set the **Report Location** (output folder)
   - Click **Start Scan**

3. When the scan completes, a dialog offers to open the generated report.

## Scan Modes

### Sample Scan (Default)
Reads a configurable number of random sectors across the disk surface. Fast and statistically representative. Sectors are sampled from the first 100 sectors, last 100 sectors, and random positions in between.

### Full Disk Scan
Reads every sector on the disk sequentially. Uses a compiled C# analysis engine with 1 MB I/O batches for maximum throughput. Provides a complete verification but takes longer depending on disk size and speed.

## What the Report Contains

- **Verification Status:** VERIFIED CLEAN / MOSTLY CLEAN / NOT VERIFIED
- **Disk Information:** Model, serial number, capacity, partition style, bus type, media type
- **Analysis Summary:** Wiped percentage, sectors analyzed, data entropy percentage
- **Detailed Sector Analysis:** Wiped / Suspicious / Not Wiped / Unreadable counts
- **Detected Wipe Patterns:** Zero-fill, one-fill, random data (DoD), cryptographic wipe, file signatures, etc.
- **Data Leftover Analysis:** Lists sector addresses where potential residual data was detected, or confirms no leftovers were found
- **Verification Methodology:** Date, technician, sampling method, detection method, standards
- **Certification Page:** Signature lines for technician and supervisor

## Detection Capabilities

The tool detects the following patterns:

| Pattern | Description |
|---------|-------------|
| Zero-filled (0x00) | All bytes are zero -- standard wipe pass |
| One-filled (0xFF) | All bytes are 0xFF -- standard wipe pass |
| Random data (DoD 5220.22-M) | High entropy + uniform distribution = final random pass |
| Random data (cryptographic wipe) | Cryptographically random data pattern |
| File signatures | PDF, ZIP/DOCX, JPEG, PNG, GIF, RAR, 7Z, SQLite, NTFS, EXE |
| Text content | High printable ASCII ratio indicating readable text |
| Structured data | Low entropy patterns indicating organized data |
| Compressed/encrypted data | Medium entropy, low ASCII, possible compressed files |

## Cancellation

Click **Cancel Scan** at any time. The scan stops at the next sector boundary, and the GUI re-enables all controls.

## Output Files

Reports are saved to the configured report location with the naming format:
```
DiskWipeReport_YYYYMMDD_HHmmss.html
DiskWipeReport_YYYYMMDD_HHmmss.pdf
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Access Denied" errors | Run PowerShell as Administrator |
| No disks listed | Check that the target disk is connected and visible in Disk Management |
| PDF generation fails | Install Edge, Chrome, or wkhtmltopdf -- the tool falls back automatically |
| Script execution blocked | Run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` |
| GUI freezes during scan | This should not happen with the current version. File a bug report. |

## License

Copyright (c) 2026 Yannick Morgenthaler / JSW. All rights reserved.

## Contact

- Yannick Morgenthaler
- yannick.morgenthaler@jsw.swiss
- yannick@n1x.ch
- yannick@projectresilience.ch
- yannick.morgenthaler@4058.net
