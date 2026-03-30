# Compiled C# engine for high-performance disk analysis
# Replaces all interpreted PowerShell byte-level loops with compiled .NET code

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

// Helper class for raw physical disk access via Win32 CreateFile
// .NET FileStream blocks device paths (\\.\), so we must P/Invoke directly
public static class RawDiskAccess
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern SafeFileHandle CreateFile(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    private const uint GENERIC_READ = 0x80000000;
    private const uint FILE_SHARE_READ = 0x00000001;
    private const uint FILE_SHARE_WRITE = 0x00000002;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_NO_BUFFERING = 0x20000000;
    private const uint FILE_FLAG_SEQUENTIAL_SCAN = 0x08000000;

    /// <summary>
    /// Opens a raw physical disk for reading (e.g., \\.\PhysicalDrive0)
    /// Returns a FileStream that can be used for sector-level reads.
    /// </summary>
    public static FileStream OpenDisk(string diskPath)
    {
        SafeFileHandle handle = CreateFile(
            diskPath,
            GENERIC_READ,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            IntPtr.Zero,
            OPEN_EXISTING,
            FILE_FLAG_SEQUENTIAL_SCAN,
            IntPtr.Zero);

        if (handle.IsInvalid)
        {
            int error = Marshal.GetLastWin32Error();
            throw new IOException("Failed to open disk: " + diskPath + " (Win32 Error: " + error + ")");
        }

        // Wrap the handle in a FileStream for easy reading
        return new FileStream(handle, FileAccess.Read, 4096, false);
    }
}

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

// Represents a single leftover finding for the report
public struct LeftoverEntry
{
    public long SectorNumber;
    public long DiskOffset;      // Byte offset on disk
    public string Status;        // "NOT Wiped" or "Suspicious"
    public string Pattern;
    public int Confidence;
}

public static class DiskAnalysisEngine
{
    // Shared accumulator for byte frequency, entropy, and distribution
    public static long[] GlobalFrequency = new long[256];
    public static long GlobalTotalBytes = 0;
    public static long GlobalPrintableAscii = 0;

    // Leftover tracking: sectors with potential residual data
    // Capped to prevent unbounded memory growth on unwiped disks
    public static List<LeftoverEntry> Leftovers = new List<LeftoverEntry>();
    public static int MaxLeftovers = 500;       // Store up to 500 detailed entries
    public static long TotalLeftoverCount = 0;  // Track the real total even beyond cap

    public static void ResetGlobalCounters()
    {
        Array.Clear(GlobalFrequency, 0, 256);
        GlobalTotalBytes = 0;
        GlobalPrintableAscii = 0;
        Leftovers.Clear();
        TotalLeftoverCount = 0;
    }

    // Record a leftover finding (thread-safe not needed in single-threaded PS)
    public static void RecordLeftover(long sectorNum, int sectorSize, SectorResult result)
    {
        TotalLeftoverCount++;
        if (Leftovers.Count < MaxLeftovers)
        {
            LeftoverEntry entry = new LeftoverEntry();
            entry.SectorNumber = sectorNum;
            entry.DiskOffset = sectorNum * sectorSize;
            entry.Status = result.Status == 1 ? "NOT Wiped" : "Suspicious";
            entry.Pattern = result.Pattern;
            entry.Confidence = result.Confidence;
            Leftovers.Add(entry);
        }
    }

    // Public accessors for PowerShell
    public static LeftoverEntry[] GetLeftovers() { return Leftovers.ToArray(); }
    public static long GetTotalLeftoverCount() { return TotalLeftoverCount; }

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
    // baseSectorIndex: the disk sector number of the first sector in the buffer
    // This allows leftover tracking to record the correct absolute sector address
    public static ChunkStats AnalyzeChunk(byte[] buffer, int bytesRead, int sectorSize,
        Dictionary<string, int> patternCounts, long baseSectorIndex)
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

            // Record leftovers for NOT Wiped (1) and Suspicious (2)
            if (result.Status == 1 || result.Status == 2)
            {
                RecordLeftover(baseSectorIndex + s, sectorSize, result);
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
