# Technical Documentation

Deep technical documentation for developers who want to understand, modify, or extend the Disk Wipe Verification Tool.

---

## Architecture Overview

The application follows a layered architecture with clear separation of concerns:

```
EXE.ps1                         Entry point (convertible to .exe)
  |
  v
Load-Components.ps1              Component loader / bootstrap
  |
  +-- Main.ps1                   Core scan logic (Main-Process function)
  +-- Index.ps1                  Module and connector loader
  +-- GUI/GUI.ps1                GUI framework and window setup
        |
        +-- GUI/Elements/        Individual GUI controls (labels, buttons, panels, etc.)
        +-- GUI/NewElements/     Factory functions for creating WinForms controls
        +-- GUI/ActionModules/   Event handlers (Start-Scan, Cancel-Scan, etc.)
        |
        +-- Modules/             Analysis modules
        |     +-- DiskAnalysisEngine.ps1   Compiled C# engine (hot path)
        |     +-- New-HtmlReport.ps1       HTML report generation
        |     +-- Convert-HtmlToPdf.ps1    PDF conversion (multi-browser fallback)
        |     +-- Get-SampleLocations.ps1  Random sector selection
        |     +-- Get-AvailableDisks.ps1   Disk enumeration
        |     +-- (legacy PS modules)      Kept for standalone/debug use
        |
        +-- Connectors/          Bridge utilities between GUI and logic
              +-- DoEvents.ps1           GUI message pump
              +-- Get-Parameters.ps1     Read GUI fields into hashtable
              +-- Write-Console.ps1      Append colored text to RichTextBox console
```

### Design Principles

1. **Dot-source loading:** All files are loaded via `. .\path\to\file.ps1`. Functions and variables from any file are globally available after loading.
2. **GUI variables are global:** WinForms controls like `$ScanProgress`, `$StatusLabel`, `$Console` are created in GUI element files and referenced directly throughout the codebase.
3. **Compiled hot path:** All byte-level analysis runs in compiled C# via `Add-Type`. PowerShell only handles I/O, orchestration, and UI updates.
4. **Throttled GUI updates:** The scan loop uses a `Stopwatch` to call `DoEvents` at most every 250ms, preventing the GUI from freezing or consuming CPU on UI repaints.

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
| `RecordLeftover(long sectorNum, int sectorSize, SectorResult result)` | Records a leftover finding (called internally by AnalyzeChunk, or explicitly from PS in sample mode) |

**Data structures:**

- `SectorResult` -- Status (0=Wiped, 1=NotWiped, 2=Suspicious, 3=Unreadable), Pattern string, Confidence int
- `ChunkStats` -- Wiped/NotWiped/Suspicious/Unreadable counts for a batch
- `LeftoverEntry` -- SectorNumber, DiskOffset, Status string, Pattern, Confidence

**Leftover tracking:** The engine caps stored entries at 500 (`MaxLeftovers`) to prevent memory issues on heavily unwiped disks, but `TotalLeftoverCount` tracks the true total.

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
| `EntropyPercent` | double | Overall entropy as a percentage of maximum (8 bits) |
| `OverallStatus` | string | Verification verdict |
| `SectorSize` | int | Bytes per sector |
| `Leftovers` | object[] | Array of LeftoverEntry structs |
| `TotalLeftoverCount` | long | Total leftovers found (may be larger than Leftovers array) |

**Report sections:** Disk Information, Analysis Summary (cards), Detailed Sector Analysis, Detected Wipe Patterns, Data Leftover Analysis, Verification Methodology, Certification (signature lines).

### Convert-HtmlToPdf.ps1

Attempts PDF conversion using four fallback methods in order:
1. Microsoft Edge (headless `--print-to-pdf`)
2. Google Chrome (headless)
3. Brave Browser (headless)
4. wkhtmltopdf
5. Microsoft Word COM object

Returns `$true` if a PDF was successfully created, `$false` otherwise.

### Get-SampleLocations.ps1

Generates a sorted, deduplicated list of sector indices to sample:
- First 100 sectors (disk start -- boot sectors, partition tables)
- Last 100 sectors (disk end -- backup structures)
- Remaining count filled with random indices from the middle

Only called when the Full Disk Scan checkbox is unchecked.

### Connectors

- **DoEvents.ps1:** Wraps `[System.Windows.Forms.Application]::DoEvents()` to pump the GUI message queue.
- **Get-Parameters.ps1:** Reads GUI input fields and returns a hashtable with `technician`, `diskNumber`, `sampleSize`, `sectorSize`, `reportFormat`, `reportPath`, `reportFile`.
- **Write-Console.ps1:** Appends a timestamped, color-coded message to the RichTextBox console and calls `DoEvents`.

---

## Extending the Tool

### Adding a New File Signature

1. Open `Main.ps1`, find the `$FileSignatures` hashtable (around line 108).
2. Add a new entry:
   ```powershell
   "BMP" = [byte[]]@(0x42, 0x4D)  # BM header
   ```
3. The compiled engine picks up signatures via `SetSignatures()` -- no C# changes needed.
4. Minimum signature length: 4 bytes recommended to avoid false positives on random data.

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

The engine stores up to 500 detailed leftover entries by default. To change this:
```csharp
// In DiskAnalysisEngine.ps1, inside the C# block:
public static int MaxLeftovers = 500;  // Change this value
```
Higher values use more memory but provide more complete leftover details in the report.

---

## Performance Architecture

### Why C# via Add-Type?

PowerShell's `foreach` loops are interpreted. A 500 GB disk at 512 bytes/sector = ~1 billion sectors. Each sector previously went through 4-5 separate PowerShell `foreach` byte loops (entropy, distribution, ASCII ratio, frequency counting). This resulted in multi-day scan times.

The compiled C# engine performs all analysis in a single loop per sector, with ~100-500x throughput improvement over interpreted PowerShell.

### I/O Strategy

- **Full disk scan:** Sequential reads in 1 MB chunks (2048 sectors per read). The OS read-ahead cache works optimally with sequential access.
- **Sample scan:** Individual sector reads via `Seek` + `Read` on a persistent `FileStream`. The stream is opened once and reused for all sectors.
- **Buffer reuse:** Pre-allocated byte arrays are reused across reads to reduce GC pressure.

### Memory Management

- **No raw byte storage:** The engine maintains only a 256-element `long[]` frequency table (~2 KB), a printable ASCII counter, and a total byte counter.
- **Leftover cap:** At most 500 `LeftoverEntry` structs are stored (~50 KB). The `TotalLeftoverCount` tracks the real count beyond the cap.
- **GUI throttling:** UI updates every 250ms via `Stopwatch`, not every sector. This eliminates millions of `DoEvents` calls.

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

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 08.01.2026 | Initial script |
| 2.0 | 11.01.2026 | Improved algorithms and reports |
| 3.0 | 12.01.2026 | Split into modular architecture |
| 3.8 | 16.01.2026 | GUI, component loader, EXE structure |
| 4.0 | Current | Compiled C# engine, batched I/O, streaming counters, leftover tracking |
