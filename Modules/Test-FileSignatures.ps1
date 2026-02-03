function Test-FileSignatures {
    param([byte[]]$Data)

    if ($null -eq $Data -or $Data.Length -lt 7) { return $null }

    foreach ($sig in $FileSignatures.GetEnumerator()) {
        $match = $true
        $sigBytes = $sig.Value

        if ($Data.Length -lt $sigBytes.Length) { continue }

        for ($i = 0; $i -lt $sigBytes.Length; $i++) {
            if ($Data[$i] -ne $sigBytes[$i]) {
                $match = $false
                break
            }
        }
        if ($match) { return $sig.Key }
    }

    return $null
}