/*
 * SectorAnalyzer.cs - High-Performance Compiled Sector Analysis Engine
 * =====================================================================
 * This C# class is loaded via Add-Type in PowerShell to replace ALL
 * interpreted byte-level loops AND the PowerShell scan loop itself with
 * compiled .NET code.
 *
 * Key methods:
 *   AnalyzeSectorInPlace()  - Analyzes a sector directly from a buffer+offset
 *                             (no per-sector array allocation / copy)
 *   RunFullScan()           - Processes an ENTIRE disk end-to-end in C#,
 *                             returning only a summary. PowerShell never
 *                             touches individual sectors or results.
 *   AnalyzeSector()         - Legacy per-sector method for sampled scans
 *
 * Performance: A 64 GB disk (~125M sectors @ 512B) now scans in minutes
 * instead of 24+ hours. The bottleneck was NOT I/O -- it was 125M
 * iterations of interpreted PowerShell per-result processing.
 *
 * Consumed by: Main.ps1
 */

using System;
using System.IO;
using System.Collections.Generic;
using System.Threading;

// ======================================================================
// Result struct for single-sector analysis (used by sampled scan path)
// ======================================================================
public struct SectorResult
{
    public string Status;       // "Wiped", "NOT Wiped", "Suspicious", "Unreadable"
    public string Pattern;      // e.g. "Zero-filled (0x00)"
    public int    Confidence;   // 0-100
    public string Details;      // Human-readable detail string
    public double Entropy;      // Shannon entropy 0.0-8.0
    public double Distribution; // Byte distribution score 0.0-1.0
    public double AsciiRatio;   // Printable ASCII ratio 0.0-1.0
}

// ======================================================================
// Data leftover marker (lightweight struct, no heap allocs per field)
// ======================================================================
public struct DataLeftoverMarker
{
    public long   SectorNumber;
    public string ByteOffset;     // hex string
    public long   ByteOffsetDec;
    public string Status;
    public string Pattern;
    public int    Confidence;
    public string Details;
    public string HexPreview;
    public string AsciiPreview;
}

// ======================================================================
// Full-scan summary returned to PowerShell (one object, no per-sector data)
// ======================================================================
public class ScanSummary
{
    public long Wiped;
    public long NotWiped;
    public long Suspicious;
    public long Unreadable;
    public long TotalScanned;
    public long TotalBytesRead;
    public Dictionary<string, long> Patterns = new Dictionary<string, long>();
    public long[] RunningHistogram = new long[256];
    public List<DataLeftoverMarker> Markers = new List<DataLeftoverMarker>();
    public int  MarkerOverflowCount;
    public long SummaryNotWiped;
    public long SummarySuspicious;
    public Dictionary<string, long> MarkerPatternCounts = new Dictionary<string, long>();
    public bool Cancelled;
}

// ======================================================================
// Progress callback delegate -- called from C# to let PowerShell update UI
// ======================================================================
public delegate void ProgressCallback(long currentSector, int percent, long scannedSoFar);

public static class SectorAnalyzer
{
    // Maximum markers to store individually
    private const int MAX_MARKERS = 500;

