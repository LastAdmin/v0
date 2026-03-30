function Location($h, $w) {
    $Location = New-Object System.Drawing.Point($h, $w)
    return $Location
}

function Size($h, $w) {
    $Size = New-Object System.Drawing.Point($h, $w)
    return $Size
}

function FontSize($FS, $FW, $F) {
    if ($F -eq $null) {
        $F = "Segoe UI"
    }
    else {
        #do nothing
    }

    if ($FW -eq "Bold") {
        $FontSize = New-Object System.Drawing.Font($F, $FS, [System.Drawing.FontStyle]::Bold)
    }
    else {
        $FontSize = New-Object System.Drawing.Font("Segoe UI", $FS)
    }
    return $FontSize
}

function Color($R, $G, $B) {
    $Color = [System.Drawing.Color]::FromArgb($R, $G, $B)
    return $Color
}

function Draw-Icon($IconPath) {
    $GetIcon = Get-Item $IconPath
    $Icon = [System.Drawing.Image]::FromFile($GetIcon)
    return $Icon
}