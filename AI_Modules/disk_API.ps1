# --- Windows API-Strukturen und Funktionen ---
$signature = @'
[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
public static extern IntPtr CreateFile(
    string lpFileName,
    uint dwDesiredAccess,
    uint dwShareMode,
    IntPtr lpSecurityAttributes,
    uint dwCreationDisposition,
    uint dwFlagsAndAttributes,
    IntPtr hTemplateFile
);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool CloseHandle(IntPtr hObject);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool ReadFile(
    IntPtr hFile,
    byte[] lpBuffer,
    uint nNumberOfBytesToRead,
    out uint lpNumberOfBytesRead,
    IntPtr lpOverlapped
);
'@

# --- API-Funktionen laden ---
$Win32Api = Add-Type -MemberDefinition $signature -Name "Win32Api" -Namespace "Win32" -PassThru

# --- Konstanten ---
$GENERIC_READ = 0x80000000
$FILE_SHARE_READ = 0x00000001
$FILE_SHARE_WRITE = 0x00000002
$OPEN_EXISTING = 3
$FILE_ATTRIBUTE_NORMAL = 0x00000080

# --- Funktion zum Öffnen des Laufwerks ---
function Open-PhysicalDrive {
    param (
        [string]$DrivePath = "\\.\PhysicalDrive0"
    )

    $handle = $Win32Api::CreateFile(
            $DrivePath,
            $GENERIC_READ,
            $FILE_SHARE_READ -bor $FILE_SHARE_WRITE,
            [IntPtr]::Zero,
            $OPEN_EXISTING,
            $FILE_ATTRIBUTE_NORMAL,
            [IntPtr]::Zero
    )

    if ($handle -eq [IntPtr]::Zero) {
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Host "Fehler beim Öffnen des Laufwerks: $errorCode"
        return $null
    }

    return $handle
}

# --- Funktion zum Schließen des Handles ---
function Close-PhysicalDrive {
    param (
        [IntPtr]$Handle
    )

    $Win32Api::CloseHandle($Handle) | Out-Null
}

# --- Funktion zum Lesen von Daten ---
function Read-PhysicalDrive {
    param (
        [IntPtr]$Handle,
        [int]$BytesToRead = 512
    )

    $buffer = New-Object byte[] $BytesToRead
    $bytesRead = 0

    $success = $Win32Api::ReadFile($Handle, $buffer, $BytesToRead, [ref]$bytesRead, [IntPtr]::Zero)

    if (-not $success) {
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Host "Fehler beim Lesen: $errorCode"
        return $null
    }

    return $buffer
}

# --- Beispielaufruf ---
$driveHandle = Open-PhysicalDrive
if ($driveHandle -ne $null) {
    $data = Read-PhysicalDrive -Handle $driveHandle
    if ($data -ne $null) {
        Write-Host "Erfolgreich gelesen: $($data.Length) Bytes"
    }
    Close-PhysicalDrive -Handle $driveHandle
}