# Deep Code Documentation

Complete code-level documentation of every file, function, data structure, and algorithm in the Disk Wipe Verification Tool. This document is intended for expert developers who need to understand the full internal workings.

---

## Table of Contents

1. [Entry Point & Bootstrap Chain](#1-entry-point--bootstrap-chain)
2. [GUI Framework](#2-gui-framework)
3. [Connectors](#3-connectors)
4. [Core Scan Logic (Main.ps1)](#4-core-scan-logic-mainps1)
5. [Compiled C# Analysis Engine](#5-compiled-c-analysis-engine)
6. [Legacy PowerShell Analysis Modules](#6-legacy-powershell-analysis-modules)
7. [Report Generation](#7-report-generation)
8. [Data Flow Diagram](#8-data-flow-diagram)

---

## 1. Entry Point & Bootstrap Chain

### EXE.ps1

```
#Requires -RunAsAdministrator
. .\Load-Components.ps1
Load-Components
```

The outermost entry point. The `#Requires -RunAsAdministrator` directive ensures the process has elevated privileges (needed for raw disk access via `\\.\PhysicalDriveN`). It dot-sources `Load-Components.ps1` and calls the `Load-Components` function.

**Design intent:** This file is designed to be converted into a standalone `.exe` via PS2EXE. Keeping it minimal means the bootstrap logic can be updated independently.

### Load-Components.ps1

```powershell
function Load-Components {
    . .\Main.ps1      # Defines Main-Process function
    . .\Index.ps1      # Loads all Modules + Connectors
    . .\GUI\GUI.ps1    # Defines Load-GUI function
    Load-GUI           # Opens the window
}
```

Dot-sources the three major subsystems in order, then calls `Load-GUI`. This is the only function that directly triggers the GUI.

**Load order matters:** `Main.ps1` must be loaded before `GUI.ps1` because the Start-Scan event handler calls `Main-Process`, which must already be defined.

### Index.ps1

Loads all module and connector files into the session scope:

```
Modules:   Convert-HtmlToPdf, Get-AvailableDisks, Get-ByteDistributionScore,
           Get-ByteHistogram, Get-PrintableAsciiRatio, Get-SampleLocations,
           Get-ShannonEntropy, New-HtmlReport, Read-DiskSector,
           Test-FileSignatures, Test-SectorWiped
Connectors: DoEvents, Get-Parameters, Write-Console
```

**Note:** The compiled C# engine (`DiskAnalysisEngine.ps1`) is NOT loaded here. It is loaded inside `Main-Process` to ensure it is compiled fresh each session (the `Add-Type` call is idempotent but must happen before any engine methods are called).

---

## 2. GUI Framework

### GUI/GUI.ps1 -- `Load-GUI`

The main function that builds and displays the WinForms application.

**Execution sequence:**

1. **Load ActionModules** -- Event handler functions: `Browse-Path`, `DataGridView-DoubleClick`, `Full-DiskScan`, `Disk-List`, `Load-Disks`, `Start-Scan`, `Cancel-Scan`
2. **Load BaseSettings** -- Common color/font definitions, helper `Color` function
3. **Load NewElement factories** -- Functions like `New-Button`, `New-Label`, etc. that create WinForms controls with consistent defaults
4. **Create MainWindow** -- `System.Windows.Forms.Form` with fixed size 1000x700, dark background (#191919), non-resizable
5. **Create elements** -- Each element file creates a global variable (e.g., `$ScanProgress`, `$StatusLabel`)
6. **Wire event handlers** -- `.Add_Click()`, `.Add_CheckedChanged()`, `.Add_SelectedIndexChanged()` bindings
7. **Load-Disks** -- Initial disk enumeration on launch
8. **ShowDialog** -- Blocking call that runs the message loop until the window closes

### GUI/Elements/ -- Individual Controls

Each file creates one or more WinForms controls and adds them to a parent container. Pattern:

```powershell
# Example: ScanProgress.ps1
$ScanProgress = New-ProgressBar -Name "ScanProgress" -Location "20,380" -Size "340,25"
$GroupBoxL.Controls.Add($ScanProgress)
```

**Key globals created by element files:**

| Variable | Type | File | Purpose |
|----------|------|------|---------|
| `$TechnicianName` | TextBox | TechnicianName.ps1 | Input for technician name |
| `$SampleSize` | NumericUpDown | SampleSize.ps1 | Sample count selector |
| `$SectorSize` | ComboBox | SectorSize.ps1 | Sector size dropdown (512, 1024, 2048, 4096) |
| `$FullDiskCheckBox` | CheckBox | FullDiskCheckBox.ps1 | Toggle full disk vs sample scan |
| `$ReportFormat` | ComboBox | ReportFormat.ps1 | HTML / PDF / Both |
| `$ReportPath` | TextBox | ReportLocation.ps1 | Output folder path |
| `$DiskList` | ListBox | DiskList.ps1 | Available disks selector |
| `$Console` | RichTextBox | Console.ps1 | Colored log output |
| `$ScanProgress` | ProgressBar | ScanProgress.ps1 | Scan progress bar |
| `$ProgressLabel` | Label | ProgressLabel.ps1 | Percentage text |
| `$StatusLabel` | Label | StatusLabel.ps1 | Current operation status |
| `$StartScan` | Button | StartScan.ps1 | Trigger scan |
| `$CancelScan` | Button | CancelScan.ps1 | Cancel running scan |
| `$VerificationPanel` | Panel | VerificationPanel.ps1 | Result color indicator |
| `$ResultLabel` | Label | ResultLabel.ps1 | Result text |
| `$GroupBoxL` | GroupBox | GroupBoxL.ps1 | Left panel container |
| `$GroupBoxR` | GroupBox | GroupBoxR.ps1 | Right panel container |

### GUI/NewElements/ -- Factory Functions

Each file defines a function that creates a WinForms control with standard properties:

```powershell
function New-Button {
    param($Name, $Text, $Location, $Size, $ForeColor, $BackColor)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Name = $Name
    $btn.Text = $Text
    # ... set Location, Size, Colors, Font
    return $btn
}
```

Available factories: `New-Button`, `New-CheckBox`, `New-ComboBox`, `New-DataGridView`, `New-GroupBox`, `New-Label`, `New-ListBox`, `New-NumericUpDown`, `New-Panel`, `New-ProgressBar`, `New-RichTextBox`, `New-StatusBar`, `New-StatusBarLabel`, `New-StatusBarProgressBar`, `New-TextBox`.

### GUI/ActionModules/ -- Event Handlers

#### Start-Scan.ps1 -- `Start-Scan`

1. Validates a disk is selected and a technician name is entered
2. Extracts disk number from `$DiskList.SelectedItem` via regex `"Disk (\d+)"`
3. Shows confirmation dialog (read-only operation warning)
4. Sets `$script:cancelRequested = $false`
5. Disables Start button, enables Cancel button, disables disk list
6. Reads parameters via `Get-Parameters`
7. Logs parameters to console
8. Calls `Main-Process`

#### Cancel-Scan.ps1 -- `Cancel-Scan`

Sets `$script:cancelRequested = $true`. The scan loop in `Main-Process` checks this flag at each chunk/sector boundary.

#### Full-DiskScan.ps1 -- `Full-DiskScan`

Toggles `$SampleSize.Enabled` based on `$FullDiskCheckBox.Checked`. When full disk is checked, the sample size input is disabled (it is not used).

#### Load-Disks.ps1 -- `Load-Disks`

Runs `Get-Disk`, populates `$DiskList` with entries like `"Disk 0 - Samsung SSD 870 (465.76 GB)"`.

#### Browse-Path.ps1 -- `Browse-Path`

Opens a `FolderBrowserDialog` and sets `$ReportPath.Text`.

#### Disk-List.ps1 -- `Disk-List`

Updates `$SectorInfoLabel` when a disk is selected, showing the total number of sectors.

---

## 3. Connectors

### DoEvents.ps1

```powershell
function DoEvents {
    [System.Windows.Forms.Application]::DoEvents()
}
```

Pumps the Windows message queue. This is the mechanism that keeps the GUI responsive during long-running operations. Without it, the window would not repaint, and button clicks would not register.

**Performance note:** This is an expensive call when invoked millions of times. The scan loop throttles it to every 250ms via a `Stopwatch`.

### Get-Parameters.ps1

```powershell
function Get-Parameters {
    $timestamp = Get-Date -Format "yyyMMdd_HHmmss"
    @{
        technician   = $TechnicianName.Text
        diskNumber   = $diskNumber
        sampleSize   = [int]$SampleSize.Value
        sectorSize   = [int]$SectorSize.SelectedItem
        reportFormat = $ReportFormat.SelectedItem
        reportPath   = $ReportPath.Text
        timestamp    = $timestamp
        reportFile   = Join-Path $ReportPath.Text "\DiskWipeReport_$timestamp"
    }
}
```

Reads all GUI input fields into a single hashtable. Called in both `Start-Scan` (for logging) and `Main-Process` (for actual use).

**Note:** `$diskNumber` comes from `Start-Scan`'s regex extraction, not from the GUI directly.

### Write-Console.ps1

```powershell
function Write-Console($Message, $Color) {
    if ($Color -eq $null) { $Color = "White" }
    $timestamp = Get-Date -Format "HH:mm:ss"
    $Console.SelectionStart = $Console.Text.Length
    $Console.SelectionColor = $Color
    $Console.AppendText("[$timestamp] $Message`r`n")
    $Console.ScrollToCaret()
    DoEvents
}
```

Appends a timestamped, color-coded line to the `$Console` RichTextBox and scrolls to the bottom. Each call also pumps the message queue via `DoEvents` to ensure the text is immediately visible.

**Color parameter:** Accepts any value valid for `System.Drawing.Color.FromName()` -- e.g., "Red", "Yellow", "SpringGreen", "Magenta", "Orange", "Gray", "White", "Info" (custom).

---

## 4. Core Scan Logic (Main.ps1)

### Function: `Main-Process`

The central orchestration function. It runs inside a `try/catch/finally` block to ensure UI re-enablement on any error path.

#### Phase 1: Initialization (Lines ~53-100)

1. Displays banner to console
2. Reads parameters via `Get-Parameters` -> `$P`
3. Sets local variables: `$Technician`, `$DiskNumber`, `$SampleSize`, `$SectorSize`, `$ReportFormat`, `$ReportPath`, `$ReportFile`
4. Dot-sources all modules including `DiskAnalysisEngine.ps1`

#### Phase 2: Signature Setup (Lines ~104-128)

Defines `$FileSignatures` as a hashtable mapping names to `[byte[]]` arrays:

```
PDF, ZIP/DOCX, JPEG, PNG, GIF87, GIF89, RAR, 7Z, SQLite, NTFS, EXE
```

Extracts the keys and values into separate arrays and passes them to `[DiskAnalysisEngine]::SetSignatures()`.

#### Phase 3: Disk Validation (Lines ~130-155)

Calls `Get-Disk -Number $DiskNumber`. If the disk does not exist, logs an error and exits. Otherwise extracts:

- `$diskPath = "\\.\PhysicalDrive$DiskNumber"` -- the raw device path for `FileStream`
- `$diskSize = $disk.Size` -- total capacity in bytes
- `$totalSectors = [math]::Floor($diskSize / $SectorSize)` -- sector count

Logs disk information (model, serial, size, total sectors, sample size, report format).

#### Phase 4: Scan Mode Selection (Lines ~157-172)

If `$FullDiskCheckBox.Checked`:
- Sets `$totalSamples = $totalSectors`
- No sample location generation

If unchecked:
- Calls `Get-SampleLocations -TotalSectors $totalSectors -SampleSize $sampleSize`
- Sets `$totalSamples = $sampleLocations.Count`

#### Phase 5: Engine Initialization (Lines ~174-212)

1. `[DiskAnalysisEngine]::ResetGlobalCounters()` -- clears frequency table, byte count, ASCII count, leftovers
2. Creates `$patternCounts` as `Dictionary<string,int>`
3. Creates `$results` hashtable with Wiped/NotWiped/Suspicious/Unreadable counters
4. Opens `$diskStream` via `[System.IO.File]::Open()` with `ReadWrite` share mode (allows other processes to access the disk)
5. Allocates buffers:
   - `$chunkBuffer` = 1 MB (2048 * SectorSize) for full disk sequential reads
   - `$readBuffer` = SectorSize for individual sector reads (sample mode)
6. Initializes `$lastUiUpdate` and `$scanTimer` Stopwatch objects

#### Phase 6A: Full Disk Scan Loop (Lines ~214-271)

```
while ($sectorIndex -lt $totalSectors) {
    1. Check $script:cancelRequested
    2. Calculate chunk size (min of 2048 sectors or remaining)
    3. $diskStream.Read($chunkBuffer, 0, $bytesToRead)
    4. [DiskAnalysisEngine]::AnalyzeChunk($chunkBuffer, $bytesRead, $SectorSize, $patternCounts, $sectorIndex)
    5. Accumulate $results from ChunkStats
    6. Every 250ms: update progress bar, percentage, speed (MB/s), ETA
}
```

**Key details:**
- No `Seek` call needed -- sequential reads advance the stream position automatically
- `$bytesRead -le 0` handles end-of-disk or unreadable regions
- `AnalyzeChunk` receives `$sectorIndex` as `baseSectorIndex` so leftovers record correct absolute sector addresses
- Speed calculated as `$progress / $scanTimer.Elapsed.TotalSeconds * SectorSize / 1MB`
- ETA calculated as `($totalSamples - $progress) / sectorsPerSec`

#### Phase 6B: Sample Scan Loop (Lines ~272-328)

```
foreach ($sectorNum in $sampleLocations) {
    1. Check $script:cancelRequested
    2. $diskStream.Seek($offset, Begin)
    3. $diskStream.Read($readBuffer, 0, $SectorSize)
    4. [DiskAnalysisEngine]::AnalyzeSector($readBuffer, 0, $SectorSize)
    5. Switch on status: increment $results, call RecordLeftover for status 1 or 2
    6. Update $patternCounts dictionary
    7. Every 250ms: update UI
}
```

**Key difference from full disk:** Each sector requires a `Seek` because sample locations are random. The `AnalyzeSector` call processes one sector and returns a `SectorResult`. Leftover recording is done explicitly from PowerShell (not inside the C# engine) because the engine's `AnalyzeSector` doesn't know the absolute sector number.

#### Phase 7: Post-Scan Calculations (Lines ~330-370)

1. Close and dispose `$diskStream`
2. Set progress to 100%, log scan duration
3. `$overallEntropy = [DiskAnalysisEngine]::ComputeGlobalEntropy()` -- Shannon entropy from the global 256-bucket frequency table
4. `$entropyPercent = Round(($overallEntropy / 8) * 100, 2)` -- as percentage of maximum (8 bits = perfectly random)
5. Convert `$patternCounts` dictionary to `$results.Patterns` hashtable
6. `$wipedPercent = Round(($results.Wiped / $totalSamples) * 100, 2)`
7. Determine `$overallStatus`:
   - >= 99.5% wiped -> "VERIFIED CLEAN - Disk Successfully Wiped"
   - >= 95% wiped -> "MOSTLY CLEAN - Manual Review Recommended"
   - < 95% -> "NOT VERIFIED - Recoverable Data Detected"
8. Retrieve leftovers: `[DiskAnalysisEngine]::GetLeftovers()` and `::GetTotalLeftoverCount()`

#### Phase 8: Report Generation (Lines ~412-452)

1. Calls `New-HtmlReport` with all computed data including leftovers
2. Saves HTML to `$ReportFile.html`
3. If PDF requested, calls `Convert-HtmlToPdf` with fallback chain
4. Shows MessageBox offering to open the report
5. Sets verification panel to green + "Verification Complete"

#### Finally Block (Lines ~502-517)

Always executes, regardless of success or error:
1. Closes `$diskStream` if it is still open (safety net)
2. Re-enables `$StartScan`, disables `$CancelScan`, re-enables `$DiskList`

---

## 5. Compiled C# Analysis Engine

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

This is what replaces the old `$allBytes.AddRange()` that caused the overflow. Instead of storing raw bytes, we only maintain 256 counters.

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

**Rationale:** The DoD 5220.22-M standard's final pass writes cryptographically random data. True random data has entropy near 8.0 and very uniform byte distribution (chi-square near 0). Text data also has high entropy but the ASCII ratio distinguishes it.

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

Returns NOT Wiped, "Structured data detected", confidence 85. Low entropy indicates repetitive patterns (e.g., file system structures, logs, databases).

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

Computes Shannon entropy from the global frequency table accumulated across all sectors. This gives the overall entropy of the entire scanned area, not per-sector.

Maximum theoretical value: 8.0 (each of 256 byte values equally likely).

---

## 6. Legacy PowerShell Analysis Modules

These modules are the original interpreted implementations. They are still loaded and available for standalone debugging but are **not called during normal scan operations**. The compiled C# engine replaces all of them in the hot path.

### Get-ShannonEntropy.ps1

```powershell
function Get-ShannonEntropy {
    param([byte[]]$Data)
    # Builds frequency table via foreach loop
    # Computes H = -SUM(p * log2(p))
    # Returns entropy value (0-8 range)
}
```

### Get-ByteDistributionScore.ps1

```powershell
function Get-ByteDistributionScore {
    param([byte[]]$Data)
    # Computes chi-square statistic against uniform distribution
    # Returns score 0-1 (1 = perfectly uniform)
}
```

### Get-PrintableAsciiRatio.ps1

```powershell
function Get-PrintableAsciiRatio {
    param([byte[]]$Data)
    # Counts bytes in range 32-126, 9, 10, 13
    # Returns ratio (0-1)
}
```

### Test-SectorWiped.ps1

```powershell
function Test-SectorWiped {
    param([byte[]]$SectorData)
    # Calls Get-ShannonEntropy, Get-ByteDistributionScore, Get-PrintableAsciiRatio
    # Applies the same classification logic as AnalyzeSector in C#
    # Returns @{ Status="Wiped"/"NOT Wiped"/"Suspicious"/"Unreadable"; Pattern="..."; Details="..." }
}
```

### Test-FileSignatures.ps1

```powershell
function Test-FileSignatures {
    param([byte[]]$Data)
    # Iterates $FileSignatures hashtable
    # Compares first N bytes of $Data against each signature
    # Returns signature name or $null
}
```

### Get-ByteHistogram.ps1

```powershell
function Get-ByteHistogram {
    param([byte[]]$Data)
    # Groups bytes into ranges and returns a histogram
    # Used for visual display (not currently in report)
}
```

### Read-DiskSector.ps1

```powershell
function Read-DiskSector {
    param([string]$DiskPath, [long]$Offset, [int]$Size)
    # Opens FileStream, seeks to offset, reads Size bytes, closes stream
    # Returns byte array or $null on error
}
```

**Performance problem:** Opens and closes a FileStream for every call. This was the original I/O path that caused severe performance issues. Now replaced by the persistent stream in Main.ps1.

### Get-SampleLocations.ps1

```powershell
function Get-SampleLocations {
    param([long]$TotalSectors, [int]$SampleSize)
    # Adds sectors 0-99 (disk start)
    # Adds sectors (end-100)..(end-1) (disk end)
    # Fills remaining with Random.Next(100, TotalSectors-100)
    # Deduplicates with Select-Object -Unique
    # Sorts ascending
    # Returns [long[]] array
}
```

Only called when Full Disk Scan is unchecked.

---

## 7. Report Generation

### New-HtmlReport.ps1

Generates a complete HTML document as a PowerShell string using a here-string (`@"..."@`).

**Parameters:** Technician, Results (hashtable), Disk (WMI object), DiskNumber, DiskSize, TotalSamples, WipedPercent, EntropyPercent, OverallStatus, SectorSize, Leftovers (LeftoverEntry[]), TotalLeftoverCount.

**CSS classes:**
- `.status-verified` / `.status-warning` / `.status-failed` -- Color-coded status banners (green/yellow/red)
- `.leftover-clean` -- Green banner for "no leftovers detected"
- `.leftover-warning` -- Yellow banner for small number of leftovers
- `.leftover-critical` -- Red banner for significant leftovers
- `.badge-not-wiped` / `.badge-suspicious` -- Inline status badges in the leftover table
- `.hex-addr` -- Monospace font for sector numbers and hex addresses
- `.grid` / `.card` -- Three-column metric cards
- `.no-break` -- Prevents page breaks inside sections (print)
- `.page-break` -- Forces a page break before the certification page

**Report sections in order:**

1. **Report ID** -- Unique ID: `WV-{timestamp}-{guid-fragment}`
2. **Status banner** -- Color-coded overall verdict
3. **Disk Information table** -- Number, model, serial, capacity, partition style, bus type, media type
4. **Analysis Summary cards** -- Wiped%, sectors analyzed, entropy%
5. **Detailed Sector Analysis table** -- Wiped/Suspicious/NotWiped/Unreadable with counts and percentages
6. **Detected Wipe Patterns table** -- Each pattern type with occurrence count, sorted descending
7. **Data Leftover Analysis** -- Conditional section:
   - If `$TotalLeftoverCount == 0`: Green "No Data Leftovers Detected" message
   - If `$TotalLeftoverCount <= 50`: Yellow warning with full table
   - If `$TotalLeftoverCount > 50`: Red critical warning with table (capped at 500 rows) and note about remaining entries
   - Table columns: #, Sector Number, Disk Offset (hex), Status (badge), Detected Pattern, Confidence%
8. **Verification Methodology table** -- Date, time, computer, technician, sampling method, sector size, detection method, standards
9. **Certification** -- Data sanitization statement, technician signature lines, supervisor signature lines
10. **Footer** -- Tool version and generation timestamp

### Convert-HtmlToPdf.ps1

Attempts PDF conversion via four fallback methods:

1. **Microsoft Edge** -- `msedge.exe --headless --print-to-pdf`
2. **Google Chrome** -- `chrome.exe --headless --print-to-pdf`
3. **Brave** -- `brave.exe --headless --print-to-pdf`
4. **wkhtmltopdf** -- `wkhtmltopdf.exe` with A4 page settings
5. **Microsoft Word COM** -- `Word.Application` COM object with `SaveAs(wdFormatPDF)`

Each method checks for the executable, attempts conversion, verifies the output file exists, and moves to the next method on failure. Returns `$true`/`$false`.

---

## 8. Data Flow Diagram

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
    |   |           +-- Accumulate GlobalFrequency, GlobalTotalBytes, GlobalPrintableAscii
    |   |           +-- RecordLeftover() if NOT Wiped or Suspicious
    |   |           +-- Update patternCounts dictionary
    |   |       +-- Return ChunkStats
    |   |
    |   +-- [sample] Seek + Read 1 sector -> AnalyzeSector()
    |   |       |
    |   |       +-- Same per-sector logic as above
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
