# Disk Wipe Verification Tool - Technical Documentation

Deep technical documentation for developers who want to understand, modify, or extend the Disk Wipe Verification Tool.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [File Structure](#file-structure)
4. [Module Reference](#module-reference)
5. [Analysis Algorithms](#analysis-algorithms)
6. [GUI Components](#gui-components)
7. [Data Flow](#data-flow)
8. [Data Structures](#data-structures)
9. [Memory Management](#memory-management)
10. [Extending the Tool](#extending-the-tool)
11. [Performance Architecture](#performance-architecture)
12. [Build & Distribution](#build--distribution)
13. [Troubleshooting](#troubleshooting)
14. [Version History](#version-history)
15. [References](#references)

---

## Overview

The Disk Wipe Verification Tool is a PowerShell-based application that verifies whether a disk has been properly wiped/sanitized. It performs statistical sampling or full-disk scanning of disk sectors, analyzes byte patterns using a compiled C# engine, and determines if the disk meets data sanitization standards such as **DoD 5220.22-M** and **NIST 800-88**.

### Key Features

- **Raw disk sector access** - Reads disk sectors directly bypassing the file system
- **Compiled C# analysis engine** - All byte-level analysis runs in compiled .NET code (100-500x faster than interpreted PowerShell)
- **Full disk scan with batched I/O** - Sequential 1 MB reads for maximum throughput
- **Statistical sampling** - Optional sample mode with configurable number of randomly selected sectors (via Debug Mode)
- **Multiple wipe pattern detection** - Zero-fill, one-fill, random data (DoD 5220.22-M), cryptographic wipe
- **Shannon entropy analysis** - Measures data randomness to detect encrypted/compressed content
- **File signature detection** - Identifies recoverable file headers (PDF, ZIP, JPEG, etc.)
- **Data leftover tracking** - Records sector addresses where residual data is found, with cap at 500 entries
- **Professional HTML/PDF reports** - Generates certification-ready documentation with leftover analysis
- **Memory-optimized** - Constant ~2MB memory regardless of disk size

---

## Architecture

### High-Level Architecture Diagram

```
+---------------------------------------------------------------------+
|                           EXE.ps1                                   |
|                    (Entry Point / Launcher)                         |
+---------------------------------------------------------------------+
                                    |
                                    v
+---------------------------------------------------------------------+
|                      Load-Components.ps1                            |
|              (Component Loader / Bootstrap)                         |
+---------------------------------------------------------------------+
                                    |
              +---------------------+---------------------+
              v                     v                     v
+---------------------+ +---------------------+ +---------------------+
|     Index.ps1       | |     Main.ps1        | |    GUI/GUI.ps1      |
|  (Module Loader)    | |  (Main Logic)       | |  (GUI Framework)    |
+---------------------+ +---------------------+ +---------------------+
          |                       |                       |
          v                       v                       v
+---------------------+ +---------------------+ +---------------------+
|     Modules/        | | DiskAnalysisEngine  | |   GUI/Elements/     |
|   (Legacy + Utils)  | |   (Compiled C#)     | |  (UI Components)    |
+---------------------+ +---------------------+ +---------------------+
          |                                               |
          v                                               v
+---------------------+                       +---------------------+
|   Connectors/       |                       | GUI/ActionModules/  |
| (Helper Functions)  |                       |  (Event Handlers)   |
+---------------------+                       +---------------------+
```

### Design Principles

1. **Dot-source loading:** All files are loaded via `. .\path\to\file.ps1`. Functions and variables from any file are globally available after loading.
2. **GUI variables are global:** WinForms controls like `$ScanProgress`, `$StatusLabel`, `$Console` are created in GUI element files and referenced directly throughout the codebase.
3. **Compiled hot path:** All byte-level analysis runs in compiled C# via `Add-Type`. PowerShell only handles I/O, orchestration, and UI updates.
4. **Throttled GUI updates:** The scan loop uses a `Stopwatch` to call `DoEvents` at most every 250ms, preventing the GUI from freezing or consuming CPU on UI repaints.
5. **Default full scan:** The tool defaults to full disk scan with locked controls. Debug Mode (via Options menu) unlocks sample size for test runs.

### Component Responsibilities

| Layer | Component | Responsibility |
|-------|-----------|----------------|
| **Entry** | `EXE.ps1` | Application entry point, requires admin privileges |
| **Bootstrap** | `Load-Components.ps1` | Loads all components in correct order |
| **Indexing** | `Index.ps1` | Loads all modules and connectors |
| **Core** | `Main.ps1` | Main scanning logic, orchestrates analysis |
| **Engine** | `DiskAnalysisEngine.ps1` | Compiled C# engine for byte-level analysis |
| **Modules** | `Modules/*.ps1` | Legacy analysis functions + utilities |
| **Connectors** | `Connectors/*.ps1` | UI-independent helper functions |
| **GUI** | `GUI/GUI.ps1` | Windows Forms GUI initialization + menu bar |
| **Elements** | `GUI/Elements/*.ps1` | Individual UI control definitions |
| **Actions** | `GUI/ActionModules/*.ps1` | Button click handlers and events |
| **Factories** | `GUI/NewElements/*.ps1` | UI element factory functions |

---

## File Structure

```
DiskWipeVerification/
|
+-- EXE.ps1                          # Entry point (convertible to .exe)
+-- Load-Components.ps1              # Component bootstrap loader
+-- Index.ps1                        # Module and connector loader
+-- Main.ps1                         # Main scanning logic
|
+-- Modules/                         # Core analysis modules
|   +-- DiskAnalysisEngine.ps1       # Compiled C# engine (hot path)
|   +-- Get-AvailableDisks.ps1       # List physical disks
|   +-- Read-DiskSector.ps1          # Raw disk I/O (legacy, single-sector)
|   +-- Get-SampleLocations.ps1      # Sample location generator
|   +-- Get-ShannonEntropy.ps1       # Entropy calculation (legacy)
|   +-- Get-ByteDistributionScore.ps1# Chi-square distribution test (legacy)
|   +-- Get-ByteHistogram.ps1        # Byte frequency histogram (legacy)
|   +-- Get-DataLeftoverMarkers.ps1  # Data leftover flagging (legacy)
|   +-- Get-PrintableAsciiRatio.ps1  # ASCII content detector (legacy)
|   +-- Test-FileSignatures.ps1      # File magic number detection (legacy)
|   +-- Test-SectorWiped.ps1         # Main sector analysis (legacy)
|   +-- New-HtmlReport.ps1           # HTML report generator
|   +-- Convert-HtmlToPdf.ps1        # PDF conversion
|
+-- Connectors/                      # Helper functions
|   +-- DoEvents.ps1                 # UI refresh helper
|   +-- Get-Parameters.ps1           # Parameter collector
|   +-- Write-Console.ps1            # Console logging
|
+-- GUI/                             # User interface
|   +-- GUI.ps1                      # Main GUI loader + menu bar
|   |
|   +-- ActionModules/               # Event handlers
|   |   +-- Browse-Path.ps1          # Folder browser dialog
|   |   +-- Cancel-Scan.ps1          # Scan cancellation
|   |   +-- DataGridView-DoubleClick.ps1
|   |   +-- Disk-List.ps1            # Disk selection handler
|   |   +-- Full-DiskScan.ps1        # Full scan checkbox handler
|   |   +-- Load-Disks.ps1           # Refresh disk list
|   |   +-- Start-Scan.ps1           # Start scan button handler
|   |
|   +-- Elements/                    # UI control definitions
|   |   +-- BaseSettings.ps1         # Global UI settings
|   |   +-- LeftPanel.ps1            # Left panel container
|   |   +-- RightPanel.ps1           # Right panel container
|   |   +-- Console.ps1              # Log console
|   |   +-- DiskList.ps1             # Disk list
|   |   +-- SampleSize.ps1           # Sample size input (disabled by default)
|   |   +-- SectorSize.ps1           # Sector size dropdown
|   |   +-- FullDiskCheckBox.ps1     # Full disk toggle (checked+disabled by default)
|   |   +-- ReportFormat.ps1         # Report format dropdown
|   |   +-- ReportLocation.ps1       # Report path input
|   |   +-- ScanProgress.ps1         # Progress bar
|   |   +-- StartScan.ps1            # Start button
|   |   +-- CancelScan.ps1           # Cancel button
|   |   +-- ... (additional UI elements)
|   |
|   +-- NewElements/                 # UI element factories
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
+-- README.md                        # User documentation
+-- DEEPCODE.md                      # Deep code-level documentation
+-- DOCUMENTATION.md                 # This file
```

---

## Module Reference

### DiskAnalysisEngine.ps1 (Compiled C# Engine)

This is the performance-critical module. It compiles a C# class `DiskAnalysisEngine` into the PowerShell session via `Add-Type`. All byte iteration, entropy computation, pattern detection, and file signature matching happen in compiled .NET code.

**Key static methods:**

| Method | Description |
|--------|-------------|
| `SetSignatures(byte[][] sigs, string[] names)` | Loads file signature definitions |
| `ResetGlobalCounters()` | Clears all accumulators (call before each scan) |
| `AnalyzeSector(byte[] data, int offset, int length)` | Analyzes a single sector, returns `SectorResult` |
| `AnalyzeChunk(byte[] buffer, int bytesRead, int sectorSize, Dictionary patternCounts, long baseSectorIndex)` | Analyzes a buffer of multiple sectors in one call |
| `ComputeGlobalEntropy()` | Returns Shannon entropy from accumulated byte frequencies |
| `GetLeftovers()` | Returns array of `LeftoverEntry` structs for the report |
| `GetTotalLeftoverCount()` | Returns the total number of leftover sectors found (may exceed the detail cap) |
| `RecordLeftover(long sectorNum, int sectorSize, SectorResult result)` | Records a leftover finding |

**Data structures:**

- `SectorResult` -- Status (0=Wiped, 1=NotWiped, 2=Suspicious, 3=Unreadable), Pattern string, Confidence int
- `ChunkStats` -- Wiped/NotWiped/Suspicious/Unreadable counts for a batch
- `LeftoverEntry` -- SectorNumber, DiskOffset, Status string, Pattern, Confidence

**Leftover tracking:** Caps stored entries at 500 (`MaxLeftovers`) to prevent memory issues on heavily unwiped disks, but `TotalLeftoverCount` tracks the true total.

### Get-SampleLocations.ps1

Generates a sorted, deduplicated list of sector indices to sample:
- First 100 sectors (disk start -- boot sectors, partition tables)
- Last 100 sectors, capped at `TotalSectors - 2` (disk end -- avoids HPA/DCO reserved area)
- Remaining count filled with random indices using long-safe generation

Uses `HashSet<long>` for O(1) dedup. Only called when Full Disk Scan is unchecked (Debug Mode).

### Get-ShannonEntropy.ps1 (Legacy)

**Functions:**

#### `Get-ShannonEntropy`
For individual sector analysis (legacy, not used in scan loop).

```powershell
$entropy = Get-ShannonEntropy -Data $sectorBytes
```

#### `Get-ShannonEntropyFromHistogram`
For aggregated analysis (memory-efficient, legacy).

```powershell
$entropy = Get-ShannonEntropyFromHistogram -Histogram $histogram -TotalBytes $totalBytes
```

**Shannon Entropy Formula:**

$$H(X) = -\sum_{i=0}^{255} p(x_i) \log_2 p(x_i)$$

Where:
- $$H(X)$$ = entropy in bits (0 to 8)
- $$p(x_i)$$ = probability of byte value $$i$$

**Entropy Interpretation:**

| Entropy | Meaning | Example |
|---------|---------|---------|
| 0.0 | All identical bytes | Zero-filled sector |
| 1.0-4.0 | Low randomness | Text, structured data |
| 4.0-6.0 | Medium randomness | Compressed files |
| 6.0-7.5 | High randomness | Encrypted data |
| 7.5-8.0 | Very high randomness | Cryptographic random, wiped data |

### Get-ByteDistributionScore.ps1 (Legacy)

**Chi-Square Test:**

$$\chi^2 = \sum_{i=0}^{255} \frac{(O_i - E_i)^2}{E_i}$$

Where:
- $$O_i$$ = observed count of byte value $$i$$
- $$E_i$$ = expected count (data length / 256)

Uses fixed `int[256]` array (optimized from hashtable in v3.9.0210).

| Score | Meaning |
|-------|---------|
| 0.90-1.00 | Excellent uniformity (random data) |
| 0.75-0.90 | Good uniformity |
| 0.50-0.75 | Moderate uniformity |
| < 0.50 | Poor uniformity (structured data) |

### Test-FileSignatures.ps1 (Legacy)

**Supported Signatures:**

| File Type | Signature (Hex) | Description |
|-----------|-----------------|-------------|
| PDF | `25 50 44 46 2D` | `%PDF-` |
| ZIP/DOCX | `50 4B 03 04` | PK header |
| JPEG | `FF D8 FF E0` | JPEG with JFIF |
| PNG | `89 50 4E 47 0D 0A` | PNG header |
| GIF87 | `47 49 46 38 37 61` | GIF87a |
| GIF89 | `47 49 46 38 39 61` | GIF89a |
| RAR | `52 61 72 21 1A 07` | RAR archive |
| 7Z | `37 7A BC AF 27 1C` | 7-Zip archive |
| SQLite | `53 51 4C 69 74 65` | SQLite database |
| NTFS | `EB 52 90 4E 54 46 53` | NTFS boot sector |
| EXE | `4D 5A 90 00` | MZ with valid header |

Signatures are 4+ bytes to avoid false positives. Matching only occurs when entropy < 7.0.

### New-HtmlReport.ps1

Generates a self-contained HTML report with inline CSS. No external dependencies.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `Technician` | string | Name of the person performing the verification |
| `Results` | hashtable | Keys: Wiped, NotWiped, Suspicious, Unreadable, Patterns |
| `Disk` | object | WMI disk object from `Get-Disk` |
| `DiskNumber` | int | Physical disk number |
| `DiskSize` | long | Disk capacity in bytes |
| `TotalSamples` | int | Number of sectors analyzed |
| `WipedPercent` | double | Percentage of sectors verified clean |
| `EntropyPercent` | double | Overall entropy as percentage of maximum (8 bits) |
| `OverallStatus` | string | Verification verdict |
| `SectorSize` | int | Bytes per sector |
| `Leftovers` | object[] | Array of LeftoverEntry structs from C# engine |
| `TotalLeftoverCount` | long | Total leftovers found (may be larger than Leftovers array) |

**Report sections:** Disk Information, Analysis Summary (cards), Detailed Sector Analysis, Detected Wipe Patterns, Data Leftover Analysis (conditional banners: green/yellow/red), Verification Methodology, Certification (signature lines).

### Convert-HtmlToPdf.ps1

Attempts PDF conversion using five fallback methods:
1. Microsoft Edge (headless `--print-to-pdf`)
2. Google Chrome (headless)
3. Brave Browser (headless)
4. wkhtmltopdf
5. Microsoft Word COM object

Returns `$true` if a PDF was successfully created, `$false` otherwise.

**Browser Locations Checked:**

```powershell
# Edge
"${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
"$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"

# Chrome
"${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
"$env:ProgramFiles\Google\Chrome\Application\chrome.exe"

# Brave
"${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe"
"$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"

# wkhtmltopdf
"C:\Program Files\wkhtmltopdf\bin\wkhtmltopdf.exe"
"C:\Program Files (x86)\wkhtmltopdf\bin\wkhtmltopdf.exe"
```

### Connectors

- **DoEvents.ps1:** Wraps `[System.Windows.Forms.Application]::DoEvents()` to pump the GUI message queue.
- **Get-Parameters.ps1:** Reads GUI input fields and returns a hashtable with `technician`, `diskNumber`, `sampleSize`, `sectorSize`, `reportFormat`, `reportPath`, `reportFile`.
- **Write-Console.ps1:** Appends a timestamped, color-coded message to the RichTextBox console and calls `DoEvents`.

---

## Analysis Algorithms

### Wipe Verification Algorithm

The compiled C# engine uses a multi-layered approach to determine if a sector is wiped:

```
Layer 1: Pattern Matching (Fast)
+-- Check for all-zeros (0x00)
+-- Check for all-ones (0xFF)
+-- If matched -> WIPED (confidence 100%)

Layer 2: Statistical Analysis
+-- Calculate Shannon entropy
+-- Calculate byte distribution score (chi-square)
+-- Calculate ASCII ratio
+-- Based on thresholds -> Determine status

Layer 3: Signature Detection (Only for entropy < 7.0)
+-- Check file magic numbers
+-- If found -> NOT WIPED (confidence 95%)
```

### Analysis Decision Tree

```
                        Sector Data
                            |
                            v
                      Null/Empty?
                       /       \
                     Yes        No
                      |          |
                      v          v
                 UNREADABLE   All 0x00?
                              /       \
                            Yes        No
                             |          |
                             v          v
                         WIPED       All 0xFF?
                       (Zero-fill)   /       \
                                   Yes        No
                                    |          |
                                    v          v
                                WIPED    Compute Entropy
                              (One-fill)     |
                                     +-------+-------+
                                     |               |
                              Entropy > 7.0   Entropy <= 7.0
                                     |               |
                                     v               v
                           HIGH ENTROPY PATH  LOW ENTROPY PATH
                           (Random data?)     (Check signatures)
                                     |               |
                   +---------+-------+-------+       |
                   |         |               |       v
             H>7.5 &    H>7.0 &       ASCII>0.7  Signatures?
             D>0.80     D>0.75                    /        \
                   |         |           |      Yes        No
                   v         v           v       |          |
               WIPED     WIPED     NOT WIPED     v          v
               (DoD)    (Crypto)    (Text)   NOT WIPED   Medium
                                            (File sig)  Entropy
                                                        Analysis
```

### DoD 5220.22-M Detection

The DoD 5220.22-M standard specifies a 3-pass wipe:

1. Pass 1: Write all zeros (0x00)
2. Pass 2: Write all ones (0xFF)
3. Pass 3: Write random data

Since the final pass overwrites previous passes, the tool detects the **random data pattern** of Pass 3:

- **High entropy** (> 7.5/8.0)
- **Uniform byte distribution** (> 0.80)
- **Low ASCII ratio** (< 0.5)

**Confidence formula:**
```
confidence = (entropy/8) * 60 + distribution * 40
```

---

## GUI Components

### Main Window Layout

```
+-----------------------------------------------------------------------------+
|  Options                                                                     |
|  [Debug Mode]                                                                |
+--------------------------------+--------------------------------------------+
|                                |                                            |
|  PARAMETERS                    |  AVAILABLE DISKS                           |
|  ----------------              |  ----------------                          |
|  Technician: [___________]    |  [Refresh Disks]                           |
|  Sample Size: [locked    ]    |  +------------------------------------+    |
|  [x] Full Disk Scan (locked) |  | Disk 0 | Samsung SSD | 256GB       |    |
|  Sector Size: [512      v]    |  | Disk 1 | WD Blue     | 1TB         |    |
|  Report Format: [PDF    v]    |  | Disk 2 | USB Drive   | 32GB        |    |
|  Report Location: [Browse]    |  +------------------------------------+    |
|                                |                                            |
|  SCAN                          |  CONSOLE                                   |
|  ----                          |  -------                                   |
|  Status: Ready                 |  +------------------------------------+    |
|  ################------  60%   |  | [12:34:56] Scanning chunk 5000    |    |
|  [Start Scan] [Cancel]        |  | [12:34:57] Speed: 125 MB/s        |    |
|                                |  | [12:34:58] ETA: 2m 30s            |    |
|  +--------------------+       |  +------------------------------------+    |
|  | VERIFICATION RESULT|       |                                            |
|  |      PASSED        |       |                                            |
|  +--------------------+       |                                            |
+--------------------------------+--------------------------------------------+
```

### GUI Component Hierarchy

```
MainWindow (Form)
+-- MenuBar (Options > Debug Mode)
+-- GroupBoxL (Left Panel)
|   +-- ParameterHeader (Label)
|   +-- TechnicianName (TextBox)
|   +-- SampleSize (NumericUpDown) -- disabled by default
|   +-- FullDiskCheckBox (CheckBox) -- checked+disabled by default
|   +-- SectorInfoLabel (Label)
|   +-- SectorSize (ComboBox)
|   +-- ReportFormat (ComboBox)
|   +-- ReportPath (TextBox)
|   +-- ReportPathButton (Button)
|   +-- ScanHeader (Label)
|   +-- StatusLabel (Label)
|   +-- ScanProgress (ProgressBar)
|   +-- ProgressLabel (Label)
|   +-- StartScan (Button)
|   +-- CancelScan (Button)
|   +-- VerificationPanel (Panel)
|       +-- ResultLabel (Label)
|
+-- GroupBoxR (Right Panel)
    +-- AvailableDiskHeader (Label)
    +-- RefreshDisks (Button)
    +-- DiskList (ListBox)
    +-- ConsoleHeader (Label)
    +-- Console (RichTextBox)
```

---

## Data Flow

### Scan Execution Flow

```
Start-Scan (GUI event)
    |
    v
Main-Process
    |
    +-- Get-Parameters -> $P (reads GUI fields)
    |
    +-- Load Modules (dot-source all .ps1 files)
    |       |
    |       +-- DiskAnalysisEngine.ps1 (Add-Type compiles C#)
    |
    +-- SetSignatures (pass file signatures to C# engine)
    |
    +-- Get-Disk $DiskNumber -> $disk, $diskPath, $totalSectors
    |
    +-- [if sample mode] Get-SampleLocations -> $sampleLocations
    |
    +-- ResetGlobalCounters (clear C# accumulators)
    |
    +-- Open FileStream($diskPath)
    |
    +-- SCAN LOOP:
    |   |
    |   +-- [full disk] Read 1MB chunk -> AnalyzeChunk()
    |   |       |
    |   |       +-- For each sector in chunk:
    |   |           +-- AnalyzeSector() -> SectorResult
    |   |           +-- Accumulate GlobalFrequency
    |   |           +-- RecordLeftover() if NOT Wiped or Suspicious
    |   |           +-- Update patternCounts dictionary
    |   |       +-- Return ChunkStats
    |   |
    |   +-- [sample] Seek + Read 1 sector -> AnalyzeSector()
    |   |       +-- RecordLeftover() called from PowerShell
    |   |
    |   +-- Every 250ms: Update progress bar, status, speed, ETA, DoEvents
    |
    +-- Close FileStream
    |
    +-- ComputeGlobalEntropy() -> $overallEntropy -> $entropyPercent
    |
    +-- GetLeftovers() -> $leftovers
    +-- GetTotalLeftoverCount() -> $totalLeftoverCount
    |
    +-- Calculate $wipedPercent, $overallStatus
    |
    +-- New-HtmlReport(all data) -> $htmlContent
    |
    +-- Save HTML / Convert to PDF
    |
    +-- Show result dialog
    |
    v
Finally: Close stream, re-enable UI
```

---

## Data Structures

### Results Hashtable

```powershell
$results = @{
    Wiped      = 0          # Count of wiped sectors
    NotWiped   = 0          # Count of not wiped sectors
    Suspicious = 0          # Count of suspicious sectors
    Unreadable = 0          # Count of unreadable sectors
    Patterns   = @{}        # Pattern -> Count mapping
}
```

### Pattern Counts Dictionary

```csharp
// Created in PowerShell, passed to C# engine
Dictionary<string, int> patternCounts
// Converted to $results.Patterns hashtable after scan
```

### SectorResult (C#)

```csharp
public struct SectorResult {
    public int Status;       // 0=Wiped, 1=NotWiped, 2=Suspicious, 3=Unreadable
    public string Pattern;   // e.g., "Zero-filled (0x00)"
    public int Confidence;   // 0-100
}
```

### LeftoverEntry (C#)

```csharp
public struct LeftoverEntry {
    public long SectorNumber;
    public string DiskOffset;  // Hex format
    public string Status;      // "NOT Wiped" or "Suspicious"
    public string Pattern;
    public int Confidence;
}
```

### Sample Locations Object

```powershell
# Sampled scan:
@{
    Count      = [long]15000
    IsFullScan = $false
    _array     = [long[]]@(0, 1, ..., 99, 4500, 8900, ..., N-2)  # Sorted, boundary-safe
}

# Full scan:
@{
    Count      = [long]976773168
    IsFullScan = $true
}
```

---

## Memory Management

### Memory Optimization Techniques

The tool is optimized to handle full disk scans on systems with limited RAM (8GB).

#### 1. Compiled C# Engine with Streaming Counters

Instead of storing any raw byte data, the C# engine maintains only:
- A 256-element `long[]` frequency table (~2 KB)
- A printable ASCII counter
- A total byte counter

Memory usage is constant regardless of disk size or scan duration.

#### 2. Sample Location Generation

Uses `HashSet<long>` for O(1) duplicate checking and long-safe random generation (combines two 31-bit randoms). Converts to sorted array at the end and clears the HashSet.

#### 3. Batched I/O

Full disk scans read 1 MB chunks (2048 sectors) using a pre-allocated, reused buffer. No per-sector allocation.

#### 4. Capped Leftover Storage

At most 500 `LeftoverEntry` structs are stored. `TotalLeftoverCount` tracks the true count.

#### 5. Time-Based GUI Refresh

UI updates every 250ms via `Stopwatch`, not every sector. Eliminates millions of unnecessary `DoEvents` calls.

### Memory Usage Summary

| Component | Memory |
|-----------|--------|
| Global frequency table | 2 KB |
| Chunk buffer (full scan) | 1 MB |
| Sector buffer (sample) | 512 B - 4 KB |
| Leftover entries (capped) | ~50 KB max |
| Pattern counts dictionary | ~1 KB |
| **Total for any scan** | **~1-2 MB** |

---

## Extending the Tool

### Adding a New File Signature

1. Open `Main.ps1`, find the `$FileSignatures` hashtable (around line 108).
2. Add a new entry:
   ```powershell
   "BMP" = [byte[]]@(0x42, 0x4D)  # BM header
   "TIFF_LE" = [byte[]]@(0x49, 0x49, 0x2A, 0x00)  # TIFF little-endian
   ```
3. The compiled engine picks up signatures via `SetSignatures()` -- no C# changes needed.
4. Minimum signature length: 4 bytes recommended to avoid false positives.

### Adding a New Wipe Pattern

Detection logic lives in `DiskAnalysisEngine.ps1` inside the `AnalyzeSector` method. The decision tree is:

1. Null/empty data -> Unreadable
2. Zero-fill check (all 0x00) -> Wiped
3. One-fill check (all 0xFF) -> Wiped
4. Entropy + distribution computation
5. High entropy path (>7.0): DoD random, crypto wipe, text, probable wipe
6. File signature matching (<7.0)
7. Medium entropy (5.0-7.0): compressed/encrypted or residual
8. Low entropy (<=5.0): structured data

To add a new pattern, insert a new condition block in the appropriate entropy range. Return a `SectorResult` with the appropriate status code and pattern string.

### Adding a New Report Section

1. Open `Modules/New-HtmlReport.ps1`
2. Add parameters to the `param()` block
3. Add CSS classes in the `<style>` block
4. Insert HTML between existing sections (use `<div class="no-break">` for print-friendly blocks)
5. Pass the new data from `Main.ps1` in the `New-HtmlReport` call

### Adding a New GUI Control

1. Create a factory function in `GUI/NewElements/` (e.g., `New-DatePicker.ps1`)
2. Create the element in `GUI/Elements/` using the factory function
3. Add the dot-source in `GUI/GUI.ps1` in the appropriate section
4. Wire up event handlers at the bottom of `GUI/GUI.ps1`

### Changing the Leftover Cap

```csharp
// In DiskAnalysisEngine.ps1, inside the C# block:
public static int MaxLeftovers = 500;  // Change this value
```

### Changing Verification Thresholds

```powershell
# In Main.ps1 for overall status:
$overallStatus = if ($wipedPercent -ge 99.5) {   # Adjust threshold
    "VERIFIED CLEAN - Disk Successfully Wiped"
}
elseif ($wipedPercent -ge 95) {   # Adjust threshold
    "MOSTLY CLEAN - Manual Review Recommended"
}
```

### Customizing the Report

```powershell
# In New-HtmlReport.ps1:

# Change colors
.status-verified {
    background: #your-color;
}

# Add company logo
<div class="header">
    <img src="file:///C:/path/to/logo.png" />
    <h1>Your Company - Disk Wipe Report</h1>
</div>

# Add custom fields
<tr><td>Asset Tag</td><td>$AssetTag</td></tr>
```

### Creating a Command-Line Version

```powershell
# CLI-Main.ps1
param(
    [Parameter(Mandatory=$true)]
    [int]$DiskNumber,
    [int]$SampleSize = 10000,
    [int]$SectorSize = 512,
    [ValidateSet("HTML", "PDF", "Both")]
    [string]$ReportFormat = "Both",
    [string]$ReportPath = "$env:USERPROFILE\Documents"
)

# Load modules only
. .\Modules\*.ps1

# Run analysis without GUI
$results = Invoke-DiskAnalysis -DiskNumber $DiskNumber ...
```

---

## Performance Architecture

### Why C# via Add-Type?

PowerShell's `foreach` loops are interpreted. A 500 GB disk at 512 bytes/sector = ~1 billion sectors. Each sector previously went through 4-5 separate PowerShell `foreach` byte loops. The compiled C# engine performs all analysis in a single loop per sector, with ~100-500x throughput improvement.

### I/O Strategy

- **Full disk scan:** Sequential reads in 1 MB chunks (2048 sectors per read). The OS read-ahead cache works optimally with sequential access.
- **Sample scan:** Individual sector reads via `Seek` + `Read` on a persistent `FileStream`. Stream opened once, reused for all sectors.
- **Buffer reuse:** Pre-allocated byte arrays reused across reads to reduce GC pressure.
- **Error handling:** Both paths wrap I/O in `try/catch`. Failed reads produce "Unreadable" sectors. Partial reads on the last chunk are handled gracefully.

---

## Build & Distribution

### Running from Source

```powershell
# Open elevated PowerShell in the project root
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\EXE.ps1
```

### Converting to .exe

The `EXE.ps1` file is designed to be compiled to a standalone executable using tools like PS2EXE or Win-PS2EXE. The `Load-Components.ps1` bridge ensures the executable only needs to bootstrap the component loader.

---

## Troubleshooting

### Common Issues

#### "Disk not found" Error

**Cause:** Disk number doesn't exist or disk is offline.

**Solution:**
```powershell
Get-Disk | Format-Table Number, FriendlyName, Size, OperationalStatus
```

#### "Access Denied" Error

**Cause:** Script not running as administrator.

**Solution:** Run PowerShell as Administrator.

#### "Sector not found" / I/O Error on Last Sectors

**Cause:** Physical drives have 1-2 unreachable sectors at the end (HPA/DCO reserved area).

**Solution (v4.0+):** Handled automatically. Sample locations capped at `TotalSectors - 2`. Both scan paths have try/catch with "Unreadable" fallback.

#### PDF Generation Fails

**Cause:** No supported browser installed.

**Solution:**
1. Install Microsoft Edge (Chromium) or Chrome
2. Or install wkhtmltopdf from https://wkhtmltopdf.org/
3. HTML report is still generated as fallback

#### Script Freezes / GUI Unresponsive

**Cause (old versions):** GUI only called `DoEvents` when percentage changed.

**Solution (v4.0+):** Scan loop uses `Stopwatch`-based timer (every 250ms). GUI stays responsive at all times.

#### False Positives (Wiped disk shows NOT Wiped)

**Solution:**
1. Check unreadable sector count
2. The thresholds in the C# engine can be adjusted if needed
3. Verify disk health with manufacturer tools

#### False Negatives (Data present but shows Wiped)

**Solution:**
1. Use full disk scan (default)
2. Add specific file signatures for expected data types

### Debug Mode

Enable Debug Mode via Options menu to:
- Unlock the Full Disk Scan checkbox
- Set custom sample sizes for faster test runs
- Useful during development and testing

### Performance Profiling

```powershell
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
# ... code to measure ...
$stopwatch.Stop()
Write-Console "Elapsed: $($stopwatch.Elapsed.TotalSeconds) seconds" "Cyan"
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 3.8.0116.01 | 2026-01-08 | Initial release |
| 3.8.0116.02 | 2026-01-11 | Improved algorithms and reports |
| 3.8.0116.03 | 2026-01-12 | Modular architecture |
| 3.9.0203.01 | 2026-02-03 | Memory optimization (streaming histogram, HashSet sampling) |
| 3.9.0209.01 | 2026-02-09 | Data leftover markers module, shared FileStream |
| 3.9.0210.01 | 2026-02-10 | Time-based UI refresh, array optimization, bug fixes |
| 4.0 | 2026-02-13 | Compiled C# engine, batched 1MB I/O, default full disk scan, Debug Mode, long-safe sampling, boundary-safe sectors, status wildcard fix |

---

## References

- [DoD 5220.22-M Standard](https://www.dss.mil/)
- [NIST SP 800-88 Guidelines](https://csrc.nist.gov/publications/detail/sp/800-88/rev-1/final)
- [Shannon Entropy](https://en.wikipedia.org/wiki/Entropy_(information_theory))
- [Chi-Square Test](https://en.wikipedia.org/wiki/Chi-squared_test)

---

## License

Copyright (c) 2026 Yannick Morgenthaler / JSW

Contact:
- yannick.morgenthaler@jsw.swiss
- yannick@n1x.ch
- yannick@projectresilience.ch
- yannick.morgenthaler@4058.net
