$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'src'
$ErrorActionPreference = 'Stop'
. (Join-Path $srcRoot 'Engine.ps1')
$powerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('hardware-launcher-ui-' + [guid]::NewGuid().ToString('N'))
$originalLocalAppData = $env:LOCALAPPDATA

function Assert-Startup($expected, $actual, [string]$description) {
    if ($actual -cne $expected) { throw "$description expected '$expected', got '$actual'." }
}

function Invoke-StartupCase([string]$name, $snapshot, [bool]$biosEnabled, [string]$theme = '', [Nullable[bool]]$showUnsupported = $null, [hashtable]$lifecycle = @{}, [switch]$SettingsProbe, [hashtable]$VendorApps=@{}) {
    $env:LOCALAPPDATA = Join-Path $testRoot $name
    $state = Join-Path $env:LOCALAPPDATA 'HardwareUpdateLauncher'
    [void][IO.Directory]::CreateDirectory($state)
    $preferences=@{ Repo = ''; Bios = $biosEnabled; Sources = @() }
    if($theme){$preferences.Theme=$theme}
    if($null -ne $showUnsupported){$preferences.ShowUnsupported=$showUnsupported}
    foreach($key in $lifecycle.Keys){$preferences[$key]=$lifecycle[$key]}
    Save-Json (Join-Path $state 'settings.json') $preferences
    if ($snapshot) { Save-Json (Join-Path $state 'inventory.json') $snapshot }
    $outputPath=Join-Path $testRoot ($name+'-output.json')
    $errorPath=Join-Path $testRoot ($name+'-error.txt')
    $originalProbe=$env:DRIVERLOOM_TEST_SETTINGS
    $originalApps=$env:DRIVERLOOM_TEST_VENDOR_APPS
    $env:DRIVERLOOM_TEST_VENDOR_APPS=''
    if($VendorApps.Count){$env:DRIVERLOOM_TEST_VENDOR_APPS=Join-Path $state 'vendor-apps-fixture.json';Save-Json $env:DRIVERLOOM_TEST_VENDOR_APPS $VendorApps}
    $env:DRIVERLOOM_TEST_SETTINGS=if($SettingsProbe){'1'}else{''}
    try{$process=Start-Process -FilePath $powerShell -WindowStyle Hidden -ArgumentList @('-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $srcRoot 'Launch.ps1')+'"'),'-SmokeTest') -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath -PassThru}
    finally{$env:DRIVERLOOM_TEST_SETTINGS=$originalProbe;$env:DRIVERLOOM_TEST_VENDOR_APPS=$originalApps}
    try{
        $null=$process.Handle
        if(!$process.WaitForExit(20000)){$process.Kill();throw "$name startup smoke test timed out."}
        if($process.ExitCode -ne 0){throw "$name startup failed: $([IO.File]::ReadAllText($errorPath))"}
    }finally{$process.Dispose()}
    $result = [IO.File]::ReadAllText($outputPath) | ConvertFrom-Json
    Assert-Startup $script:LauncherVersion $result.Version "$name version"
    Assert-Startup 'DriverLoom' $result.ProductName "$name product identity"
    Assert-Startup "DriverLoom $script:LauncherVersion" $result.WindowTitle "$name branded window title"
    Assert-Startup $true $result.HasIcon "$name multi-resolution icon loads"
    Assert-Startup $(if($theme){$theme}else{'Dark'}) $result.ThemePreference "$name saved appearance and legacy default"
    if($result.Background -eq $result.TextColor){throw 'Theme text has no contrast.'}
    Assert-Startup $true $result.Visible "$name real form shown"
    Assert-Startup $true $result.Is64BitProcess "$name 64-bit host"
    Assert-Startup 'STA' $result.ApartmentState "$name apartment"
    Assert-Startup $false $result.ScanStarted "$name no network scan in test mode"
    Assert-Startup $false $result.ApplyOnStartup "$name startup scan cannot auto-install"
    Assert-Startup 1 $result.MainButtonCount "$name exactly one primary action"
    Assert-Startup 'Update All' $result.MainActionText "$name update action label"
    Assert-Startup $false $result.MainActionUsesMnemonic "$name ampersand remains visible"
    Assert-Startup $false $result.MainActionEnabled "$name cached scan cannot start updates"
    Assert-Startup $false $result.MainActionVisible "$name updates hidden until fresh scan"
    Assert-Startup $true $result.RefreshEnabled "$name refresh remains available"
    Assert-Startup $true $result.Borderless "$name single title bar"
    Assert-Startup 'Settings' ($result.MenuItems -join ',') "$name gear-only top navigation"
    Assert-Startup $false $result.UpdateAllEnabled "$name saved offers cannot be installed"
    Assert-Startup $biosEnabled $result.BiosEnabled "$name BIOS opt-in"
    Assert-Startup $(if($lifecycle.ContainsKey('CheckFrequency')){$lifecycle.CheckFrequency}else{'On opening'}) $result.CheckFrequency "$name check schedule preference"
    Assert-Startup ([bool]$lifecycle.KeepRunningInTray) $result.KeepRunningInTray "$name tray opt-in preference"
    Assert-Startup ([bool]$lifecycle.StartWithWindows) $result.StartWithWindows "$name Windows startup preference"
    Assert-Startup $(if($lifecycle.ContainsKey('CheckAppUpdates')){$lifecycle.CheckAppUpdates}else{$true}) $result.CheckAppUpdates "$name app update preference"
    Assert-Startup $false $result.AppUpdateCheckStarted "$name smoke mode never contacts GitHub"
    Assert-Startup 'Hardware type' $result.GroupBy "$name always groups by hardware type, including legacy preferences"
    Assert-Startup 0 $result.GroupingSelectorCount "$name has no application grouping selector"
    Assert-Startup 13 $result.ManufacturerLogoCount "$name bundled manufacturer artwork loads"
    Assert-Startup $true $result.SetupExitDeferredWhileBusy "$name setup cannot interrupt driver installation"
    Assert-Startup $true $result.SetupExitDeferredDuringPackage "$name setup cannot interrupt manufacturer installation"
    Assert-Startup $true $result.SetupExitDeferredDuringPackageDownload "$name setup cannot interrupt manufacturer download"
    Assert-Startup $true $result.SetupExitClosesWindow "$name setup request exits even when tray mode is enabled"
    Assert-Startup ([bool]$lifecycle.KeepRunningInTray) $result.TrayVisible "$name notification area icon follows preference"
    Assert-Startup ([bool]$lifecycle.KeepRunningInTray) $result.CloseHidesToTray "$name close hides only when enabled"
    Assert-Startup $true $result.RestoreRequestShowsWindow "$name reopening restores existing window"
    Assert-Startup $true $result.ShutdownAllowsExit "$name tray mode does not block Windows shutdown"
    return $result
}

try {
    $empty = Invoke-StartupCase 'empty' $null $false
    Assert-Startup 0 $empty.HardwareRows 'empty inventory'
    Assert-Startup 0 $empty.DriverRows 'empty offers'
    Assert-Startup $false $empty.FreshActionVisible 'no updates means no Update All action'
    Assert-Startup $true $empty.AutomaticCheckOnOpening 'default checks on opening'
    $manual=Invoke-StartupCase 'manual-tray' $null $false '' $null @{CheckFrequency='Manual';KeepRunningInTray=$true;StartWithWindows=$true;CheckAppUpdates=$false}
    Assert-Startup $false $manual.AutomaticCheckOnOpening 'manual mode suppresses automatic startup check'
    $daily=Invoke-StartupCase 'daily' $null $false '' $null @{CheckFrequency='Daily'}
    Assert-Startup $true $daily.AutomaticCheckOnOpening 'daily first launch is due'
    $snapshot = [pscustomobject]@{
        CapturedAt = '2026-11-19T00:00:00Z'; OS = 'Windows test fixture'
        Inventory = @(
            (New-HardwareRow 'GPU driver' 'Example' 'Test GPU' 'PCI TEST' '' '1.0' @('PCI TEST'))
            (New-HardwareRow 'BIOS' 'Example' 'Test board' '' '1' '1.0' @())
            (New-HardwareRow 'Storage driver' '(Standard controller)' 'Standard NVM Express Controller' '' '' '10.0.26100.1' @() 'Microsoft' 'stornvme.inf')
            (New-HardwareRow 'Storage firmware' 'Corsair' 'Unsupported test SSD' '' '' '1.0' @())
        )
        Checks = @(); Warnings = @(); Repository = $null; WindowsUpdateOK = $true; WindowsUpdateOfferCount = 3
        Offers = @([pscustomobject]@{ Title = 'Test offer'; Class = 'Display'; HardwareId = 'PCI TEST'; Date = '2026-11-19' })
        ExcludedOffers = @(
            [pscustomobject]@{ Title = 'Test monitor'; Class = 'OtherHardware'; HardwareId = 'TEST MONITOR'; Date = '2026-11-19'; Reasons = @('Unsupported automatic-install class: OtherHardware.', 'Package may request user interaction; review in Windows Update.') }
            [pscustomobject]@{ Title = 'Test firmware'; Class = 'Firmware'; HardwareId = 'TEST FIRMWARE'; Date = '2026-11-19'; Reasons = @('Firmware/BIOS is excluded from Update All; use the manufacturer workflow.') }
        )
    }
    $snapshot.Checks=@([pscustomobject]@{Key=$snapshot.Inventory[0].Key;Current='1.0';Available='1.2';Status='Newer at source';Checked=$true;Detail='Fixture manufacturer result.';Url='https://example.com/driver'})
    $cached = Invoke-StartupCase 'cached' $snapshot $false
    Assert-Startup 2 $cached.HardwareRows 'checked manufacturer and eligible Windows Update rows only'
    Assert-Startup 1 $cached.DriverRows 'only eligible Windows Update packages are shown in main results'
    Assert-Startup 2 $cached.ExcludedDriverRows 'excluded offers remain visible'
    Assert-Startup $true $cached.FreshUpdateAllEnabled 'fresh eligible offer can enable Update All'
    Assert-Startup $true $cached.FreshActionVisible 'fresh available updates reveal Update All'
    Assert-Startup 1 $cached.UnsupportedCount 'unsupported devices are separated into settings'
    Assert-Startup 1 $cached.UpdateMethodGroupCount 'manual firmware item has an update-method group'
    Assert-Startup 1 $cached.WindowsManagedHidden 'Windows-managed controller removed from main results'
    Assert-Startup $false ($cached.MainDevices -contains 'Standard NVM Express Controller') 'inbox controller absent from results'
    Assert-Startup $false ($cached.MainDevices -contains 'Unsupported test SSD') 'unsupported firmware absent from results'
    Assert-Startup $false $cached.ShowUnsupported 'legacy settings keep unsupported devices hidden'
    $shown = Invoke-StartupCase 'unsupported-visible' $snapshot $false '' $true -SettingsProbe
    Assert-Startup $true $shown.ShowUnsupported 'saved visibility preference loads'
    Assert-Startup 3 $shown.HardwareRows 'unsupported devices can be included without inbox components'
    Assert-Startup $true ($shown.MainDevices -contains 'Unsupported test SSD') 'unsupported device appears when requested'
    Assert-Startup $true ($shown.MainStatuses -contains 'CORSAIR SSD Toolbox') 'status names the actual update software'
    Assert-Startup $false ($shown.MainStatuses -contains 'VENDOR APP') 'generic vendor app badge is absent'
    Assert-Startup $true ($null -ne $shown.SettingsProbe) 'settings interaction probe ran'
    foreach($property in $shown.SettingsProbe.PSObject.Properties){Assert-Startup $true $property.Value ("settings interaction: "+$property.Name)}
    Assert-Startup $false ($shown.MainDevices -contains 'Standard NVM Express Controller') 'inbox components remain hidden with unsupported devices shown'
    $snapshot.Offers = @()
    $snapshot.WindowsUpdateOfferCount = 2
    $excludedOnly = Invoke-StartupCase 'excluded-only' $snapshot $false
    Assert-Startup 0 $excludedOnly.DriverRows 'excluded packages stay out of main results'
    Assert-Startup $false $excludedOnly.UpdateAllEnabled 'excluded offers never enable Update All'
    Assert-Startup $false $excludedOnly.FreshUpdateAllEnabled 'fresh excluded-only scan cannot enable Update All'
    Assert-Startup $true $excludedOnly.FreshActionVisible 'manufacturer-only updates still have a review action'
    $unsupportedSnapshot=[pscustomobject]@{CapturedAt=$snapshot.CapturedAt;Inventory=@($snapshot.Inventory[3]);Checks=@();Offers=@();ExcludedOffers=@();Warnings=@()}
    $unsupportedOnly=Invoke-StartupCase 'unsupported-only' $unsupportedSnapshot $false '' $true
    Assert-Startup 1 $unsupportedOnly.HardwareRows 'unsupported-only inventory remains inspectable'
    Assert-Startup $false $unsupportedOnly.FreshActionVisible 'showing unsupported devices never creates an update offer'
    $optIn = Invoke-StartupCase 'bios-opt-in' $snapshot $true
    Assert-Startup 1 $optIn.HardwareRows 'unsupported BIOS does not add an unchecked row to main results'
    $light = Invoke-StartupCase 'light-theme' $snapshot $false 'Light'
    Assert-Startup 'Light' $light.ResolvedTheme 'explicit light appearance'
    $system = Invoke-StartupCase 'system-theme' $snapshot $false 'System'
    Assert-Startup $true ($system.ResolvedTheme -in 'Dark','Light') 'system appearance resolves to a supported palette'
    if($light.Background -eq $cached.Background){throw 'Dark and light theme backgrounds did not change.'}

    $equal=New-HardwareRow 'GPU driver' 'Example' 'Zeta current GPU' '' '' '2.0' @()
    $higher=New-HardwareRow 'Audio/video driver' 'Example' 'Alpha installed newer' '' '' '3.0' @()
    $failed=New-HardwareRow 'Network driver' 'Example' 'Failed network check' '' '' '1.0' @()
    $ambiguous=New-HardwareRow 'Storage firmware' 'Example' 'Ambiguous firmware' '' '' 'A12' @()
    $listSnapshot=[pscustomobject]@{CapturedAt=$snapshot.CapturedAt;Inventory=@($equal,$higher,$failed,$ambiguous);Offers=@();ExcludedOffers=@();Warnings=@();Checks=@(
        [pscustomobject]@{Key=$equal.Key;Current=$equal.Current;Available='2.0';Status='Current at source';Checked=$true;Detail='Fixture current version.';Url='https://example.com/current'},
        [pscustomobject]@{Key=$higher.Key;Current=$higher.Current;Available='2.0';Status='Installed version is higher';Checked=$true;Detail='The installed version exceeds the checked source.';Url='https://example.com/older'},
        [pscustomobject]@{Key=$failed.Key;Current=$failed.Current;Available='';Status='Unsupported automatic check; source unavailable';Checked=$false;Detail='Fixture source is temporarily unavailable.';Url='https://example.com/network'},
        [pscustomobject]@{Key=$ambiguous.Key;Current=$ambiguous.Current;Available='A13';Status='Different version; verify vendor ordering';Checked=$true;Detail='Version ordering is not established.';Url='https://example.com/firmware'}
    )}
    $list=Invoke-StartupCase 'list-statuses' $listSnapshot $false
    Assert-Startup 'Alpha installed newer|Zeta current GPU|Failed network check|Ambiguous firmware' ($list.MainDevices -join '|') 'main list opens by hardware category, then Device A-Z'
    foreach($name in $equal.Model,$higher.Model){
        $item=$list.MainItems|Where-Object Device -eq $name
        Assert-Startup 'UP TO DATE' $item.Status "$name remains visible and green"
        Assert-Startup 'Vendor details' $item.Action "$name retains secondary vendor details"
        Assert-Startup $true ([bool]$item.Url) "$name retains its source link"
    }
    Assert-Startup 'Installed version is higher' ($list.MainItems|Where-Object Device -eq $higher.Model).Comparison 'installed-newer explanation remains in device details'
    foreach($name in $failed.Model,$ambiguous.Model){Assert-Startup 'CHECK UNAVAILABLE' ($list.MainItems|Where-Object Device -eq $name).Status "$name cannot imply a successful comparison"}
    Assert-Startup $false $list.FreshActionVisible 'current, failed and ambiguous checks never create an update action'
    $headset=New-HardwareRow 'Audio/video driver' 'Corsair' 'CORSAIR Headset' '' '' '2.4.2.0' @()
    $input=New-HardwareRow 'Input device driver' 'Corsair' 'Corsair virtual input' '' '' '3.0.88.0' @()
    $groupSnapshot=[pscustomobject]@{CapturedAt=$snapshot.CapturedAt;Inventory=@($headset,$input,$snapshot.Inventory[3]);Offers=@();Checks=@();ExcludedOffers=@();Warnings=@()}
    $apps=@{icue=[pscustomobject]@{Key='icue';Name='iCUE';Vendor='Corsair';Path='C:\Fixtures\iCUE.exe'}}
    $grouped=Invoke-StartupCase 'launcher-groups' $groupSnapshot $false '' $true -VendorApps $apps
    Assert-Startup 3 $grouped.HardwareRows 'shared launchers retain separate devices under hardware categories'
    Assert-Startup 0 @($grouped.LauncherGroups).Count 'application groups are removed'
    Assert-Startup $true (@($grouped.MainItems.Status) -contains 'CORSAIR iCUE') 'unverified firmware names its app'
    Assert-Startup 2 @($grouped.MainItems|Where-Object Action -eq 'Open iCUE').Count 'each iCUE device retains its action'
    $categories=Invoke-StartupCase 'hardware-categories' $groupSnapshot $false '' $true @{GroupBy='Hardware type'} -VendorApps $apps
    Assert-Startup 0 @($categories.LauncherGroups).Count 'hardware view does not merge devices sharing a launcher'
    Assert-Startup 'Audio & media|Peripherals|Storage' ($categories.HardwareCategories -join '|') 'hardware categories have clear names and default alphabetical order'
    Assert-Startup 3 $categories.HardwareRows 'all three devices are present beneath category headers'
    Assert-Startup 2 @($categories.MainItems|Where-Object Action -eq 'Open iCUE').Count 'each device retains its own correct launcher action'
    Assert-Startup 3 @($categories.MainItems|Where-Object Action).Count 'category headers expose no action'
    $checkedCategories=Invoke-StartupCase 'hardware-categories-checked' $listSnapshot $false '' $false @{GroupBy='Hardware type'}
    Assert-Startup 4 @($checkedCategories.MainItems|Where-Object Action).Count 'category view retains current, unavailable and ambiguous devices'
    $managedDevice=New-HardwareRow 'Chipset package' 'AMD' 'AMD Chipset Software' '' '' '7.01.08.129' @()
    $managedPackage=New-ManagedPackage 'AMDChipset' $managedDevice ([pscustomobject]@{Family='11'}) '8.09.28.1124' 'https://www.amd.com/en/support/downloads/drivers.html/chipsets/am5/x670e.html' 'https://drivers.amd.com/drivers/amd_chipset_software_8.09.28.1124.exe'
    $managedSnapshot=[pscustomobject]@{CapturedAt=$snapshot.CapturedAt;Inventory=@($managedDevice);Offers=@();ExcludedOffers=@();Warnings=@();Checks=@([pscustomobject]@{Key=$managedDevice.Key;Current=$managedDevice.Current;Available=$managedPackage.Version;Checked=$true;Status='Newer at source';Url=$managedPackage.SourceUrl;Package=$managedPackage})}
    $managedApps=@{amdManager=[pscustomobject]@{Key='amdManager';Name='AMD Install Manager';Vendor='AMD';Path='C:\Fixtures\AMDInstallManager.exe'}}
    $managed=Invoke-StartupCase 'managed-package' $managedSnapshot $false '' $false @{GroupBy='Application'} -VendorApps $managedApps
    Assert-Startup 'Download update' $managed.MainItems[0].Action 'verified newer package takes priority over its installed vendor app'
    Assert-Startup 'System & chipset' $managed.HardwareCategories[0] 'legacy application grouping preference is ignored'
    $radeon=New-HardwareRow 'GPU driver' 'AMD' 'AMD Radeon(TM) Graphics' '' '' '32.0.21030.2001' @()
    $software=New-HardwareRow 'GPU software' 'AMD' 'AMD Software: Adrenalin Edition' '' '' '24.6.1' @()
    $source='https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-7000-series/amd-ryzen-9-7900x3d.html'
    $package=New-ManagedPackage 'AMDRadeon' $software (Get-WindowsDriverTarget '10.0.26300.0') '26.11.2' $source 'https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-26.11.2-win11-a.exe' $radeon
    $radeonSnapshot=[pscustomobject]@{CapturedAt=$snapshot.CapturedAt;Inventory=@($software,$radeon);Offers=@();ExcludedOffers=@();Warnings=@();Checks=@(
        [pscustomobject]@{Key=$software.Key;Current=$software.Current;Available=$package.Version;Checked=$true;Status='Newer at source';Url=$source;Package=$package},
        [pscustomobject]@{Key=$radeon.Key;Current=$radeon.Current;Available=$package.Version;Checked=$true;Status='Vendor package found; compare the AMD Software row';Url=$source}
    )}
    $radeonView=Invoke-StartupCase 'managed-radeon' $radeonSnapshot $false '' $false -VendorApps $managedApps
    Assert-Startup 1 @($radeonView.MainItems|Where-Object Action -eq 'Download update').Count 'Radeon offers one download on the comparable software row'
    Assert-Startup 'Download update' ($radeonView.MainItems|Where-Object Device -eq $software.Model).Action 'Radeon package download takes priority over installed AMD updater'
    Assert-Startup 'CHECK UNAVAILABLE' ($radeonView.MainItems|Where-Object Device -eq $radeon.Model).Status 'display-driver version is not compared with an Adrenalin package version'
    $board=New-HardwareRow 'Motherboard' 'ASUSTeK' 'ROG STRIX X670E-A GAMING WIFI' '' '' '' @()
    $asusDevices=@(
        (New-HardwareRow 'Network driver' 'Intel' 'Intel I225-V' '' '' '1.0.0.0' @('PCI\VEN_8086&DEV_15F3&REV_03')),
        (New-HardwareRow 'Network driver' 'MediaTek' 'MediaTek Wi-Fi MT7922 RZ616' '' '' '1.0.0.0' @('PCI\VEN_14C3&DEV_0616&SUBSYS_061614C3')),
        (New-HardwareRow 'Bluetooth driver' 'MediaTek' 'MediaTek Bluetooth Adapter' '' '' '1.0.0.0' @('USB\VID_0489&PID_E0E2&MI_00')),
        (New-HardwareRow 'Audio/video driver' 'Microsoft' 'Realtek USB Audio' '' '' '1.0.0.0' @('USB\VID_0B05&PID_1A52&MI_00'))
    )
    $asusChecks=@(for($i=0;$i -lt 4;$i++){
        $category=@('LAN','Wireless','Bluetooth','Audio')[$i]
        $package=New-AsusPackage $asusDevices[$i] $board (Get-WindowsDriverTarget '10.0.26300.0') $category ([pscustomobject]@{Version='2.3.4.5';DownloadUrl=[pscustomobject]@{Global='/pub/ASUS/mb/fixture_RZ616.zip'};sha256=''}) ('https://www.asus.com/supportonly/'+[Uri]::EscapeDataString($board.Model)+'/helpdesk_download/')
        [pscustomobject]@{Key=$asusDevices[$i].Key;Current=$asusDevices[$i].Current;Available=$package.Version;Checked=$true;Status='Newer at source';Url=$package.SourceUrl;Package=$package}
    })
    $asusSnapshot=[pscustomobject]@{CapturedAt=$snapshot.CapturedAt;Inventory=@($board)+$asusDevices;Checks=$asusChecks;Offers=@();ExcludedOffers=@();Warnings=@()}
    $asusView=Invoke-StartupCase 'managed-asus' $asusSnapshot $false
    Assert-Startup 4 @($asusView.MainItems|Where-Object Action -eq 'Download update').Count 'all four ASUS driver categories expose managed download actions'

    $env:LOCALAPPDATA = Join-Path $testRoot 'failure'
    $broken = Join-Path $testRoot 'broken-payload'
    [void][IO.Directory]::CreateDirectory($broken)
    foreach ($name in 'Launch.ps1', 'App.ps1', 'Install.ps1') {
        Copy-Item -LiteralPath (Join-Path $srcRoot $name) -Destination (Join-Path $broken $name)
    }
    $failureProcess = Start-Process -FilePath $powerShell -WindowStyle Hidden -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $broken 'Launch.ps1') + '"'), '-SmokeTest') -RedirectStandardError (Join-Path $broken 'error.txt') -PassThru
    $null = $failureProcess.Handle
    if (!$failureProcess.WaitForExit(15000)) { $failureProcess.Kill(); throw 'Startup error reporting timed out.' }
    Assert-Startup 1 $failureProcess.ExitCode 'missing engine fails visibly'
    $failureProcess.Dispose()
    $logPath = Join-Path $env:LOCALAPPDATA 'HardwareUpdateLauncher\startup-error.log'
    $log = Get-Content -LiteralPath $logPath -Raw
    if ($log -notmatch 'Engine\.ps1' -or $log -notmatch '64-bit process: True' -or $log -notmatch 'Apartment: STA') {
        throw 'Startup log is missing the failure or host details.'
    }
    Write-Output 'Windows startup checks passed: DriverLoom branding/icon, legacy settings, dark/light/system themes, cached install guards, BIOS opt-in, 64-bit STA host and startup errors.'
} finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (!$resolvedTestRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove a test directory outside TEMP.' }
    if (Test-Path -LiteralPath $resolvedTestRoot) { Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force }
}
