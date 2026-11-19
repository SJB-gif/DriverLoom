$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Engine.ps1')
function Assert-Coverage($expected,$actual,[string]$description){if($actual -cne $expected){throw "$description expected '$expected', got '$actual'."}}
$nvme=New-HardwareRow 'Storage driver' '(Standard NVM Express Controller)' 'Standard NVM Express Controller' '' '' '10.0.26100.1' @() 'Microsoft' 'stornvme.inf'
$pan=New-HardwareRow 'Network driver' 'Microsoft' 'Bluetooth Device (Personal Area Network)' '' '' '10.0.26100.1' @()
$audio=New-HardwareRow 'Audio/video driver' 'Microsoft' 'Realtek USB Audio' '' '' '6.3.9600.2393' @() 'Realtek' 'oem42.inf'
$surface=New-HardwareRow 'Camera driver' 'Microsoft' 'Microsoft Surface Camera' '' '' '10.0.1.0' @() 'Microsoft' 'oem52.inf'
Assert-Coverage $true (Test-WindowsManagedHardware $nvme) 'Windows NVMe component'
Assert-Coverage $true (Test-WindowsManagedHardware $pan) 'legacy inbox PAN row'
Assert-Coverage $false (Test-WindowsManagedHardware $audio) 'third-party Microsoft-signed audio is retained'
Assert-Coverage $false (Test-WindowsManagedHardware $surface) 'Microsoft hardware with an OEM INF is retained'
$oemStorage=New-HardwareRow 'Storage driver' 'Microsoft' 'Standard NVM Express Controller' '' '' '1.0' @() 'Microsoft' 'oem53.inf'
Assert-Coverage $false (Test-WindowsManagedHardware $oemStorage) 'published OEM INF takes precedence over generic legacy names'
$bt=New-HardwareRow 'Bluetooth driver' 'Microsoft' 'Bluetooth LE Generic Attribute Service' '' '' '10.0.1.0' @() 'Microsoft' 'bthleenum.inf'
Assert-Coverage $true (Test-WindowsManagedHardware $bt) 'generic Bluetooth service is Windows managed'
Assert-Coverage 'Realtek' (Get-HardwareVendor $audio) 'driver provider resolves manufacturer'
$intel=New-HardwareRow 'Network driver' 'Unknown' 'Wireless network adapter' '' '' '1.0' @('PCI\VEN_8086&DEV_2725')
Assert-Coverage 'Intel' (Get-HardwareVendor $intel) 'PCI vendor recognition independent of PC model'
$corsair=New-HardwareRow 'Storage firmware' '(Standard disk drives)' 'Corsair MP600 PRO NH' '' '' 'EIFM80.0' @()
Assert-Coverage 'Corsair' (Get-HardwareVendor $corsair) 'disk model resolves generic disk manufacturer'
$dell=New-HardwareRow 'System' 'Dell Inc.' 'Latitude example' '' '' '' @()
$codec=New-HardwareRow 'Audio/video driver' 'Realtek' 'Realtek Audio' '' '' '1.0' @()
Assert-Coverage 'Dell' (Get-OfficialSupportRoute $codec @($dell)).Vendor 'OEM route for laptop codec'
Assert-Coverage 'Unsupported' (Get-CoverageMode $corsair $null) 'unhandled firmware is unsupported, never current'
Assert-Coverage 'Windows' (Get-CoverageMode $nvme $null) 'Windows components are not unsupported items'
$headset=New-HardwareRow 'Audio/video driver' 'CORSAIR' 'CORSAIR VOID ELITE SURROUND USB Adapter' '' '' '2.4.2.0' @('USB\VID_1B1C&PID_0A53')
$virtual=New-HardwareRow 'Input device driver' 'Corsair' 'Corsair composite virtual input device' 'SERIAL-DO-NOT-COPY' '' '3.0.88.0' @()
$headsetMethod=Get-UpdateMethod $headset @()
$virtualMethod=Get-UpdateMethod $virtual @()
$ssdMethod=Get-UpdateMethod $corsair @()
Assert-Coverage 'CORSAIR iCUE' $headsetMethod.Name 'headset follows its software, not SSD firmware tooling'
Assert-Coverage $headsetMethod.Name $virtualMethod.Name 'Corsair virtual component shares the iCUE group'
Assert-Coverage 'CORSAIR SSD Toolbox' $ssdMethod.Name 'SSD firmware has its own update utility'
$xbox=New-HardwareRow 'Storage driver' 'Xbox' 'Xvdd SCSI Miniport' '' '' '10.0.1.0' @() 'Xbox' 'oem10.inf'
Assert-Coverage 'Microsoft Gaming Services' (Get-UpdateMethod $xbox @()).Name 'Xbox virtual storage is app managed'
$vpn=New-HardwareRow 'Network driver' 'TAP-Windows Provider V9' 'WLVPN Windows Tap Adapter' '' '' '9.26.0.0' @()
Assert-Coverage '' (Get-UpdateMethod $vpn @()).Url 'VPN adapter does not invent an owning-app download link'
$items=@(foreach($entry in @(@($headset,$headsetMethod),@($virtual,$virtualMethod),@($corsair,$ssdMethod))){
    [pscustomobject]@{Manager=$entry[1].Name;Device=$entry[0].Model;Manufacturer=Get-HardwareVendor $entry[0];Reason=$entry[1].Reason;Url=$entry[1].Url;Hardware=$entry[0]}
})
$groups=@(Get-UpdateMethodGroups $items)
Assert-Coverage 2 $groups.Count 'utility grouping retains separate iCUE and SSD Toolbox rows'
Assert-Coverage 2 @($groups|Where-Object Manager -eq 'CORSAIR iCUE'|ForEach-Object Items).Count 'both iCUE devices remain inspectable'
$copy=Get-UpdateMethodsCopyText $items
Assert-Coverage $true ($copy -like '*CORSAIR iCUE*' -and $copy -like '*Corsair composite virtual input device*' -and $copy -like '*https://www.corsair.com/us/en/s/icue*') 'copy includes manager, individual device and official webpage'
Assert-Coverage $false ($copy -like '*SERIAL-DO-NOT-COPY*') 'copy never serializes private hardware identity'
$intelCpu=New-HardwareRow 'CPU' 'GenuineIntel' 'Intel Core i7 example' '' '' '' @()
$rx=New-HardwareRow 'GPU driver' 'Advanced Micro Devices' 'AMD Radeon RX 7900 XTX' '' '' '32.0.1.0' @()
Assert-Coverage 'https://www.amd.com/en/support/downloads/drivers.html/graphics/radeon-rx/radeon-rx-7000-series/amd-radeon-rx-7900-xtx.html' (Get-AmdGraphicsSource @($intelCpu,$rx) $rx) 'Radeon discrete GPU on an Intel PC'
$rx6=New-HardwareRow 'GPU driver' 'AMD' 'AMD Radeon RX 6800 XT' '' '' '32.0.1.0' @()
Assert-Coverage 'https://www.amd.com/en/support/downloads/drivers.html/graphics/radeon-rx/radeon-rx-6000-series/amd-radeon-rx-6800-xt.html' (Get-AmdGraphicsSource @($intelCpu,$rx6) $rx6) 'RX 6000 family has its own exact source'
$board=New-HardwareRow 'Motherboard' 'Micro-Star International' 'MAG B550 TOMAHAWK' '' '' '' @()
$cpu=New-HardwareRow 'CPU' 'AuthenticAMD' 'AMD Ryzen 7 5800X 8-Core Processor' '' '' '' @()
Assert-Coverage 'https://www.amd.com/en/support/downloads/drivers.html/chipsets/am4/b550.html' (Get-AmdChipsetSource @($board,$cpu)) 'MSI AM4 platform independent of ASUS'
$wifi=New-HardwareRow 'Network driver' 'Intel' 'Intel(R) Wi-Fi 6E AX210 160MHz' '' '' '23.100.0.4' @()
$script:unsupportedProduct=$false
function Read-WebSource([string]$url,[int]$limit=2097152){
    $product=if($script:unsupportedProduct){'AX211'}else{'AX210'}
    return '<h2>Detailed Description</h2><p>Windows 10 64-bit / Windows 11</p><p>The package installs the Wi-Fi driver version 24.80.0.2 for supported adapters.</p><h2>This download is valid for the product(s) listed below.</h2><p>Intel Wi-Fi 6E '+$product+'</p><h2>Documentation</h2><p>Old AX210 package reference</p>'
}
$check=Get-IntelWirelessCheck $wifi (Get-WindowsDriverTarget '10.0.22631.0') @{}
Assert-Coverage '24.80.0.2' $check.Available 'Intel compares driver number rather than package number'
Assert-Coverage 'Newer at source' $check.Status 'Intel wireless check on a non-ASUS machine'
$script:unsupportedProduct=$true
$rejected=$false
try{$null=Get-IntelWirelessCheck $wifi (Get-WindowsDriverTarget '10.0.22631.0') @{}}catch{$rejected=$true}
Assert-Coverage $true $rejected 'mentions outside supported-product list do not establish compatibility'
$ssd=New-HardwareRow 'Storage firmware' '(Standard disk drives)' 'Samsung SSD 970 EVO 500GB' '' '' '2B2QEXE7' @()
$source=Get-SamsungSource $ssd
Assert-Coverage $true ([bool]$source) 'older retail Samsung models have a firmware source'
$pattern=New-VersionPattern $source.Pattern
Assert-Coverage '2B2QEXE7' ($pattern.Match('970 EVO Firmware ISO 2B2QEXE7').Groups['version'].Value) 'Samsung exact model firmware version'
Assert-Coverage $false ($pattern.Match('970 EVO Plus Firmware ISO 4B2QEXM7').Success) 'Samsung EVO must not match EVO Plus'
Write-Output 'General coverage checks passed: inbox classification, vendor IDs, OEM routing, Intel wireless, discrete Radeon on Intel and MSI AMD platforms.'