    // ==================================================================
    // RunFullScan: Entire full-disk scan in C# -- PowerShell only does UI
    // ==================================================================
    // Reads the disk in large sequential batches (4 MB each), analyzes
    // every sector in compiled code, accumulates all results, collects
    // data leftover markers, and returns a single ScanSummary object.
    //
    // The ProgressCallback is invoked periodically so PowerShell can
    // update the status label / progress bar / call DoEvents.
    //
    // cancelFlag: set cancelFlag[0] = 1 from PowerShell to stop early.
    // ==================================================================
    public static ScanSummary RunFullScan(
        FileStream stream,
        long totalSectors,
        int sectorSize,
        byte[][] signatureValues,
        string[] signatureNames,
        ProgressCallback progressCallback,
        int[] cancelFlag)
    {
        var summary = new ScanSummary();
        summary.TotalScanned = 0;

        // 4 MB batch = 8192 sectors @ 512 bytes (or 1024 sectors @ 4096 bytes)
        int batchSectors = Math.Max(1, 4 * 1024 * 1024 / sectorSize);
        byte[] batchBuffer = new byte[batchSectors * sectorSize];

        long sectorNum = 0;
        int lastPercent = -1;
        long lastCallbackSector = -1;
        // Time-based callback: at least every 200ms
        long callbackIntervalTicks = TimeSpan.FromMilliseconds(200).Ticks;
        long lastCallbackTicks = DateTime.UtcNow.Ticks;

        // Reusable frequency array (avoid allocation per sector)
        int[] freq = new int[256];

        while (sectorNum < totalSectors)
        {
            // Check cancellation
            if (cancelFlag != null && cancelFlag.Length > 0 && cancelFlag[0] != 0)
            {
                summary.Cancelled = true;
                break;
            }

            // Determine batch size
            long remaining = totalSectors - sectorNum;
            int currentBatch = (int)Math.Min(batchSectors, remaining);
            int totalBytes = currentBatch * sectorSize;

            // Read entire batch in one I/O call
            long offset = sectorNum * sectorSize;
            int bytesRead = 0;
            try
            {
                stream.Seek(offset, SeekOrigin.Begin);
                while (bytesRead < totalBytes)
                {
                    int chunk = stream.Read(batchBuffer, bytesRead, totalBytes - bytesRead);
                    if (chunk == 0) break;
                    bytesRead += chunk;
                }
            }
            catch
            {
                // On I/O error for entire batch, mark all as unreadable
                int unreadable = currentBatch;
                summary.Unreadable += unreadable;
                summary.TotalScanned += unreadable;
                AddPattern(summary, "N/A", unreadable);
                sectorNum += currentBatch;
                continue;
            }

            int sectorsRead = bytesRead / sectorSize;
            int unreadableInBatch = currentBatch - sectorsRead;

            // Analyze each sector from the batch buffer IN PLACE (no copy)
            for (int i = 0; i < sectorsRead; i++)
            {
                int bufferOffset = i * sectorSize;

                // --- SINGLE PASS over sector bytes ---
                Array.Clear(freq, 0, 256);
                bool allZero = true;
                bool allFF = true;
                int printableCount = 0;

                for (int j = 0; j < sectorSize; j++)
                {
                    byte b = batchBuffer[bufferOffset + j];
                    freq[b]++;
                    if (b != 0x00) allZero = false;
                    if (b != 0xFF) allFF = false;
                    if ((b >= 32 && b <= 126) || b == 9 || b == 10 || b == 13)
                        printableCount++;
                }

                // Accumulate running histogram
                for (int k = 0; k < 256; k++)
                    summary.RunningHistogram[k] += freq[k];

                summary.TotalBytesRead += sectorSize;

                // --- CLASSIFY ---
                string status, pattern, details;
                int confidence;

                if (allZero)
                {
                    status = "Wiped"; pattern = "Zero-filled (0x00)"; confidence = 100;
                    details = "All bytes are 0x00 - standard wipe pattern";
                }
                else if (allFF)
                {
                    status = "Wiped"; pattern = "One-filled (0xFF)"; confidence = 100;
                    details = "All bytes are 0xFF - standard wipe pattern";
                }
                else
                {
                    // Compute entropy
                    double entropy = 0.0;
                    double invLen = 1.0 / sectorSize;
                    for (int k = 0; k < 256; k++)
                    {
                        if (freq[k] > 0)
                        {
                            double p = freq[k] * invLen;
                            entropy -= p * Math.Log(p, 2);
                        }
                    }

                    // Compute distribution score
                    double expected = sectorSize / 256.0;
                    double chiSquare = 0.0;
                    for (int k = 0; k < 256; k++)
                    {
                        double diff = freq[k] - expected;
                        chiSquare += (diff * diff) / expected;
                    }
                    double maxChi = (double)sectorSize * 255;
                    double distribution = Math.Max(0, Math.Min(1, 1.0 - (chiSquare / maxChi)));

                    double asciiRatio = (double)printableCount / sectorSize;

                    // Classification logic (mirrors Test-SectorWiped)
                    ClassifySector(entropy, distribution, asciiRatio,
                        batchBuffer, bufferOffset, sectorSize,
                        signatureValues, signatureNames,
                        out status, out pattern, out confidence, out details);
                }

                // Accumulate results
                switch (status)
                {
                    case "Wiped":      summary.Wiped++; break;
                    case "NOT Wiped":  summary.NotWiped++; break;
                    case "Suspicious": summary.Suspicious++; break;
                    default:           summary.Unreadable++; break;
                }
                AddPattern(summary, pattern, 1);
                summary.TotalScanned++;

                // Data leftover markers
                if (status == "NOT Wiped" || status == "Suspicious")
                {
                    long actualSector = sectorNum + i;
                    long byteOff = actualSector * sectorSize;

                    // Always update summary counts
                    if (status == "NOT Wiped") summary.SummaryNotWiped++;
                    else summary.SummarySuspicious++;

                    if (!summary.MarkerPatternCounts.ContainsKey(pattern))
                        summary.MarkerPatternCounts[pattern] = 0;
                    summary.MarkerPatternCounts[pattern]++;

                    // Store individual marker if under cap
                    if (summary.Markers.Count < MAX_MARKERS)
                    {
                        var marker = new DataLeftoverMarker();
                        marker.SectorNumber = actualSector;
                        marker.ByteOffset = "0x" + byteOff.ToString("X");
                        marker.ByteOffsetDec = byteOff;
                        marker.Status = status;
                        marker.Pattern = pattern;
                        marker.Confidence = confidence;
                        marker.Details = details;
                        marker.HexPreview = BuildHexPreviewFromBuffer(batchBuffer, bufferOffset, sectorSize, 32);
                        marker.AsciiPreview = BuildAsciiPreviewFromBuffer(batchBuffer, bufferOffset, sectorSize, 32);
                        summary.Markers.Add(marker);
                    }
                    else
                    {
                        summary.MarkerOverflowCount++;
                    }
                }
            }

            // Mark unreadable sectors at end of batch
            if (unreadableInBatch > 0)
            {
                summary.Unreadable += unreadableInBatch;
                summary.TotalScanned += unreadableInBatch;
                AddPattern(summary, "N/A", unreadableInBatch);
            }

            sectorNum += currentBatch;

            // Progress callback (time-based + percent-based)
            int percent = (int)((sectorNum * 100) / totalSectors);
            long nowTicks = DateTime.UtcNow.Ticks;
            if (percent != lastPercent || (nowTicks - lastCallbackTicks) >= callbackIntervalTicks)
            {
                if (progressCallback != null)
                {
                    try { progressCallback(sectorNum, Math.Min(percent, 100), summary.TotalScanned); }
                    catch { /* UI errors should not kill the scan */ }
                }
                lastPercent = percent;
                lastCallbackTicks = nowTicks;
            }
        }

        return summary;
    }

