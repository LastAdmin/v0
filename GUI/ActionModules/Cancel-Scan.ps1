function Cancel-Scan {
    $script:cancelRequested = $true
    return $script:cancelRequested
}