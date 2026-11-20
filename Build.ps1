param([string]$MakeNSIS = '')
$ErrorActionPreference = 'Stop'
if (![Environment]::Is64BitProcess -or $PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Build with 64-bit Windows PowerShell 5.1.'
}
if (!$MakeNSIS) {
    $command = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($command) { $MakeNSIS = $command.Source }
    else { $MakeNSIS = Join-Path ${env:ProgramFiles(x86)} 'NSIS\makensis.exe' }
}
if (!(Test-Path -LiteralPath $MakeNSIS)) { throw 'Install stock NSIS 3.11 or later, or pass -MakeNSIS with its executable path.' }
$compilerVersion = (& $MakeNSIS /VERSION) -join ''
if ($LASTEXITCODE -ne 0 -or $compilerVersion -notmatch '^v(\d+\.\d+)' -or [version]$Matches[1] -lt [version]'3.11') {
    throw "NSIS 3.11 or later is required; found $compilerVersion."
}
& (Join-Path $PSScriptRoot 'Build-BrandAssets.ps1')
& (Join-Path $PSScriptRoot 'Build-Host.ps1')
& (Join-Path $PSScriptRoot 'Build-SetupBridge.ps1')
& (Join-Path $PSScriptRoot 'Test-Engine.ps1')
& (Join-Path $PSScriptRoot 'Test-Manufacturers.ps1')
& (Join-Path $PSScriptRoot 'Test-Coverage.ps1')
& (Join-Path $PSScriptRoot 'Test-Lifecycle.ps1')
& (Join-Path $PSScriptRoot 'Test-AppUpdates.ps1')
& (Join-Path $PSScriptRoot 'Test-AppDownloads.ps1')
& (Join-Path $PSScriptRoot 'Test-AppDownloadUI.ps1')
& (Join-Path $PSScriptRoot 'Test-VendorApps.ps1')
& (Join-Path $PSScriptRoot 'Test-SetupBridge.ps1')
& (Join-Path $PSScriptRoot 'Test-Grid.ps1')
& (Join-Path $PSScriptRoot 'Test-App.ps1')
& (Join-Path $PSScriptRoot 'Test-Host.ps1')
$dist = Join-Path $PSScriptRoot 'dist'
[void][IO.Directory]::CreateDirectory($dist)
$installer = Join-Path $dist 'DriverLoom-Setup.exe'
Push-Location $PSScriptRoot
try {
    & $MakeNSIS /V3 /WX '/INPUTCHARSET' 'UTF8' ('/DOUTPUT_EXE=' + $installer) Setup.nsi
    if ($LASTEXITCODE -ne 0) { throw "NSIS build failed with exit code $LASTEXITCODE." }
} finally { Pop-Location }
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($installer + '.sha256'), "$hash  DriverLoom-Setup.exe`n", [Text.UTF8Encoding]::new($false))
Write-Output "Built $installer ($compilerVersion)"
Write-Output "SHA256: $hash"
