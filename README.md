# Disk Wipe Verification Tool

A PowerShell-based GUI application for verifying complete data sanitization on disk drives. Compliant with DoD 5220.22-M and NIST 800-88 standards for detecting wipe patterns including zero-fill, one-fill, and random data passes.

## Features

- **DoD 5220.22-M Compatible** - Detects standard military wipe patterns including random final pass
- **NIST 800-88 Compliant** - Meets media sanitization guidelines
- **Compiled C# Analysis Engine** - All byte-level analysis runs in compiled .NET code for maximum throughput (100-500x faster than interpreted PowerShell)
- **Shannon Entropy Analysis** - Calculates data randomness to verify cryptographic wipes
- **File Signature Detection** - Identifies recoverable data by detecting common file headers (PDF, ZIP, JPEG, PNG, etc.)
- **Data Leftover Markers** - Flags and records sector addresses where potential data remnants are found, with hex/ASCII previews for manual forensic review
- **Low Memory Footprint** - Optimized to handle full disk scans on systems with only 8GB RAM using streaming counters (~2MB regardless of disk size)
- **Batched I/O** - Full disk scans use 1 MB sequential reads for optimal throughput
- **Detailed Reports** - Generates HTML and PDF reports with comprehensive analysis results, including a dedicated data leftover section
- **GUI Interface** - User-friendly Windows Forms interface with dark theme
- **Debug Mode** - Menu option to unlock sample size controls for smaller test runs

<div style="page-break-after: always;"></div>

## Requirements

- **Operating System**: Windows 10/11 or Windows Server 2016+
- **PowerShell**: Version 5.1 or higher
- **Permissions**: Must run as Administrator (required for raw disk access)
- **RAM**: Minimum 4GB, recommended 8GB+
- **PDF Export (optional):** Microsoft Edge, Google Chrome, Brave, wkhtmltopdf, or Microsoft Word

## Installation

1. Clone or download this repository
2. Ensure all files maintain their folder structure
3. Run the script as Administrator

<div style="page-break-after: always;"></div>

## Usage

### Running the Application

```powershell
# Run as Administrator
Set-Location "C:\Path\To\DiskWipeVerification"
.\EXE.ps1
```

