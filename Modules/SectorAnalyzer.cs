/*
 * SectorAnalyzer.cs - High-Performance Compiled Sector Analysis Engine
 * =====================================================================
 * This C# class is loaded via Add-Type in PowerShell to replace ALL
 * interpreted byte-level loops with compiled .NET code. A single call
 * to AnalyzeSector() performs every analysis that previously required
 * 6+ separate PowerShell foreach loops over each 512-byte sector.
 *
 * Performance gain: ~100-1000x faster than interpreted PowerShell for
 * byte-level operations on 125+ million sectors (64GB+ disks).
 *
 * Consumed by: Main.ps1 scan loops via [SectorAnalyzer]::AnalyzeSector()
 */

using System;
using System.IO;
using System.Collections.Generic;

public struct SectorResult
{
    public string Status;       // "Wiped", "NOT Wiped", "Suspicious", "Unreadable"
    public string Pattern;      // e.g. "Zero-filled (0x00)", "Random data (DoD 5220.22-M)"
    public int    Confidence;   // 0-100
    public string Details;      // Human-readable detail string
    public double Entropy;      // Shannon entropy 0.0-8.0
    public double Distribution; // Byte distribution score 0.0-1.0
    public double AsciiRatio;   // Printable ASCII ratio 0.0-1.0
}

