# Compiled C# engine for high-performance disk analysis
# Replaces all interpreted PowerShell byte-level loops with compiled .NET code

Add-Type -TypeDefinition @"
using System;
using System.IO;

public struct SectorResult
{
    public int Status;      // 0=Wiped, 1=NotWiped, 2=Suspicious, 3=Unreadable
    public string Pattern;
    public int Confidence;
}

public struct ChunkStats
{
    public int Wiped;
    public int NotWiped;
    public int Suspicious;
    public int Unreadable;
}

public static class DiskAnalysisEngine
{
    // Shared accumulator: 256 byte frequencies + printable ASCII count + total byte count
    // Index 0-255 = byte frequencies, 256 = printableAsciiCount, 257 = totalByteCount (high), 258 = totalByteCount (low)
    // We use long[] for the global accumulator
    public static long[] GlobalFrequency = new long[256];
    public static long GlobalTotalBytes = 0;
    public static long GlobalPrintableAscii = 0;

    public static void ResetGlobalCounters()
    {
        Array.Clear(GlobalFrequency, 0, 256);
        GlobalTotalBytes = 0;
        GlobalPrintableAscii = 0;
    }

    // File signature definitions (populated once from PowerShell)
    private static byte[][] sigBytes;
    private static string[] sigNames;

    public static void SetSignatures(byte[][] signatures, string[] names)
    {
        sigBytes = signatures;
        sigNames = names;
    }

    // Analyze a single sector: classify + accumulate global frequency counters
    // Returns SectorResult with status and pattern
    public static SectorResult AnalyzeSector(byte[] data, int offset, int length)
    {
        SectorResult r = new SectorResult();

        if (data == null || length == 0)
        {
            r.Status = 3; // Unreadable
            r.Pattern = "N/A";
            r.Confidence = 0;
            return r;
        }

        int end = offset + length;

        // --- Accumulate into global frequency table ---
        int printable = 0;
        int[] localFreq = new int[256];
        for (int i = offset; i < end; i++)
        {
            byte b = data[i];
            localFreq[b]++;
            // Printable ASCII: 32-126, tab(9), LF(10), CR(13)
            if ((b >= 32 && b <= 126) || b == 9 || b == 10 || b == 13)
                printable++;
        }

        // Merge into global counters
        for (int i = 0; i < 256; i++)
        {
            if (localFreq[i] > 0)
                GlobalFrequency[i] += localFreq[i];
        }
        GlobalTotalBytes += length;
        GlobalPrintableAscii += printable;

        // --- Check zero-fill ---
        if (localFreq[0x00] == length)
        {
            r.Status = 0; r.Pattern = "Zero-filled (0x00)"; r.Confidence = 100;
            return r;
        }

        // --- Check one-fill ---
        if (localFreq[0xFF] == length)
        {
            r.Status = 0; r.Pattern = "One-filled (0xFF)"; r.Confidence = 100;
            return r;
        }

        // --- Compute entropy and distribution from local frequency ---
        double entropy = 0.0;
        double expected = length / 256.0;
        double chiSquare = 0.0;

        for (int i = 0; i < 256; i++)
        {
            if (localFreq[i] > 0)
            {
                double p = (double)localFreq[i] / length;
                entropy -= p * Math.Log(p, 2.0);
            }
            double diff = localFreq[i] - expected;
            chiSquare += (diff * diff) / expected;
        }

        double maxChi = (double)length * 255.0;
        double distribution = Math.Max(0.0, Math.Min(1.0, 1.0 - (chiSquare / maxChi)));
        double asciiRatio = (double)printable / length;

        // --- HIGH ENTROPY PATH: DoD 5220.22-M random pass detection ---
        if (entropy > 7.0)
        {
            if (entropy > 7.5 && distribution > 0.80)
            {
                r.Status = 0; r.Pattern = "Random data (DoD 5220.22-M)";
                r.Confidence = (int)Math.Round((entropy / 8.0) * 60.0 + distribution * 40.0);
                return r;
            }
            if (distribution > 0.75 && asciiRatio < 0.5)
            {
                r.Status = 0; r.Pattern = "Random data (cryptographic wipe)";
                r.Confidence = (int)Math.Round((entropy / 8.0) * 50.0 + distribution * 50.0);
                return r;
            }
            if (asciiRatio > 0.7)
            {
                r.Status = 1; r.Pattern = "Text content detected"; r.Confidence = 75;
                return r;
            }
            if (distribution > 0.70)
            {
                r.Status = 0; r.Pattern = "Random data (probable wipe)";
                r.Confidence = (int)Math.Round(entropy / 8.0 * 100.0);
                return r;
            }
        }

        // --- LOW/MEDIUM ENTROPY: check file signatures ---
        if (entropy < 7.0 && sigBytes != null)
        {
            for (int s = 0; s < sigBytes.Length; s++)
            {
                byte[] sig = sigBytes[s];
                if (length < sig.Length) continue;
                bool match = true;
                for (int j = 0; j < sig.Length; j++)
                {
                    if (data[offset + j] != sig[j]) { match = false; break; }
                }
                if (match)
                {
                    r.Status = 1; r.Pattern = "File signature: " + sigNames[s]; r.Confidence = 95;
                    return r;
                }
            }
        }

        // --- Medium entropy ---
        if (entropy > 5.0 && entropy <= 7.0)
        {
            if (asciiRatio < 0.3 && distribution > 0.6)
            {
                r.Status = 2; r.Pattern = "Compressed/encrypted data possible"; r.Confidence = 60;
                return r;
            }
            r.Status = 1; r.Pattern = "Residual data likely"; r.Confidence = 65;
            return r;
        }

        // --- Low entropy ---
        if (entropy <= 5.0)
        {
            r.Status = 1; r.Pattern = "Structured data detected"; r.Confidence = 85;
            return r;
        }

        r.Status = 1; r.Pattern = "Unknown data pattern"; r.Confidence = 50;
        return r;
    }

