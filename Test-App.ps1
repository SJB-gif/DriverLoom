$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Engine.ps1')
$powerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('hardware-launcher-ui-' + [guid]::NewGuid().ToString('N'))
$originalLocalAppData = $env:LOCALAPPDATA

function Assert-Startup($expected, $actual, [string]$description) {
    if ($actual -cne $expected) { throw "$description expected '$expected', got '$actual'." }
}

function Invoke-StartupCase([string]$name, $snapshot, [bool]$biosEnabled, [string]$theme = '') {
    $env:LOCALAPPDATA = Join-Path $testRoot $name
    $state = Join-Path $env:LOCALAPPDATA 'HardwareUpdateLauncher'
    [void][IO.Directory]::CreateDirectory($state)
    $preferences=@{ Repo = ''; Bios = $biosEnabled; Sources = @() }
    if($theme){$preferences.Theme=$theme}
    Save-Json (Join-Path $state 'settings.json') $preferences
    if ($snapshot) { Save-Json (Join-Path $state 'inventory.json') $snapshot }
    $output = & $powerShell -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Launch.ps1') -SmokeTest
    if ($LASTEXITCODE -ne 0) { throw "$name startup failed with exit code $LASTEXITCODE." }
    $result = ($output -join [Environment]::NewLine) | ConvertFrom-Json
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
    Assert-Startup 'Check & Update All' $result.MainActionText "$name combined action label"
    Assert-Startup $false $result.MainActionUsesMnemonic "$name ampersand remains visible"
    Assert-Startup $true $result.MainActionEnabled "$name idle action can check even with no installable offers"
    Assert-Startup 'Settings,About,Help' ($result.MenuItems -join ',') "$name top menu"
    Assert-Startup $false $result.UpdateAllEnabled "$name saved offers cannot be installed"
    Assert-Startup $biosEnabled $result.BiosEnabled "$name BIOS opt-in"
    return $result
}

try {
    $empty = Invoke-StartupCase 'empty' $null $false
    Assert-Startup 0 $empty.HardwareRows 'empty inventory'
    Assert-Startup 0 $empty.DriverRows 'empty offers'
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
    Assert-Startup 1 $cached.UnsupportedCount 'unsupported devices are separated into settings'
    Assert-Startup 1 $cached.WindowsManagedHidden 'Windows-managed controller removed from main results'
    Assert-Startup $false ($cached.MainDevices -contains 'Standard NVM Express Controller') 'inbox controller absent from results'
    Assert-Startup $false ($cached.MainDevices -contains 'Unsupported test SSD') 'unsupported firmware absent from results'
    Assert-Startup $true ($cached.Summary -like '*1 Windows Update package(s) ready*') 'summary distinguishes installable packages'
    $snapshot.Offers = @()
    $snapshot.WindowsUpdateOfferCount = 2
    $excludedOnly = Invoke-StartupCase 'excluded-only' $snapshot $false
    Assert-Startup 0 $excludedOnly.DriverRows 'excluded packages stay out of main results'
    Assert-Startup $false $excludedOnly.UpdateAllEnabled 'excluded offers never enable Update All'
    Assert-Startup $false $excludedOnly.FreshUpdateAllEnabled 'fresh excluded-only scan cannot enable Update All'
    $optIn = Invoke-StartupCase 'bios-opt-in' $snapshot $true
    Assert-Startup 1 $optIn.HardwareRows 'unsupported BIOS does not add an unchecked row to main results'
    $light = Invoke-StartupCase 'light-theme' $snapshot $false 'Light'
    Assert-Startup 'Light' $light.ResolvedTheme 'explicit light appearance'
    $system = Invoke-StartupCase 'system-theme' $snapshot $false 'System'
    Assert-Startup $true ($system.ResolvedTheme -in 'Dark','Light') 'system appearance resolves to a supported palette'
    if($light.Background -eq $cached.Background){throw 'Dark and light theme backgrounds did not change.'}

    $env:LOCALAPPDATA = Join-Path $testRoot 'failure'
    $broken = Join-Path $testRoot 'broken-payload'
    [void][IO.Directory]::CreateDirectory($broken)
    foreach ($name in 'Launch.ps1', 'App.ps1', 'Install.ps1') {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $broken $name)
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
