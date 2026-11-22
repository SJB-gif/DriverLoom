$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'src'
$ErrorActionPreference = 'Stop'
$scriptRoots = @($srcRoot, (Join-Path $repoRoot 'scripts'), $PSScriptRoot)
foreach ($file in (Get-ChildItem -LiteralPath $scriptRoots -Filter '*.ps1' -File)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "$($file.Name) : $($errors -join [Environment]::NewLine)" }
}
. (Join-Path $srcRoot 'Engine.ps1')

function Assert-Equal($expected, $actual, [string]$description) {
    if ($actual -cne $expected) { throw "$description expected '$expected', got '$actual'." }
}

Assert-Equal 'Newer at source' (Compare-ReportedVersion '31.0.9.2' '31.0.10.0') 'numeric comparison'
Assert-Equal 'Current at source' (Compare-ReportedVersion '2.19.0' '2.19') 'trailing zero'
Assert-Equal 'Different version; verify vendor ordering' (Compare-ReportedVersion 'A12' 'A13') 'vendor-defined versions'
Assert-Equal 'Installed version unavailable' (Compare-ReportedVersion '' '1.2') 'unknown installed version'

function Read-WebSource([string]$url, [int]$limit = 2097152) {
    switch ($url) {
        'https://example.com/driver' { return '{"latest":"31.0.10.2"}' }
        'https://example.com/ambiguous' { return '{"latest":"1.2","archive":{"latest":"1.1"}}' }
        'https://semiconductor.samsung.com/consumer-storage/support/tools/' {
            return '<div>NVMe SSD-990 PRO Series Firmware</div><span>ISO 8B2QJXD7 | 50MB Download</span><div>NVMe SSD-990 EVO Plus Firmware</div><span>ISO 2B2QKXG7 | 32MB Download</span><p>previous 7B2QJXD7</p>'
        }
        'https://api.github.com/repos/example/source/releases/latest' { return '{"tag_name":"v0.1.0"}' }
        'https://api.github.com/repos/SJB-gif/DriverLoom/releases/latest' { return '{"tag_name":"v0.1.8"}' }
        'https://raw.githubusercontent.com/SJB-gif/DriverLoom/main/catalog.json' { return '{"schema":1,"sources":[]}' }
        'https://raw.githubusercontent.com/example/source/main/catalog.json' {
            return '{"schema":1,"sources":[{"Key":"spoofed","Kind":"GPU driver","Manufacturer":"NVIDIA","Model":"Example","Part":"PCI TEST","Revision":"","SystemManufacturer":"Dell","SystemModel":"Example system","SystemPart":"A","Url":"https://unknown.com/driver","Pattern":"(?<version>\\d+)"}]}'
        }
        default { throw "Unexpected test URL $url" }
    }
}

$gpu = New-HardwareRow 'GPU driver' 'NVIDIA' 'Example' 'PCI TEST' '' '31.0.9.2' @('PCI TEST')
$ssd = New-HardwareRow 'Storage firmware' 'Samsung' 'NVMe Samsung SSD 990 PRO 2TB' '' '' '7B2QJXD7' @()
$oemSSD = New-HardwareRow 'Storage firmware' 'Samsung' 'SAMSUNG MZVL22T0HBLB-00B00' '' '' '7B2QJXD7' @()
$bios = New-HardwareRow 'BIOS' 'Dell' 'Example board' '' '1' '1.1' @()
$system = New-HardwareRow 'System' 'Dell' 'Example system' 'A' '' '' @()
$warnings = [System.Collections.Generic.List[string]]::new()
$settings = [pscustomobject]@{ Repo = ''; Bios = $false; Sources = @() }
$settings.Sources += [pscustomobject]@{ Key = $gpu.Key; Url = 'https://example.com/driver'; Pattern = '"latest":"(?<version>[0-9.]+)"' }
$settings.Sources += [pscustomobject]@{ Key = $bios.Key; Url = 'https://example.com/driver'; Pattern = '' }
$result = Get-VendorResults @($gpu, $ssd, $oemSSD, $bios, $system) $settings $warnings
Assert-Equal 4 $result.Checks.Count 'disabled BIOS'
Assert-Equal '31.0.10.2' $result.Checks[0].Available 'saved source'
Assert-Equal '8B2QJXD7' $result.Checks[1].Available 'Samsung version extraction'
Assert-Equal 'Newer at source' $result.Checks[1].Status 'Samsung comparison'
Assert-Equal 'Unsupported automatic check' $result.Checks[2].Status 'OEM SSD must use its exact source'
$settings.Bios = $true
$settings.Sources[0].Url = 'https://example.com/ambiguous'
$result = Get-VendorResults @($gpu, $bios) $settings $warnings
Assert-Equal $true ($result.Checks[0].Status -like 'Source check failed:*') 'different matches rejected'
Assert-Equal 'Saved support link; manual version check' $result.Checks[1].Status 'link without version pattern'
$settings.Repo = 'example/source'
$settings.Sources = @()
$result = Get-VendorResults @($gpu, $system) $settings $warnings
Assert-Equal 'v0.1.0' $result.Repository.Release 'latest release tag'
Assert-Equal $true ($result.Checks[0].Status -like '*differs from the device vendor domain*') 'remote URL domain bound'

