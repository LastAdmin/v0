function Get-HardwareInfo {
    $FullInfo = Get-ComputerInfo
    @{
        WindowsKey = $FullInfo.WindowsProductId
        OSKey = $FullInfo.OsSerialNumber
        BiosVersion = $FullInfo.BiosBIOSVersion
        BiosFWType = $FullInfo.BiosFirmwareType
        BiosManufacturer = $FullInfo.BiosManufacturer
        BiosName = $FullInfo.BiosName
        BiosSN = $FullInfo.BiosSeralNumber
        BiosStatus = $FullInfo.BiosStatus
        AdminPasswordStatus = $FullInfo.CsAdminPasswordStatus
        PowerOnPasswordStatus = $FullInfo.CsPowerOnPasswordStatus
        BootUpState = $FullInfo.CsBootupState
        Manufacturer = $FullInfo.CsManufacturer
        Model = $FullInfo.CsModel
        CPU = $FullInfo.CsProcessors
        SystemFamily = $FullInfo.CsSystemFamily
        MemorySize = $FullInfo.OsTotalVisibleMemorySize
    }
    return $FullInfo
}