public static class SectorAnalyzer
{
    // ==================================================================
    // AnalyzeSector: ONE call replaces 6+ PowerShell foreach loops
    // ==================================================================
    // Performs in a SINGLE pass over the byte array:
    //   1. All-zero check
    //   2. All-0xFF check
    //   3. Byte frequency counting (for entropy + distribution)
    //   4. Printable ASCII counting
    // Then computes entropy, distribution score, and classification.
    // Also accumulates into the running histogram for overall stats.
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
            result.Status = "Unreadable";
            result.Pattern = "N/A";
            result.Confidence = 0;
            result.Details = "Could not read sector";
            return result;
        }

        int len = data.Length;

        // --- SINGLE PASS: frequency, zero/ff check, ascii count ---
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

            // Printable ASCII: 32-126, tab(9), LF(10), CR(13)
            if ((b >= 32 && b <= 126) || b == 9 || b == 10 || b == 13)
                printableCount++;
        }

        // Accumulate into running histogram (for overall entropy calc)
        if (runningHistogram != null)
        {
            for (int i = 0; i < 256; i++)
            {
                runningHistogram[i] += freq[i];
            }
        }

        // --- PATTERN CHECKS (fast exits) ---
        if (allZero)
        {
            result.Status = "Wiped";
            result.Pattern = "Zero-filled (0x00)";
            result.Confidence = 100;
            result.Details = "All bytes are 0x00 - standard wipe pattern";
            return result;
        }

        if (allFF)
        {
            result.Status = "Wiped";
            result.Pattern = "One-filled (0xFF)";
            result.Confidence = 100;
            result.Details = "All bytes are 0xFF - standard wipe pattern";
            return result;
        }

        // --- COMPUTE ENTROPY ---
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

        // --- COMPUTE BYTE DISTRIBUTION SCORE (chi-square based) ---
        double expected = len / 256.0;
        double chiSquare = 0.0;
        for (int i = 0; i < 256; i++)
        {
            double diff = freq[i] - expected;
            chiSquare += (diff * diff) / expected;
        }
        double maxChi = (double)len * 255;
        double distribution = 1.0 - (chiSquare / maxChi);
        if (distribution < 0) distribution = 0;
        if (distribution > 1) distribution = 1;

        // --- ASCII RATIO ---
        double asciiRatio = (double)printableCount / len;

        // Store computed values
        result.Entropy = entropy;
        result.Distribution = distribution;
        result.AsciiRatio = asciiRatio;

        // === CLASSIFICATION LOGIC (mirrors Test-SectorWiped) ===

        // HIGH ENTROPY PATH: DoD 5220.22-M random pass detection
        if (entropy > 7.0)
        {
            if (entropy > 7.5 && distribution > 0.80)
            {
                int conf = (int)Math.Round((entropy / 8.0) * 60 + distribution * 40);
                result.Status = "Wiped";
                result.Pattern = "Random data (DoD 5220.22-M)";
                result.Confidence = conf;
                result.Details = String.Format("Entropy: {0:F2}/8.0, Distribution: {1:F1}%",
                    entropy, distribution * 100);
                return result;
            }

            if (distribution > 0.75 && asciiRatio < 0.5)
            {
                int conf = (int)Math.Round((entropy / 8.0) * 50 + distribution * 50);
                result.Status = "Wiped";
                result.Pattern = "Random data (cryptographic wipe)";
                result.Confidence = conf;
                result.Details = String.Format("Entropy: {0:F2}/8.0, Distribution: {1:F1}%",
                    entropy, distribution * 100);
                return result;
            }

            if (asciiRatio > 0.7)
            {
                result.Status = "NOT Wiped";
                result.Pattern = "Text content detected";
                result.Confidence = 75;
                result.Details = String.Format("High ASCII ratio ({0:F1}%) indicates text data",
                    asciiRatio * 100);
                return result;
            }

            if (distribution > 0.70)
            {
                result.Status = "Wiped";
                result.Pattern = "Random data (probable wipe)";
                result.Confidence = (int)Math.Round(entropy / 8.0 * 100);
                result.Details = String.Format("Entropy: {0:F2}/8.0 - consistent with random wipe",
                    entropy);
                return result;
            }
        }

        // LOW/MEDIUM ENTROPY: check file signatures
        if (entropy < 7.0 && signatureValues != null)
        {
            for (int s = 0; s < signatureValues.Length; s++)
            {
                byte[] sig = signatureValues[s];
                if (len < sig.Length) continue;

                bool match = true;
                for (int j = 0; j < sig.Length; j++)
                {
                    if (data[j] != sig[j]) { match = false; break; }
                }
                if (match)
                {
                    result.Status = "NOT Wiped";
                    result.Pattern = "File signature: " + signatureNames[s];
                    result.Confidence = 95;
                    result.Details = String.Format("Found {0} file header - recoverable data present",
                        signatureNames[s]);
                    return result;
                }
            }
        }

        // Medium entropy
        if (entropy > 5.0 && entropy <= 7.0)
        {
            if (asciiRatio < 0.3 && distribution > 0.6)
            {
                result.Status = "Suspicious";
                result.Pattern = "Compressed/encrypted data possible";
                result.Confidence = 60;
                result.Details = String.Format("Medium entropy ({0:F2}) - may be compressed files",
                    entropy);
                return result;
            }

            result.Status = "NOT Wiped";
            result.Pattern = "Residual data likely";
            result.Confidence = 65;
            result.Details = String.Format("Entropy: {0:F2} - does not match wipe patterns", entropy);
            return result;
        }

        // Low entropy
        if (entropy <= 5.0)
        {
            result.Status = "NOT Wiped";
            result.Pattern = "Structured data detected";
            result.Confidence = 85;
            result.Details = String.Format("Low entropy ({0:F2}) indicates organized/recoverable data",
                entropy);
            return result;
        }

        // Fallback
        result.Status = "NOT Wiped";
        result.Pattern = "Unknown data pattern";
        result.Confidence = 50;
        result.Details = String.Format("Entropy: {0:F2}, unable to classify", entropy);
        return result;
    }

    // ==================================================================
    // ScanDiskBatch: Read and analyze sectors in large sequential batches
    // ==================================================================
    // Reads BATCH_SIZE sectors at once from the stream into a single large
    // buffer, then analyzes each sector from that buffer. This minimizes
    // the number of .Seek()/.Read() calls and maximizes sequential I/O.
    // ==================================================================
    public static List<SectorResult> ScanDiskBatch(
        FileStream stream,
        long startSector,
        int sectorCount,
        int sectorSize,
        long[] runningHistogram,
        byte[][] signatureValues,
        string[] signatureNames)
    {
        var results = new List<SectorResult>(sectorCount);
        long offset = startSector * sectorSize;
        int totalBytes = sectorCount * sectorSize;

        // Read entire batch in one I/O call
        byte[] batchBuffer = new byte[totalBytes];
        stream.Seek(offset, SeekOrigin.Begin);
        int bytesRead = 0;
        while (bytesRead < totalBytes)
        {
            int chunk = stream.Read(batchBuffer, bytesRead, totalBytes - bytesRead);
            if (chunk == 0) break;
            bytesRead += chunk;
        }

        int sectorsRead = bytesRead / sectorSize;

        for (int i = 0; i < sectorsRead; i++)
        {
            byte[] sectorData = new byte[sectorSize];
            Buffer.BlockCopy(batchBuffer, i * sectorSize, sectorData, 0, sectorSize);
            results.Add(AnalyzeSector(sectorData, runningHistogram, signatureValues, signatureNames));
        }

        // Pad unreadable for sectors that couldn't be read
        for (int i = sectorsRead; i < sectorCount; i++)
        {
            results.Add(new SectorResult
            {
                Status = "Unreadable",
                Pattern = "N/A",
                Confidence = 0,
                Details = "Could not read sector"
            });
        }

        return results;
    }

    // ==================================================================
    // BuildHexPreview / BuildAsciiPreview for data leftover markers
    // ==================================================================
    public static string BuildHexPreview(byte[] data, int maxBytes)
    {
        if (data == null || data.Length == 0) return "";
        int count = Math.Min(maxBytes, data.Length);
        var parts = new string[count];
        for (int i = 0; i < count; i++)
            parts[i] = data[i].ToString("X2");
        return string.Join(" ", parts);
    }

    public static string BuildAsciiPreview(byte[] data, int maxBytes)
    {
        if (data == null || data.Length == 0) return "";
        int count = Math.Min(maxBytes, data.Length);
        char[] chars = new char[count];
        for (int i = 0; i < count; i++)
        {
            byte b = data[i];
            chars[i] = (b >= 32 && b <= 126) ? (char)b : '.';
        }
        return new string(chars);
    }

    // ==================================================================
    // ComputeEntropyFromHistogram - replaces Get-ShannonEntropyFromHistogram
    // ==================================================================
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
