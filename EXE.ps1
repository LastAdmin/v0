
<#
.SYNOPSIS
    EXE for the Disk Verification Tool. Initialize and start modules here.
.DESCRIPTION
    This file will be converted into the loading .exe to provide a easy to maintain, debug and update
    script base.
.NOTES
    Version:        1.0
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

#. .\Load-Components.ps1
#
#Load-Components

#Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File C:\Users\Yannick Morgenthaler\Documents\GitHub\CoreProtocol\Load-Components.ps1" -Verb RunAs Administrator