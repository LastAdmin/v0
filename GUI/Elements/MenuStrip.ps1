$MenuStrip = New-MenuStrip
$MenuStrip.BackColor = Color 50 50 50
$MenuStrip.ForeColor = Color 255 255 255

#######################################
#   Help Menu
$HelpMenuIcon = $IconsPath + "help2.png"

$HelpMenu = New-MenuItem
$HelpMenu.Image = Draw-Icon $HelpMenuIcon
#######################################


#######################################
#   Module Menu
$ModuleMenu = New-MenuItem
$ModuleMenu.Text = "Modules"
$ModuleMenu.ForeColor = Color 255 255 255

$HardwareReportItem = New-MenuItem
$HardwareReportItem.Text = "Specs Report"
$HardwareReportItem.ForeColor = Color 255 255 255
$HardwareReportItem.BackColor = Color 50 50 50
#######################################


#######################################
#   Options Menu
$OptionsMenu = New-MenuItem
$OptionsMenu.Text = "Options"
$OptionsMenu.ForeColor = Color 255 255 255

$DebugModeItem = New-MenuItem
$DebugModeItem.Text = "Debug Mode"
$DebugModeItem.CheckOnClick = $true
$DebugModeItem.Checked = $false
$DebugModeItem.ToolTipText = "Enable sample size and full disk checkbox for debug runs"
$DebugModeItem.BackColor = Color 50 50 50
$DebugModeItem.ForeColor = Color 255 255 255
#######################################

$MainWindow.Controls.Add($MenuStrip)
$MainWindow.MainMenuStrip = $MenuStrip

$MenuStrip.Items.Add($HelpMenu) | Out-Null

$MenuStrip.Items.Add($ModuleMenu) | Out-Null
$ModuleMenu.DropDownItems.Add($HardwareReportItem) | Out-Null

$MenuStrip.Items.Add($OptionsMenu) | Out-Null
$OptionsMenu.DropDownItems.Add($DebugModeItem) | Out-Null