    // ==================================================================
    // Classification logic (shared by RunFullScan and AnalyzeSector)
    // ==================================================================
    private static void ClassifySector(
        double entropy, double distribution, double asciiRatio,
        byte[] buffer, int offset, int length,
        byte[][] signatureValues, string[] signatureNames,
        out string status, out string pattern, out int confidence, out string details)
    {
        // HIGH ENTROPY PATH: DoD 5220.22-M random pass detection
        if (entropy > 7.0)
        {
            if (entropy > 7.5 && distribution > 0.80)
            {
                confidence = (int)Math.Round((entropy / 8.0) * 60 + distribution * 40);
                status = "Wiped"; pattern = "Random data (DoD 5220.22-M)";
                details = String.Format("Entropy: {0:F2}/8.0, Distribution: {1:F1}%", entropy, distribution * 100);
                return;
            }
            if (distribution > 0.75 && asciiRatio < 0.5)
            {
                confidence = (int)Math.Round((entropy / 8.0) * 50 + distribution * 50);
                status = "Wiped"; pattern = "Random data (cryptographic wipe)";
                details = String.Format("Entropy: {0:F2}/8.0, Distribution: {1:F1}%", entropy, distribution * 100);
                return;
            }
            if (asciiRatio > 0.7)
            {
                status = "NOT Wiped"; pattern = "Text content detected"; confidence = 75;
                details = String.Format("High ASCII ratio ({0:F1}%) indicates text data", asciiRatio * 100);
                return;
            }
            if (distribution > 0.70)
            {
                status = "Wiped"; pattern = "Random data (probable wipe)";
                confidence = (int)Math.Round(entropy / 8.0 * 100);
                details = String.Format("Entropy: {0:F2}/8.0 - consistent with random wipe", entropy);
                return;
            }
        }

        // LOW/MEDIUM ENTROPY: check file signatures
        if (entropy < 7.0 && signatureValues != null)
        {
            for (int s = 0; s < signatureValues.Length; s++)
            {
                byte[] sig = signatureValues[s];
                if (length < sig.Length) continue;
                bool match = true;
                for (int j = 0; j < sig.Length; j++)
                {
                    if (buffer[offset + j] != sig[j]) { match = false; break; }
                }
                if (match)
                {
                    status = "NOT Wiped"; pattern = "File signature: " + signatureNames[s]; confidence = 95;
                    details = String.Format("Found {0} file header - recoverable data present", signatureNames[s]);
                    return;
                }
            }
        }

        // Medium entropy
        if (entropy > 5.0 && entropy <= 7.0)
        {
            if (asciiRatio < 0.3 && distribution > 0.6)
            {
                status = "Suspicious"; pattern = "Compressed/encrypted data possible"; confidence = 60;
                details = String.Format("Medium entropy ({0:F2}) - may be compressed files", entropy);
                return;
            }
            status = "NOT Wiped"; pattern = "Residual data likely"; confidence = 65;
            details = String.Format("Entropy: {0:F2} - does not match wipe patterns", entropy);
            return;
        }

        // Low entropy
        if (entropy <= 5.0)
        {
            status = "NOT Wiped"; pattern = "Structured data detected"; confidence = 85;
            details = String.Format("Low entropy ({0:F2}) indicates organized/recoverable data", entropy);
            return;
        }

        // Fallback
        status = "NOT Wiped"; pattern = "Unknown data pattern"; confidence = 50;
        details = String.Format("Entropy: {0:F2}, unable to classify", entropy);
    }

