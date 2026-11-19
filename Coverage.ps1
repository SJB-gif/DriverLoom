function Test-WindowsManagedHardware($row) {
    if (!$row) { return $false }
    $inf = [IO.Path]::GetFileName([string]$row.InfName)
    # Published oemNN.inf packages remain visible even when Microsoft is their signer/provider.
    if ($inf -match '(?i)^oem\d+\.inf$') { return $false }
    if ($row.Provider -eq 'Microsoft' -and $inf -match '(?i)^(?!oem\d+\.inf$).+\.inf$') { return $true }
    if ($row.Model -match '^(Microsoft (?:Bluetooth |Streaming Service Proxy$|Kernel Debug Network Adapter$|Wi-Fi Direct Virtual Adapter|Virtual Disk$|Storage Spaces Controller$|VHD Loopback Controller$)|WAN Miniport|PCI Express |PCI standard |High Definition Audio Controller$|Bluetooth Device \(Personal Area Network\)$|Standard NVM Express Controller$|Standard SATA AHCI Controller$)') { return $true }
    $inbox = @('pci.inf','machine.inf','mshdc.inf','stornvme.inf','disk.inf','volume.inf','volmgr.inf','bthpan.inf','netrasa.inf','netrass.inf','netavpna.inf','netvwifimp.inf','spaceport.inf','vhdmp.inf','vhdparser.inf','hdaudbus.inf','hidusb.inf','input.inf','usb.inf','usbport.inf','usbhub3.inf','usbxhci.inf')
    return ($row.Provider -eq 'Microsoft' -and $row.InfName -in $inbox)
}

function Get-HardwareVendor($row) {
    $identity = "$($row.Manufacturer) $($row.Provider) $($row.Model)"
    switch -Regex ($identity) {
        'NVIDIA|GeForce|Quadro' { return 'NVIDIA' }
        'Advanced Micro Devices|AuthenticAMD|\bAMD\b|Radeon' { return 'AMD' }
        'Samsung' { return 'Samsung' }
        'Corsair' { return 'Corsair' }
        'Seagate|\bST\d{3,}' { return 'Seagate' }
        'Western Digital|\bWDC\b|WD_BLACK' { return 'Western Digital' }
        'Crucial|Micron' { return 'Crucial' }
        'Kingston' { return 'Kingston' }
        'Realtek' { return 'Realtek' }
        'MediaTek|Ralink' { return 'MediaTek' }
        'Intel' { return 'Intel' }
        'ASUSTeK|\bASUS\b|Sonic Studio' { return 'ASUS' }
        'Micro-Star|\bMSI\b' { return 'MSI' }
        'GIGABYTE|AORUS' { return 'Gigabyte' }
        'ASRock' { return 'ASRock' }
        'Logitech' { return 'Logitech' }
        'Razer' { return 'Razer' }
        'Qualcomm|Atheros' { return 'Qualcomm' }
        'Broadcom' { return 'Broadcom' }
        'Marvell' { return 'Marvell' }
        'Brother' { return 'Brother' }
        'Canon' { return 'Canon' }
        'Hewlett-Packard|\bHP\b' { return 'HP' }
        '\bDell\b|Alienware' { return 'Dell' }
        'Lenovo' { return 'Lenovo' }
    }
    $ids = @($row.IDs) -join ' '
    foreach ($entry in @(
        @('VEN_10DE','NVIDIA'), @('VEN_(?:1002|1022)','AMD'), @('VEN_8086','Intel'), @('(?:VEN_10EC|VID_0BDA)','Realtek'),
        @('(?:VEN_14C3|VID_0E8D)','MediaTek'), @('VID_1B1C','Corsair'), @('VID_046D','Logitech'), @('VID_1532','Razer')
    )) { if ($ids -match $entry[0]) { return $entry[1] } }
    return [string]$row.Manufacturer
}

