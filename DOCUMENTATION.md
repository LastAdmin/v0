# Disk Wipe Verification Tool - Technical Documentation

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [File Structure](#file-structure)
4. [Core Modules](#core-modules)
5. [Analysis Algorithms](#analysis-algorithms)
6. [GUI Components](#gui-components)
7. [Data Flow](#data-flow)
8. [Memory Management](#memory-management)
9. [Customization Guide](#customization-guide)
10. [Troubleshooting](#troubleshooting)

---

## Overview

The Disk Wipe Verification Tool is a PowerShell-based application that verifies whether a disk has been properly wiped/sanitized. It performs statistical sampling of disk sectors, analyzes byte patterns, and determines if the disk meets data sanitization standards such as **DoD 5220.22-M** and **NIST 800-88**.

### Key Features

- **Raw disk sector access** - Reads disk sectors directly bypassing the file system
- **Statistical sampling** - Analyzes a configurable number of randomly selected sectors
- **Multiple wipe pattern detection** - Zero-fill, one-fill, random data (DoD 5220.22-M)
- **Shannon entropy analysis** - Measures data randomness to detect encrypted/compressed content
- **File signature detection** - Identifies recoverable file headers (PDF, ZIP, JPEG, etc.)
- **Professional HTML/PDF reports** - Generates certification-ready documentation
- **Memory-optimized** - Supports 100,000+ sector samples on systems with 8GB RAM

---

## Architecture

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                           EXE.ps1                                   │
│                    (Entry Point / Launcher)                         │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Load-Components.ps1                            │
│              (Component Loader / Bootstrap)                         │
└─────────────────────────────────────────────────────────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              ▼                     ▼                     ▼
┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
│     Index.ps1       │ │     Main.ps1        │ │    GUI/GUI.ps1      │
│  (Module Loader)    │ │  (Main Logic)       │ │  (GUI Framework)    │
└─────────────────────┘ └─────────────────────┘ └─────────────────────┘
          │                       │                       │
          ▼                       ▼                       ▼
┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
│     Modules/        │ │    Analysis         │ │   GUI/Elements/     │
│   (Core Logic)      │ │   Functions         │ │  (UI Components)    │
└─────────────────────┘ └─────────────────────┘ └─────────────────────┘
          │                                               │
          ▼                                               ▼
┌─────────────────────┐                       ┌─────────────────────┐
│   Connectors/       │                       │ GUI/ActionModules/  │
│ (Helper Functions)  │                       │  (Event Handlers)   │
└─────────────────────┘                       └─────────────────────┘
```

### Component Responsibilities

| Layer | Component | Responsibility |
|-------|-----------|----------------|
| **Entry** | `EXE.ps1` | Application entry point, requires admin privileges |
| **Bootstrap** | `Load-Components.ps1` | Loads all components in correct order |
| **Indexing** | `Index.ps1` | Loads all modules and connectors |
| **Core** | `Main.ps1` | Main scanning logic, orchestrates analysis |
| **Modules** | `Modules/*.ps1` | Individual analysis functions |
| **Connectors** | `Connectors/*.ps1` | UI-independent helper functions |
| **GUI** | `GUI/GUI.ps1` | Windows Forms GUI initialization |
| **Elements** | `GUI/Elements/*.ps1` | Individual UI control definitions |
| **Actions** | `GUI/ActionModules/*.ps1` | Button click handlers and events |
| **Factories** | `GUI/NewElements/*.ps1` | UI element factory functions |

---

## File Structure

```
DiskWipeVerification/
│
├── EXE.ps1                          # Entry point (convert to .exe)
├── Load-Components.ps1              # Component bootstrap loader
├── Index.ps1                        # Module and connector loader
├── Main.ps1                         # Main scanning logic
│
├── Modules/                         # Core analysis modules
│   ├── Get-AvailableDisks.ps1       # List physical disks
│   ├── Read-DiskSector.ps1          # Raw disk I/O
│   ├── Get-SampleLocations.ps1      # Sample location generator
│   ├── Get-ShannonEntropy.ps1       # Entropy calculation
│   ├── Get-ByteDistributionScore.ps1# Chi-square distribution test
│   ├── Get-ByteHistogram.ps1        # Byte frequency histogram
│   ├── Get-PrintableAsciiRatio.ps1  # ASCII content detector
│   ├── Test-FileSignatures.ps1      # File magic number detection
│   ├── Test-SectorWiped.ps1         # Main sector analysis
│   ├── New-HtmlReport.ps1           # HTML report generator
│   └── Convert-HtmlToPdf.ps1        # PDF conversion
│
├── Connectors/                      # Helper functions
│   ├── DoEvents.ps1                 # UI refresh helper
│   ├── Get-Parameters.ps1           # Parameter collector
│   └── Write-Console.ps1            # Console logging
│
├── GUI/                             # User interface
│   ├── GUI.ps1                      # Main GUI loader
│   │
│   ├── ActionModules/               # Event handlers
│   │   ├── Browse-Path.ps1          # Folder browser dialog
│   │   ├── Cancel-Scan.ps1          # Scan cancellation
│   │   ├── DataGridView-DoubleClick.ps1
│   │   ├── Disk-List.ps1            # Disk selection handler
│   │   ├── Full-DiskScan.ps1        # Full scan checkbox handler
│   │   ├── Load-Disks.ps1           # Refresh disk list
│   │   └── Start-Scan.ps1           # Start scan button handler
│   │
│   ├── Elements/                    # UI control definitions
│   │   ├── BaseSettings.ps1         # Global UI settings
│   │   ├── LeftPanel.ps1            # Left panel container
│   │   ├── RightPanel.ps1           # Right panel container
│   │   ├── Console.ps1              # Log console
│   │   ├── DiskList.ps1             # Disk dropdown
│   │   ├── SampleSize.ps1           # Sample size input
│   │   ├── SectorSize.ps1           # Sector size dropdown
│   │   ├── ReportFormat.ps1         # Report format dropdown
│   │   ├── ReportLocation.ps1       # Report path input
│   │   ├── ScanProgress.ps1         # Progress bar
│   │   ├── StartScan.ps1            # Start button
│   │   ├── CancelScan.ps1           # Cancel button
│   │   └── ... (additional UI elements)
│   │
│   └── NewElements/                 # UI element factories
│       ├── New-Button.ps1
│       ├── New-CheckBox.ps1
│       ├── New-ComboBox.ps1
│       ├── New-DataGridView.ps1
│       ├── New-GroupBox.ps1
│       ├── New-Label.ps1
│       ├── New-ListBox.ps1
│       ├── New-NumericUpDown.ps1
│       ├── New-Panel.ps1
│       ├── New-ProgressBar.ps1
│       ├── New-RichTextBox.ps1
│       └── New-TextBox.ps1
│
├── README.md                        # User documentation
└── DOCUMENTATION.md                 # This file
```

---

## Core Modules

### 1. Read-DiskSector.ps1

**Purpose:** Low-level raw disk I/O operations.

**Function:** `Read-DiskSector`

```powershell
Read-DiskSector -DiskPath "\\.\PhysicalDrive0" -Offset 0 -Size 512
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `DiskPath` | string | Physical disk path (e.g., `\\.\PhysicalDrive0`) |
| `Offset` | long | Byte offset from disk start |
| `Size` | int | Number of bytes to read (typically 512 or 4096) |

**Returns:** `byte[]` - Raw sector data, or `$null` on read failure.

**Implementation Details:**
- Uses `System.IO.File.Open()` with `FileShare.ReadWrite` for safe access
- Requires administrator privileges
- Returns `$null` for bad sectors (handled gracefully by caller)

**Customization:**
- Modify buffer size for different sector sizes
- Add retry logic for transient read failures

---

### 2. Get-SampleLocations.ps1

**Purpose:** Generates a statistically representative sample of sector locations.

**Function:** `Get-SampleLocations`

```powershell
$locations = Get-SampleLocations -TotalSectors 1000000000 -SampleSize 10000
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `TotalSectors` | long | Total sectors on the disk |
| `SampleSize` | int | Desired number of samples |

**Returns:** `long[]` - Sorted array of unique sector indices.

**Sampling Strategy:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Disk Layout                                │
├─────────────────┬───────────────────────────────┬───────────────────┤
│  First 100      │         Random Middle         │    Last 100       │
│  Sectors        │         Selection             │    Sectors        │
│  (Always)       │     (Remaining samples)       │    (Always)       │
└─────────────────┴───────────────────────────────┴───────────────────┘
     Sector 0-99        Sector 100 to N-100           Sector N-99 to N
```

**Algorithm:**

1. **Always include first 100 sectors** - Captures MBR, partition tables, boot sectors
2. **Always include last 100 sectors** - Captures backup partition tables, end-of-disk structures
3. **Random middle sampling** - Uniformly distributed random samples from the middle region

**Memory Optimization:**
- Uses `HashSet<long>` for O(1) duplicate checking
- Converts to `List<long>` only at the end
- Supports 100,000+ samples on 8GB RAM systems

**Customization:**
```powershell
# Change the number of guaranteed start/end sectors
$firstCount = [math]::Min(200, $TotalSectors)  # Increase to 200

# Adjust middle sampling range
$middleStart = 200   # Skip more at the beginning
$middleEnd = $TotalSectors - 200  # Skip more at the end
```

---

### 3. Get-ShannonEntropy.ps1

**Purpose:** Calculates Shannon entropy to measure data randomness.

**Functions:**

#### `Get-ShannonEntropy`
For individual sector analysis.

```powershell
$entropy = Get-ShannonEntropy -Data $sectorBytes
```

#### `Get-ShannonEntropyFromHistogram`
For aggregated analysis (memory-efficient).

```powershell
$entropy = Get-ShannonEntropyFromHistogram -Histogram $histogram -TotalBytes $totalBytes
```

**Shannon Entropy Formula:**

$$H(X) = -\sum_{i=0}^{255} p(x_i) \log_2 p(x_i)$$

Where:
- $H(X)$ = entropy in bits (0 to 8)
- $p(x_i)$ = probability of byte value $i$
- Range: 0 (completely uniform) to 8 (perfectly random)

**Entropy Interpretation:**

| Entropy | Meaning | Example |
|---------|---------|---------|
| 0.0 | All identical bytes | Zero-filled sector |
| 1.0-4.0 | Low randomness | Text, structured data |
| 4.0-6.0 | Medium randomness | Compressed files |
| 6.0-7.5 | High randomness | Encrypted data |
| 7.5-8.0 | Very high randomness | Cryptographic random, wiped data |

**Implementation Details:**
- Uses fixed-size `int[256]` array for byte counting (efficient)
- No hashtable overhead
- O(n) time complexity where n = data length

**Customization:**
```powershell
# Adjust thresholds in Test-SectorWiped.ps1
if ($entropy -gt 7.5) {  # Lower from 7.5 for stricter detection
    # Treat as random/wiped
}
```

---

### 4. Get-ByteDistributionScore.ps1

**Purpose:** Measures how uniformly distributed bytes are using a Chi-square test.

**Function:** `Get-ByteDistributionScore`

```powershell
$score = Get-ByteDistributionScore -Data $sectorBytes
```

**Returns:** `double` - Score from 0.0 (non-uniform) to 1.0 (perfectly uniform).

**Chi-Square Test:**

$$\chi^2 = \sum_{i=0}^{255} \frac{(O_i - E_i)^2}{E_i}$$

Where:
- $O_i$ = observed count of byte value $i$
- $E_i$ = expected count (data length / 256)

**Score Calculation:**
```powershell
$normalizedScore = 1 - ($chiSquare / $maxChiSquare)
```

**Score Interpretation:**

| Score | Meaning |
|-------|---------|
| 0.90-1.00 | Excellent uniformity (random data) |
| 0.75-0.90 | Good uniformity |
| 0.50-0.75 | Moderate uniformity |
| < 0.50 | Poor uniformity (structured data) |

---

### 5. Get-PrintableAsciiRatio.ps1

**Purpose:** Detects text content by measuring printable ASCII character ratio.

**Function:** `Get-PrintableAsciiRatio`

```powershell
$ratio = Get-PrintableAsciiRatio -Data $sectorBytes
```

**Returns:** `double` - Ratio from 0.0 to 1.0.

**Printable Characters:**
- ASCII 32-126 (space through tilde)
- Tab (0x09)
- Newline (0x0A)
- Carriage return (0x0D)

**Ratio Interpretation:**

| Ratio | Meaning |
|-------|---------|
| > 0.70 | Likely text content |
| 0.30-0.70 | Mixed content |
| < 0.30 | Binary/random data |

---

### 6. Test-FileSignatures.ps1

**Purpose:** Detects file headers (magic numbers) in sector data.

**Function:** `Test-FileSignatures`

```powershell
$fileType = Test-FileSignatures -Data $sectorBytes
```

**Returns:** `string` - File type name or `$null` if no match.

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

**Customization - Adding New Signatures:**

In `Main.ps1`, modify the `$FileSignatures` hashtable:

```powershell
$FileSignatures = @{
    # Existing signatures...
    
    # Add new signature (minimum 4 bytes recommended)
    "BMP" = @(0x42, 0x4D)  # BM header (2 bytes - may cause false positives)
    "TIFF_LE" = @(0x49, 0x49, 0x2A, 0x00)  # TIFF little-endian
    "TIFF_BE" = @(0x4D, 0x4D, 0x00, 0x2A)  # TIFF big-endian
}
```

**Important Notes:**
- Signatures should be 4+ bytes to avoid false positives
- Short signatures (2 bytes like MZ) have been removed to prevent false positives with random data
- Signature matching only occurs when entropy < 7.0 to avoid misidentifying random data

---

### 7. Test-SectorWiped.ps1

**Purpose:** Main sector analysis function that determines wipe status.

**Function:** `Test-SectorWiped`

```powershell
$result = Test-SectorWiped -SectorData $sectorBytes
```

**Returns:** Hashtable with:

| Key | Type | Description |
|-----|------|-------------|
| `Status` | string | "Wiped", "NOT Wiped", "Suspicious", "Unreadable" |
| `Pattern` | string | Detected pattern description |
| `Confidence` | int | Confidence percentage (0-100) |
| `Details` | string | Additional analysis details |

**Analysis Decision Tree:**

```
                        ┌─────────────────────┐
                        │   Sector Data       │
                        └─────────┬───────────┘
                                  │
                                  ▼
                        ┌─────────────────────┐
                        │  Null/Empty?        │
                        └─────────┬───────────┘
                             Yes  │  No
                                  │
                ┌─────────────────┴─────────────────┐
                ▼                                   ▼
        ┌───────────────┐                  ┌───────────────┐
        │  UNREADABLE   │                  │  All Zeros?   │
        └───────────────┘                  └───────┬───────┘
                                              Yes  │  No
                                  ┌────────────────┴────────────────┐
                                  ▼                                 ▼
                          ┌───────────────┐                ┌───────────────┐
                          │  WIPED        │                │  All 0xFF?    │
                          │  (Zero-fill)  │                └───────┬───────┘
                          └───────────────┘                   Yes  │  No
                                                  ┌────────────────┴────────────┐
                                                  ▼                             ▼
                                          ┌───────────────┐            ┌───────────────┐
                                          │  WIPED        │            │ Calculate     │
                                          │  (One-fill)   │            │ Entropy       │
                                          └───────────────┘            └───────┬───────┘
                                                                               │
                                                         ┌─────────────────────┴─────────────────────┐
                                                         │                                           │
                                              Entropy > 7.0                              Entropy ≤ 7.0
                                                         │                                           │
                                                         ▼                                           ▼
                                               ┌───────────────────┐                    ┌───────────────────┐
                                               │ HIGH ENTROPY PATH │                    │ LOW ENTROPY PATH  │
                                               │ (Random data?)    │                    │ (Check signatures)│
                                               └─────────┬─────────┘                    └─────────┬─────────┘
                                                         │                                        │
                                      ┌──────────────────┼──────────────────┐                     │
                                      ▼                  ▼                  ▼                     ▼
                               Entropy > 7.5    Entropy > 7.0      High ASCII?          File Signature?
                               Dist > 0.80      Dist > 0.75                              │
                                      │              │                  │           Yes  │  No
                                      ▼              ▼                  ▼                │
                               ┌───────────┐  ┌───────────┐     ┌───────────┐    ┌──────┴──────┐
                               │  WIPED    │  │  WIPED    │     │ NOT WIPED │    │  Medium     │
                               │  (DoD)    │  │ (Crypto)  │     │  (Text)   │    │  Entropy    │
                               └───────────┘  └───────────┘     └───────────┘    │  Analysis   │
                                                                                  └─────────────┘
```

**Status Meanings:**

| Status | Description |
|--------|-------------|
| **Wiped** | Sector matches known wipe patterns (zero, one, random) |
| **NOT Wiped** | Sector contains recoverable data |
| **Suspicious** | Sector may contain compressed/encrypted data |
| **Unreadable** | Sector could not be read (bad sector) |

**Customization - Adjusting Thresholds:**

```powershell
# In Test-SectorWiped.ps1

# Adjust entropy threshold for random detection
if ($entropy -gt 7.5) {  # Default: 7.5, lower = stricter
    # Very high entropy path
}

# Adjust distribution score threshold
if ($distribution -gt 0.80) {  # Default: 0.80, lower = more lenient
    # Good distribution
}

# Adjust ASCII ratio threshold
if ($asciiRatio -gt 0.7) {  # Default: 0.7, higher = stricter text detection
    # Likely text content
}
```

---

### 8. New-HtmlReport.ps1

**Purpose:** Generates a professional HTML verification report.

**Function:** `New-HtmlReport`

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `Technician` | string | Name of the technician |
| `Results` | hashtable | Scan results |
| `Disk` | object | Disk information object |
| `DiskNumber` | int | Physical disk number |
| `DiskSize` | long | Disk size in bytes |
| `TotalSamples` | int | Number of sectors analyzed |
| `WipedPercent` | double | Percentage of wiped sectors |
| `EntropyPercent` | double | Overall entropy percentage |
| `OverallStatus` | string | Final verification status |
| `SectorSize` | int | Sector size in bytes |

**Report Sections:**

1. **Header** - Report ID, title, verification status
2. **Disk Information** - Model, serial, capacity, bus type
3. **Analysis Summary** - Key metrics cards
4. **Detailed Sector Analysis** - Category breakdown
5. **Detected Wipe Patterns** - Pattern distribution
6. **Verification Methodology** - Parameters used
7. **Certification** - Signature blocks

**Customization - Adding Company Branding:**

```powershell
# In New-HtmlReport.ps1, modify the HTML template

# Add logo
<img src="file:///C:/Company/logo.png" style="height: 50px;" />

# Change colors
.status-verified {
    background: #your-brand-color;
    border-left: 5px solid #your-accent-color;
}

# Add footer text
<div class="footer">
    <p>Company Name - Internal Use Only</p>
    <p>Generated by Disk Wipe Verification Tool v2.1</p>
</div>
```

---

### 9. Convert-HtmlToPdf.ps1

**Purpose:** Converts HTML reports to PDF using available browsers.

**Function:** `Convert-HtmlToPdf`

**Conversion Priority:**

1. **Microsoft Edge (Chromium)** - Best quality, most common
2. **Google Chrome** - Good alternative
3. **Brave Browser** - Chrome-based alternative
4. **wkhtmltopdf** - Dedicated tool if installed
5. **Microsoft Word** - Fallback using COM automation

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

---

## Analysis Algorithms

### Wipe Verification Algorithm

The tool uses a multi-layered approach to determine if a sector is wiped:

```
Layer 1: Pattern Matching (Fast)
├── Check for all-zeros (0x00)
├── Check for all-ones (0xFF)
└── If matched → WIPED

Layer 2: Statistical Analysis
├── Calculate Shannon entropy
├── Calculate byte distribution score
├── Calculate ASCII ratio
└── Based on thresholds → Determine status

Layer 3: Signature Detection (Only for low entropy)
├── Check file magic numbers
└── If found → NOT WIPED
```

### DoD 5220.22-M Detection

The DoD 5220.22-M standard specifies a 3-pass wipe:

1. Pass 1: Write all zeros (0x00)
2. Pass 2: Write all ones (0xFF)
3. Pass 3: Write random data

Since the final pass overwrites previous passes, the tool detects the **random data pattern** of Pass 3:

- **High entropy** (> 7.0/8.0)
- **Uniform byte distribution** (> 0.75)
- **Low ASCII ratio** (< 0.5)

---

## GUI Components

### Main Window Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Disk Wipe Verification Tool                         │
├────────────────────────────────┬────────────────────────────────────────────┤
│                                │                                            │
│  PARAMETERS                    │  AVAILABLE DISKS                           │
│  ─────────────────            │  ──────────────                            │
│  Technician: [___________]    │  [Refresh Disks]                           │
│  Sample Size: [10000    ▼]    │  ┌────────────────────────────────────┐   │
│  □ Full Disk Scan             │  │ Disk 0: Samsung SSD 256GB          │   │
│  Sector Size: [512      ▼]    │  │ Disk 1: WD Blue 1TB                │   │
│  Report Format: [PDF    ▼]    │  │ Disk 2: USB Drive 32GB             │   │
│  Report Location: [Browse]    │  └────────────────────────────────────┘   │
│                                │                                            │
│  SCAN                          │  CONSOLE                                   │
│  ────                          │  ───────                                   │
│  Status: Ready                 │  ┌────────────────────────────────────┐   │
│  ████████████░░░░░░░░░░ 60%   │  │ [12:34:56] Scanning sector 5000   │   │
│  [Start Scan] [Cancel]        │  │ [12:34:57] Found wiped sector     │   │
│                                │  │ [12:34:58] Progress: 60%          │   │
│  ┌────────────────────┐       │  └────────────────────────────────────┘   │
│  │ VERIFICATION RESULT│       │                                            │
│  │      PASSED        │       │                                            │
│  └────────────────────┘       │                                            │
└────────────────────────────────┴────────────────────────────────────────────┘
```

### GUI Component Hierarchy

```
MainWindow (Form)
├── GroupBoxL (Left Panel)
│   ├── ParameterHeader (Label)
│   ├── TechnicianName (TextBox)
│   ├── SampleSize (NumericUpDown)
│   ├── FullDiskCheckBox (CheckBox)
│   ├── SectorInfoLabel (Label)
│   ├── SectorSize (ComboBox)
│   ├── ReportFormat (ComboBox)
│   ├── ReportPath (TextBox)
│   ├── ReportPathButton (Button)
│   ├── ScanHeader (Label)
│   ├── StatusLabel (Label)
│   ├── ScanProgress (ProgressBar)
│   ├── ProgressLabel (Label)
│   ├── StartScan (Button)
│   ├── CancelScan (Button)
│   └── VerificationPanel (Panel)
│       └── ResultLabel (Label)
│
└── GroupBoxR (Right Panel)
    ├── AvailableDiskHeader (Label)
    ├── RefreshDisks (Button)
    ├── DiskList (ListBox)
    ├── ConsoleHeader (Label)
    └── Console (RichTextBox)
```

---

## Data Flow

### Scan Execution Flow

```
┌───────────────┐
│ User Clicks   │
│ "Start Scan"  │
└───────┬───────┘
        │
        ▼
┌───────────────┐     ┌───────────────┐
│ Validate      │────▶│ Show Warning  │
│ Inputs        │ No  │ Dialog        │
└───────┬───────┘     └───────────────┘
        │ Yes
        ▼
┌───────────────┐
│ Confirm       │
│ Dialog        │
└───────┬───────┘
        │ Yes
        ▼
┌───────────────┐
│ Disable UI    │
│ Reset State   │
└───────┬───────┘
        │
        ▼
┌───────────────┐
│ Get-Parameters│
│ from GUI      │
└───────┬───────┘
        │
        ▼
┌───────────────┐
│ Load Modules  │
└───────┬───────┘
        │
        ▼
┌───────────────┐
│ Validate Disk │
│ Exists        │
└───────┬───────┘
        │
        ▼
┌───────────────┐
│ Get-Sample    │
│ Locations     │
└───────┬───────┘
        │
        ▼
┌───────────────────────────────────────┐
│          Main Scan Loop               │
│  ┌─────────────────────────────────┐  │
│  │ For each sector location:       │  │
│  │   1. Read-DiskSector            │  │
│  │   2. Test-SectorWiped           │  │
│  │   3. Update results             │  │
│  │   4. Update histogram           │  │
│  │   5. Update UI progress         │  │
│  │   6. Check cancel flag          │  │
│  └─────────────────────────────────┘  │
└───────────────┬───────────────────────┘
                │
                ▼
┌───────────────┐
│ Calculate     │
│ Overall       │
│ Entropy       │
└───────┬───────┘
        │
        ▼
┌───────────────┐
│ Determine     │
│ Final Status  │
└───────┬───────┘
        │
        ▼
┌───────────────┐
│ Generate      │
│ HTML Report   │
└───────┬───────┘
        │
        ▼
┌───────────────┐
│ Convert to    │
│ PDF (optional)│
└───────┬───────┘
        │
        ▼
┌───────────────┐
│ Show Complete │
│ Dialog        │
└───────┬───────┘
        │
        ▼
┌───────────────┐
│ Re-enable UI  │
└───────────────┘
```

### Data Structures

#### Results Hashtable

```powershell
$results = @{
    Wiped      = 0          # Count of wiped sectors
    NotWiped   = 0          # Count of not wiped sectors
    Suspicious = 0          # Count of suspicious sectors
    Unreadable = 0          # Count of unreadable sectors
    Patterns   = @{}        # Pattern -> Count mapping
    Details    = @()        # Array of detailed results (unused for memory optimization)
}
```

#### Running Histogram

```powershell
# 256-element array for byte frequency counting
$runningHistogram = New-Object 'long[]' 256

# Update for each sector
foreach ($byte in $sectorData) {
    $runningHistogram[$byte]++
}
$totalBytesRead += $sectorData.Length
```

---

## Memory Management

### Memory Optimization Techniques

The tool is optimized to handle large sample sizes (100,000+ sectors) on systems with limited RAM (8GB).

#### 1. Sample Location Generation

**Before (Memory-intensive):**
```powershell
$sampleLocations = @()
$sampleLocations += 0..99  # Creates new array each time
$sampleLocations += $random.Next(...)  # O(n) array resize
```

**After (Optimized):**
```powershell
$locationSet = New-Object 'System.Collections.Generic.HashSet[long]'
$locationSet.Add($sector) | Out-Null  # O(1) add
$sortedList = New-Object 'System.Collections.Generic.List[long]' $locationSet
```

**Memory Impact:**
- 100,000 sectors: ~800KB vs ~20MB+ (with array resizing overhead)

#### 2. Entropy Calculation

**Before (Memory-intensive):**
```powershell
$allBytes = New-Object System.Collections.ArrayList
foreach ($sectorNum in $sampleLocations) {
    $sectorData = Read-DiskSector ...
    $allBytes.AddRange($sectorData)  # Stores ALL bytes
}
$entropy = Get-ShannonEntropy -Data $allBytes.ToArray()
```

**After (Optimized):**
```powershell
$runningHistogram = New-Object 'long[]' 256  # Fixed 2KB
foreach ($sectorNum in $sampleLocations) {
    $sectorData = Read-DiskSector ...
    foreach ($byte in $sectorData) {
        $runningHistogram[$byte]++
    }
}
$entropy = Get-ShannonEntropyFromHistogram -Histogram $runningHistogram -TotalBytes $totalBytesRead
```

**Memory Impact:**
- 100,000 sectors x 512 bytes = ~50MB stored
- With running histogram: ~2KB fixed regardless of sample size

#### 3. Byte Frequency Counting

**Before:**
```powershell
$frequency = @{}  # Hashtable with object overhead
```

**After:**
```powershell
$frequency = New-Object 'int[]' 256  # Fixed array, no object overhead
```

### Memory Usage Summary

| Component | Old Approach | New Approach |
|-----------|--------------|--------------|
| Sample Locations | O(n) with reallocation | O(n) with HashSet |
| Byte Storage | O(n * sectorSize) | O(1) - 2KB fixed |
| Entropy Calculation | Requires all bytes | Uses histogram |
| **Total for 100K sectors** | ~200MB+ | ~2MB |

---

## Customization Guide

### Adding a New Wipe Pattern

1. **Add pattern detection in Test-SectorWiped.ps1:**

```powershell
# Add after zero-fill and one-fill checks

# Check for alternating pattern (0xAA)
$allAlternating = $true
foreach ($byte in $SectorData) {
    if ($byte -ne 0xAA) {
        $allAlternating = $false; break
    }
}
if ($allAlternating) {
    return @{
        Status = "Wiped"
        Pattern = "Alternating (0xAA)"
        Confidence = 100
        Details = "All bytes are 0xAA - custom wipe pattern"
    }
}
```

### Adding a New File Signature

1. **Add to $FileSignatures in Main.ps1:**

```powershell
$FileSignatures = @{
    # Existing signatures...
    
    # Add new signature
    "MP3" = @(0xFF, 0xFB)              # MP3 frame sync
    "WAVE" = @(0x52, 0x49, 0x46, 0x46) # RIFF header
    "OGG" = @(0x4F, 0x67, 0x67, 0x53)  # OggS
}
```

### Changing Verification Thresholds

1. **Edit Test-SectorWiped.ps1:**

```powershell
# Change from 99.5% to 99.0% for VERIFIED status
$overallStatus = if ($wipedPercent -ge 99.0) {  # Was 99.5
    "VERIFIED CLEAN - Disk Successfully Wiped"
}
```

2. **Edit Main.ps1 for overall status:**

```powershell
$overallStatus = if ($wipedPercent -ge 99.0) {  # Adjust threshold
    "VERIFIED CLEAN - Disk Successfully Wiped"
}
elseif ($wipedPercent -ge 90) {  # Was 95
    "MOSTLY CLEAN - Manual Review Recommended"
}
```

### Customizing the Report

1. **Edit New-HtmlReport.ps1:**

```powershell
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
<tr><td>Location</td><td>$Location</td></tr>
```

### Creating a Command-Line Version

Remove GUI dependencies and accept parameters:

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

## Troubleshooting

### Common Issues

#### "Disk not found" Error

**Cause:** Disk number doesn't exist or disk is offline.

**Solution:**
```powershell
# List available disks
Get-Disk | Format-Table Number, FriendlyName, Size, OperationalStatus

# Check if disk is online
Get-Disk -Number 0 | Select-Object OperationalStatus
```

#### "Access Denied" Error

**Cause:** Script not running as administrator.

**Solution:** Run PowerShell as Administrator, or right-click the script and select "Run as Administrator".

#### PDF Generation Fails

**Cause:** No supported browser installed.

**Solution:**
1. Install Microsoft Edge (Chromium)
2. Or install wkhtmltopdf from https://wkhtmltopdf.org/
3. HTML report will still be generated as fallback

#### Script Freezes with Large Sample Size

**Cause:** Memory exhaustion (should be fixed in optimized version).

**Solution:**
1. Ensure you're using the latest optimized version
2. Close other applications to free memory
3. Reduce sample size if still occurring

#### False Positives (Wiped disk shows NOT Wiped)

**Cause:** Low entropy threshold or sector read errors.

**Solution:**
1. Check for unreadable sector count
2. Adjust entropy thresholds in Test-SectorWiped.ps1
3. Verify disk health with manufacturer tools

#### False Negatives (Data present but shows Wiped)

**Cause:** Data has high entropy (compressed/encrypted files).

**Solution:**
1. Increase sample size
2. Lower the entropy threshold for random detection
3. Add specific file signatures for expected data types

### Debug Mode

Add debug output to trace execution:

```powershell
# In any module, add:
$DebugPreference = "Continue"
Write-Debug "Variable value: $variable"

# Or use Write-Console for GUI output:
Write-Console "Debug: Entropy = $entropy" "Yellow"
```

### Performance Profiling

```powershell
# Measure execution time
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
| 3.8.0203.01 | 2026-02-03 | Memory optimization for large samples |

---

## License

Copyright (c) 2026 Yannick Morgenthaler / JSW

Contact: yannick.morgenthaler@jsw.swiss

---

## References

- [DoD 5220.22-M Standard](https://www.dss.mil/)
- [NIST SP 800-88 Guidelines](https://csrc.nist.gov/publications/detail/sp/800-88/rev-1/final)
- [Shannon Entropy](https://en.wikipedia.org/wiki/Entropy_(information_theory))
- [Chi-Square Test](https://en.wikipedia.org/wiki/Chi-squared_test)