    // Process an entire buffer of multiple sectors at once (the hot path)
    // Returns aggregated counts: [wiped, notWiped, suspicious, unreadable]
    // Also returns pattern counts via the patternCounts dictionary
    public static ChunkStats AnalyzeChunk(byte[] buffer, int bytesRead, int sectorSize,
        System.Collections.Generic.Dictionary<string, int> patternCounts)
    {
        ChunkStats stats = new ChunkStats();
        int sectorsInChunk = bytesRead / sectorSize;

        for (int s = 0; s < sectorsInChunk; s++)
        {
            int offset = s * sectorSize;
            SectorResult result = AnalyzeSector(buffer, offset, sectorSize);

            switch (result.Status)
            {
                case 0: stats.Wiped++; break;
                case 1: stats.NotWiped++; break;
                case 2: stats.Suspicious++; break;
                case 3: stats.Unreadable++; break;
            }

            if (patternCounts.ContainsKey(result.Pattern))
                patternCounts[result.Pattern]++;
            else
                patternCounts[result.Pattern] = 1;
        }

        return stats;
    }

    // Compute Shannon entropy from the global frequency table
    public static double ComputeGlobalEntropy()
    {
        if (GlobalTotalBytes == 0) return 0.0;
        double entropy = 0.0;
        for (int i = 0; i < 256; i++)
        {
            if (GlobalFrequency[i] > 0)
            {
                double p = (double)GlobalFrequency[i] / GlobalTotalBytes;
                entropy -= p * Math.Log(p, 2.0);
            }
        }
        return entropy;
    }

    // Get the printable ASCII ratio from global counters
    public static double GetGlobalPrintableAsciiRatio()
    {
        if (GlobalTotalBytes == 0) return 0.0;
        return (double)GlobalPrintableAscii / GlobalTotalBytes;
    }

    // Get the byte distribution score from global frequency table
    public static double ComputeGlobalByteDistribution()
    {
        if (GlobalTotalBytes == 0) return 0.0;
        double expected = (double)GlobalTotalBytes / 256.0;
        double chiSquare = 0.0;
        for (int i = 0; i < 256; i++)
        {
            double diff = GlobalFrequency[i] - expected;
            chiSquare += (diff * diff) / expected;
        }
        double maxChi = (double)GlobalTotalBytes * 255.0;
        return Math.Max(0.0, Math.Min(1.0, 1.0 - (chiSquare / maxChi)));
    }

    // Get the global frequency table as long[] for histogram
    public static long[] GetGlobalFrequency()
    {
        return (long[])GlobalFrequency.Clone();
    }
}
"@ -Language CSharp