    // ==================================================================
    // AnalyzeSector: Per-sector method (used by sampled scan path)
    // ==================================================================
    public static SectorResult AnalyzeSector(
        byte[] data,
        long[] runningHistogram,
        byte[][] signatureValues,
        string[] signatureNames)
    {
        var result = new SectorResult();

        if (data == null || data.Length == 0)
        {
            result.Status = "Unreadable"; result.Pattern = "N/A";
            result.Confidence = 0; result.Details = "Could not read sector";
            return result;
        }

        int len = data.Length;
        int[] freq = new int[256];
        bool allZero = true;
        bool allFF = true;
        int printableCount = 0;

        for (int i = 0; i < len; i++)
        {
            byte b = data[i];
            freq[b]++;
            if (b != 0x00) allZero = false;
            if (b != 0xFF) allFF = false;
            if ((b >= 32 && b <= 126) || b == 9 || b == 10 || b == 13)
                printableCount++;
        }

        if (runningHistogram != null)
        {
            for (int i = 0; i < 256; i++)
                runningHistogram[i] += freq[i];
        }

        if (allZero)
        {
            result.Status = "Wiped"; result.Pattern = "Zero-filled (0x00)";
            result.Confidence = 100; result.Details = "All bytes are 0x00 - standard wipe pattern";
            return result;
        }
        if (allFF)
        {
            result.Status = "Wiped"; result.Pattern = "One-filled (0xFF)";
            result.Confidence = 100; result.Details = "All bytes are 0xFF - standard wipe pattern";
            return result;
        }

        double entropy = 0.0;
        double invLen = 1.0 / len;
        for (int i = 0; i < 256; i++)
        {
            if (freq[i] > 0)
            {
                double p = freq[i] * invLen;
                entropy -= p * Math.Log(p, 2);
            }
        }

        double expected = len / 256.0;
        double chiSquare = 0.0;
        for (int i = 0; i < 256; i++)
        {
            double diff = freq[i] - expected;
            chiSquare += (diff * diff) / expected;
        }
        double maxChi = (double)len * 255;
        double distribution = Math.Max(0, Math.Min(1, 1.0 - (chiSquare / maxChi)));
        double asciiRatio = (double)printableCount / len;

        result.Entropy = entropy;
        result.Distribution = distribution;
        result.AsciiRatio = asciiRatio;

        ClassifySector(entropy, distribution, asciiRatio,
            data, 0, len, signatureValues, signatureNames,
            out result.Status, out result.Pattern, out result.Confidence, out result.Details);

        return result;
    }

    // ==================================================================
    // Helper methods
    // ==================================================================
    private static void AddPattern(ScanSummary summary, string pattern, int count)
    {
        if (!summary.Patterns.ContainsKey(pattern))
            summary.Patterns[pattern] = 0;
        summary.Patterns[pattern] += count;
    }

    private static string BuildHexPreviewFromBuffer(byte[] buffer, int offset, int sectorSize, int maxBytes)
    {
        int count = Math.Min(maxBytes, sectorSize);
        var parts = new string[count];
        for (int i = 0; i < count; i++)
            parts[i] = buffer[offset + i].ToString("X2");
        return string.Join(" ", parts);
    }

    private static string BuildAsciiPreviewFromBuffer(byte[] buffer, int offset, int sectorSize, int maxBytes)
    {
        int count = Math.Min(maxBytes, sectorSize);
        char[] chars = new char[count];
        for (int i = 0; i < count; i++)
        {
            byte b = buffer[offset + i];
            chars[i] = (b >= 32 && b <= 126) ? (char)b : '.';
        }
        return new string(chars);
    }

    // Legacy methods kept for compatibility
    public static string BuildHexPreview(byte[] data, int maxBytes)
    {
        if (data == null || data.Length == 0) return "";
        return BuildHexPreviewFromBuffer(data, 0, data.Length, maxBytes);
    }

    public static string BuildAsciiPreview(byte[] data, int maxBytes)
    {
        if (data == null || data.Length == 0) return "";
        return BuildAsciiPreviewFromBuffer(data, 0, data.Length, maxBytes);
    }

    public static double ComputeEntropyFromHistogram(long[] histogram, long totalBytes)
    {
        if (totalBytes == 0) return 0;
        double entropy = 0;
        double invTotal = 1.0 / totalBytes;
        for (int i = 0; i < 256; i++)
        {
            if (histogram[i] > 0)
            {
                double p = histogram[i] * invTotal;
                entropy -= p * Math.Log(p, 2);
            }
        }
        return entropy;
    }
}
