function Read-DiskSector {
    <#
    .SYNOPSIS
        Reads a single sector from a physical disk.
    .DESCRIPTION
        Opens the disk, reads the specified number of bytes at the given offset,
        and returns the byte array. This function opens and closes the stream
        per call. For high-performance scanning, use a shared FileStream directly
        (as done in Main.ps1) instead of calling this function per sector.
    #>
    param(
        [string]$DiskPath,
        [long]$Offset,
        [int]$Size
    )

    try {
        $stream = [System.IO.File]::Open($DiskPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $buffer = New-Object byte[] $Size
        [void]$stream.Seek($Offset, [System.IO.SeekOrigin]::Begin)
        $bytesRead = $stream.Read($buffer, 0, $Size)
        $stream.Close()
        $stream.Dispose()
        return $buffer
    }
    catch {
        if ($stream) { $stream.Dispose() }
        return $null
    }
}