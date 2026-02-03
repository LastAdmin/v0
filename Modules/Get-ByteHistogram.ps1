function Get-ByteHistogram {
    param([byte[]]$Data)

    $histogram = @{}
    foreach ($byte in $Data) {
        if ($histogram.ContainsKey($byte)) {
            $histogram[$byte]++
        } else {
            $histogram[$byte] = 1
        }
    }
    return $histogram
}