$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Engine.ps1')

function Assert-Manufacturer($expected, $actual, [string]$description) {
    if ($actual -cne $expected) { throw "$description expected '$expected', got '$actual'." }
}

$script:requests = [System.Collections.Generic.List[string]]::new()
$script:wrongGpu = $false
$script:wrongBoard = $false
$script:failedSource = $false
$script:wrongOS = $false
function Read-WebSource([string]$url, [int]$limit = 2097152) {
    $script:requests.Add($url)
    if ($script:failedSource) { throw 'Fixture: manufacturer unavailable.' }
    if ($url -like '*TypeID=2&ParentID=1') { return '<LookupValueSearch><LookupValues><LookupValue><Name>GeForce RTX 40 Series</Name><Value>127</Value></LookupValue></LookupValues></LookupValueSearch>' }
    if ($url -like '*TypeID=3&ParentID=127') { return '<LookupValueSearch><LookupValues><LookupValue><Name>NVIDIA GeForce RTX 4080 SUPER</Name><Value>1041</Value></LookupValue></LookupValues></LookupValueSearch>' }
    if ($url -like '*DriverManualLookup*') {
        if ($url -notlike '*psid=127&pfid=1041&osID=135&*') { throw 'Fixture received incorrect NVIDIA product or OS IDs.' }
        $product = if ($script:wrongGpu) { 'NVIDIA GeForce RTX 4090' } else { 'NVIDIA GeForce RTX 4080 SUPER' }
        $os = if ($script:wrongOS) { 'Windows 10 64-bit' } else { 'Windows 11' }
        return (@{ Success = '10'; IDS = @(@{ downloadInfo = @{
            Success = '1'; Name = 'GeForce%20Game%20Ready%20Driver'; Version = '622.10'; IsWHQL = '1'; IsBeta = '0'; IsActive = '1'
            OSName = $os; DetailsURL = 'https://www.nvidia.com/en-us/drivers/details/123456/'
            series = @(@{ products = @(@{ productName = $product }) })
        } }) } | ConvertTo-Json -Depth 10 -Compress)
    }
    if ($url -like '*GetPDDrivers*') {
        if ($url -notlike '*osid=52') { throw 'Fixture received incorrect ASUS OS ID.' }
        $model = if ($script:wrongBoard) { 'ROG STRIX X670E-E GAMING WIFI' } else { 'ROG STRIX X670E-A GAMING WIFI' }
        return (@{ Status = 'SUCCESS'; Result = @{ Model = $model; Obj = @(
            @{ Name = 'LAN'; Files = @(
                @{ Title = 'Intel I226 LAN driver'; Version = '2.1.5.10'; ReleaseDate = '2026/03/31' }
                @{ Title = 'Intel I225 / I226 LAN Driver'; Version = '2.1.3.3'; ReleaseDate = '2023/03/21' }
            ) }
            @{ Name = 'Wireless'; Files = @(
                @{ Title = 'Intel WiFi Driver'; Version = '23.80.0.7'; ReleaseDate = '2024/11/06' }
                @{ Title = 'AMD WiFi Driver'; Version = '3.3.0.918'; ReleaseDate = '2024/01/23' }
            ) }
            @{ Name = 'Audio'; Files = @(@{ Title = 'Realtek USB Audio Driver'; Version = '6.3.9600.2342'; ReleaseDate = '2023/01/30' }) }
            @{ Name = 'Bluetooth'; Files = @(
                @{ Title = 'AMD Bluetooth Driver'; Version = '1.1037.0.399'; ReleaseDate = '2024/01/23'; DownloadUrl = @{Global='/pub/ASUS/mb/02BT/DRV_Bluetooth_AMD_RZ616_TP_W11_64.zip'} }
                @{ Title = 'AMD Bluetooth Driver'; Version = '9.0.0.0'; ReleaseDate = '2026/01/01'; DownloadUrl = @{Global='/pub/ASUS/mb/02BT/DRV_Bluetooth_AMD_RZ608_TP_W11_64.zip'} }
                @{ Title = 'Intel Bluetooth Driver'; Version = '99.0.0.0'; ReleaseDate = '2026/01/01'; DownloadUrl = @{Global='/pub/ASUS/mb/02BT/Intel.zip'} }
            ) }
        ) } } | ConvertTo-Json -Depth 10 -Compress)
    }
    if ($url -like '*amd.com/en/support/downloads/drivers.html/*') {
        $heading = if ($url -like '*/chipsets/am5/x670e.html') { 'AMD Chipset Drivers' } else { 'AMD Software: Adrenalin Edition' }
        $revision = if ($url -like '*/chipsets/*') { '8.09.28.1124' } else { 'Adrenalin 26.11.2 WHQL (Recommended)' }
        return '<button class="accordion-button">Windows 11 - 64-Bit Edition</button><article class="driver-download-details"><h4>' + $heading + '</h4><strong>Revision Number</strong><p>' + $revision + '</p></article><div class="accordion-item"><button>Windows 10 - 64-Bit Edition</button><article class="driver-download-details"><h4>' + $heading + '</h4><strong>Revision Number</strong><p>99.99.9</p></article>'
    }
    throw "Unexpected fixture URL: $url"
}

