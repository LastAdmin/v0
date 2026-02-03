function Read-DiskSector {
    param(
        [string]$DiskPath,
        [long]$Offset,
        [int]$Size
    )

    try {
        $stream = [System.IO.File]::Open($DiskPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $buffer = New-Object byte[] $Size
        $stream.Seek($Offset, [System.IO.SeekOrigin]::Begin) | Out-Null
        $bytesRead = $stream.Read($buffer, 0, $Size)
        $stream.Close()
        return $buffer
    }
    catch {
        return $null
    }
}