function Get-OfficialSupportRoute($row, $inventory) {
    $vendor = Get-HardwareVendor $row
    $system = $inventory | Where-Object Kind -eq 'System' | Select-Object -First 1
    $board = $inventory | Where-Object Kind -eq 'Motherboard' | Select-Object -First 1
    $oem = if ($system) { Get-HardwareVendor $system } else { '' }
    $routes = @{
        'NVIDIA' = @('https://www.nvidia.com/en-us/drivers/', 'NVIDIA product lookup or NVIDIA App is required for this product family.')
        'AMD' = @('https://www.amd.com/en/support/download/drivers.html', 'Use the exact AMD product page or AMD Auto-Detect for this product.')
        'Intel' = @('https://www.intel.com/content/www/us/en/support/detect.html', 'Intel Driver & Support Assistant handles products without a verified direct version feed.')
        'Samsung' = @('https://semiconductor.samsung.com/consumer-storage/magician/', 'Samsung Magician is required when firmware is not published as an unambiguous model-specific version.')
        'Corsair' = @('https://www.corsair.com/us/en/s/downloads', 'Corsair iCUE or the SSD utility must check this device; its firmware version is not exposed by a public model feed.')
        'Seagate' = @('https://www.seagate.com/support/downloads/', 'Seagate firmware eligibility can require the drive serial number; it is not submitted automatically.')
        'Western Digital' = @('https://support-en.wd.com/', 'Use the official drive utility or exact-product support workflow.')
        'Crucial' = @('https://www.crucial.com/support/storage-executive', 'Crucial Storage Executive checks exact drive firmware compatibility.')
        'Kingston' = @('https://www.kingston.com/en/support/technical/ssdmanager', 'Kingston SSD Manager checks exact drive firmware compatibility.')
        'ASUS' = @('https://www.asus.com/support/download-center/', 'This board/component needs a verified matching ASUS feed or vendor utility.')
        'MSI' = @('https://www.msi.com/support/download', 'Use the exact MSI system or motherboard support page.')
        'Gigabyte' = @('https://www.gigabyte.com/Support', 'Use the exact Gigabyte model and physical board revision.')
        'ASRock' = @('https://www.asrock.com/support/', 'Use the exact ASRock model and board revision.')
        'Realtek' = @('https://www.realtek.com/Download/List?cate_id=593', 'This codec/controller needs an exact OEM or Realtek package match.')
        'MediaTek' = @('https://www.mediatek.com/products/connectivity-and-networking', 'Obtain the matching MediaTek package from the PC or motherboard manufacturer.')
        'Logitech' = @('https://support.logi.com/', 'The official Logitech utility or product support page must check device firmware.')
        'Razer' = @('https://mysupport.razer.com/', 'Use the exact Razer product firmware or Synapse workflow.')
        'Dell' = @('https://www.dell.com/support/home/en-us?app=drivers', 'Use Dell SupportAssist or exact-model support. Service tags are not submitted automatically.')
        'HP' = @('https://support.hp.com/drivers', 'Use HP Support Assistant or exact-model support.')
        'Lenovo' = @('https://pcsupport.lenovo.com/', 'Use Lenovo Vantage/System Update or exact-model support.')
        'Brother' = @('https://support.brother.com/', 'Use the exact Brother printer/scanner and operating system.')
        'Canon' = @('https://www.usa.canon.com/support', 'Use the exact Canon printer/scanner and operating system.')
    }
    if ($oem -in 'Dell','HP','Lenovo' -and $row.Kind -in 'BIOS','Chipset/system driver','Network driver','Audio/video driver','Bluetooth driver','Camera driver') { $vendor = $oem }
    if ($vendor -eq 'MediaTek' -and $board) { $boardVendor = Get-HardwareVendor $board; if ($routes.ContainsKey($boardVendor)) { $vendor = $boardVendor } }
    if ($routes.ContainsKey($vendor)) { return [pscustomobject]@{ Vendor=$vendor; Url=$routes[$vendor][0]; Reason=$routes[$vendor][1] } }
    return [pscustomobject]@{ Vendor=$vendor; Url=''; Reason='No verified manufacturer adapter is available. An exact official source can be saved in advanced settings.' }
}

function Get-CoverageMode($row, $check) {
    if (Test-WindowsManagedHardware $row) { return 'Windows' }
    if ($row.Kind -in 'CPU','RAM','System','Motherboard') { return 'Identity' }
    if ($check.Checked) { return 'Checked' }
    if ($check.Status -like 'See *package check' -or $check.Status -like 'See AMD Chipset Software package check') { return 'Package component' }
    return 'Unsupported'
}
