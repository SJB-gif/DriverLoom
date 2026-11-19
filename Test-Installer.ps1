param([string]$InstallerPath = (Join-Path $PSScriptRoot 'dist\HardwareUpdateLauncher-Setup.exe'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Engine.ps1')
if (![Environment]::Is64BitProcess) { throw 'Run installer checks from 64-bit Windows PowerShell.' }
if (!(Test-Path -LiteralPath $InstallerPath)) { throw 'Build the installer first.' }
$regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\HardwareUpdateLauncher'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'Hardware Update Launcher.lnk'
if ((Test-Path -LiteralPath $regPath) -or (Test-Path -LiteralPath $shortcutPath)) {
    throw 'Installer checks require no existing Hardware Update Launcher installation. Use a disposable Windows user or clean test machine.'
}
$mutex = $null
if ([Threading.Mutex]::TryOpenExisting('Local\HardwareUpdateLauncher', [ref]$mutex)) {
    $mutex.Dispose()
    throw 'Close Hardware Update Launcher before running installer checks.'
}
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('hardware-launcher-setup-' + [guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $testRoot 'program with spaces'
$powerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$originalLocalAppData = $env:LOCALAPPDATA
$launchProcess = $null
$installationStarted = $false

function Assert-Installer($expected, $actual, [string]$description) {
    if ($actual -cne $expected) { throw "$description expected '$expected', got '$actual'." }
}

function Wait-TestProcess($process) {
    $null = $process.Handle
    if (!$process.WaitForExit(30000)) { $process.Kill(); throw 'Installer process timed out.' }
    Assert-Installer 0 $process.ExitCode 'installer process exit'
    $process.Dispose()
}

function Invoke-TestUninstall {
    $uninstaller = Join-Path $installRoot 'Uninstall.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        $process = Start-Process -FilePath $uninstaller -WindowStyle Hidden -ArgumentList '/S' -PassThru
        Wait-TestProcess $process
    }
    $deadline = [datetime]::UtcNow.AddSeconds(20)
    while (((Test-Path -LiteralPath $regPath) -or (Test-Path -LiteralPath $shortcutPath) -or (Test-Path -LiteralPath $installRoot)) -and [datetime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    Assert-Installer $false (Test-Path -LiteralPath $regPath) 'uninstall registration removed'
    Assert-Installer $false (Test-Path -LiteralPath $shortcutPath) 'Start menu shortcut removed'
    Assert-Installer $false (Test-Path -LiteralPath $installRoot) 'program payload removed'
}

try {
    [void][IO.Directory]::CreateDirectory($testRoot)
    $env:LOCALAPPDATA = Join-Path $testRoot 'state'
    $stateRoot = Join-Path $env:LOCALAPPDATA 'HardwareUpdateLauncher'
    [void][IO.Directory]::CreateDirectory($stateRoot)
    $settingsPath = Join-Path $stateRoot 'settings.json'
    Save-Json $settingsPath @{ Repo = ''; Bios = $false; Sources = @() }
    $settingsHash = (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash
    $installationStarted = $true
    $setup = Start-Process -FilePath $InstallerPath -WindowStyle Hidden -ArgumentList @('/S', ('/D=' + $installRoot)) -PassThru
    Wait-TestProcess $setup
    $registration = Get-ItemProperty -LiteralPath $regPath
    Assert-Installer $script:LauncherVersion $registration.DisplayVersion 'installed version'
    Assert-Installer $installRoot $registration.InstallLocation 'installation path with spaces'
    foreach ($name in 'App.ps1', 'Engine.ps1', 'Manufacturers.ps1', 'Install.ps1', 'Launch.ps1', 'LICENSE') {
        Assert-Installer (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash (Get-FileHash -LiteralPath (Join-Path $installRoot $name)).Hash "$name payload matches source"
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    Assert-Installer $true ([string]::Equals($powerShell, $shortcut.TargetPath, [StringComparison]::OrdinalIgnoreCase)) 'shortcut uses 64-bit System32 PowerShell'
    foreach ($required in @('-STA', '-WindowStyle Hidden', ('-File "' + (Join-Path $installRoot 'Launch.ps1') + '"'))) {
        if (!$shortcut.Arguments.Contains($required)) { throw "Shortcut is missing $required." }
    }
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut)
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    $smoke = & $powerShell -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $installRoot 'Launch.ps1') -SmokeTest
    Assert-Installer 0 $LASTEXITCODE 'installed entry point exit'
    $startup = ($smoke -join [Environment]::NewLine) | ConvertFrom-Json
    Assert-Installer $true $startup.Visible 'installed form shown'
    Assert-Installer $true $startup.Is64BitProcess 'installed application bitness'

    # Execute the finish-page command from a real 32-bit process (the NSIS host architecture).
    $wow64Test = Join-Path $testRoot 'finish-page-command.ps1'
    $command = '& (Join-Path $env:WINDIR ''Sysnative\WindowsPowerShell\v1.0\powershell.exe'') -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ''' + (Join-Path $installRoot 'Launch.ps1').Replace("'", "''") + ''' -SmokeTest' + "`r`nexit `$LASTEXITCODE"
    [IO.File]::WriteAllText($wow64Test, $command, [Text.UTF8Encoding]::new($false))
    $wow64Output = & (Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $wow64Test
    Assert-Installer 0 $LASTEXITCODE 'finish-page WOW64 launch command exit'
    $wow64Result = ($wow64Output -join [Environment]::NewLine) | ConvertFrom-Json
    Assert-Installer $true $wow64Result.Is64BitProcess 'finish-page command reaches 64-bit PowerShell'
    Assert-Installer $true $wow64Result.Visible 'finish-page command shows the form'

    # Launch the installed, unmodified Start menu shortcut twice; never request driver installation.
    foreach ($attempt in 1, 2) {
        $launchProcess = Start-Process -FilePath $shortcutPath -WindowStyle Hidden -PassThru
        $deadline = [datetime]::UtcNow.AddSeconds(25)
        do {
            Start-Sleep -Milliseconds 200
            $launchProcess.Refresh()
        } while (!$launchProcess.HasExited -and $launchProcess.MainWindowTitle -ne "Hardware Update Launcher $script:LauncherVersion" -and [datetime]::UtcNow -lt $deadline)
        Assert-Installer $false $launchProcess.HasExited "shortcut launch $attempt remains running"
        Assert-Installer "Hardware Update Launcher $script:LauncherVersion" $launchProcess.MainWindowTitle "shortcut launch $attempt shows app window"
        Assert-Installer $true $launchProcess.Responding "shortcut launch $attempt responds"
        Stop-Process -Id $launchProcess.Id
        [void]$launchProcess.WaitForExit(10000)
        $launchProcess.Dispose()
        $launchProcess = $null
    }
    Invoke-TestUninstall
    $installationStarted = $false
    Assert-Installer $settingsHash (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash 'uninstall preserves saved user settings'
    Write-Output 'Windows installer checks passed: silent install, source payload hashes, HKCU registration, 64-bit finish command, Start menu launch and relaunch, uninstall and settings retention.'
} finally {
    if ($launchProcess -and !$launchProcess.HasExited) { Stop-Process -Id $launchProcess.Id; [void]$launchProcess.WaitForExit(10000) }
    if ($installationStarted) { Invoke-TestUninstall }
    $env:LOCALAPPDATA = $originalLocalAppData
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (!$resolvedTestRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove a test directory outside TEMP.' }
    if (Test-Path -LiteralPath $resolvedTestRoot) { Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force }
}
