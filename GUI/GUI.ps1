<#
.SYNOPSIS
    GUI Loader
.DESCRIPTION
    Loading GUI and all Elements inside the GUI.
    Loading sidescripts for element actions.
.NOTES
    Version:        3.8.0116.01
    Creation Date:  12.01.2026
    Author:         Yannick Morgenthaler
    Company:        JSW
    Contact:        yannick.morgenthaler@jsw.swiss
    Alternative
    Contacts:       yannick@n1x.ch
                    yannick@projectresilience.ch
                    yannick.morgenthaler@4058.net

    Copyright (c) 2026 Yannick Morgenthaler

    HISTORY:
    Date            By                      Comments
    ----------      ---                     ----------------------------------------------------------
    12.01.2026      Yannick Morgenthaler    Script was created initially.
    15.01.2026      Yannick Morgenthaler    Added Panels and Elements
    16.01.2026      Yannick Morgenthaler    Added Synopsis
#>

function Load-GUI {
    ##########################################
    # Load Index
    ##########################################

    ##########################################
    # Load Action Modules
    ##########################################
    . .\GUI\ActionModules\Browse-Path.ps1
    . .\GUI\ActionModules\DataGridView-DoubleClick.ps1
    . .\GUI\ActionModules\Full-DiskScan.ps1
    . .\GUI\ActionModules\Disk-List.ps1
    . .\GUI\ActionModules\Load-Disks.ps1
    . .\GUI\ActionModules\Start-Scan.ps1
    . .\GUI\ActionModules\Cancel-Scan.ps1

    ##########################################
    # Load Element Settings
    ##########################################
    . .\GUI\Elements\BaseSettings.ps1

    ##########################################
    # Load New Element Functions
    ##########################################
    . .\GUI\NewElements\New-Button.ps1
    . .\GUI\NewElements\New-CheckBox.ps1
    . .\GUI\NewElements\New-ComboBox.ps1
    . .\GUI\NewElements\New-DataGridView.ps1
    . .\GUI\NewElements\New-GroupBox.ps1
    . .\GUI\NewElements\New-Label.ps1
    . .\GUI\NewElements\New-ListBox.ps1
    . .\GUI\NewElements\New-NumericUpDown.ps1
    . .\GUI\NewElements\New-Panel.ps1
    . .\GUI\NewElements\New-ProgressBar.ps1
    . .\GUI\NewElements\New-RichTextBox.ps1
    . .\GUI\NewElements\New-StatusBar.ps1
    . .\GUI\NewElements\New-StatusBarLabel.ps1
    . .\GUI\NewElements\New-StatusBarProgressBar.ps1
    . .\GUI\NewElements\New-TextBox.ps1

    ##########################################
    # Create GUI
    ##########################################
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Application]::EnableVisualStyles()
    Add-Type -AssemblyName System.drawing

    $MainWindow = New-Object System.Windows.Forms.Form
    $MainWindow.Text = "Disk Report"
    #$Form1.Icon = '.\itemContent.ico' -> icon has to be set
    #$MainWindow.BackgroundImage = $formbg
    #$MainWindow.BackgroundImageLayout = "Stretch"
    $MainWindow.BackColor = Color 25 25 25
    $MainWindow.FormBorderStyle = 'Fixed3D'
    $MainWindow.MaximizeBox = $false

    ##########################################
    # Menu Bar
    ##########################################
    $MenuStrip = New-Object System.Windows.Forms.MenuStrip
    $MenuStrip.BackColor = Color 50 50 50
    $MenuStrip.ForeColor = Color 255 255 255

    # Options Menu
    $OptionsMenu = New-Object System.Windows.Forms.ToolStripMenuItem
    $OptionsMenu.Text = "Options"
    $OptionsMenu.ForeColor = Color 255 255 255

    # Debug Mode Toggle
    $DebugModeItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $DebugModeItem.Text = "Debug Mode"
    $DebugModeItem.CheckOnClick = $true
    $DebugModeItem.Checked = $false
    $DebugModeItem.ToolTipText = "Enable sample size and full disk checkbox for debug runs"
    $DebugModeItem.ForeColor = Color 255 255 255

    $DebugModeItem.Add_CheckedChanged({
        if ($DebugModeItem.Checked) {
            # Enable debug controls
            $FullDiskCheckBox.Enabled = $true
            $SampleSize.Enabled = -not $FullDiskCheckBox.Checked
            if ($SampleSize.Enabled) {
                $SampleSize.BackColor = Color 100 100 100
            }
            $MainWindow.Text = "Disk Report [DEBUG MODE]"
        } else {
            # Disable debug controls, force full disk scan
            $FullDiskCheckBox.Checked = $true
            $FullDiskCheckBox.Enabled = $false
            $SampleSize.Enabled = $false
            $SampleSize.BackColor = Color 15 15 15
            $MainWindow.Text = "Disk Report"
        }
        DoEvents
    })

    $OptionsMenu.DropDownItems.Add($DebugModeItem) | Out-Null
    $MenuStrip.Items.Add($OptionsMenu) | Out-Null
    $MainWindow.MainMenuStrip = $MenuStrip
    $MainWindow.Controls.Add($MenuStrip)

    ##########################################
    # Elements
    ##########################################

    $components = New-Object System.ComponentModel.Container

    #=========================
    # Main GUI
    #=========================

    #=========================
    # Left Panel
    #=========================
    . .\GUI\Elements\LeftPanel.ps1
    . .\GUI\Elements\ParameterHeader.ps1
    . .\GUI\Elements\TechnicianName.ps1
    . .\GUI\Elements\SampleSize.ps1
    . .\GUI\Elements\FullDiskCheckBox.ps1
    . .\GUI\Elements\SectorInfoLabel.ps1
    . .\GUI\Elements\SectorSize.ps1
    . .\GUI\Elements\ReportFormat.ps1
    . .\GUI\Elements\ReportLocation.ps1
    . .\GUI\Elements\Separator.ps1
    . .\GUI\Elements\ScanHeader.ps1
    . .\GUI\Elements\StatusLabel.ps1
    . .\GUI\Elements\ScanProgress.ps1
    . .\GUI\Elements\ProgressLabel.ps1
    . .\GUI\Elements\StartScan.ps1
    . .\GUI\Elements\CancelScan.ps1
    #=========================
    # Verification Result Panel
    #=========================
    . .\GUI\Elements\VerificationPanel.ps1
    . .\GUI\Elements\ResultLabel.ps1

    #=========================
    # Right Panel
    #=========================
    . .\GUI\Elements\RightPanel.ps1
    . .\GUI\Elements\AvailableDiskHeader.ps1
    . .\GUI\Elements\RefreshDisks.ps1
    . .\GUI\Elements\DiskList.ps1
    . .\GUI\Elements\ConsoleHeader.ps1
    . .\GUI\Elements\Console.ps1

    #=========================
    # Elements Event Handlers
    #=========================
    $FullDiskCheckBox.Add_CheckedChanged({
        Full-DiskScan
    })

    $ReportPathButton.Add_Click({
        Browse-Path
    })

    $DiskList.Add_SelectedIndexChanged({
        Disk-List
    })

    $RefreshDisks.Add_Click({
        Load-Disks
    })

    $CancelScan.Add_Click({
        Cancel-Scan
    })

    $StartScan.Add_Click({
        Start-Scan
    })

    ##########################################
    # Set Window Settings
    ##########################################
    $MainWindow.ClientSize = New-Object System.Drawing.Size(1000, 700)
    $MainWindow.Controls.AddRange(@(
        $GroupBoxL,
        $GroupBoxR
    ))
    $MainWindow.Name = "Disk Report"

    #=========================
    # Load Disks on Launch
    #=========================
    Load-Disks | Out-Null

    ##########################################
    # Show GUI
    ##########################################
    $MainWindow.ShowDialog() | Out-Null
    $MainWindow.Dispose() | Out-Null
}