Or if the script is blocked:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\EXE.ps1
```

### GUI Operation

1. **Enter Technician Name** - Required for report generation
2. **Select Disk** - Choose the target disk from the list on the right panel
3. **Configure Scan Mode**:
   - **Full Disk Scan** (default, locked) - Scans every sector sequentially using the compiled C# engine with 1 MB I/O batches
   - **Debug Mode** - Enable via Options menu to unlock sample size controls for smaller test runs
4. **Set Sector Size**: Usually 512 bytes (standard) or 4096 bytes (Advanced Format)
5. **Set Report Options**:
   - Choose HTML, PDF, or Both
   - Select output directory
6. **Start Scan** - Click to begin verification
7. When the scan completes, a dialog offers to open the generated report

<div style="page-break-after: always;"></div>

### Scan Modes

#### Full Disk Scan (Default)
Reads every sector on the disk sequentially. Uses the compiled C# analysis engine with 1 MB I/O batches (2048 sectors per read) for maximum throughput. Provides a complete verification but takes longer depending on disk size and speed.

#### Sample Scan (Debug Mode)
Reads a configurable number of random sectors across the disk surface. Fast and statistically representative. Sectors are sampled from the first 100 sectors, last 100 sectors, and random positions in between. Enable via Options > Debug Mode.

### Interpreting Results

| Status | Meaning |
|--------|---------|
| **VERIFIED CLEAN** | 99.5%+ sectors show wipe patterns - disk successfully sanitized |
| **MOSTLY CLEAN** | 95-99.5% wiped - manual review recommended |
| **NOT VERIFIED** | <95% wiped - recoverable data detected |

<div style="page-break-after: always;"></div>

### Detected Wipe Patterns

- **Zero-filled (0x00)** - All bytes are zero
- **One-filled (0xFF)** - All bytes are 0xFF
- **Random data (DoD 5220.22-M)** - High entropy + uniform distribution (final random pass)
- **Random data (cryptographic wipe)** - Cryptographically random data pattern
- **File signatures** - PDF, ZIP/DOCX, JPEG, PNG, GIF, RAR, 7Z, SQLite, NTFS, EXE
- **Text content** - High printable ASCII ratio indicating readable text
- **Structured data** - Low entropy patterns indicating organized data
- **Compressed/encrypted data** - Medium entropy, low ASCII, possible compressed files

### Cancellation

Click **Cancel Scan** at any time. The scan stops at the next sector/chunk boundary, and the GUI re-enables all controls.

<div style="page-break-after: always;"></div>

### What the Report Contains

- **Verification Status:** VERIFIED CLEAN / MOSTLY CLEAN / NOT VERIFIED
- **Disk Information:** Model, serial number, capacity, partition style, bus type, media type
- **Analysis Summary:** Wiped percentage, sectors analyzed, data entropy percentage
- **Detailed Sector Analysis:** Wiped / Suspicious / Not Wiped / Unreadable counts
- **Detected Wipe Patterns:** Frequency table of all pattern types found
- **Data Leftover Analysis:** Lists sector addresses where potential residual data was detected, or confirms no leftovers were found
- **Verification Methodology:** Date, technician, sampling method, detection method, standards
- **Certification Page:** Signature lines for technician and supervisor

### Output Files

Reports are saved to the configured report location with the naming format:
```
DiskWipeReport_YYYYMMDD_HHmmss.html
DiskWipeReport_YYYYMMDD_HHmmss.pdf
```

<div style="page-break-after: always;"></div>

## Project Structure

```
DiskWipeVerification/
|
+-- EXE.ps1                          # Entry point (convertible to .exe)
+-- Load-Components.ps1              # Component bootstrap loader
+-- Index.ps1                        # Module and connector loader
+-- Main.ps1                         # Core scanning logic
|
+-- Modules/                         # Analysis modules
|   +-- DiskAnalysisEngine.ps1       # Compiled C# engine (hot path)
|   +-- Get-AvailableDisks.ps1       # Disk enumeration
|   +-- Get-ByteDistributionScore.ps1 # Chi-square distribution test (legacy)
|   +-- Get-ByteHistogram.ps1        # Byte frequency histogram (legacy)
|   +-- Get-DataLeftoverMarkers.ps1  # Data leftover flagging & collection (legacy)
|   +-- Get-PrintableAsciiRatio.ps1  # ASCII content detection (legacy)
|   +-- Get-SampleLocations.ps1      # Sector sampling algorithm
|   +-- Get-ShannonEntropy.ps1       # Entropy calculation (legacy)
|   +-- Read-DiskSector.ps1          # Raw disk I/O (legacy, single-sector)
|   +-- Test-FileSignatures.ps1      # File header detection (legacy)
|   +-- Test-SectorWiped.ps1         # Wipe pattern analysis (legacy)
|   +-- New-HtmlReport.ps1           # HTML report generation
|   +-- Convert-HtmlToPdf.ps1        # PDF conversion (multi-browser fallback)
|
+-- Connectors/                      # Utility connectors
|   +-- DoEvents.ps1                 # UI refresh handler
|   +-- Get-Parameters.ps1           # Parameter collection
|   +-- Write-Console.ps1            # Console output handler
|
+-- GUI/                             # User interface
|   +-- GUI.ps1                      # Main GUI setup (includes menu bar)
|   +-- ActionModules/               # Button handlers and actions
|   |   +-- Browse-Path.ps1
|   |   +-- Cancel-Scan.ps1
|   |   +-- DataGridView-DoubleClick.ps1
|   |   +-- Disk-List.ps1
|   |   +-- Full-DiskScan.ps1
|   |   +-- Load-Disks.ps1
|   |   +-- Start-Scan.ps1
|   +-- Elements/                    # UI components
|   |   +-- BaseSettings.ps1         # Global UI settings (Color, Size, Location, FontSize helpers)
|   |   +-- LeftPanel.ps1
|   |   +-- RightPanel.ps1
|   |   +-- Console.ps1
|   |   +-- DiskList.ps1
|   |   +-- SampleSize.ps1           # Disabled by default (locked to full scan)
|   |   +-- SectorSize.ps1
|   |   +-- FullDiskCheckBox.ps1     # Checked and disabled by default
|   |   +-- ReportFormat.ps1
|   |   +-- ReportLocation.ps1
|   |   +-- ScanProgress.ps1
|   |   +-- StartScan.ps1
|   |   +-- CancelScan.ps1
|   |   +-- VerificationPanel.ps1
|   |   +-- ResultLabel.ps1
|   |   +-- ... (additional elements)
|   +-- NewElements/                 # Component factories
|       +-- New-Button.ps1
|       +-- New-CheckBox.ps1
|       +-- New-ComboBox.ps1
|       +-- New-DataGridView.ps1
|       +-- New-GroupBox.ps1
|       +-- New-Label.ps1
|       +-- New-ListBox.ps1
|       +-- New-NumericUpDown.ps1
|       +-- New-Panel.ps1
|       +-- New-ProgressBar.ps1
|       +-- New-RichTextBox.ps1
|       +-- New-StatusBar.ps1
|       +-- New-StatusBarLabel.ps1
|       +-- New-StatusBarProgressBar.ps1
|       +-- New-TextBox.ps1
|
+-- README.md                        # This file
+-- DEEPCODE.md                      # Deep code-level documentation
+-- DOCUMENTATION.md                 # Technical documentation
```

<div style="page-break-after: always;"></div>

## Technical Details

### Compiled C# Analysis Engine

Starting with v4.0, all byte-level analysis runs in a compiled C# class (`DiskAnalysisEngine`) loaded via `Add-Type`. This replaces the original interpreted PowerShell modules in the hot path, providing 100-500x throughput improvement. The engine performs entropy computation, byte distribution analysis, ASCII ratio calculation, file signature matching, and sector classification in a single compiled loop per sector.

### Memory Optimization

The tool uses several techniques to minimize memory usage:

1. **Streaming Counters** - Instead of storing all read bytes in memory, the C# engine maintains a 256-element `long[]` frequency table (~2KB) plus counters for total bytes and printable ASCII. Memory usage is constant regardless of disk size.

2. **HashSet for Sampling** - Sample locations use a `HashSet<long>` for O(1) duplicate checking and long-safe random generation.

3. **Buffer Reuse** - Pre-allocated byte arrays are reused across reads to reduce GC pressure. Full disk scans use a 1 MB chunk buffer; sample scans use a single sector-sized buffer.

4. **Capped Leftover Storage** - At most 500 `LeftoverEntry` structs are stored (~50 KB). `TotalLeftoverCount` tracks the true total beyond the cap.

5. **Time-Based GUI Refresh** - A `Stopwatch` timer calls `DoEvents` every 250ms during the scan loop, preventing the GUI from freezing regardless of scan speed.

**Memory Usage:**
| Scan Type | Memory |
|-----------|--------|
| Full disk scan (any size) | ~2 MB |
| Sample scan (any size) | ~2 MB |

<div style="page-break-after: always;"></div>

### Sampling Strategy (Debug Mode)

When using sample scan mode (via Debug Mode), the tool strategically samples:
- **First 100 sectors** - Boot sector and partition tables
- **Last 100 sectors** (capped at `TotalSectors - 2`) - End of disk markers, avoiding HPA/DCO reserved area
- **Random middle sectors** - Distributed across the disk using long-safe random generation

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

<div style="page-break-after: always;"></div>

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

All signatures are 4+ bytes to minimize false positives. Signature matching only occurs when sector entropy < 7.0 to avoid misidentifying random data.

<div style="page-break-after: always;"></div>

## Data Leftover Markers

When the scan encounters sectors classified as **NOT Wiped** or **Suspicious**, the C# engine records a **leftover entry** for each one. These entries are collected during the scan and included as a dedicated section in the HTML/PDF report.

### What is stored per entry

| Field | Description |
|-------|-------------|
| **Sector Number** | Logical sector index on the disk |
| **Disk Offset** | Hex byte offset (e.g., `0x0000FA00`) |
| **Status** | `NOT Wiped` or `Suspicious` |
| **Pattern** | What was detected (e.g., "File signature: PDF", "Text content detected") |
| **Confidence** | Analysis confidence percentage |

### Report section

The report includes:
- A conditional banner: green (no leftovers), yellow (<=50), or red (>50)
- Summary showing how many sectors were flagged (NOT Wiped vs. Suspicious)
- A pattern breakdown table showing which leftover types were found
- A detailed table listing each flagged sector with its address, status badge, pattern, and confidence

### Memory safeguard

The collection is capped at **500 entries** by default. If more than 500 sectors are flagged, the summary counts still reflect all of them but individual entry details are only stored for the first 500. The overflow count is noted in the report.

<div style="page-break-after: always;"></div>

## Troubleshooting

### "Access Denied" Error
- Ensure PowerShell is running as Administrator
- Check if the disk is in use by another application

### "Sector not found" / I/O Error on Last Sectors
- **v4.0+:** Both scan paths wrap disk I/O in `try/catch` with graceful fallback to "Unreadable". Sample locations are capped at `TotalSectors - 2` to avoid HPA/DCO reserved area.
- On older versions, update to the latest.

### Script Freezes / GUI Unresponsive During Scan
- **v4.0+:** The scan loop uses a time-based UI refresh (every 250ms) via Stopwatch. The GUI stays responsive at all times.
- Close other applications to free RAM if needed.

### PDF Generation Fails
- HTML report is still generated as fallback
- Install Microsoft Edge, Chrome, or wkhtmltopdf
- Check if sufficient disk space is available
- Verify write permissions to output directory

### Script Execution Blocked
- Run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`

### Disk Not Listed
- Click "Refresh Disks" button
- Ensure disk is properly connected
- Check Device Manager for driver issues

<div style="page-break-after: always;"></div>

## Version History

For the Version History please have a look at the HISTORY.md

<div style="page-break-after: always;"></div>

## Author
> This tool was developed for a Project at JSW. This tool will not be maintained by JSW but by the original Author.

**Yannick Morgenthaler**

**JSW / AIP Plus**
- Company: JSW
- Contact: yannick.morgenthaler@jsw.swiss

**N1X**
- Company: N1X
- Contact: yannick@n1x.ch

**Project Resilience**
- Company: ProjectResilience
- Contact: yannick@projectresilience.ch


## License

Copyright (c) 2026 Yannick Morgenthaler / JSW. All rights reserved.

## Disclaimer

This tool performs READ-ONLY operations and does not modify disk contents. However, always ensure you have selected the correct disk before scanning. The authors are not responsible for any data loss or system issues resulting from the use of this software.