$target = Get-WindowsDriverTarget '10.0.26300.0'
Assert-Manufacturer 52 $target.Asus 'Windows 11 ASUS target'
Assert-Manufacturer 57 (Get-WindowsDriverTarget '10.0.19045.0').Nvidia 'Windows 10 NVIDIA target'
Assert-Manufacturer '621.24' (Convert-NvidiaInstalledVersion '32.0.16.2124') 'NVIDIA Windows version conversion'
Assert-Manufacturer '572.83' (Convert-NvidiaInstalledVersion '32.0.15.7283') 'previous NVIDIA branch conversion'
Assert-Manufacturer '' (Convert-NvidiaInstalledVersion 'unavailable') 'unrecognised installed version'
$gpu = New-HardwareRow 'GPU driver' 'NVIDIA' 'NVIDIA GeForce RTX 4080 SUPER' 'TEST GPU' '' '32.0.16.2124' @()
$board = New-HardwareRow 'Motherboard' 'ASUSTeK' 'ROG STRIX X670E-A GAMING WIFI' '' '1.0' '' @()
$cpu = New-HardwareRow 'CPU' 'AuthenticAMD' 'AMD Ryzen 9 7900X3D 12-Core Processor' '' '' '' @()
$amdGpu = New-HardwareRow 'GPU driver' 'Advanced Micro Devices' 'AMD Radeon(TM) Graphics' '' '' '32.0.21030.2001' @()
$chipset = New-HardwareRow 'Chipset package' 'AMD' 'AMD Chipset Software' $board.Model '' '7.01.08.129' @()
$amdSoftware = New-HardwareRow 'GPU software' 'AMD' 'AMD Software: Adrenalin Edition' '' '' '24.6.1' @()
$lan = New-HardwareRow 'Network driver' 'Intel' 'Intel(R) Ethernet Controller (3) I225-V' '' '' '2.1.5.7' @()
$wifi = New-HardwareRow 'Network driver' 'MediaTek' 'MediaTek Wi-Fi 6E MT7922 (RZ616)' '' '' '3.3.0.918' @()
$audio = New-HardwareRow 'Audio/video driver' 'Microsoft' 'Realtek USB Audio' '' '' '6.3.9600.2393' @('USB\VID_0BDA&PID_4082')
$inventory = @($board, $cpu, $gpu, $amdGpu, $chipset, $amdSoftware, $lan, $wifi, $audio)
$cache = @{}
$check = Get-NvidiaCheck $gpu $target $cache
Assert-Manufacturer 'Newer at source' $check.Status 'exact NVIDIA version comparison'
Assert-Manufacturer '622.10' $check.Available 'published NVIDIA version'
Assert-Manufacturer 3 $script:requests.Count 'one product lookup chain'
$null = Get-NvidiaCheck $gpu $target $cache
Assert-Manufacturer 3 $script:requests.Count 'manufacturer responses cached per scan'
$script:wrongGpu = $true
$check = Get-AutomaticManufacturerCheck $gpu $inventory $target @{}
Assert-Manufacturer $false $check.Checked 'other GPU cannot be reported as checked'
$script:wrongGpu = $false
$script:wrongOS = $true
$check = Get-AutomaticManufacturerCheck $gpu $inventory $target @{}
Assert-Manufacturer $false $check.Checked 'wrong OS cannot be reported as checked'
$script:wrongOS = $false
$check = Get-AmdCheck $chipset $inventory $target $cache
Assert-Manufacturer '8.09.28.1124' $check.Available 'AMD chipset package version'
Assert-Manufacturer 'Newer at source' $check.Status 'like-for-like chipset package comparison'
$check = Get-AmdCheck $amdSoftware $inventory $target $cache
Assert-Manufacturer '26.11.2' $check.Available 'OS-specific AMD Adrenalin package'
Assert-Manufacturer 'Newer at source' $check.Status 'AMD software package comparison'
$check = Get-AmdCheck $amdGpu $inventory $target $cache
Assert-Manufacturer 'Vendor package found; compare the AMD Software row' $check.Status 'AMD Windows driver is never compared to a package version'
$check = Get-AsusCheck $lan $inventory $target $cache
Assert-Manufacturer '2.1.3.3' $check.Available 'I225 cannot select the newer I226-only package'
Assert-Manufacturer 'Installed version is higher' $check.Status 'older board package is not an upgrade'
$check = Get-AsusCheck $wifi $inventory $target $cache
Assert-Manufacturer '3.3.0.918' $check.Available 'MediaTek/AMD Wi-Fi does not select Intel Wi-Fi'
Assert-Manufacturer 'Current at source' $check.Status 'matching Wi-Fi version'
$check = Get-AsusCheck $audio $inventory $target $cache
Assert-Manufacturer '6.3.9600.2342' $check.Available 'board USB audio package'
$asusAudio = New-HardwareRow 'Audio/video driver' 'Microsoft' 'Realtek USB Audio' '' '' '6.3.9600.2393' @('USB\VID_0B05&PID_1A52')
$check = Get-AsusCheck $asusAudio $inventory $target $cache
Assert-Manufacturer '6.3.9600.2342' $check.Available 'ASUS onboard USB audio identity'
$externalAudio = New-HardwareRow 'Audio/video driver' 'Realtek' 'Realtek USB Audio' '' '' '1.0' @('USB\VID_0BDA&PID_1234')
Assert-Manufacturer $null (Get-AsusCheck $externalAudio $inventory $target $cache) 'unrelated USB audio hardware is not matched to the board'
$bluetooth=New-HardwareRow 'Bluetooth driver' 'MediaTek' 'MediaTek Bluetooth Adapter' '' '' '1.930.0.257' @('USB\VID_0489&PID_E0E2&REV_0100')
$check=Get-AsusCheck $bluetooth $inventory $target $cache
Assert-Manufacturer '1.1037.0.399' $check.Available 'verified OEM Bluetooth ID selects the RZ616 package, not a higher version for another chipset'
Assert-Manufacturer 'Newer at source' $check.Status 'matching Bluetooth update is detected'
$unrelatedBluetooth=New-HardwareRow 'Bluetooth driver' 'MediaTek' 'MediaTek Bluetooth Adapter' '' '' '1.0' @('USB\VID_0489&PID_E0E20')
Assert-Manufacturer $null (Get-AsusCheck $unrelatedBluetooth $inventory $target $cache) 'partial product ID cannot establish a Bluetooth match'
$script:wrongBoard = $true
$check = Get-AutomaticManufacturerCheck $bluetooth $inventory $target @{}
Assert-Manufacturer $false $check.Checked 'Bluetooth also rejects a sibling-board response'
$check = Get-AutomaticManufacturerCheck $lan $inventory $target @{}
Assert-Manufacturer $false $check.Checked 'sibling ASUS board rejected'
$script:wrongBoard = $false
$script:failedSource = $true
$check = Get-AutomaticManufacturerCheck $gpu $inventory $target @{}
Assert-Manufacturer $false $check.Checked 'offline manufacturer is not reported current'
Assert-Manufacturer 'Unsupported automatic check; source unavailable' $check.Status 'source failure is explicit'
Write-Output 'Manufacturer checks passed: exact GPU/board/OS matching, NVIDIA version conversion, AMD package numbering, component matching, caching and failure handling.'
