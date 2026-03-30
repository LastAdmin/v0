 function Convert-HtmlToPdf {
    param(
        [string]$HtmlPath,
        [string]$PdfPath
    )

    $success = $false

    # Method 1: Try Microsoft Edge (Chromium)
    $edgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    if (-not (Test-Path $edgePath)) {
        $edgePath = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    }

    if (Test-Path $edgePath) {
        Write-Console "  Using Microsoft Edge for PDF generation..." "Yellow"
        $StatusLabel.Text = "Status: Using MS Edge for PDF..."
        DoEvents
        try {
            $htmlUri = "file:///$($HtmlPath -replace '\\','/')"
            $arguments = @(
                "--headless",
                "--disable-gpu",
                "--no-pdf-header-footer",
                "--print-to-pdf=`"$PdfPath`"",
                "--print-to-pdf-no-header",
                "`"$htmlUri`""
            )
            $process = Start-Process -FilePath $edgePath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
            Start-Sleep -Seconds 2
            if (Test-Path $PdfPath) {
                $success = $true
            }
        }
        catch {
            Write-Console "  Edge PDF generation failed: $_" "Red"
            $StatusLabel.Text = "Status: Edge PDF generation failed!"
            DoEvents
        }
    }

    # Method 2: Try Google Chrome
    if (-not $success) {
        Write-Console "Try Chrome for PDF generation..." "Orange"
        $StatusLabel.Text = "Status: Try Chrome..."
        $chromePath = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
        if (-not (Test-Path $chromePath)) {
            $chromePath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
        }

        if (Test-Path $chromePath) {
            Write-Console "  Using Google Chrome for PDF generation..." "Yellow"
            $StatusLabel.Text = "Status: Using Chrome for PDF..."
            DoEvents
            try {
                $htmlUri = "file:///$($HtmlPath -replace '\\','/')"
                $arguments = @(
                    "--headless",
                    "--disable-gpu",
                    "--no-pdf-header-footer",
                    "--print-to-pdf=`"$PdfPath`"",
                    $htmlUri
                )
                $process = Start-Process -FilePath $chromePath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
                Start-Sleep -Seconds 2
                if (Test-Path $PdfPath) {
                    $success = $true
                }
            }
            catch {
                Write-Console "  Chrome PDF generation failed: $_" "Red"
                $StatusLabel.Text = "Status: Chrome PDF generation failed!"
                DoEvents
            }
        }
    }

    # Method 2: Try Brave
    if (-not $success) {
        Write-Console "Try Brave for PDF generation..." "Orange"
        $StatusLabel.Text = "Status: Try Chrome..."
        $chromePath = "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe"
        if (-not (Test-Path $chromePath)) {
            $chromePath = "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"
        }

        if (Test-Path $chromePath) {
            Write-Console "  Using Brave for PDF generation..." "Yellow"
            $StatusLabel.Text = "Status: Using Brave for PDF..."
            DoEvents
            try {
                $htmlUri = "file:///$($HtmlPath -replace '\\','/')"
                $arguments = @(
                    "--headless",
                    "--disable-gpu",
                    "--no-pdf-header-footer",
                    "--print-to-pdf=`"$PdfPath`"",
                    $htmlUri
                )
                $process = Start-Process -FilePath $chromePath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
                Start-Sleep -Seconds 2
                if (Test-Path $PdfPath) {
                    $success = $true
                }
            }
            catch {
                Write-Console "  Chrome PDF generation failed: $_" "Red"
                $StatusLabel.Text = "Status: Chrome PDF generation failed!"
                DoEvents
            }
        }
    }

    # Method 3: Try wkhtmltopdf if installed
    if (-not $success) {
        Write-Console "Try wkhtmltopdf for PDF generation..." "Orange"
        $StatusLabel.Text = "Status: Try wkhtmltopdf..."
        DoEvents
        $wkhtmlPath = "C:\Program Files\wkhtmltopdf\bin\wkhtmltopdf.exe"
        if (-not (Test-Path $wkhtmlPath)) {
            $wkhtmlPath = "C:\Program Files (x86)\wkhtmltopdf\bin\wkhtmltopdf.exe"
        }

        if (Test-Path $wkhtmlPath) {
            Write-Console "  Using wkhtmltopdf for PDF generation..." "Yellow"
            $StatusLabel.Text = "Status: Using wkhtmltopdf for PDF..."
            DoEvents

            try {
                $arguments = @(
                    "--page-size", "A4",
                    "--margin-top", "15mm",
                    "--margin-bottom", "15mm",
                    "--margin-left", "15mm",
                    "--margin-right", "15mm",
                    "--no-header-line",
                    "--no-footer-line",
                    "--disable-smart-shrinking",
                    "`"$HtmlPath`"",
                    "`"$PdfPath`""
                )
                $process = Start-Process -FilePath $wkhtmlPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
                if (Test-Path $PdfPath) {
                    $success = $true
                }
            }
            catch {
                Write-Console "  wkhtmltopdf generation failed: $_" "Red"
                $StatusLabel.Text = "Status: wkhtmltopdf PDF generation failed!"
                DoEvents
            }
        }
    }

    # Method 4: Use Word COM (fallback)
    if (-not $success) {
        Write-Console "Try MS Word for PDF..." "Orange"
        $StatusLabel.Text = "Status: Try MS Word for PDF..."
        DoEvents
        try {
            Write-Console "  Using Microsoft Word for PDF generation..." "Yellow"
            $StatusLabel.Text = "Status: Use MS Word for PDF..."
            DoEvents
            $word = New-Object -ComObject Word.Application
            $word.Visible = $false

            # Create a new document and insert HTML content
            $doc = $word.Documents.Add()
            $htmlContent = Get-Content -Path $HtmlPath -Raw
            $doc.Content.InsertAfter($htmlContent)

            # Save as PDF
            $doc.SaveAs([ref]$PdfPath, [ref]17)  # 17 = wdFormatPDF
            $doc.Close()
            $word.Quit()

            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($word) | Out-Null

            if (Test-Path $PdfPath) {
                $success = $true
            }
        }
        catch {
            Write-Console "  Word COM PDF generation failed: $_" "Red"
            $StatusLabel.Text = "Status: Word COM PDF Failed!"
            DoEvents
        }
    }

    return $success
}