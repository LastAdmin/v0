# Disk Wipe Verification Tool

A PowerShell-based GUI application for verifying complete data sanitization on disk drives. Compliant with DoD 5220.22-M standards for detecting wipe patterns including zero-fill, one-fill, and random data passes.

## Features

- **DoD 5220.22-M Compatible** - Detects standard military wipe patterns including random final pass
- **Shannon Entropy Analysis** - Calculates data randomness to verify cryptographic wipes
- **File Signature Detection** - Identifies recoverable data by detecting common file headers (PDF, ZIP, JPEG, PNG, etc.)
- **Data Leftover Markers** - Flags and records sector addresses where potential data remnants are found, with hex/ASCII previews for manual forensic review
- **Low Memory Footprint** - Optimized to handle 100,000+ sector samples on systems with only 8GB RAM
- **Detailed Reports** - Generates HTML and PDF reports with comprehensive analysis results, including a dedicated data leftover section
- **GUI Interface** - User-friendly Windows Forms interface for easy operation

## Requirements

- **Operating System**: Windows 10/11 or Windows Server 2016+
- **PowerShell**: Version 5.1 or higher
- **Permissions**: Must run as Administrator (required for raw disk access)
- **RAM**: Minimum 4GB, recommended 8GB+

## Installation

1. Clone or download this repository
2. Ensure all files maintain their folder structure
3. Run the script as Administrator

## Usage

### Running the Application

```powershell
# Run as Administrator
.\Index.ps1
```

Or use the compiled executable:
```powershell
.\EXE.ps1
```

### GUI Operation

1. **Select Disk** - Choose the target disk from the dropdown list
2. **Enter Technician Name** - Required for report generation
3. **Configure Parameters**:
   - **Sample Size**: Number of sectors to analyze (default: 1,000)
   - **Sector Size**: Usually 512 bytes (standard) or 4096 bytes (Advanced Format)
   - **Full Disk Scan**: Check to scan every sector (warning: very slow on large disks)
4. **Set Report Options**:
   - Choose HTML, PDF, or Both
   - Select output directory
5. **Start Scan** - Click to begin verification

### Interpreting Results

| Status | Meaning |
|--------|---------|
| **VERIFIED CLEAN** | 99.5%+ sectors show wipe patterns - disk successfully sanitized |
| **MOSTLY CLEAN** | 95-99.5% wiped - manual review recommended |
| **NOT VERIFIED** | <95% wiped - recoverable data detected |

### Detected Wipe Patterns

- **Zero-filled (0x00)** - All bytes are zero
- **One-filled (0xFF)** - All bytes are 0xFF
- **Random data (DoD 5220.22-M)** - High entropy random overwrite
- **Cryptographic wipe** - Random data consistent with secure erase

## Project Structure

```
├── Index.ps1                    # Main entry point
├── Main.ps1                     # Core processing logic
├── Load-Components.ps1          # Component loader
├── EXE.ps1                      # Executable wrapper
│
├── Connectors/                  # Utility connectors
│   ├── DoEvents.ps1             # UI refresh handler
│   ├── Get-Parameters.ps1       # Parameter collection
│   └── Write-Console.ps1        # Console output handler
│
├── GUI/                         # User interface
│   ├── GUI.ps1                  # Main GUI setup
│   ├── ActionModules/           # Button handlers and actions
│   │   ├── Browse-Path.ps1
│   │   ├── Cancel-Scan.ps1
│   │   ├── Disk-List.ps1
│   │   ├── Full-DiskScan.ps1
│   │   ├── Load-Disks.ps1
│   │   └── Start-Scan.ps1
│   ├── Elements/                # UI components
│   └── NewElements/             # Component factories
│
└── Modules/                     # Analysis modules
    ├── Get-AvailableDisks.ps1        # Disk enumeration
    ├── Get-ByteDistributionScore.ps1 # Chi-square distribution test
    ├── Get-ByteHistogram.ps1         # Byte frequency histogram
    ├── Get-DataLeftoverMarkers.ps1   # Data leftover flagging & collection
    ├── Get-PrintableAsciiRatio.ps1   # ASCII content detection
    ├── Get-SampleLocations.ps1       # Sector sampling algorithm
    ├── Get-ShannonEntropy.ps1        # Entropy calculation
    ├── Read-DiskSector.ps1           # Raw disk I/O
    ├── Test-FileSignatures.ps1       # File header detection
    ├── Test-SectorWiped.ps1          # Wipe pattern analysis
    ├── New-HtmlReport.ps1            # Report generation
    └── Convert-HtmlToPdf.ps1         # PDF conversion
```

## Technical Details

### Memory Optimization

The tool uses several techniques to minimize memory usage:

1. **Streaming Histogram** - Instead of storing all read bytes in memory, a running 256-element histogram tracks byte frequencies. This uses ~2KB regardless of sample size.

2. **HashSet for Sampling** - Sample locations use a `HashSet<long>` for O(1) duplicate checking instead of array concatenation.

3. **Pre-allocated Collections** - Uses `List<T>` and typed arrays instead of ArrayList and hashtables.

**Memory Usage Comparison:**
| Sample Size | Old Algorithm | New Algorithm |
|-------------|---------------|---------------|
| 10,000 sectors | ~50 MB | ~2 MB |
| 100,000 sectors | ~500 MB | ~2 MB |
| 1,000,000 sectors | ~5 GB (fails) | ~2 MB |

### Sampling Strategy

The tool strategically samples:
- **First 100 sectors** - Boot sector and partition tables
- **Last 100 sectors** - End of disk markers
- **Random middle sectors** - Distributed across the disk

This ensures detection of:
- Incomplete wipes that missed the beginning/end
- Partition-specific remnants
- Statistically representative data patterns

### Entropy Thresholds

| Entropy Value | Interpretation |
|---------------|----------------|
| 0.0 | Completely uniform (all same byte) |
| < 5.0 | Structured data, likely recoverable |
| 5.0 - 7.0 | Compressed or partially random |
| > 7.0 | High randomness, likely wiped |
| > 7.5 | Very high randomness, cryptographic wipe |

Maximum possible entropy is 8.0 bits (perfectly random).

## File Signatures Detected

The tool checks for these file headers to identify recoverable data:

| Type | Signature | Bytes |
|------|-----------|-------|
| PDF | `%PDF-` | 5 |
| ZIP/DOCX | `PK..` | 4 |
| JPEG | `FF D8 FF E0` | 4 |
| PNG | `.PNG\r\n` | 6 |
| GIF | `GIF87a` / `GIF89a` | 6 |
| RAR | `Rar!..` | 6 |
| 7-Zip | `7z....` | 6 |
| SQLite | `SQLite` | 6 |
| NTFS | Boot sector | 7 |
| EXE | `MZ..` | 4 |

## Data Leftover Markers

When the scan encounters sectors classified as **NOT Wiped** or **Suspicious**, the tool creates a **data leftover marker** for each one. These markers are collected during the scan and included as a dedicated section in the HTML/PDF report.

### What is stored per marker

| Field | Description |
|-------|-------------|
| **Sector Number** | Logical sector index on the disk |
| **Byte Offset** | Hex and decimal byte offset (e.g., `0x0000FA00`) |
| **Status** | `NOT Wiped` or `Suspicious` |
| **Pattern** | What was detected (e.g., "File signature: PDF", "Text content detected") |
| **Confidence** | Analysis confidence percentage |
| **Hex Preview** | First 32 bytes in hex for manual inspection |
| **ASCII Preview** | First 32 bytes as printable ASCII (non-printable shown as `.`) |

### Report section

The report includes:
- A summary showing how many sectors were flagged (NOT Wiped vs. Suspicious)
- A pattern breakdown table showing which leftover types were found
- A detailed table listing each flagged sector with its address, hex preview, and ASCII preview

### Memory safeguard

The collection is capped at **500 markers** by default. If more than 500 sectors are flagged, the summary counts still reflect all of them but individual marker details are only stored for the first 500. The overflow count is noted in the report.

## Troubleshooting

### "Access Denied" Error
- Ensure PowerShell is running as Administrator
- Check if the disk is in use by another application

### Script Freezes
- Reduce sample size for low-memory systems
- Avoid "Full Disk Scan" on large drives
- Close other applications to free RAM

### PDF Generation Fails
- HTML report is still generated as fallback
- Check if sufficient disk space is available
- Verify write permissions to output directory

### Disk Not Listed
- Refresh the disk list
- Ensure disk is properly connected
- Check Device Manager for driver issues

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 3.8.0116.01 | 2026-01-08 | Initial release |
| 3.8.0116.02 | 2026-01-11 | Improved algorithms and reports |
| 3.8.0116.03 | 2026-01-12 | Modular architecture |
| 3.9.0203.01 | 2026-02-03 | Memory optimization for large sample sizes |
| 3.9.0209.01 | 2026-02-09 | Data leftover markers module, report section for manual review |

## Author

**Yannick Morgenthaler**  
Company: JSW  
Contact: yannick.morgenthaler@jsw.swiss

## License

Copyright (c) 2026 Yannick Morgenthaler. All rights reserved.

## Disclaimer

This tool performs READ-ONLY operations and does not modify disk contents. However, always ensure you have selected the correct disk before scanning. The authors are not responsible for any data loss or system issues resulting from the use of this software.
