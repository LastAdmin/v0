<#
.SYNOPSIS
    Component Loader - Loading all needed script components
.DESCRIPTION
    The Component Loader is the bridge between the EXE and the other script components.
    In the EXE is just the call for the Load-Components function which will trigger the
    components to load. This is done to make it easier to update the scipt base and
    if needed to update the component loader.
.NOTES
    Version:        3.26.0116.1143
    Creation Date:  16.01.2026
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
    16.01.2026      Yannick Morgenthaler    Script was created initially.
#>

function Load-Components {
    #======================
    # Load Components
    #======================
    . .\Main.ps1
    . .\Index.ps1
    . .\Info.ps1
    . .\GUI\GUI.ps1

    #======================
    # Make Current Directory available
    #======================
    $WorkingDirectory = Get-WorkingDirectory

    #======================
    # Call GUI
    #======================
    Load-GUI
}