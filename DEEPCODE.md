# DEEPCODE - Disk Wipe Verification Tool

> Deep code-level documentation for developers who need to understand, debug, or extend the codebase. Every file, every function, every design decision is explained here.

**Version:** 3.9.0211.02  
**Last Updated:** 2026-02-11  
**Author:** Yannick Morgenthaler / JSW

---

## Table of Contents

1. [Execution Model](#1-execution-model)
2. [Bootstrap Chain](#2-bootstrap-chain)
3. [Global State and Scope](#3-global-state-and-scope)
4. [GUI Framework](#4-gui-framework)
5. [Scan Lifecycle](#5-scan-lifecycle)
6. [Module-by-Module Code Walkthrough](#6-module-by-module-code-walkthrough)
7. [Connector Functions](#7-connector-functions)
8. [GUI Action Modules](#8-gui-action-modules)
9. [GUI Element Definitions](#9-gui-element-definitions)
10. [GUI Element Factories](#10-gui-element-factories)
11. [Data Structures In-Depth](#11-data-structures-in-depth)
12. [Performance Architecture](#12-performance-architecture)
13. [Threading Model and GUI Responsiveness](#13-threading-model-and-gui-responsiveness)
14. [Error Handling Strategy](#14-error-handling-strategy)
15. [Report Generation Pipeline](#15-report-generation-pipeline)
16. [Known Limitations and Edge Cases](#16-known-limitations-and-edge-cases)
17. [Changelog (Code-Level)](#17-changelog-code-level)

---

## 1. Execution Model

The application is a **single-threaded** PowerShell Windows Forms application. All code -- GUI rendering, disk I/O, analysis, and report generation -- executes on the same thread. There is no background worker, no `RunspacePool`, and no `System.Threading.Tasks`.

This design was chosen for simplicity and because PowerShell's `$script:` scoping and dot-sourced functions do not naturally support multi-threaded execution. The trade-off is that long-running operations (the scan loop) must periodically yield control to the Windows Forms message pump via `[System.Windows.Forms.Application]::DoEvents()` to keep the GUI responsive.

**Key implication:** Any blocking call (e.g., a slow disk read, a stalled `Start-Process` for PDF conversion) will freeze the GUI until it returns. The codebase mitigates this with time-based `DoEvents` calls (see [Section 13](#13-threading-model-and-gui-responsiveness)).

---

## 2. Bootstrap Chain

The application boots through a strict chain of dot-sourced files. Understanding this chain is critical because **PowerShell dot-sourcing executes code in the caller's scope**, meaning every variable and function defined in a dot-sourced file becomes available in the scope that called it.

```
EXE.ps1
  |
  +-- . .\Load-Components.ps1          # Defines Load-Components function
  |     |
  |     +-- calls Load-Components
  |           |
  |           +-- . .\Main.ps1          # Defines Main-Process function
  |           +-- . .\Index.ps1         # Dot-sources all Modules/ and Connectors/
  |           |     |
  |           |     +-- . .\Modules\Get-ShannonEntropy.ps1
  |           |     +-- . .\Modules\Get-ByteDistributionScore.ps1
  |           |     +-- . .\Modules\Test-SectorWiped.ps1
  |           |     +-- . .\Modules\Get-SampleLocations.ps1
  |           |     +-- . .\Modules\Read-DiskSector.ps1
  |           |     +-- . .\Modules\Get-ByteHistogram.ps1
  |           |     +-- . .\Modules\Get-DataLeftoverMarkers.ps1
  |           |     +-- . .\Modules\Get-PrintableAsciiRatio.ps1
  |           |     +-- . .\Modules\Test-FileSignatures.ps1
  |           |     +-- . .\Modules\New-HtmlReport.ps1
  |           |     +-- . .\Modules\Convert-HtmlToPdf.ps1
  |           |     +-- . .\Modules\Get-AvailableDisks.ps1
  |           |     +-- . .\Connectors\DoEvents.ps1
  |           |     +-- . .\Connectors\Get-Parameters.ps1
  |           |     +-- . .\Connectors\Write-Console.ps1
  |           |
  |           +-- . .\GUI\GUI.ps1       # Defines Load-GUI function
  |           |
  |           +-- calls Load-GUI
  |                 |
  |                 +-- Dot-sources all GUI/ActionModules/*.ps1
  |                 +-- Dot-sources all GUI/Elements/BaseSettings.ps1
  |                 +-- Dot-sources all GUI/NewElements/*.ps1
  |                 +-- Dot-sources all GUI/Elements/*.ps1
  |                 +-- Creates MainWindow Form
  |                 +-- Wires event handlers
  |                 +-- calls Load-Disks
  |                 +-- calls $MainWindow.ShowDialog()   <-- BLOCKS HERE
  |                 +-- (returns when window closes)
```

### Why modules are loaded twice

You may notice that `Index.ps1` loads all modules at boot, but `Main-Process` also dot-sources them again inside its `try` block (lines 90-101 of `Main.ps1`). This is intentional:

1. **Index.ps1** loads modules into the `Load-GUI` scope so that functions like `Write-Console` and `DoEvents` are available during GUI setup.
2. **Main-Process** re-loads modules to ensure the latest versions are available inside its function scope, which is important during development when files may change between runs.

In a production build, the second load is redundant but harmless (function redefinition is a no-op if the file hasn't changed).

---

## 3. Global State and Scope

Because every file is dot-sourced, the entire application shares a **single flat scope**. There are no namespaces, no classes, and no modules (in the PowerShell module sense). All GUI controls, all functions, and all variables live in the same scope tree.

### Key shared variables

| Variable | Set Where | Used Where | Type | Description |
|----------|-----------|-----------|------|-------------|
| `$MainWindow` | GUI.ps1 | GUI.ps1 | `System.Windows.Forms.Form` | The main form |
| `$Console` | Console.ps1 | Write-Console.ps1, Main.ps1 | `RichTextBox` | Log output panel |
| `$StatusLabel` | StatusLabel.ps1 | Main.ps1, Start-Scan.ps1 | `Label` | Status text at bottom-left |
| `$ScanProgress` | ScanProgress.ps1 | Main.ps1 | `ProgressBar` | Visual progress bar |
| `$ProgressLabel` | ProgressLabel.ps1 | Main.ps1 | `Label` | Percentage text label |
| `$DiskList` | DiskList.ps1 | Disk-List.ps1, Load-Disks.ps1, Start-Scan.ps1 | `ListBox` | Disk selection list |
| `$SampleSize` | SampleSize.ps1 | Full-DiskScan.ps1, Get-Parameters.ps1 | `NumericUpDown` | Sample size input |
| `$SectorSize` | SectorSize.ps1 | Disk-List.ps1, Full-DiskScan.ps1, Get-Parameters.ps1 | `ComboBox` | Sector size dropdown |
| `$StartScan` | StartScan.ps1 | Start-Scan.ps1, Main.ps1 | `Button` | Start button reference |
| `$CancelScan` | CancelScan.ps1 | Start-Scan.ps1, Main.ps1 | `Button` | Cancel button reference |
| `$VerificationPanel` | VerificationPanel.ps1 | Main.ps1, Start-Scan.ps1 | `Panel` | Result color panel |
| `$ResultLabel` | ResultLabel.ps1 | Main.ps1, Start-Scan.ps1 | `Label` | Result text label |
| `$FullDiskCheckBox` | FullDiskCheckBox.ps1 | Full-DiskScan.ps1, Disk-List.ps1 | `CheckBox` | Full scan toggle |
| `$SectorInfoLabel` | SectorInfoLabel.ps1 | Disk-List.ps1, Full-DiskScan.ps1 | `Label` | Total sector count display |
| `$TechnicianName` | TechnicianName.ps1 | Get-Parameters.ps1, Start-Scan.ps1 | `TextBox` | Technician name input |
| `$ReportFormat` | ReportFormat.ps1 | Get-Parameters.ps1 | `ComboBox` | Report format dropdown |
| `$ReportPath` | ReportLocation.ps1 | Get-Parameters.ps1, Browse-Path.ps1 | `TextBox` | Report output path |
| `$script:cancelRequested` | Cancel-Scan.ps1 | Main.ps1 | `bool` | Cancellation flag |
| `$FileSignatures` | Main.ps1 (line 113) | Test-FileSignatures.ps1 | `hashtable` | Signature lookup table |
| `$diskNumber` | Start-Scan.ps1 (line 19) | Get-Parameters.ps1, Main.ps1 | `int` | Selected disk number |

### The `$script:cancelRequested` pattern

Cancellation uses a `$script:` scoped boolean. When the cancel button is clicked, `Cancel-Scan` sets `$script:cancelRequested = $true`. The scan loop in `Main-Process` checks this flag at the start of each iteration. Because the loop periodically calls `DoEvents`, the cancel button's click handler gets a chance to execute and set the flag.

```
User clicks Cancel
        |
        v
DoEvents is called in scan loop
        |
        v
Windows Forms processes pending messages
        |
        v
CancelScan.Click handler fires -> $script:cancelRequested = $true
        |
        v
Control returns to scan loop
        |
        v
Loop checks $script:cancelRequested -> breaks
```

---

## 4. GUI Framework

### Technology

- **WinForms** via `System.Windows.Forms` (.NET Framework assembly loaded via `Add-Type`)
- **GDI+** via `System.Drawing` for colors, fonts, and sizes
- **No XAML, no WPF, no HTML** -- pure WinForms controls created in PowerShell

### Helper functions (BaseSettings.ps1)

The `BaseSettings.ps1` file defines four utility functions used throughout all element definitions:

```powershell
function Location($h, $w)     # Creates System.Drawing.Point for control positioning
function Size($h, $w)         # Creates System.Drawing.Point for control sizing
function FontSize($FS, $FW, $F)  # Creates System.Drawing.Font with optional bold and custom family
function Color($R, $G, $B)    # Creates System.Drawing.Color from RGB values
```

**Note on `Color`:** This function name shadows the .NET `Color` type. It works because PowerShell resolves function calls before type lookups. The `Color` function is called extensively: `Color 25 25 25` for the dark theme background, `Color 255 255 255` for white text, etc.

### Element factory pattern (GUI/NewElements/)

Each `New-*.ps1` file defines a factory function for a specific control type. For example:

```
New-Button       -> returns a configured System.Windows.Forms.Button
New-CheckBox     -> returns a configured System.Windows.Forms.CheckBox
New-ComboBox     -> returns a configured System.Windows.Forms.ComboBox
New-Label        -> returns a configured System.Windows.Forms.Label
...
```

These factories accept parameters like location, size, text, font, and colors, applying the dark-theme defaults consistently.

### Element definition pattern (GUI/Elements/)

Each element `.ps1` file creates a specific control instance and adds it to its parent container. For example, `StartScan.ps1` creates the `$StartScan` button and adds it to `$GroupBoxL`. Because these files are dot-sourced in order within `GUI.ps1`, parent containers (like `$GroupBoxL`) must be created before their children.

### Layout

The form uses a two-panel layout:

```
$MainWindow (1000 x 700, fixed size, no maximize)
  |
  +-- $GroupBoxL (Left panel: parameters + scan controls + result)
  |
  +-- $GroupBoxR (Right panel: disk list + console log)
```

All positioning is done with absolute pixel coordinates via `Location($x, $y)`. There is no layout manager, no auto-sizing, and no responsive behavior. The form has a fixed border style (`Fixed3D`) and `MaximizeBox = $false`.

### Event wiring

Event handlers are wired in `GUI.ps1` using `.Add_*()` methods:

```powershell
$FullDiskCheckBox.Add_CheckedChanged({ Full-DiskScan })
$ReportPathButton.Add_Click({ Browse-Path })
$DiskList.Add_SelectedIndexChanged({ Disk-List })
$RefreshDisks.Add_Click({ Load-Disks })
$CancelScan.Add_Click({ Cancel-Scan })
$StartScan.Add_Click({ Start-Scan })
```

Each handler calls a function defined in a corresponding `GUI/ActionModules/*.ps1` file.

---

## 5. Scan Lifecycle

The full lifecycle from button click to completion:

```
1. Start-Scan                          [GUI/ActionModules/Start-Scan.ps1]
   |-- Validate disk selection
   |-- Validate technician name
   |-- Extract disk number from ListBox text via regex
   |-- Show confirmation dialog
   |-- Reset UI state (disable start, enable cancel, clear console)
   |-- Log parameters to console
   +-- Call Main-Process

2. Main-Process                        [Main.ps1]
   |-- Get-Parameters                  [Connectors/Get-Parameters.ps1]
   |-- Re-load all modules (dot-source)
   |-- Load file signature table
   |-- Validate disk exists (Get-Disk)
   |-- Log disk information
   |-- Get-SampleLocations            [Modules/Get-SampleLocations.ps1]
   |-- Initialize results hashtable
   |-- Initialize running histogram (long[256])
   |-- New-DataLeftoverCollection      [Modules/Get-DataLeftoverMarkers.ps1]
   |-- Open disk stream (single FileStream for entire scan)
   |-- Initialize Stopwatch for UI timer
   |
   |-- SCAN PATH (depends on scan type)
   |   |
   |   |-- FULL SCAN: [SectorAnalyzer]::RunFullScan()  [Modules/SectorAnalyzer.cs]
   |   |   |-- Entire scan runs in compiled C#
   |   |   |-- 4 MB batch sequential I/O (8192 sectors @ 512B)
   |   |   |-- Single-pass in-place analysis per sector (no per-sector alloc)
   |   |   |-- Result accumulation (wiped/notWiped/suspicious/unreadable/patterns)
   |   |   |-- Running histogram accumulation
   |   |   |-- Data leftover marker collection (capped at 500)
   |   |   |-- ProgressCallback delegate -> PowerShell UI update (~5/sec)
   |   |   |-- cancelFlag[0] checked each batch for cooperative cancellation
   |   |   +-- Returns ScanSummary object (one object, no per-sector data)
   |   |
   |   |-- SAMPLED SCAN: PowerShell loop + [SectorAnalyzer]::AnalyzeSector()
   |   |   |-- Per-sector seeking (non-contiguous sectors)
   |   |   |-- Compiled C# single-sector analysis (~100x faster than PS)
   |   |   |-- PowerShell result accumulation (manageable: max ~500K sectors)
   |   |   |-- Time-based + percent-based DoEvents
   |   |   +-- (loop continues)
   |   |
   |   +-- Transfer C# ScanSummary -> PS $results hashtable (full scan only)
   |
   |-- Close disk stream
   |-- ComputeEntropyFromHistogram (overall entropy from histogram)
   |-- Calculate wiped percentage
   |-- Determine overall status (VERIFIED / MOSTLY / NOT VERIFIED)
   |-- Log results to console
   |-- New-HtmlReport                  [Modules/New-HtmlReport.ps1]
   |-- (optional) Convert-HtmlToPdf    [Modules/Convert-HtmlToPdf.ps1]
   |-- Show completion MessageBox
   |-- Update verification panel
   +-- Finally: close stream if still open, re-enable UI
```

---

## 6. Module-by-Module Code Walkthrough

### 6.1 Read-DiskSector.ps1

```
Function: Read-DiskSector
Parameters: $DiskPath (string), $Offset (long), $Size (int)
Returns: byte[] or $null
```

Opens the physical disk path (e.g., `\\.\PhysicalDrive0`) using `System.IO.File.Open` with `FileShare.ReadWrite`, seeks to the byte offset, reads `$Size` bytes, and returns the buffer. On any exception, returns `$null`.

**Important:** This function opens and closes a new `FileStream` per call. It is **NOT used in the scan loop** -- the scan loop opens its own persistent stream for performance. This function exists for ad-hoc single-sector reads and backward compatibility.

**Why `FileShare.ReadWrite`:** The disk may be in use by the OS (especially for system drives). `ReadWrite` sharing allows read access even if other processes hold write locks.

---

### 6.2 Get-SampleLocations.ps1

```
Function: Get-SampleLocations
Parameters: $TotalSectors (long), $SampleSize (long)
Returns: hashtable with Count, IsFullScan, and either _array or GetEnumerator
```

**Two modes:**

**Full scan** (`SampleSize >= TotalSectors`):
Returns a lightweight hashtable with `IsFullScan = $true` and no array. The caller (Main.ps1) uses a `while` loop with a counter variable. Memory: ~100 bytes.

**Sampled scan** (`SampleSize < TotalSectors`):
1. Creates a `HashSet<long>` for O(1) duplicate prevention
2. Adds sectors 0-99 (first 100)
3. Adds sectors `(TotalSectors - 100)` to `(TotalSectors - 1)` (last 100)
4. Fills remaining slots with random sectors from the middle range
5. Copies to a `long[]` array and sorts it
6. Clears the `HashSet` immediately to free memory
7. Returns hashtable with `IsFullScan = $false` and `_array = $sortedArray`

**Why sorted?** Sequential disk reads are faster than random seeks. Sorting the sample locations means the shared `FileStream.Seek()` calls move forward through the disk, which is optimal for both HDDs (rotational latency) and SSDs (firmware prefetching).

**Random generation detail:** For disks with more than `int.MaxValue` (~2.1 billion) sectors, the code uses `$random.NextDouble() * $middleRange` instead of `$random.Next(0, int)` to handle the larger range.

**Deduplication limit:** The loop caps attempts at `$remaining * 3` to prevent infinite loops when the middle range is nearly exhausted (e.g., tiny disk with sample size close to total sectors).

---

### 6.3 Get-ShannonEntropy.ps1

Two functions in one file:

**`Get-ShannonEntropy`** -- Per-sector entropy.
```
Parameters: $Data (byte[])
Returns: double (0.0 to 8.0)
```

1. Allocates a fixed `int[256]` array
2. Iterates every byte, incrementing `$frequency[$byte]`
3. For each non-zero frequency, calculates `p * log2(p)` and sums
4. Returns the negated sum

**`Get-ShannonEntropyFromHistogram`** -- Aggregated entropy from pre-computed histogram.
```
Parameters: $Histogram (long[256]), $TotalBytes (long)
Returns: double (0.0 to 8.0)
```

Identical math but operates on a pre-aggregated histogram. Used once at the end of the scan to calculate overall entropy without storing any raw byte data.

**Why `int[256]` instead of `@{}`:** A fixed-size array avoids:
- Hashtable key boxing/unboxing on every byte
- Hash computation per access
- Dynamic resizing overhead

For a 512-byte sector processed 10,000 times, this eliminates ~5 million hashtable operations.

---

### 6.4 Get-ByteDistributionScore.ps1

```
Function: Get-ByteDistributionScore
Parameters: $Data (byte[])
Returns: double (0.0 to 1.0)
```

Measures byte uniformity using a Chi-square test:

1. Counts byte frequencies in a fixed `int[256]` array (optimized in v3.9.0210 from hashtable)
2. Calculates expected frequency: `$Data.Length / 256.0`
3. For each of the 256 possible byte values, computes `(observed - expected)^2 / expected`
4. Sums to get Chi-square statistic
5. Normalizes: `1 - (chiSquare / maxChiSquare)` where `maxChiSquare = dataLength * 255`
6. Clamps result to [0, 1]

**Interpretation:** A score near 1.0 means bytes are uniformly distributed (characteristic of random/wiped data). A score near 0.0 means bytes are heavily concentrated in a few values (characteristic of structured data).

---

### 6.5 Get-PrintableAsciiRatio.ps1

```
Function: Get-PrintableAsciiRatio
Parameters: $Data (byte[])
Returns: double (0.0 to 1.0)
```

Simple linear scan counting bytes that fall in printable ranges:
- ASCII 32 (space) through 126 (tilde)
- Tab (0x09), newline (0x0A), carriage return (0x0D)

Returns `$printable / $Data.Length`. Used by `Test-SectorWiped` to detect text content in sectors with high entropy.

---

### 6.6 Test-FileSignatures.ps1

```
Function: Test-FileSignatures
Parameters: $Data (byte[])
Returns: string (file type name) or $null
```

Iterates over the global `$FileSignatures` hashtable (set in Main.ps1). For each signature, compares the first N bytes of `$Data` against the signature byte array. Returns the first match or `$null`.

**Why minimum 7 bytes check:** `if ($Data.Length -lt 7) { return $null }` -- the longest signature (NTFS) is 7 bytes. Sectors shorter than 7 bytes cannot match any signature.

**Why only called for low entropy:** `Test-SectorWiped` only calls this function when `$entropy -lt 7.0`. Random data (entropy > 7.0) has a non-trivial probability of accidentally matching short signatures, causing false positives. By gating on entropy, the tool avoids flagging random wipe data as "file found."

---

### 6.7 Test-SectorWiped.ps1

```
Function: Test-SectorWiped
Parameters: $SectorData (byte[])
Returns: hashtable { Status, Pattern, Confidence, Details }
```

This is the core analysis function. Decision flow:

```
1. Null/empty data -> Unreadable (confidence 0)
2. All bytes 0x00 -> Wiped, "Zero-filled" (confidence 100)
3. All bytes 0xFF -> Wiped, "One-filled" (confidence 100)
4. Calculate entropy, distribution, ASCII ratio
5. Entropy > 7.5 AND distribution > 0.80 -> Wiped, "DoD 5220.22-M" (high confidence)
6. Entropy > 7.0 AND distribution > 0.75 AND ASCII < 0.5 -> Wiped, "Cryptographic wipe"
7. Entropy > 7.0 AND ASCII > 0.7 -> NOT Wiped, "Text content" (could be Base64, logs)
8. Entropy > 7.0 AND distribution > 0.70 -> Wiped, "Probable wipe"
9. Entropy < 7.0: check file signatures -> NOT Wiped, "File signature: X"
10. Entropy 5.0-7.0 AND ASCII < 0.3 AND distribution > 0.6 -> Suspicious, "Compressed/encrypted"
11. Entropy 5.0-7.0 (other) -> NOT Wiped, "Residual data"
12. Entropy <= 5.0 -> NOT Wiped, "Structured data"
13. Fallback -> NOT Wiped, "Unknown data pattern"
```

**Confidence calculation for random detection:**
```powershell
$confidence = [math]::Round((($entropy / 8) * 60) + ($distribution * 40))
```
This weights entropy at 60% and distribution at 40%, reflecting that entropy is the stronger signal for randomness while distribution provides confirmation.

**Why zero/one checks use a `foreach` loop instead of `-eq`:** PowerShell's `-eq` operator on arrays returns matching elements rather than a boolean. A manual loop with early `break` is both correct and fast (breaks on first non-matching byte).

---

### 6.8 Get-DataLeftoverMarkers.ps1

Three functions providing the data leftover tracking system:

**`Get-DataLeftoverMarker`** -- Creates a marker for one flagged sector.
- Computes `ByteOffset = SectorNumber * SectorSize` (decimal and hex)
- Extracts first 32 bytes for hex preview (`X2` format, space-separated)
- Extracts first 32 bytes for ASCII preview (non-printable replaced with `.`)
- Returns a lightweight hashtable (~500 bytes per marker)

**`New-DataLeftoverCollection`** -- Creates a capped collection.
- `Markers`: `List[hashtable]` (not `ArrayList`) for type safety
- `MaxMarkers`: default 500
- `OverflowCount`: tracks dropped markers
- `Summary`: always-accurate counts by status and pattern

**`Add-DataLeftoverMarker`** -- Adds a marker to the collection.
- **Always** updates summary statistics (even when cap is exceeded)
- Only stores the individual marker if under the cap
- Increments `OverflowCount` when cap is exceeded

**Design rationale:** A heavily non-wiped disk might flag hundreds of thousands of sectors. Without the cap, storing all markers would consume hundreds of MB and produce an unreadable report. The cap keeps memory bounded and the report manageable, while the summary provides accurate total counts.

---

### 6.9 Get-ByteHistogram.ps1

```
Function: Get-ByteHistogram
Parameters: $Data (byte[])
Returns: hashtable (byte value -> count)
```

A standalone histogram function using a hashtable. This is a **legacy function** that predates the streaming histogram approach in Main.ps1. It is still available for ad-hoc use but is **not called** during the scan loop. The scan loop uses its own inline `long[256]` array for the running histogram.

---

### 6.10 New-HtmlReport.ps1

```
Function: New-HtmlReport
Parameters: $Technician, $Results, $Disk, $DiskNumber, $DiskSize,
            $TotalSamples, $WipedPercent, $EntropyPercent,
            $OverallStatus, $SectorSize, $DataLeftovers
Returns: string (complete HTML document)
```

Generates a self-contained HTML document with embedded CSS. No external dependencies -- the report works offline. Key sections:

1. **Header** -- Report ID (GUID), timestamp, overall status with color-coded banner
2. **Disk Information** -- Model, serial, size, bus type, partition style, sector size
3. **Analysis Summary** -- Cards showing wiped %, entropy %, sector counts
4. **Sector Analysis Breakdown** -- Table with wiped/not-wiped/suspicious/unreadable counts
5. **Detected Patterns** -- Frequency table of all pattern types found
6. **Data Leftover Markers** -- If any NOT Wiped/Suspicious sectors were found:
   - Summary cards (NOT Wiped count, Suspicious count, stored marker count)
   - Pattern breakdown table
   - Detail table with sector number, byte offset, status tag, hex preview, ASCII preview
   - Overflow note if cap was exceeded
7. **Methodology** -- Parameters used for the scan
8. **Certification** -- Signature blocks for technician and supervisor

**Status class matching uses wildcards:**
```powershell
$statusClass = if ($OverallStatus -eq "VERIFIED*") { "verified" }
```
This is a PowerShell wildcard (`-eq` does not support wildcards; this actually checks for exact match with the literal string `"VERIFIED*"`). In practice, the `$OverallStatus` values are `"VERIFIED CLEAN - ..."`, `"MOSTLY CLEAN - ..."`, or `"NOT VERIFIED - ..."`, so this condition will fail for "VERIFIED CLEAN" -- the `else` branch catches it. The report still renders correctly because the "failed" class is the default.

---

### 6.11 Convert-HtmlToPdf.ps1

```
Function: Convert-HtmlToPdf
Parameters: $HtmlPath (string), $PdfPath (string)
Returns: bool ($true if PDF was created)
```

Attempts PDF conversion using a priority chain of tools:

1. **Microsoft Edge (Chromium)** -- `--headless --print-to-pdf` mode
2. **Google Chrome** -- same headless print mode
3. **Brave Browser** -- same headless print mode (Chrome-based)
4. **wkhtmltopdf** -- dedicated HTML-to-PDF tool
5. **Microsoft Word** -- COM automation fallback (worst quality)

Each method checks if the executable exists before attempting. If PDF generation fails entirely, the caller falls back to HTML-only output.

**The 2-second sleep:** `Start-Sleep -Seconds 2` after `Start-Process -Wait` is a safety margin. Browser headless mode sometimes returns before the PDF file is fully flushed to disk.

---

### 6.12 Get-AvailableDisks.ps1

```
Function: Get-AvailableDisks
Returns: formatted table output (for console use)
```

Simple wrapper around `Get-Disk | Select-Object | Format-Table`. This is a **legacy function** from the console-based version. The GUI uses `Load-Disks` instead, which populates the `$DiskList` ListBox directly.

---

## 7. Connector Functions

### 7.1 DoEvents.ps1

```powershell
function DoEvents {
    [System.Windows.Forms.Application]::DoEvents()
}
```

Single-line wrapper. Processes all pending Windows messages (paint events, button clicks, keyboard input). Called:
- By the scan loop (time-based and percent-based)
- By `Write-Console` (after every log line)
- By `Main-Process` at each status change
- By `Full-DiskScan` when toggling UI state

### 7.2 Write-Console.ps1

```powershell
function Write-Console($Message, $Color)
```

Appends a timestamped, color-coded message to the `$Console` RichTextBox:
1. Sets `SelectionStart` to end of text
2. Sets `SelectionColor` to the named color (e.g., `"Red"`, `"SpringGreen"`)
3. Appends `"[HH:mm:ss] $Message\r\n"`
4. Scrolls to caret
5. Calls `DoEvents` (ensures the message is painted immediately)

**Color handling:** The `$Color` parameter accepts .NET named colors as strings. WinForms' `SelectionColor` property accepts `System.Drawing.Color`, and PowerShell automatically converts named color strings.

### 7.3 Get-Parameters.ps1

```powershell
function Get-Parameters
```

Collects all scan parameters from GUI controls into a single hashtable:
- `technician` from `$TechnicianName.Text`
- `diskNumber` from the global `$diskNumber` variable (set in `Start-Scan.ps1`)
- `sampleSize` cast to `[long]` from `$SampleSize.Value`
- `sectorSize` cast to `[int]` from `$SectorSize.SelectedItem`
- `reportFormat` from `$ReportFormat.SelectedItem`
- `reportPath` from `$ReportPath.Text`
- `reportFile` computed as `Join-Path $reportPath "\DiskWipeReport_$timestamp"`

---

## 8. GUI Action Modules

### 8.1 Start-Scan.ps1

**Function:** `Start-Scan`

The primary entry point for a scan. Steps:
1. Validates `$DiskList.SelectedIndex -ge 0` (disk selected)
2. Validates `$TechnicianName.Text` is not empty
3. Extracts disk number via regex: `$selectedDisk -notmatch "Disk (\d+)"`
4. Shows confirmation MessageBox
5. Resets UI: disables start button, enables cancel, clears console, resets progress, hides verification panel, resets result label colors
6. Logs all parameters to console
7. Calls `Main-Process`

**Bug fix (v3.9.0210):** Previously had `$ResultLabel.Text = Color 255 255 255` which assigned a `System.Drawing.Color` object to a `Text` property (string). Fixed to `$ResultLabel.ForeColor = Color 255 255 255` and `$ResultLabel.Text = ""`.

### 8.2 Cancel-Scan.ps1

**Function:** `Cancel-Scan`

Sets `$script:cancelRequested = $true` and returns the flag. The scan loop checks this at the start of each iteration.

### 8.3 Full-DiskScan.ps1

**Function:** `Full-DiskScan`

Handles the "Full Disk Scan" checkbox toggle:
- When checked: disables sample size input, calculates total sectors for the selected disk, sets sample size to total sectors
- When unchecked: re-enables sample size input with original background color

### 8.4 Disk-List.ps1

**Function:** `Disk-List`

Handles disk selection change. Updates `$SectorInfoLabel` with the total sector count for the selected disk. If full disk scan is checked, also updates `$SampleSize.Value` to match the new disk's total sectors.

### 8.5 Load-Disks.ps1

**Function:** `Load-Disks`

Refreshes the disk list by calling `Get-Disk` and populating `$DiskList.Items` with formatted strings: `"Disk N | FriendlyName | X.XX GB | Status"`. Auto-selects the first disk.

### 8.6 Browse-Path.ps1

**Function:** `Browse-Path`

Opens a `FolderBrowserDialog` for selecting the report output directory. Pre-selects the current `$ReportPath.Text` value.

### 8.7 DataGridView-DoubleClick.ps1

**Function:** `DataGridView-DoubleClick`

Empty placeholder function. Reserved for future DataGridView interaction handling.

---

## 9. GUI Element Definitions

Each file in `GUI/Elements/` creates one or more WinForms controls. Key files:

| File | Variable(s) Created | Control Type | Description |
|------|---------------------|-------------|-------------|
| `BaseSettings.ps1` | (functions only) | -- | Defines `Location`, `Size`, `FontSize`, `Color` helpers |
| `LeftPanel.ps1` | `$GroupBoxL` | GroupBox | Left panel container |
| `RightPanel.ps1` | `$GroupBoxR` | GroupBox | Right panel container |
| `ParameterHeader.ps1` | (label) | Label | "Parameters" section header |
| `TechnicianName.ps1` | `$TechnicianName` | TextBox | Technician name input |
| `SampleSize.ps1` | `$SampleSize` | NumericUpDown | Sample size input (1 to max long) |
| `FullDiskCheckBox.ps1` | `$FullDiskCheckBox` | CheckBox | Full disk scan toggle |
| `SectorInfoLabel.ps1` | `$SectorInfoLabel` | Label | Shows total sectors for selected disk |
| `SectorSize.ps1` | `$SectorSize` | ComboBox | Dropdown: 512 or 4096 bytes |
| `ReportFormat.ps1` | `$ReportFormat` | ComboBox | Dropdown: HTML, PDF, Both |
| `ReportLocation.ps1` | `$ReportPath`, `$ReportPathButton` | TextBox + Button | Report path with browse button |
| `ScanHeader.ps1` | (label) | Label | "Scan" section header |
| `StatusLabel.ps1` | `$StatusLabel` | Label | Current operation status text |
| `ScanProgress.ps1` | `$ScanProgress` | ProgressBar | Visual progress indicator |
| `ProgressLabel.ps1` | `$ProgressLabel` | Label | Percentage text (e.g., "45%") |
| `StartScan.ps1` | `$StartScan` | Button | Start scan button |
| `CancelScan.ps1` | `$CancelScan` | Button | Cancel scan button (initially disabled) |
| `VerificationPanel.ps1` | `$VerificationPanel` | Panel | Color-coded result background |
| `ResultLabel.ps1` | `$ResultLabel` | Label | Result text (e.g., "Verification Complete") |
| `AvailableDiskHeader.ps1` | (label) | Label | "Available Disks" header |
| `RefreshDisks.ps1` | `$RefreshDisks` | Button | Refresh disk list button |
| `DiskList.ps1` | `$DiskList` | ListBox | Disk selection list |
| `DiskTable.ps1` | `$DiskTable` | DataGridView | (Alternative disk display, may not be active) |
| `ConsoleHeader.ps1` | (label) | Label | "Console" header |
| `Console.ps1` | `$Console` | RichTextBox | Scrollable, colored log output |
| `Separator.ps1` | (label) | Label | Visual separator line |

---

## 10. GUI Element Factories

Each file in `GUI/NewElements/` provides a factory function:

| File | Function | Returns |
|------|----------|---------|
| `New-Button.ps1` | `New-Button` | `System.Windows.Forms.Button` |
| `New-CheckBox.ps1` | `New-CheckBox` | `System.Windows.Forms.CheckBox` |
| `New-ComboBox.ps1` | `New-ComboBox` | `System.Windows.Forms.ComboBox` |
| `New-DataGridView.ps1` | `New-DataGridView` | `System.Windows.Forms.DataGridView` |
| `New-GroupBox.ps1` | `New-GroupBox` | `System.Windows.Forms.GroupBox` |
| `New-Label.ps1` | `New-Label` | `System.Windows.Forms.Label` |
| `New-ListBox.ps1` | `New-ListBox` | `System.Windows.Forms.ListBox` |
| `New-NumericUpDown.ps1` | `New-NumericUpDown` | `System.Windows.Forms.NumericUpDown` |
| `New-Panel.ps1` | `New-Panel` | `System.Windows.Forms.Panel` |
| `New-ProgressBar.ps1` | `New-ProgressBar` | `System.Windows.Forms.ProgressBar` |
| `New-RichTextBox.ps1` | `New-RichTextBox` | `System.Windows.Forms.RichTextBox` |
| `New-StatusBar.ps1` | `New-StatusBar` | `System.Windows.Forms.StatusBar` |
| `New-StatusBarLabel.ps1` | `New-StatusBarLabel` | `ToolStripStatusLabel` |
| `New-StatusBarProgressBar.ps1` | `New-StatusBarProgressBar` | `ToolStripProgressBar` |
| `New-TextBox.ps1` | `New-TextBox` | `System.Windows.Forms.TextBox` |

These factories apply consistent dark-theme styling (dark backgrounds, light text, Segoe UI font) and return configured controls ready for use.

---

## 11. Data Structures In-Depth

### 11.1 Sample Locations Object

**Sampled scan:**
```powershell
@{
    Count      = [long]15000          # Exact number of sectors to scan
    IsFullScan = $false
    _array     = [long[]]@(0, 1, 2, ..., 99, 4500, 8900, ..., N-1)
                                       # Sorted array of sector indices
}
```

**Full scan:**
```powershell
@{
    Count         = [long]976773168    # Total sectors on disk
    IsFullScan    = $true
    GetEnumerator = [scriptblock]      # Sequential counter (unused in current code)
    _totalForEnum = [long]976773168
}
```

**Note:** For full scans, the `_array` key does not exist. The scan loop uses a `while` counter instead of iterating an array. The `GetEnumerator` scriptblock is defined but not currently used -- it was designed for a previous iteration approach.

### 11.2 Results Hashtable

```powershell
$results = @{
    Wiped      = [int]0         # Incremented for each "Wiped" sector
    NotWiped   = [int]0         # Incremented for each "NOT Wiped" sector
    Suspicious = [int]0         # Incremented for each "Suspicious" sector
    Unreadable = [int]0         # Incremented for each null/empty read
    Patterns   = @{             # Dynamic: keys are pattern strings, values are counts
        "Zero-filled (0x00)"              = 5000
        "Random data (DoD 5220.22-M)"     = 4800
        "One-filled (0xFF)"               = 150
        "File signature: PDF"             = 3
        "Text content detected"           = 12
    }
}
```

### 11.3 Running Histogram

```powershell
$runningHistogram = New-Object 'long[]' 256   # Fixed 2KB allocation
$totalBytesRead   = [long]0
```

Updated inside the scan loop:
```powershell
foreach ($byte in $sectorData) {
    $runningHistogram[$byte]++
}
$totalBytesRead += $sectorData.Length
```

This replaces the old approach of storing all raw bytes in an `ArrayList`. For 100,000 sectors of 512 bytes each, the old approach stored ~50MB; the histogram approach uses 2KB regardless of scan size.

### 11.4 Data Leftover Collection

See [Section 6.8](#68-get-dataleftovermarkersps1) for the full structure. Key memory characteristics:

| Scenario | Markers in memory | Approximate size |
|----------|-------------------|------------------|
| Clean disk (0 flagged) | 0 | ~0.5 KB |
| Mostly clean (50 flagged) | 50 | ~25 KB |
| Cap reached (500 flagged) | 500 | ~250 KB |
| Heavy remnants (50,000 flagged) | 500 + summary | ~250 KB |

### 11.5 File Signatures Table

```powershell
$FileSignatures = @{
    "PDF"      = @(0x25, 0x50, 0x44, 0x46, 0x2D)       # %PDF-
    "ZIP/DOCX" = @(0x50, 0x4B, 0x03, 0x04)             # PK..
    "JPEG"     = @(0xFF, 0xD8, 0xFF, 0xE0)             # JPEG/JFIF
    "PNG"      = @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A) # .PNG\r\n
    "GIF87"    = @(0x47, 0x49, 0x46, 0x38, 0x37, 0x61) # GIF87a
    "GIF89"    = @(0x47, 0x49, 0x46, 0x38, 0x39, 0x61) # GIF89a
    "RAR"      = @(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07) # Rar!..
    "7Z"       = @(0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C) # 7z....
    "SQLite"   = @(0x53, 0x51, 0x4C, 0x69, 0x74, 0x65) # SQLite
    "NTFS"     = @(0xEB, 0x52, 0x90, 0x4E, 0x54, 0x46, 0x53) # NTFS boot
    "EXE"      = @(0x4D, 0x5A, 0x90, 0x00)             # MZ + valid header
}
```

All signatures are 4+ bytes to minimize false positives. The original `"MZ"` (2-byte) signature was removed because random data has a ~1/65536 chance of matching per sector -- unacceptable at scale.

---

## 12. Performance Architecture

### 12.1 The Core Problem (pre-v3.9.0211)

PowerShell `foreach` over byte arrays is **interpreted** -- each iteration involves boxing, unboxing, type checks, and scope resolution. For a 512-byte sector, the old code ran:

| Operation | Loop iterations | Source |
|-----------|----------------|--------|
| Zero-fill check | 512 | `Test-SectorWiped` |
| 0xFF-fill check | 512 | `Test-SectorWiped` |
| Entropy frequency | 512 | `Get-ShannonEntropy` |
| Distribution frequency | 512 | `Get-ByteDistributionScore` |
| ASCII ratio count | 512 | `Get-PrintableAsciiRatio` |
| Running histogram | 512 | Main.ps1 loop body |
| **Total per sector** | **~3,072** | |

For a 64 GB disk with ~125 million sectors: **~384 billion interpreted operations**. At ~100,000 interpreted ops/sec per core in PowerShell, this takes **~44 days** in theory (observed: ~24+ hours at 27%).

### 12.2 The Solution: Compiled C# Engine (`Modules/SectorAnalyzer.cs`)

All byte-level work is moved to a compiled C# class loaded at startup via `Add-Type`. Compiled .NET code runs at native CLR speed, which is ~100-1000x faster than PowerShell `foreach` for tight byte loops.

**Loading (Main.ps1, during startup):**
```powershell
$csPath = Join-Path $PSScriptRoot "Modules\SectorAnalyzer.cs"
$csCode = [System.IO.File]::ReadAllText($csPath)
Add-Type -TypeDefinition $csCode -Language CSharp -ErrorAction Stop
```

This compiles the C# code into an in-memory assembly. The `[SectorAnalyzer]` type is then available for static method calls.

### 12.3 `SectorAnalyzer.AnalyzeSector()` -- Single-Pass Analysis

The key method. In **ONE `for` loop** over the sector bytes, it simultaneously:

```csharp
for (int i = 0; i < len; i++) {
    byte b = data[i];
    freq[b]++;                                    // frequency counting
    if (b != 0x00) allZero = false;               // zero-fill check
    if (b != 0xFF) allFF = false;                 // 0xFF-fill check
    if ((b >= 32 && b <= 126) || b == 9 || b == 10 || b == 13)
        printableCount++;                          // ASCII ratio
}
```

Then from the `freq[]` array (computed once), it calculates:
- Shannon entropy (256-element loop with `Math.Log`)
- Chi-square byte distribution score (256-element loop)
- Classification (same logic as `Test-SectorWiped.ps1`)
- File signature matching (if entropy < 7.0)
- Running histogram accumulation

**Operations per sector: 512 compiled (single loop) + 512 (entropy/distribution math) = ~1,024 compiled ops** vs. ~3,072 interpreted ops before.

### 12.4 `SectorAnalyzer.RunFullScan()` -- Entire Full-Disk Scan in C# (v3.9.0211.02)

This is the most critical performance method. It moves the **entire full-disk scan loop** into C# -- not just byte analysis, but also I/O, result accumulation, histogram building, and data leftover marker collection. PowerShell never touches individual sectors or results during a full scan.

**Method signature:**
```csharp
public static ScanSummary RunFullScan(
    FileStream stream,          // Pre-opened disk stream
    long totalSectors,          // Total sectors to scan
    int sectorSize,             // Bytes per sector (512 or 4096)
    byte[][] signatureValues,   // File signature byte arrays
    string[] signatureNames,    // File signature names
    ProgressCallback callback,  // PS delegate for UI updates
    int[] cancelFlag)           // cancelFlag[0] != 0 = stop
```

**Key design decisions:**

1. **4 MB batch I/O** -- reads 8,192 sectors at 512B per batch in a single `FileStream.Read()` call. At 4096B sectors, this is 1,024 sectors per batch (still 4 MB). Larger than the previous 1 MB batches to minimize syscalls.

2. **Zero-copy in-place analysis** -- sectors are analyzed directly from the batch buffer using `batchBuffer[bufferOffset + j]` instead of copying each sector to a new `byte[sectorSize]`. This eliminates ~125 million array allocations for a 64 GB disk at 512B sectors.

3. **Reusable `int[256]` frequency array** -- a single `freq` array is allocated once and cleared with `Array.Clear(freq, 0, 256)` per sector. No per-sector allocation.

4. **All result accumulation in C#** -- the `ScanSummary` class holds wiped/notWiped/suspicious/unreadable counts, a `Dictionary<string, long>` for patterns, the running histogram, and a `List<DataLeftoverMarker>` (capped at 500). PowerShell never iterates results.

5. **ProgressCallback delegate** -- C# invokes the PowerShell delegate every ~200ms (tracked via `DateTime.UtcNow.Ticks`). The delegate updates the status label, progress bar, and calls `DoEvents`. This is the ONLY PowerShell code that runs during the scan (~5 calls/sec).

6. **Cooperative cancellation** -- PowerShell sets `cancelFlag[0] = 1` inside the ProgressCallback when `$script:cancelRequested` is true. C# checks this at the start of each batch.

**Why the scan loop in C# matters more than just analysis:**

Even with compiled C# analysis, the previous architecture had the PowerShell scan loop calling `Process-BatchResults` which iterated every `SectorResult` struct with interpreted `switch`, hashtable lookups, and function calls. For 125 million sectors in batches of 2048, this was ~61,000 PowerShell iterations processing 125M results total -- each with string comparisons and hashtable operations. This alone took hours.

With `RunFullScan()`, PowerShell only executes ~5 lightweight callback invocations per second. Everything else is compiled.

**I/O pattern:**
```csharp
// 4 MB batch buffer allocated once
byte[] batchBuffer = new byte[batchSectors * sectorSize];

while (sectorNum < totalSectors) {
    // ONE I/O call per batch
    stream.Seek(offset, SeekOrigin.Begin);
    while (bytesRead < totalBytes) {
        int chunk = stream.Read(batchBuffer, bytesRead, totalBytes - bytesRead);
        ...
    }
    
    // Analyze each sector IN PLACE from the batch buffer
    for (int i = 0; i < sectorsRead; i++) {
        int bufferOffset = i * sectorSize;
        // Single pass over bytes at batchBuffer[bufferOffset..bufferOffset+sectorSize]
        // No copy, no allocation
    }
}
```

### 12.5 Sampled Scan Path

Sampled scans cannot use `RunFullScan()` because sectors are non-contiguous (randomly distributed across the disk). However, they still use `[SectorAnalyzer]::AnalyzeSector()` for the per-sector analysis, which is ~100x faster than the PowerShell analysis functions. The I/O pattern remains per-sector seeking:

```powershell
[void]$diskStream.Seek($offset, [System.IO.SeekOrigin]::Begin)
$bytesRead = $diskStream.Read($buffer, 0, $SectorSize)
# ...
$analysis = [SectorAnalyzer]::AnalyzeSector($sectorData, $runningHistogram, $sigValues, $sigNames)
```

The PowerShell result loop for sampled scans is acceptable because sample sizes are typically 1,000 - 500,000 sectors, not 125 million.

### 12.6 Signature Array Preparation

File signatures are stored in PowerShell as a hashtable but the C# engine needs typed arrays. Main.ps1 converts them once at startup:

```powershell
$sigNames  = [string[]]@($FileSignatures.Keys)
$sigValues = [byte[][]]@(foreach ($key in $sigNames) { ,([byte[]]$FileSignatures[$key]) })
```

These arrays are passed to every `AnalyzeSector()` / `ScanDiskBatch()` call. The C# code iterates them with a simple indexed `for` loop -- no hashtable lookups.

### 12.7 Shared FileStream

The disk is opened **once** before the scan loop and closed **once** after:

```powershell
$diskStream = [System.IO.File]::Open($diskPath, [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
```

This eliminates ~125M+ `Open`/`Close`/`Dispose` calls for a full disk scan.

### 12.8 Early-Exit Pattern Checks

Even in the compiled C# code, zero-fill and one-fill flags (`allZero`, `allFF`) are tracked in the single main loop. If a non-matching byte is found, the flag is set to `false` but the loop continues (because it's also counting frequencies). However, the **classification** after the loop immediately returns for zero-fill/one-fill sectors without computing entropy or distribution math.

### 12.9 Entropy Gate for Signatures

File signature checking is only performed when `entropy < 7.0`. This:
- Avoids false positives from random data matching signatures
- Saves iterating 11 signatures x their byte lengths when the sector is clearly random

### 12.10 Performance Summary

| Metric | v3.9.0209 (PS) | v3.9.0211 (C# + PS loop) | v3.9.0211.02 (RunFullScan) |
|--------|----------------|--------------------------|----------------------------|
| Ops per sector | ~3,072 interpreted | ~1,024 compiled + PS result loop | ~1,024 compiled (zero PS) |
| I/O calls per sector | 1 | 1/2048 (batch) | 1/8192 (4 MB batch) |
| Per-sector allocation | byte[] per function | byte[] per sector (BlockCopy) | Zero (in-place from buffer) |
| PowerShell ops during scan | All byte analysis | 125M switch/hashtable | ~5 callback invocations/sec |
| 64 GB full scan time | ~24+ hours | ~1-3 hours | ~5-15 minutes |
| CPU bottleneck | PowerShell foreach | PS result accumulation | Disk I/O throughput |

---

## 13. Threading Model and GUI Responsiveness

### The Problem

PowerShell WinForms runs on a single thread. When `Main-Process` enters its scan loop, the GUI message pump is blocked. The user cannot:
- Click the cancel button
- Move/resize the window
- See progress updates

### The Solution: ProgressCallback Delegate (Full Scans) + DoEvents (Sampled Scans)

**Full scans (v3.9.0211.02+):** The entire scan runs inside `[SectorAnalyzer]::RunFullScan()` -- a compiled C# method. C# invokes a `ProgressCallback` delegate every ~200ms (tracked via `DateTime.UtcNow.Ticks`). The delegate is a PowerShell scriptblock that updates the GUI and calls `DoEvents`:

```powershell
$progressCallback = [ProgressCallback]{
    param([long]$currentSector, [int]$percent, [long]$scannedSoFar)
    if ($script:cancelRequested) { $cancelFlag[0] = 1 }
    $StatusLabel.Text = "Status: Scanning Sector: $($currentSector.ToString('N0')) ($percent%)"
    $ScanProgress.Value = [math]::Min($percent, 100)
    $ProgressLabel.Text = "$percent%"
    DoEvents
}
```

The C# code holds the call stack during the scan. When it invokes the delegate, control returns to PowerShell briefly for the UI update, then C# resumes. This is NOT multi-threading -- it's a synchronous callback on the same thread.

**Sampled scans:** PowerShell retains the scan loop with time-based `DoEvents`:

```powershell
$uiTimer = [System.Diagnostics.Stopwatch]::StartNew()
$uiIntervalMs = 200

if ($percent -ne $lastPercent) {
    DoEvents; $uiTimer.Restart()
} elseif ($uiTimer.ElapsedMilliseconds -ge $uiIntervalMs) {
    DoEvents; $uiTimer.Restart()
}
```

**Why 200ms?** This provides ~5 updates per second, which is perceived as smooth by users.

### DoEvents Overhead

`[System.Windows.Forms.Application]::DoEvents()` processes all pending messages. When there are no pending messages (the usual case), it returns almost instantly (~0.01ms). The overhead is negligible.

### Cancellation Latency

**Full scan:** Cancellation is cooperative via `cancelFlag[0]`. PowerShell sets it inside the `ProgressCallback`, and C# checks it at the start of each batch. Since the callback fires every ~200ms, the maximum cancel delay is one 4 MB batch read (~20-50ms) plus the 200ms callback interval. In practice, cancellation feels instant.

**Sampled scan:** Cancel checking happens at the start of each PowerShell loop iteration. Since each iteration is one sector read + one C# analysis call (~1-5ms), cancellation is near-instant.

---

## 14. Error Handling Strategy

### Main-Process try/catch/finally

```powershell
function Main-Process {
    try {
        # ... entire scan logic ...
    }
    catch {
        Write-Console "ERROR: $_" "Red"
        $StatusLabel.Text = "Status: ERROR"
        $VerificationPanel.Visible = $true
        $VerificationPanel.BackColor = Color 255 0 0
        $ResultLabel.Text = "ERROR"
        [System.Windows.Forms.MessageBox]::Show("An error occurred: $_", ...)
    }
    finally {
        # ALWAYS executed: cleanup disk stream and re-enable UI
        if ($diskStream) {
            try { $diskStream.Close(); $diskStream.Dispose() } catch {}
            $diskStream = $null
        }
        $StartScan.Enabled = $true
        $CancelScan.Enabled = $false
        $DiskList.Enabled = $true
    }
}
```

The `finally` block ensures:
1. The disk stream is always closed (even on error or cancel)
2. UI controls are always re-enabled (preventing a locked state)

### Per-Sector Error Handling

Inside the scan loop, sector reads are wrapped in individual try/catch:

```powershell
try {
    [void]$diskStream.Seek($offset, ...)
    $bytesRead = $diskStream.Read(...)
    if ($bytesRead -gt 0) { ... }
}
catch {
    $sectorData = $null
}
```

A failed read results in `$sectorData = $null`, which `Test-SectorWiped` classifies as "Unreadable". The scan continues to the next sector.

### Module Loading Error

If any module fails to load (`try/catch` block at lines 90-107 of Main.ps1):
```powershell
catch {
    Write-Console "ERROR: could not load modules!" "Red"
    exit 1
}
```

This is a fatal error because the scan cannot proceed without analysis functions.

---

## 15. Report Generation Pipeline

```
1. Scan completes
        |
        v
2. New-HtmlReport generates complete HTML string
   (self-contained: embedded CSS, no external dependencies)
        |
        v
3. Branch on $ReportFormat:
   |
   +-- "HTML" -> Save HTML to $reportFile.html
   |
   +-- "PDF"  -> Save HTML to temp file -> Convert-HtmlToPdf -> Delete temp
   |
   +-- "Both" -> Save HTML to $reportFile.html -> Convert-HtmlToPdf (uses same HTML)
        |
        v
4. Show completion MessageBox with option to open report
        |
        v
5. If user clicks "Yes":
   - PDF format or Both: Start-Process "$reportFile.pdf"
   - HTML only: Start-Process "$reportFile.html"
```

**PDF fallback chain:**
```
Edge (Chromium) -> Chrome -> Brave -> wkhtmltopdf -> Word COM -> HTML fallback
```

If PDF generation fails entirely and the user requested "PDF" only, the HTML file is moved from its temp location to the final `$reportFile.html` path as a fallback.

---

## 16. Known Limitations and Edge Cases

### 16.1 Status Wildcard Matching Bug

In `Main.ps1` and `New-HtmlReport.ps1`, status matching uses `-eq` with wildcards:
```powershell
$statusColor = if ($OverallStatus -eq "VERIFIED*") { "SpringGreen" }
```

PowerShell's `-eq` operator does **not** support wildcards. This condition will never match because the actual status is `"VERIFIED CLEAN - Disk Successfully Wiped"`, not literally `"VERIFIED*"`. The `-like` operator should be used instead. Currently, the `else` branch handles all three cases, so the report still works, but status colors in the console are not differentiated.

### 16.2 Full Scan GetEnumerator

The `GetEnumerator` scriptblock returned for full scans is defined but never called. The scan loop uses a direct `while ($sectorNum -lt $totalSamples)` counter. This is intentional -- the direct counter is faster than invoking a scriptblock.

### 16.3 Sector Size Mismatch

If the user selects a sector size that doesn't match the disk's physical sector size, the tool will still read that many bytes per seek. This may cause:
- Reading across sector boundaries (harmless but technically imprecise)
- Slightly different entropy values compared to physical-sector-aligned reads

### 16.4 Cancel Timing

If the user cancels during report generation (after the scan loop), cancellation has no effect -- the report generation runs to completion. Cancellation only works during the scan loop.

### 16.5 PDF Browser Popup

`Start-Process` for Edge/Chrome headless PDF may briefly show a console window or taskbar entry depending on the system configuration, even with `-NoNewWindow`.

### 16.6 Disk Stream Sharing

The shared `FileStream` uses `FileShare.ReadWrite`. If another process writes to the disk during the scan (e.g., Windows writing to a mounted volume), the read data may include both old and new content. For accurate verification, the disk should be unmounted or idle.

---

## 17. Changelog (Code-Level)

### v3.9.0211.02 (2026-02-11)

**Files changed:** `Modules/SectorAnalyzer.cs`, `Main.ps1`

1. **SectorAnalyzer.cs -- RunFullScan() method**
   - New `RunFullScan()` static method processes the entire full-disk scan in compiled C#
   - 4 MB batch I/O (8192 sectors @ 512B) instead of 1 MB -- fewer syscalls
   - Zero-copy in-place analysis: sectors analyzed directly from `batchBuffer[offset + j]`, no `Buffer.BlockCopy` or per-sector `byte[]` allocation
   - Reusable `int[256]` frequency array cleared with `Array.Clear()` per sector
   - All result accumulation (wiped/notWiped/suspicious/unreadable counts, pattern dictionary, running histogram) done in C#
   - Data leftover marker collection with cap (500) and overflow tracking in C#
   - `ProgressCallback` delegate invoked every ~200ms via `DateTime.UtcNow.Ticks` for PowerShell UI updates
   - `cancelFlag[0]` cooperative cancellation checked each batch
   - Returns `ScanSummary` object (one object with all results, no per-sector data)
   - New structs: `DataLeftoverMarker`, `ScanSummary`
   - Shared `ClassifySector()` private method used by both `RunFullScan()` and `AnalyzeSector()`
   - Removed `ScanDiskBatch()` (replaced by `RunFullScan()`)
   - Legacy `AnalyzeSector()` retained for sampled scan path

2. **Main.ps1 -- Full scan path rewritten**
   - Replaced the PowerShell `while` loop + `Process-BatchResults` with a single `[SectorAnalyzer]::RunFullScan()` call
   - Removed `Process-BatchResults` function (no longer needed)
   - Removed `$batchSize` variable (batch size now managed by C#)
   - Added `$cancelFlag = [int[]]@(0)` for cooperative cancellation
   - Added `$progressCallback = [ProgressCallback]{...}` for UI updates
   - Added summary transfer code: C# `ScanSummary` -> PS `$results` hashtable and `$dataLeftovers` collection
   - Sampled scan path unchanged (still uses PowerShell loop + `AnalyzeSector()`)

**Performance impact:** 64 GB disk full scan reduced from ~1-3 hours (C# analysis + PS result loop) to ~5-15 minutes (entire scan in C#, disk I/O is now the only bottleneck).

### v3.9.0210.01 (2026-02-10)

**Files changed:** `Main.ps1`, `GUI/ActionModules/Start-Scan.ps1`, `Modules/Get-ByteDistributionScore.ps1`

1. **Main.ps1 -- Time-based UI refresh**
   - Added `$uiTimer = [System.Diagnostics.Stopwatch]::StartNew()` before the scan loop
   - Added `$uiIntervalMs = 200` constant
   - Both full-scan and sampled-scan loops now call `DoEvents` when `$uiTimer.ElapsedMilliseconds -ge $uiIntervalMs`, in addition to the existing percent-change trigger
   - Timer is restarted after each `DoEvents` call (both percent-based and time-based paths)

2. **Start-Scan.ps1 -- ResultLabel bug fix**
   - Changed `$ResultLabel.Text = Color 255 255 255` to `$ResultLabel.ForeColor = Color 255 255 255` and `$ResultLabel.Text = ""`
   - The old code assigned a `System.Drawing.Color` object to a `string` property, which would display the color's `.ToString()` representation instead of clearing the label

3. **Get-ByteDistributionScore.ps1 -- Array optimization**
   - Replaced hashtable-based frequency counting with a fixed `int[256]` array
   - Removed the initialization loop (`for ($i = 0; $i -lt 256; $i++) { $frequency[$i] = 0 }`) -- `New-Object 'int[]' 256` initializes to zeros automatically
   - Matches the pattern already used in `Get-ShannonEntropy.ps1`

### v3.9.0209.01 (2026-02-09)

**Files changed:** `Main.ps1`, `Modules/Get-DataLeftoverMarkers.ps1` (new), `Modules/New-HtmlReport.ps1`

- Added `Get-DataLeftoverMarkers.ps1` module with three functions: `Get-DataLeftoverMarker`, `New-DataLeftoverCollection`, `Add-DataLeftoverMarker`
- Integrated marker collection into both scan loops in `Main.ps1`
- Added data leftover section to HTML report with summary cards, pattern breakdown, and detail table
- Added capped collection with overflow tracking

### v3.9.0209.01 (2026-02-09) -- Second commit

**Files changed:** `Main.ps1`, `Modules/Get-SampleLocations.ps1`

- Fixed critical memory crash for full-disk scans by introducing streaming iterator pattern
- Shared `FileStream` for the entire scan instead of per-sector opens
- Eliminated array-limit errors on very large sample sizes
- `Get-SampleLocations` now returns a lightweight object for full scans (no array)

### v3.9.0203.01 (2026-02-03)

**Files changed:** `Main.ps1`, `Modules/Get-SampleLocations.ps1`, `Modules/Get-ShannonEntropy.ps1`

- Replaced `ArrayList` byte storage with running `long[256]` histogram
- Added `Get-ShannonEntropyFromHistogram` function for aggregate entropy
- Replaced array concatenation in `Get-SampleLocations` with `HashSet<long>`
- Memory usage reduced from ~200MB to ~2MB for 100K-sector scans

### v3.8.0116.03 (2026-01-12)

- Split monolithic script into modular architecture (Modules/, Connectors/, GUI/)
- Introduced element factory pattern (GUI/NewElements/)
- Separated action handlers into GUI/ActionModules/

### v3.8.0116.02 (2026-01-11)

- Improved analysis algorithms and thresholds
- Enhanced HTML report layout and styling

### v3.8.0116.01 (2026-01-08)

- Initial release as a single-file PowerShell script

---

## License

Copyright (c) 2026 Yannick Morgenthaler / JSW  
Contact: yannick.morgenthaler@jsw.swiss
