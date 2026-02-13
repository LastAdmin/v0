# DEEPCODE - Disk Wipe Verification Tool

> Deep code-level documentation for developers who need to understand, debug, or extend the codebase. Every file, every function, every design decision is explained here.

**Version:** 4.0
**Last Updated:** 2026-02-13
**Author:** Yannick Morgenthaler / JSW

---

## Table of Contents

1. [Execution Model](#1-execution-model)
2. [Bootstrap Chain](#2-bootstrap-chain)
3. [Global State and Scope](#3-global-state-and-scope)
4. [GUI Framework](#4-gui-framework)
5. [Scan Lifecycle](#5-scan-lifecycle)
6. [Compiled C# Analysis Engine](#6-compiled-c-analysis-engine)
7. [Legacy PowerShell Analysis Modules](#7-legacy-powershell-analysis-modules)
8. [Connector Functions](#8-connector-functions)
9. [GUI Action Modules](#9-gui-action-modules)
10. [GUI Element Definitions](#10-gui-element-definitions)
11. [GUI Element Factories](#11-gui-element-factories)
12. [Data Structures In-Depth](#12-data-structures-in-depth)
13. [Performance Architecture](#13-performance-architecture)
14. [Threading Model and GUI Responsiveness](#14-threading-model-and-gui-responsiveness)
15. [Error Handling Strategy](#15-error-handling-strategy)
16. [Report Generation Pipeline](#16-report-generation-pipeline)
17. [Known Limitations and Edge Cases](#17-known-limitations-and-edge-cases)
18. [Changelog (Code-Level)](#18-changelog-code-level)

---

## 1. Execution Model

The application is a **single-threaded** PowerShell Windows Forms application. All code -- GUI rendering, disk I/O, analysis, and report generation -- executes on the same thread. There is no background worker, no `RunspacePool`, and no `System.Threading.Tasks`.

This design was chosen for simplicity and because PowerShell's `$script:` scoping and dot-sourced functions do not naturally support multi-threaded execution. The trade-off is that long-running operations (the scan loop) must periodically yield control to the Windows Forms message pump via `[System.Windows.Forms.Application]::DoEvents()` to keep the GUI responsive.

**Key implication:** Any blocking call (e.g., a slow disk read, a stalled `Start-Process` for PDF conversion) will freeze the GUI until it returns. The codebase mitigates this with time-based `DoEvents` calls (see [Section 14](#14-threading-model-and-gui-responsiveness)).

**Performance architecture:** All byte-level analysis runs in compiled C# code (via `Add-Type`) rather than interpreted PowerShell. PowerShell handles only I/O, orchestration, and UI updates.

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
  |                 +-- Creates Menu Bar (Options > Debug Mode)
  |                 +-- Wires event handlers
  |                 +-- calls Load-Disks
  |                 +-- calls $MainWindow.ShowDialog()   <-- BLOCKS HERE
  |                 +-- (returns when window closes)
```

**Note:** The compiled C# engine (`DiskAnalysisEngine.ps1`) is NOT loaded via `Index.ps1`. It is loaded inside `Main-Process` to ensure it is compiled fresh each session (the `Add-Type` call is idempotent but must happen before any engine methods are called).

### Why modules are loaded twice

You may notice that `Index.ps1` loads all modules at boot, but `Main-Process` also dot-sources them again inside its `try` block. This is intentional:

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
| `$SampleSize` | SampleSize.ps1 | Full-DiskScan.ps1, Get-Parameters.ps1 | `NumericUpDown` | Sample size input (disabled by default) |
| `$SectorSize` | SectorSize.ps1 | Disk-List.ps1, Full-DiskScan.ps1, Get-Parameters.ps1 | `ComboBox` | Sector size dropdown |
| `$StartScan` | StartScan.ps1 | Start-Scan.ps1, Main.ps1 | `Button` | Start button reference |
| `$CancelScan` | CancelScan.ps1 | Start-Scan.ps1, Main.ps1 | `Button` | Cancel button reference |
| `$VerificationPanel` | VerificationPanel.ps1 | Main.ps1, Start-Scan.ps1 | `Panel` | Result color panel |
| `$ResultLabel` | ResultLabel.ps1 | Main.ps1, Start-Scan.ps1 | `Label` | Result text label |
| `$FullDiskCheckBox` | FullDiskCheckBox.ps1 | Full-DiskScan.ps1, Disk-List.ps1 | `CheckBox` | Full scan toggle (checked+disabled by default) |
| `$SectorInfoLabel` | SectorInfoLabel.ps1 | Disk-List.ps1, Full-DiskScan.ps1 | `Label` | Total sector count display |
| `$TechnicianName` | TechnicianName.ps1 | Get-Parameters.ps1, Start-Scan.ps1 | `TextBox` | Technician name input |
| `$ReportFormat` | ReportFormat.ps1 | Get-Parameters.ps1 | `ComboBox` | Report format dropdown |
| `$ReportPath` | ReportLocation.ps1 | Get-Parameters.ps1, Browse-Path.ps1 | `TextBox` | Report output path |
| `$script:cancelRequested` | Cancel-Scan.ps1 | Main.ps1 | `bool` | Cancellation flag |
| `$FileSignatures` | Main.ps1 | Test-FileSignatures.ps1 | `hashtable` | Signature lookup table |
| `$diskNumber` | Start-Scan.ps1 | Get-Parameters.ps1, Main.ps1 | `int` | Selected disk number |

### The `$script:cancelRequested` pattern

Cancellation uses a `$script:` scoped boolean. When the cancel button is clicked, `Cancel-Scan` sets `$script:cancelRequested = $true`. The scan loop in `Main-Process` checks this flag at the start of each iteration. Because the loop periodically calls `DoEvents`, the cancel button's click handler gets a chance to execute and set the flag.

```
User clicks Cancel
        |
        v
DoEvents is called in scan loop (every 250ms)
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

**Note on `Color`:** This function name shadows the .NET `Color` type. It works because PowerShell resolves function calls before type lookups.

### Element factory pattern (GUI/NewElements/)

Each `New-*.ps1` file defines a factory function for a specific control type. For example:

```
New-Button       -> returns a configured System.Windows.Forms.Button
New-CheckBox     -> returns a configured System.Windows.Forms.CheckBox
New-ComboBox     -> returns a configured System.Windows.Forms.ComboBox
New-DataGridView -> returns a configured System.Windows.Forms.DataGridView
New-Label        -> returns a configured System.Windows.Forms.Label
New-StatusBar    -> returns a configured System.Windows.Forms.StatusBar
...
```

These factories accept parameters like location, size, text, font, and colors, applying the dark-theme defaults consistently.

### Element definition pattern (GUI/Elements/)

Each element `.ps1` file creates a specific control instance and adds it to its parent container. Because these files are dot-sourced in order within `GUI.ps1`, parent containers (like `$GroupBoxL`) must be created before their children.

### Layout

The form uses a two-panel layout with a menu bar:

```
$MainWindow (1000 x 700, fixed size, no maximize)
  |
  +-- $MenuBar (Options > Debug Mode toggle)
  |
  +-- $GroupBoxL (Left panel: parameters + scan controls + result)
  |
  +-- $GroupBoxR (Right panel: disk list + console log)
```

All positioning is done with absolute pixel coordinates via `Location($x, $y)`. There is no layout manager, no auto-sizing, and no responsive behavior. The form has a fixed border style (`Fixed3D`) and `MaximizeBox = $false`.

### Menu Bar and Debug Mode

The GUI includes an "Options" menu with a "Debug Mode" toggle. When Debug Mode is enabled:
- The FullDiskCheckBox is unlocked (user can uncheck it)
- The SampleSize control is unlocked (user can set a custom sample count)
- This enables smaller test runs during development

When Debug Mode is disabled:
- FullDiskCheckBox is forced to checked and disabled
- SampleSize is disabled with a darkened background
- Full disk scan is the only available mode

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
   |-- Re-load all modules (dot-source) including DiskAnalysisEngine.ps1
   |-- Load file signature table -> pass to [DiskAnalysisEngine]::SetSignatures()
   |-- Validate disk exists (Get-Disk)
   |-- Log disk information
   |-- Get-SampleLocations (if sample mode) [Modules/Get-SampleLocations.ps1]
   |-- [DiskAnalysisEngine]::ResetGlobalCounters()
   |-- Initialize results hashtable and patternCounts dictionary
   |-- Open disk stream (single FileStream for entire scan)
   |-- Initialize Stopwatch for UI timer
   |
   |-- SCAN LOOP (two paths):
   |   |
   |   +-- FULL DISK PATH:
   |   |   |-- Read 1 MB chunk (2048 sectors) via sequential FileStream.Read
   |   |   |-- [DiskAnalysisEngine]::AnalyzeChunk($buffer, $bytesRead, $sectorSize, $patternCounts, $baseSectorIndex)
   |   |   |-- AnalyzeChunk internally calls AnalyzeSector for each sector
   |   |   |-- AnalyzeChunk internally calls RecordLeftover for NOT Wiped/Suspicious
   |   |   |-- Accumulate results from ChunkStats
   |   |   |-- Every 250ms: update progress bar, percentage, speed (MB/s), ETA
   |   |   +-- try/catch with partial-read handling for last chunk
   |   |
   |   +-- SAMPLE PATH:
   |       |-- Check $script:cancelRequested
   |       |-- Seek to sector offset + Read single sector
   |       |-- [DiskAnalysisEngine]::AnalyzeSector($buffer, 0, $sectorSize)
   |       |-- Switch on status: increment $results
   |       |-- RecordLeftover called from PowerShell (engine doesn't know sector number)
   |       |-- Update $patternCounts dictionary
   |       +-- Every 250ms: update UI
   |
   |-- Close disk stream
   |-- [DiskAnalysisEngine]::ComputeGlobalEntropy() -> overall entropy from 256-bucket frequency table
   |-- Calculate wiped percentage
   |-- Determine overall status (VERIFIED / MOSTLY / NOT VERIFIED)
   |-- Retrieve leftovers: [DiskAnalysisEngine]::GetLeftovers() and ::GetTotalLeftoverCount()
   |-- Log results to console
   |-- New-HtmlReport                  [Modules/New-HtmlReport.ps1]
   |-- (optional) Convert-HtmlToPdf    [Modules/Convert-HtmlToPdf.ps1]
   |-- Show completion MessageBox
   |-- Update verification panel
   +-- Finally: close stream if still open, re-enable UI
```

---

## 6. Compiled C# Analysis Engine

### File: Modules/DiskAnalysisEngine.ps1

The file wraps a complete C# source in `Add-Type -TypeDefinition @"..."@ -Language CSharp`. This compiles at runtime into a .NET assembly loaded into the PowerShell session.

### Static State

```csharp
public static long[] GlobalFrequency = new long[256];   // Byte value frequency table
public static long GlobalTotalBytes = 0;                 // Total bytes processed
public static long GlobalPrintableAscii = 0;             // Count of printable ASCII bytes
public static List<LeftoverEntry> Leftovers;             // Sector addresses with potential data
public static int MaxLeftovers = 500;                    // Cap on stored leftover details
public static long TotalLeftoverCount = 0;               // Uncapped total count
private static byte[][] sigBytes;                        // File signature byte patterns
private static string[] sigNames;                        // File signature names
```

### AnalyzeSector Algorithm

This is the core classification logic. Input: a byte array with an offset and length (one sector).

**Step 1: Build local frequency table**

```csharp
int[] localFreq = new int[256];
for (int i = offset; i < end; i++) {
    localFreq[data[i]]++;
    if (isPrintable(data[i])) printable++;
}
```

Single pass over all bytes. Counts each byte value 0-255 and counts printable ASCII characters (32-126, 9, 10, 13).

**Step 2: Merge into global accumulators**

```csharp
for (int i = 0; i < 256; i++) {
    if (localFreq[i] > 0) GlobalFrequency[i] += localFreq[i];
}
GlobalTotalBytes += length;
GlobalPrintableAscii += printable;
```

This replaces the old `$allBytes.AddRange()` that caused memory overflow. Instead of storing raw bytes, we only maintain 256 counters.

**Step 3: Zero-fill / One-fill detection**

```csharp
if (localFreq[0x00] == length) -> Wiped, "Zero-filled (0x00)", confidence 100
if (localFreq[0xFF] == length) -> Wiped, "One-filled (0xFF)", confidence 100
```

Fastest check. If all bytes are the same value, it is a standard wipe pattern.

**Step 4: Compute per-sector entropy and chi-square distribution**

Shannon entropy:
```
H = -SUM(p_i * log2(p_i)) for each byte value i where count > 0
p_i = localFreq[i] / length
```

Chi-square byte distribution:
```
expected = length / 256.0
chiSquare = SUM((localFreq[i] - expected)^2 / expected) for all i
distribution = max(0, min(1, 1 - chiSquare / (length * 255)))
```

ASCII ratio:
```
asciiRatio = printable / length
```

**Step 5: High entropy classification (H > 7.0)**

| Condition | Result |
|-----------|--------|
| H > 7.5 AND distribution > 0.80 | Wiped, "Random data (DoD 5220.22-M)" |
| distribution > 0.75 AND asciiRatio < 0.5 | Wiped, "Random data (cryptographic wipe)" |
| asciiRatio > 0.7 | NOT Wiped, "Text content detected" |
| distribution > 0.70 | Wiped, "Random data (probable wipe)" |

**Confidence formula for DoD:**
```
confidence = (entropy/8) * 60 + distribution * 40
```

**Step 6: File signature matching (H < 7.0)**

Iterates through all registered signatures, comparing the first N bytes of the sector to each signature's byte pattern:

```csharp
for each signature:
    if data[offset..offset+sig.Length] == sig.bytes:
        return (NOT Wiped, "File signature: " + name, confidence 95)
```

Only checked at lower entropy because high-entropy random data would produce false matches at the rate of `1 / 256^sigLength`.

**Step 7: Medium entropy (5.0 < H <= 7.0)**

| Condition | Result |
|-----------|--------|
| asciiRatio < 0.3 AND distribution > 0.6 | Suspicious, "Compressed/encrypted data possible" |
| Otherwise | NOT Wiped, "Residual data likely" |

**Step 8: Low entropy (H <= 5.0)**

Returns NOT Wiped, "Structured data detected", confidence 85.

**Step 9: Fallback**

Returns NOT Wiped, "Unknown data pattern", confidence 50.

### AnalyzeChunk

Processes a buffer containing multiple sectors. Called once per 1 MB chunk in full-disk mode.

```csharp
public static ChunkStats AnalyzeChunk(byte[] buffer, int bytesRead, int sectorSize,
    Dictionary<string, int> patternCounts, long baseSectorIndex)
{
    int sectorsInChunk = bytesRead / sectorSize;
    for (int s = 0; s < sectorsInChunk; s++) {
        SectorResult result = AnalyzeSector(buffer, s * sectorSize, sectorSize);
        // Accumulate counts
        // Record leftover if status == 1 or 2
        if (result.Status == 1 || result.Status == 2)
            RecordLeftover(baseSectorIndex + s, sectorSize, result);
        // Update patternCounts dictionary
    }
    return stats;
}
```

**Why the Dictionary is passed from PowerShell:** C# cannot define a `Dictionary<string,int>` as a static field that is cleanly readable from PowerShell. Passing it as a parameter lets PowerShell own the object and convert it to a hashtable after the scan.

### RecordLeftover

```csharp
public static void RecordLeftover(long sectorNum, int sectorSize, SectorResult result)
{
    TotalLeftoverCount++;
    if (Leftovers.Count < MaxLeftovers) {
        // Create LeftoverEntry with sector number, byte offset, status, pattern, confidence
        Leftovers.Add(entry);
    }
}
```

Always increments the total count. Only stores detailed entries up to `MaxLeftovers` (default 500). This prevents memory issues on disks where millions of sectors are not wiped.

### ComputeGlobalEntropy

```csharp
public static double ComputeGlobalEntropy()
{
    double entropy = 0.0;
    for (int i = 0; i < 256; i++) {
        if (GlobalFrequency[i] > 0) {
            double p = (double)GlobalFrequency[i] / GlobalTotalBytes;
            entropy -= p * Math.Log(p, 2.0);
        }
    }
    return entropy;
}
```

Computes Shannon entropy from the global frequency table accumulated across all sectors. Maximum theoretical value: 8.0 (each of 256 byte values equally likely).

### Data Structures

- `SectorResult` -- Status (0=Wiped, 1=NotWiped, 2=Suspicious, 3=Unreadable), Pattern string, Confidence int
- `ChunkStats` -- Wiped/NotWiped/Suspicious/Unreadable counts for a batch
- `LeftoverEntry` -- SectorNumber, DiskOffset, Status string, Pattern, Confidence

---

## 7. Legacy PowerShell Analysis Modules

These modules are the original interpreted implementations. They are still loaded and available for standalone debugging but are **not called during normal scan operations**. The compiled C# engine replaces all of them in the hot path.

### Get-ShannonEntropy.ps1

Two functions in one file:

**`Get-ShannonEntropy`** -- Per-sector entropy.
```
Parameters: $Data (byte[])
Returns: double (0.0 to 8.0)
```
Uses a fixed `int[256]` array, iterates every byte, computes `p * log2(p)`.

**`Get-ShannonEntropyFromHistogram`** -- Aggregated entropy from pre-computed histogram.
```
Parameters: $Histogram (long[256]), $TotalBytes (long)
Returns: double (0.0 to 8.0)
```

### Get-ByteDistributionScore.ps1

```
Function: Get-ByteDistributionScore
Parameters: $Data (byte[])
Returns: double (0.0 to 1.0)
```

Measures byte uniformity using a Chi-square test with a fixed `int[256]` array (optimized in v3.9.0210 from hashtable). Score near 1.0 = uniformly distributed (random/wiped), near 0.0 = concentrated (structured data).

### Get-PrintableAsciiRatio.ps1

```
Function: Get-PrintableAsciiRatio
Parameters: $Data (byte[])
Returns: double (0.0 to 1.0)
```

Counts bytes in printable ranges: ASCII 32-126, Tab (0x09), newline (0x0A), carriage return (0x0D).

### Test-SectorWiped.ps1

```
Function: Test-SectorWiped
Parameters: $SectorData (byte[])
Returns: hashtable { Status, Pattern, Confidence, Details }
```

Applies the same classification logic as `AnalyzeSector` in C# but in interpreted PowerShell.

### Test-FileSignatures.ps1

```
Function: Test-FileSignatures
Parameters: $Data (byte[])
Returns: string (file type name) or $null
```

Iterates over `$FileSignatures` hashtable and compares first N bytes.

### Get-ByteHistogram.ps1

Legacy standalone histogram function. Not called during the scan loop.

### Read-DiskSector.ps1

Opens/closes a new `FileStream` per call. Exists for ad-hoc single-sector reads and backward compatibility. **Not used in the scan loop** -- the scan loop opens its own persistent stream.

### Get-DataLeftoverMarkers.ps1

Three functions for legacy PowerShell leftover tracking (replaced by C# engine's `RecordLeftover`):
- `Get-DataLeftoverMarker` -- Creates a marker for one flagged sector with hex/ASCII preview
- `New-DataLeftoverCollection` -- Creates a capped collection
- `Add-DataLeftoverMarker` -- Adds a marker with summary tracking

### Get-SampleLocations.ps1

```
Function: Get-SampleLocations
Parameters: $TotalSectors (long), $SampleSize (long)
Returns: hashtable with Count, IsFullScan, and either _array or GetEnumerator
```

**Two modes:**

**Full scan** (`SampleSize >= TotalSectors`):
Returns a lightweight hashtable with `IsFullScan = $true` and no array. Memory: ~100 bytes.

**Sampled scan** (`SampleSize < TotalSectors`):
1. Creates a `HashSet<long>` for O(1) duplicate prevention
2. Adds sectors 0-99 (first 100)
3. Adds sectors `(TotalSectors - 101)` to `(TotalSectors - 2)` (last 100, boundary-safe -- avoids HPA/DCO reserved area)
4. Fills remaining slots with random sectors using long-safe generation (combines two 31-bit randoms for full long range)
5. Copies to a `long[]` array and sorts it
6. Clears the `HashSet` immediately to free memory

**Why sorted?** Sequential disk reads are faster than random seeks. Sorting means the `FileStream.Seek()` calls move forward through the disk.

**Boundary safety:** Caps at `TotalSectors - 2` because the last 1-2 sectors on physical drives are often unreachable (HPA/DCO reserved area, firmware rounding vs OS-reported size).

---

## 8. Connector Functions

### DoEvents.ps1

```powershell
function DoEvents {
    [System.Windows.Forms.Application]::DoEvents()
}
```

Single-line wrapper. Called by the scan loop (time-based), by `Write-Console` (after every log line), and by `Main-Process` at each status change.

### Write-Console.ps1

```powershell
function Write-Console($Message, $Color)
```

Appends a timestamped, color-coded message to the `$Console` RichTextBox, scrolls to caret, and calls `DoEvents`.

**Color parameter:** Accepts .NET named colors as strings: "Red", "Yellow", "SpringGreen", "Magenta", "Orange", "Gray", "White".

### Get-Parameters.ps1

```powershell
function Get-Parameters
```

Collects all scan parameters from GUI controls into a single hashtable:
- `technician`, `diskNumber`, `sampleSize` (cast to `[long]`), `sectorSize` (cast to `[int]`), `reportFormat`, `reportPath`, `reportFile` (with timestamp).

---

## 9. GUI Action Modules

### Start-Scan.ps1

1. Validates disk selected and technician name entered
2. Extracts disk number via regex: `"Disk (\d+)"`
3. Shows confirmation dialog
4. Sets `$script:cancelRequested = $false`
5. Disables Start button, enables Cancel button, disables disk list
6. Resets UI: clears console, resets progress, hides verification panel
7. Sets `$ResultLabel.ForeColor = Color 255 255 255` and `$ResultLabel.Text = ""`
8. Logs parameters to console
9. Calls `Main-Process`

### Cancel-Scan.ps1

Sets `$script:cancelRequested = $true`. The scan loop checks this at each chunk/sector boundary.

### Full-DiskScan.ps1

Toggles `$SampleSize.Enabled` based on `$FullDiskCheckBox.Checked`. When full disk is checked, the sample size input is disabled. When unchecked (Debug Mode), sample size is enabled.

### Load-Disks.ps1

Runs `Get-Disk`, populates `$DiskList` with entries like `"Disk 0 | Samsung SSD 870 | 465.76 GB | Status"`. Auto-selects the first disk.

### Browse-Path.ps1

Opens a `FolderBrowserDialog` and sets `$ReportPath.Text`.

### Disk-List.ps1

Updates `$SectorInfoLabel` when a disk is selected, showing the total number of sectors. If full disk scan is checked, also updates `$SampleSize.Value`.

### DataGridView-DoubleClick.ps1

Empty placeholder function. Reserved for future DataGridView interaction handling.

---

## 10. GUI Element Definitions

Each file in `GUI/Elements/` creates one or more WinForms controls:

| File | Variable(s) Created | Control Type | Description |
|------|---------------------|-------------|-------------|
| `BaseSettings.ps1` | (functions only) | -- | Defines `Location`, `Size`, `FontSize`, `Color` helpers |
| `LeftPanel.ps1` | `$GroupBoxL` | GroupBox | Left panel container |
| `RightPanel.ps1` | `$GroupBoxR` | GroupBox | Right panel container |
| `ParameterHeader.ps1` | (label) | Label | "Parameters" section header |
| `TechnicianName.ps1` | `$TechnicianName` | TextBox | Technician name input |
| `SampleSize.ps1` | `$SampleSize` | NumericUpDown | Sample size input (disabled by default) |
| `FullDiskCheckBox.ps1` | `$FullDiskCheckBox` | CheckBox | Full disk scan toggle (checked + disabled by default) |
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
| `ResultLabel.ps1` | `$ResultLabel` | Label | Result text |
| `AvailableDiskHeader.ps1` | (label) | Label | "Available Disks" header |
| `RefreshDisks.ps1` | `$RefreshDisks` | Button | Refresh disk list button |
| `DiskList.ps1` | `$DiskList` | ListBox | Disk selection list |
| `DiskTable.ps1` | `$DiskTable` | DataGridView | Alternative disk display |
| `ConsoleHeader.ps1` | (label) | Label | "Console" header |
| `Console.ps1` | `$Console` | RichTextBox | Scrollable, colored log output |
| `Separator.ps1` | (label) | Label | Visual separator line |

---

## 11. GUI Element Factories

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

## 12. Data Structures In-Depth

### 12.1 Sample Locations Object

**Sampled scan:**
```powershell
@{
    Count      = [long]15000
    IsFullScan = $false
    _array     = [long[]]@(0, 1, 2, ..., 99, 4500, 8900, ..., N-2)
                                       # Sorted, capped at TotalSectors - 2
}
```

**Full scan:**
```powershell
@{
    Count         = [long]976773168
    IsFullScan    = $true
    GetEnumerator = [scriptblock]      # Sequential counter (unused -- direct while loop used instead)
    _totalForEnum = [long]976773168
}
```

### 12.2 Results Hashtable

```powershell
$results = @{
    Wiped      = [int]0
    NotWiped   = [int]0
    Suspicious = [int]0
    Unreadable = [int]0
    Patterns   = @{
        "Zero-filled (0x00)"              = 5000
        "Random data (DoD 5220.22-M)"     = 4800
        "One-filled (0xFF)"               = 150
        "File signature: PDF"             = 3
        "Text content detected"           = 12
    }
}
```

### 12.3 Pattern Counts Dictionary

```csharp
// Created in PowerShell, passed to C# engine
Dictionary<string, int> patternCounts
// Converted to $results.Patterns hashtable after scan
```

### 12.4 File Signatures Table

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

All signatures are 4+ bytes. The original 2-byte `"MZ"` signature was removed because random data has a ~1/65536 chance of matching per sector.

---

## 13. Performance Architecture

### 13.1 Why C# via Add-Type?

PowerShell's `foreach` loops are interpreted. A 500 GB disk at 512 bytes/sector = ~1 billion sectors. Each sector previously went through 4-5 separate PowerShell `foreach` byte loops (entropy, distribution, ASCII ratio, frequency counting). This resulted in multi-day scan times.

The compiled C# engine performs all analysis in a single loop per sector, with ~100-500x throughput improvement over interpreted PowerShell.

### 13.2 I/O Strategy

- **Full disk scan:** Sequential reads in 1 MB chunks (2048 sectors per read). No `Seek` needed -- sequential reads advance the stream position automatically. The OS read-ahead cache works optimally.
- **Sample scan:** Individual sector reads via `Seek` + `Read` on a persistent `FileStream`. The stream is opened once and reused.
- **Buffer reuse:** Pre-allocated byte arrays reused across reads to reduce GC pressure. `$chunkBuffer` = 1 MB for full disk; `$readBuffer` = sector size for sample mode.

### 13.3 Shared FileStream

The disk is opened **once** before the scan loop and closed **once** after. This eliminates one `Open` + `Close` + `Dispose` per sector (was ~100,000+ syscalls for a typical sample scan).

### 13.4 Early-Exit Pattern Checks

The C# engine checks zero-fill and one-fill **before** calculating entropy, distribution, and ASCII ratio. For a zero-filled sector, this confirms the status using only the frequency table (all 512 counts in bucket 0x00). Without early exit, entropy/distribution/ASCII would add unnecessary computation.

### 13.5 Entropy Gate for Signatures

File signature checking only occurs when `entropy < 7.0`. This avoids false positives from random data and saves the overhead of iterating 11 signatures when the sector is clearly random.

### 13.6 Memory Management

| Component | Memory |
|-----------|--------|
| Global frequency table | 2 KB (256 x 8 bytes) |
| Chunk buffer (full scan) | 1 MB |
| Sector buffer (sample) | 512 bytes or 4 KB |
| Leftover entries (capped) | ~50 KB max |
| Pattern counts dictionary | ~1 KB |
| **Total** | **~1-2 MB** |

---

## 14. Threading Model and GUI Responsiveness

### The Problem

PowerShell WinForms runs on a single thread. When `Main-Process` enters its scan loop, the GUI message pump is blocked. The user cannot click cancel, move the window, or see progress updates.

### The Solution: DoEvents + Time-Based Refresh

The scan loop uses a `Stopwatch`-based timer:

```powershell
$uiTimer = [System.Diagnostics.Stopwatch]::StartNew()
$uiIntervalMs = 250

if ($percent -ne $lastPercent) {
    # Percent changed: full UI update
    $StatusLabel.Text = "..."
    $ScanProgress.Value = ...
    $ProgressLabel.Text = "..."
    DoEvents
    $lastPercent = $percent
    $uiTimer.Restart()
} elseif ($uiTimer.ElapsedMilliseconds -ge $uiIntervalMs) {
    # 250ms elapsed: minimal UI update (status text + DoEvents)
    $StatusLabel.Text = "..."
    DoEvents
    $uiTimer.Restart()
}
```

This ensures `DoEvents` is called at least every 250ms regardless of scan speed.

**Why 250ms?** This provides ~4 updates per second, perceived as smooth. Lower values add measurable overhead; higher values feel sluggish when clicking cancel.

### DoEvents Overhead

When no pending messages exist, `DoEvents` returns almost instantly (~0.01ms). If many messages queue up (rapid console logging), it can take longer -- this is why `Write-Console` calls `DoEvents` internally to prevent queue buildup.

### Cancellation Latency

Maximum delay between clicking "Cancel" and the scan checking `$script:cancelRequested` is 250ms. This feels instantaneous.

---

## 15. Error Handling Strategy

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
        # ALWAYS executed: cleanup
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

The `finally` block ensures the disk stream is always closed and UI controls are always re-enabled.

### Per-Sector Error Handling

Both scan paths wrap disk I/O in individual try/catch:

**Sample path:**
```powershell
try {
    [void]$diskStream.Seek($offset, ...)
    $bytesRead = $diskStream.Read(...)
    if ($bytesRead -gt 0) { ... }
}
catch {
    $sectorData = $null  # Classified as "Unreadable"
}
```

**Full disk path:**
```powershell
try {
    $bytesRead = $diskStream.Read($chunkBuffer, 0, $bytesToRead)
    if ($bytesRead -le 0) { ... handle as unreadable ... }
    # Partial read handling for last chunk
}
catch {
    # Mark remaining sectors in chunk as unreadable
}
```

A failed read results in "Unreadable" classification. The scan continues.

### Module Loading Error

If any module fails to load, the scan aborts with a fatal error message.

---

## 16. Report Generation Pipeline

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
```

**PDF fallback chain:**
```
Edge (Chromium) -> Chrome -> Brave -> wkhtmltopdf -> Word COM -> HTML fallback
```

### Report CSS Classes

- `.status-verified` / `.status-warning` / `.status-failed` -- Color-coded status banners
- `.leftover-clean` / `.leftover-warning` / `.leftover-critical` -- Conditional leftover banners
- `.badge-not-wiped` / `.badge-suspicious` -- Inline status badges in leftover table
- `.hex-addr` -- Monospace font for sector numbers and hex addresses
- `.grid` / `.card` -- Three-column metric cards
- `.no-break` -- Prevents page breaks inside sections (print)
- `.page-break` -- Forces a page break before the certification page

### Status Matching

Uses `-like` operator for wildcard matching:
```powershell
$statusClass = if ($OverallStatus -like "VERIFIED*") { "verified" }
               elseif ($OverallStatus -like "MOSTLY*") { "warning" }
               else { "failed" }
```

---

## 17. Known Limitations and Edge Cases

### 17.1 Full Scan GetEnumerator

The `GetEnumerator` scriptblock returned for full scans is defined but never called. The scan loop uses a direct `while` counter -- faster than invoking a scriptblock.

### 17.2 Sector Size Mismatch

If the user selects a sector size that doesn't match the disk's physical sector size, the tool will still read that many bytes per seek. This may cause reading across sector boundaries (harmless but technically imprecise).

### 17.3 Cancel During Report Generation

If the user cancels during report generation (after the scan loop), cancellation has no effect -- the report generation runs to completion. Cancellation only works during the scan loop.

### 17.4 PDF Browser Popup

`Start-Process` for Edge/Chrome headless PDF may briefly show a console window or taskbar entry depending on the system configuration.

### 17.5 Disk Stream Sharing

The shared `FileStream` uses `FileShare.ReadWrite`. If another process writes to the disk during the scan, the read data may include both old and new content. The disk should be unmounted or idle.

### 17.6 Last-Sector Boundary

Physical drives often have 1-2 unreachable sectors at the very end (HPA/DCO reserved area). Sample locations are capped at `TotalSectors - 2`. The full disk scan wraps I/O in try/catch and handles partial reads on the last chunk.

---

## 18. Changelog (Code-Level)

### v4.0 (2026-02-13)

**Files changed:** `Main.ps1`, `Modules/DiskAnalysisEngine.ps1` (new), `GUI/GUI.ps1`, `GUI/Elements/FullDiskCheckBox.ps1`, `GUI/Elements/SampleSize.ps1`, `Modules/Get-SampleLocations.ps1`, `Modules/New-HtmlReport.ps1`

1. **DiskAnalysisEngine.ps1 -- Compiled C# engine**
   - All byte-level analysis (entropy, distribution, ASCII ratio, signatures, classification) compiled to .NET via `Add-Type`
   - `AnalyzeSector` processes one sector with full classification in compiled code
   - `AnalyzeChunk` processes 1 MB buffers (2048 sectors) for full-disk mode
   - `RecordLeftover` tracks NOT Wiped/Suspicious entries with a cap of 500
   - `ComputeGlobalEntropy` calculates overall entropy from accumulated frequency table
   - 100-500x throughput improvement over interpreted PowerShell

2. **Main.ps1 -- Dual scan paths with compiled engine**
   - Full disk: sequential 1 MB chunk reads -> `AnalyzeChunk()`
   - Sample: seek + read single sector -> `AnalyzeSector()`
   - Both paths use try/catch around disk I/O with graceful "Unreadable" fallback
   - Partial-read handling for last chunk in full disk mode
   - Status matching fixed from `-eq "VERIFIED*"` to `-like "VERIFIED*"`
   - Speed and ETA display during scan

3. **GUI.ps1 -- Menu bar with Debug Mode**
   - "Options" menu with "Debug Mode" toggle
   - When enabled: unlocks FullDiskCheckBox and SampleSize for test runs
   - When disabled: forces full disk scan and locks controls

4. **FullDiskCheckBox.ps1 + SampleSize.ps1 -- Default full scan**
   - FullDiskCheckBox checked and disabled by default
   - SampleSize disabled with darkened background by default

5. **Get-SampleLocations.ps1 -- Long-safe and boundary-safe**
   - Uses `HashSet<long>` for O(1) dedup
   - Long-safe random generation (combines two 31-bit randoms)
   - Last sectors capped at `TotalSectors - 2` to avoid HPA/DCO reserved area
   - Converts to sorted `[long[]]` array

6. **New-HtmlReport.ps1 -- Updated status matching and leftover display**
   - Status matching uses `-like` operator
   - Leftover section with conditional banners (green/yellow/red based on count)
   - Accepts `Leftovers` (LeftoverEntry[]) and `TotalLeftoverCount` parameters

### v3.9.0210.01 (2026-02-10)

**Files changed:** `Main.ps1`, `GUI/ActionModules/Start-Scan.ps1`, `Modules/Get-ByteDistributionScore.ps1`

1. **Main.ps1 -- Time-based UI refresh**
   - Added `Stopwatch`-based timer with 200ms interval (later updated to 250ms in v4.0)
   - Both scan loops call `DoEvents` when timer elapses, in addition to percent-change trigger

2. **Start-Scan.ps1 -- ResultLabel bug fix**
   - Changed `$ResultLabel.Text = Color 255 255 255` to `$ResultLabel.ForeColor = Color 255 255 255` and `$ResultLabel.Text = ""`

3. **Get-ByteDistributionScore.ps1 -- Array optimization**
   - Replaced hashtable-based frequency counting with fixed `int[256]` array

### v3.9.0209.01 (2026-02-09)

**Files changed:** `Main.ps1`, `Modules/Get-DataLeftoverMarkers.ps1` (new), `Modules/New-HtmlReport.ps1`, `Modules/Get-SampleLocations.ps1`

- Added `Get-DataLeftoverMarkers.ps1` module with three functions
- Integrated marker collection into scan loops in `Main.ps1`
- Added data leftover section to HTML report
- Fixed critical memory crash for full-disk scans (streaming iterator pattern)
- Shared `FileStream` for the entire scan instead of per-sector opens
- `Get-SampleLocations` returns lightweight object for full scans (no array)

### v3.9.0203.01 (2026-02-03)

**Files changed:** `Main.ps1`, `Modules/Get-SampleLocations.ps1`, `Modules/Get-ShannonEntropy.ps1`

- Replaced `ArrayList` byte storage with running `long[256]` histogram
- Added `Get-ShannonEntropyFromHistogram` function
- Replaced array concatenation with `HashSet<long>` in `Get-SampleLocations`
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

## Appendix: Status Codes

| Code | SectorResult.Status | Meaning | Report Category |
|------|---------------------|---------|-----------------|
| 0 | Wiped | Sector shows wipe pattern | Wiped Sectors |
| 1 | NOT Wiped | Residual data detected | Not Wiped + Leftover table |
| 2 | Suspicious | Ambiguous, could be data | Suspicious + Leftover table |
| 3 | Unreadable | I/O error or empty read | Unreadable Sectors |

## Appendix: Confidence Scores

| Pattern | Confidence | Derivation |
|---------|-----------|------------|
| Zero-filled | 100% | Exact byte match |
| One-filled | 100% | Exact byte match |
| DoD 5220.22-M random | ~93-97% | `(entropy/8)*60 + distribution*40` |
| Cryptographic wipe | ~88-95% | `(entropy/8)*50 + distribution*50` |
| Probable wipe | ~87-99% | `entropy/8 * 100` |
| File signature | 95% | Fixed (exact header match) |
| Text content | 75% | Fixed (heuristic) |
| Residual data | 65% | Fixed (medium entropy catch-all) |
| Compressed/encrypted | 60% | Fixed (heuristic) |
| Structured data | 85% | Fixed (low entropy = organized) |
| Unknown pattern | 50% | Fixed (fallback) |

---

## License

Copyright (c) 2026 Yannick Morgenthaler / JSW
Contact: yannick.morgenthaler@jsw.swiss
