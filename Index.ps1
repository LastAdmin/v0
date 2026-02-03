<#
.SYNOPSIS
    Index Loader
.DESCRIPTION
    Index for Files outside the GUI
.NOTES
    Version:        1.1
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
    16.01.2026      Yannick Morgenthaler    Edit Description and removing GUI Dot Sources
#>

#======================
# Modules
#======================
. .\Modules\Convert-HtmlToPdf.ps1
. .\Modules\Get-AvailableDisks.ps1
. .\Modules\Get-ByteDistributionScore.ps1
. .\Modules\Get-ByteHistogram.ps1
. .\Modules\Get-PrintableAsciiRatio.ps1
. .\Modules\Get-SampleLocations.ps1
. .\Modules\Get-ShannonEntropy.ps1
. .\Modules\New-HtmlReport.ps1
. .\Modules\Read-DiskSector.ps1
. .\Modules\Test-FileSignatures.ps1
. .\Modules\Test-SectorWiped.ps1

#======================
# Connectors
#======================
. .\Connectors\DoEvents.ps1
. .\Connectors\Get-Parameters.ps1
. .\Connectors\Write-Console.ps1