$offer = [pscustomobject]@{
    DriverClass = 'Display'; Title = 'Example display driver'; DriverHardwareID = 'PCI\VEN_1234'
    DriverVerDate = '2026-11-19'; Identity = @{ UpdateID = '706591a4-434c-4088-b01b-aa463a34f071'; RevisionNumber = 3 }
    InstallationBehavior = @{ CanRequestUserInput = $false }
}
$eligible = Get-DriverOffer $offer
Assert-Equal 3 $eligible.Revision 'preserve the scanned revision'
$offer.Title = 'Example display firmware'
Assert-Equal $null (Get-DriverOffer $offer) 'firmware is excluded'
$offer.DriverClass = 'Firmware'
$offer.Title = 'Example device update'
Assert-Equal $null (Get-DriverOffer $offer) 'firmware class is excluded'
$offer.DriverClass = 'Display'
$offer.InstallationBehavior.CanRequestUserInput = $true
Assert-Equal $null (Get-DriverOffer $offer) 'interactive offer is excluded'
Assert-Equal 0 @(Get-UnambiguousOffers @($eligible, $eligible) $warnings).Count 'duplicate offers are held for review'
$offer.DriverClass = 'OtherHardware'
$report = Get-WindowsOfferReport @($offer) $warnings
Assert-Equal 1 $report.Total 'all offered packages are counted'
Assert-Equal 0 $report.Offers.Count 'excluded packages do not enter the install queue'
Assert-Equal 1 $report.ExcludedOffers.Count 'excluded package retained for display'
Assert-Equal 2 $report.ExcludedOffers[0].Reasons.Count 'class and interaction reasons are both retained'
$duplicate = [pscustomobject]@{
    DriverClass = 'Display'; Title = 'Duplicate test'; DriverHardwareID = 'PCI TEST'
    DriverVerDate = '2026-11-19'; Identity = @{ UpdateID = '706591a4-434c-4088-b01b-aa463a34f071'; RevisionNumber = 3 }
    InstallationBehavior = @{ CanRequestUserInput = $false }
}
$report = Get-WindowsOfferReport @($duplicate, $duplicate) $warnings
Assert-Equal 0 $report.Offers.Count 'duplicate report cannot enable installation'
Assert-Equal 2 $report.ExcludedOffers.Count 'both duplicate packages have an explanation'
Assert-Equal $true ($report.ExcludedOffers[0].Reasons[0] -like 'Multiple offers*') 'duplicate reason'
$report = Get-WindowsOfferReport @() $warnings
Assert-Equal 0 $report.Total 'empty Windows Update result'
$temp = Join-Path ([IO.Path]::GetTempPath()) ("hardware-launcher-" + [guid]::NewGuid() + '.json')
try {
    Save-Json $temp @{ Revision = 1 }
    Save-Json $temp @{ Revision = 2 }
    Assert-Equal 2 ((Get-Content -LiteralPath $temp -Raw | ConvertFrom-Json).Revision) 'replacing a saved JSON file'
} finally {
    if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
}
$actionSnapshot=[pscustomobject]@{WindowsUpdateOK=$true;Offers=@();Checks=@()}
Assert-Equal $false (Get-UpdateAction $actionSnapshot $true $false).Visible 'no updates hides Update All'
$actionSnapshot.Checks=@([pscustomobject]@{Checked=$true;Status='Newer at source'})
Assert-Equal $true (Get-UpdateAction $actionSnapshot $true $false).Visible 'manufacturer-only updates have review action'
Assert-Equal $false (Test-CanInstallSnapshot $actionSnapshot $true $false) 'manufacturer review never enables Windows installation'
Assert-Equal $false (Get-UpdateAction $actionSnapshot $false $false).Visible 'saved updates cannot start a new install'
Assert-Equal $false (Get-UpdateAction $actionSnapshot $true $true).Enabled 'busy action cannot run'
$actionSnapshot.Checks=@();$actionSnapshot.Offers=@([pscustomobject]@{Title='Fixture'})
Assert-Equal $true (Get-UpdateAction $actionSnapshot $true $false).Enabled 'eligible fresh Windows offer reveals update action'
$actionSnapshot.WindowsUpdateOK=$false
Assert-Equal $false (Get-UpdateAction $actionSnapshot $true $false).Visible 'failed Windows scan cannot offer an installation'
Assert-Equal 'CHECKED 2 MIN AGO' (Get-CheckCaption '2026-11-19T13:00:00+11:00' ([datetimeoffset]'2026-11-19T02:02:12Z')) 'footer age handles local timezone'
Assert-Equal 'NOT CHECKED YET' (Get-CheckCaption 'invalid') 'invalid date never claims a recent check'
$renameWarnings=[System.Collections.Generic.List[string]]::new()
$renamedCatalog=Get-RepositoryCatalog 'SJB-gif/HardwareUpdateLauncher' $renameWarnings
Assert-Equal 'https://github.com/SJB-gif/DriverLoom/releases' $renamedCatalog.ReleaseUrl 'renamed repository canonical link'
Assert-Equal 'v0.1.8' $renamedCatalog.Release 'old catalog setting follows renamed repository'
Assert-Equal 0 $renameWarnings.Count 'renamed catalog uses final URLs without redirects'
Write-Output 'PowerShell parsed and engine checks passed.'
