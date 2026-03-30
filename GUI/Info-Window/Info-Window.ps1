function Info-Window {
    ##########################################
    # Create GUI
    ##########################################
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Application]::EnableVisualStyles()
    Add-Type -AssemblyName System.drawing

    $InfoWindow = New-Object System.Windows.Forms.Form
    $InfoWindow.Text = "Information"
    $InfoWindow.BackColor = Color 25 25 25
    $InfoWindow.FormBorderStyle = 'Fixed3D'
    $InfoWindow.MaximizeBox = $false
    $LogoIcon = $IconsPath + "ssd.png"

    $Logo = New-PictureBox
    $Logo.Image = Draw-Icon $LogoIcon
    $Logo.SizeMode = "Zoom"
    $Logo.Size = Size 50 50
    $Logo.Location = Location 10 10
    $InfoWindow.Controls.Add($Logo)

    $TitleLabel = New-Label
    $TitleLabel.Text = "Disk Wipe Verification Tool"
    $TitleLabel.ForeColor = Color 255 255 255
    $TitleLabel.Location = Location 70 22.5
    $TitleLabel.Size = Size 260 25
    $TitleLabel.Font = FontSize 12 "Bold"
    $InfoWindow.Controls.Add($TitleLabel)

    $InfoLabel = New-Label
    $InfoLabel.Text = "Info"
    $InfoLabel.ForeColor = Color 255 255 255
    $InfoLabel.Location = Location 10 70
    $InfoLabel.Size = Size 330 30
    $InfoLabel.Font = FontSize 15 "Bold"
    $InfoWindow.Controls.Add($InfoLabel)

    $VersionLabel = New-Label
    $VersionLabel.Text = "Version: $Version `nRelease Date: $ReleaseDate `nBuild Number: $BuildNumber `nPatch Number: $PatchNumber"
    $VersionLabel.ForeColor = Color 255 255 255
    $VersionLabel.Location = Location 10 110
    $VersionLabel.Size = Size 330 50
    $InfoWindow.Controls.Add($VersionLabel)

    $AuthorLabel = New-Label
    $AuthorLabel.Text = "This tool was developed for a Project at JSW. This tool will not be maintained by JSW but by the original Author.

    Company: $Company1
    Author: $Author
    Contact: $Mail1

    Company: $Company2
    Author: $Author
    Contact: $Mail2

    Company: $Company3
    Author: $Author
    Contact: $Mail3
    "
    $AuthorLabel.ForeColor = Color 255 255 255
    $AuthorLabel.Location = Location 10 170
    $AuthorLabel.Size = Size 330 180
    $InfoWindow.Controls.Add($AuthorLabel)

    $GitHubButton = New-Button
    $GitHubButton.Location = Location 10 370
    $GitHubButton.Size = Size 75 25
    $GitHubButton.Text = "GitHub"
    $GitHubButton.BackColor = Color 0 125 125
    $GitHubButton.ForeColor = Color 255 255 255
    $GitHubButton.FlatStyle = "Flat"
    $GitHubButton.Font = FontSize 10 "Bold"
    $GitHubButton.add_Click({
        explorer https://github.com/LastAdmin/CoreProtocol
    })
    $InfoWindow.Controls.Add($GitHubButton)

    $DocuButton = New-Button
    $DocuButton.Location = Location 100 370
    $DocuButton.Size = Size 150 25
    $DocuButton.Text = "Documentation"
    $DocuButton.BackColor = Color 125 125 0
    $DocuButton.ForeColor = Color 255 255 255
    $DocuButton.Font = FontSize 10 "Bold"
    $DocuButton.add_Click({
        .\Documents\Documentation.pdf
    })
    $InfoWindow.Controls.Add($DocuButton)

    $InfoWindow.ClientSize = New-Object System.Drawing.Size(350, 420)

    $InfoWindow.ShowDialog() | Out-Null
    $InfoWindow.Dispose()
}