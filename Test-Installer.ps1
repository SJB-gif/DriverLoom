param([string]$InstallerPath = (Join-Path $PSScriptRoot 'dist\DriverLoom-Setup.exe'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Engine.ps1')
if (![Environment]::Is64BitProcess) { throw 'Run installer checks from 64-bit Windows PowerShell.' }
if (!(Test-Path -LiteralPath $InstallerPath)) { throw 'Build the installer first.' }
$regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\HardwareUpdateLauncher'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'DriverLoom.lnk'
$legacyShortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'Hardware Update Launcher.lnk'
if ((Test-Path -LiteralPath $regPath) -or (Test-Path -LiteralPath $shortcutPath) -or (Test-Path -LiteralPath $legacyShortcutPath)) {
    throw 'Installer checks require no existing DriverLoom or Hardware Update Launcher installation. Use a disposable Windows user or clean test machine.'
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
$legacyFixtureCreated = $false

function Assert-Installer($expected, $actual, [string]$description) {
    if ($actual -cne $expected) { throw "$description expected '$expected', got '$actual'." }
}

function Wait-TestProcess($process) {
    $null = $process.Handle
    if (!$process.WaitForExit(30000)) { $process.Kill(); throw 'Installer process timed out.' }
    Assert-Installer 0 $process.ExitCode 'installer process exit'
    $process.Dispose()
}

function Invoke-InstalledHost([string[]]$arguments) {
    $output=Join-Path $testRoot ('host-output-'+[guid]::NewGuid().ToString('N')+'.txt')
    $errors=$output+'.err'
    $process=Start-Process -FilePath (Join-Path $installRoot 'DriverLoom.exe') -WindowStyle Hidden -ArgumentList $arguments -PassThru -RedirectStandardOutput $output -RedirectStandardError $errors
    Wait-TestProcess $process
    return [IO.File]::ReadAllText($output,[Text.Encoding]::UTF8).Trim()
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
    $legacyShell = New-Object -ComObject WScript.Shell
    $legacyShortcut = $legacyShell.CreateShortcut($legacyShortcutPath)
    $legacyShortcut.TargetPath=$powerShell
    $legacyShortcut.Save()
    $legacyFixtureCreated=$true
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($legacyShortcut)
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($legacyShell)
    $installationStarted = $true
    $setup = Start-Process -FilePath $InstallerPath -WindowStyle Hidden -ArgumentList @('/S', ('/D=' + $installRoot)) -PassThru
    Wait-TestProcess $setup
    $registration = Get-ItemProperty -LiteralPath $regPath
    Assert-Installer 'DriverLoom' $registration.DisplayName 'branded installed application name'
    Assert-Installer $false (Test-Path -LiteralPath $legacyShortcutPath) 'legacy shortcut replaced during upgrade'
    Assert-Installer $script:LauncherVersion $registration.DisplayVersion 'installed version'
    Assert-Installer $installRoot $registration.InstallLocation 'installation path with spaces'
    foreach ($name in 'App.ps1', 'Engine.ps1', 'Manufacturers.ps1', 'Coverage.ps1', 'Install.ps1', 'Launch.ps1', 'Theme.ps1', 'Theme.cs', 'assets\DriverLoom.ico', 'assets\DriverLoom.png', 'assets\DriverLoom-brand.png', 'assets\GitHub-light.png', 'assets\GitHub-dark.png', 'LICENSE') {
        Assert-Installer (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash (Get-FileHash -LiteralPath (Join-Path $installRoot $name)).Hash "$name payload matches source"
    }
    Assert-Installer (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'dist\host\DriverLoom.exe')).Hash (Get-FileHash -LiteralPath (Join-Path $installRoot 'DriverLoom.exe')).Hash 'native host matches build'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    Assert-Installer ((Join-Path $installRoot 'assets\DriverLoom.ico')+',0') $shortcut.IconLocation 'branded shortcut icon'
    Assert-Installer $true ([string]::Equals((Join-Path $installRoot 'DriverLoom.exe'), $shortcut.TargetPath, [StringComparison]::OrdinalIgnoreCase)) 'shortcut uses native DriverLoom executable'
    Assert-Installer '' $shortcut.Arguments 'shortcut has no PowerShell command line'
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut)
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    Assert-Installer 'SJB.DriverLoom' (Invoke-InstalledHost @('--read-shortcut-id',('"'+$shortcutPath+'"'))) 'installed shortcut taskbar AppID'
    $startup = (Invoke-InstalledHost @('-SmokeTest')) | ConvertFrom-Json
    Assert-Installer $true $startup.Visible 'installed form shown'
    Assert-Installer $true $startup.Is64BitProcess 'installed application bitness'
    Assert-Installer 'DriverLoom' $startup.NativeProcess 'taskbar executable identity'
    Assert-Installer 'SJB.DriverLoom' $startup.NativeAppID 'taskbar process AppID'

    # Execute the finish-page command from a real 32-bit process (the NSIS host architecture).
    $wow64Test = Join-Path $testRoot 'finish-page-command.ps1'
    $wow64Json=Join-Path $testRoot 'wow64-smoke.json'
    $command = '$p=Start-Process -FilePath '''+(Join-Path $installRoot 'DriverLoom.exe').Replace("'","''")+''' -WindowStyle Hidden -ArgumentList ''-SmokeTest'' -PassThru -RedirectStandardOutput '''+$wow64Json.Replace("'","''")+''' -Wait; if($p.ExitCode -ne 0){exit $p.ExitCode}; Get-Content -LiteralPath '''+$wow64Json.Replace("'","''")+''' -Raw -Encoding UTF8'
    [IO.File]::WriteAllText($wow64Test, $command, [Text.UTF8Encoding]::new($false))
    $wow64Output = & (Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $wow64Test
    Assert-Installer 0 $LASTEXITCODE 'finish-page WOW64 launch command exit'
    $wow64Result = ($wow64Output -join [Environment]::NewLine) | ConvertFrom-Json
    Assert-Installer $true $wow64Result.Is64BitProcess '32-bit setup reaches 64-bit native app'
    Assert-Installer 'DriverLoom' $wow64Result.NativeProcess 'finish-page launch uses native app'
    Assert-Installer $true $wow64Result.Visible 'finish-page command shows the form'

    # Launch the installed, unmodified Start menu shortcut twice; never request driver installation.
    foreach ($attempt in 1, 2) {
        $launchProcess = Start-Process -FilePath $shortcutPath -WindowStyle Hidden -PassThru
        $deadline = [datetime]::UtcNow.AddSeconds(25)
        do {
            Start-Sleep -Milliseconds 200
            $launchProcess.Refresh()
        } while (!$launchProcess.HasExited -and $launchProcess.MainWindowTitle -ne "DriverLoom $script:LauncherVersion" -and [datetime]::UtcNow -lt $deadline)
        Assert-Installer $false $launchProcess.HasExited "shortcut launch $attempt remains running"
        Assert-Installer "DriverLoom $script:LauncherVersion" $launchProcess.MainWindowTitle "shortcut launch $attempt shows app window"
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
    if ($legacyFixtureCreated -and (Test-Path -LiteralPath $legacyShortcutPath)) { Remove-Item -LiteralPath $legacyShortcutPath -Force }
    $env:LOCALAPPDATA = $originalLocalAppData
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (!$resolvedTestRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove a test directory outside TEMP.' }
    if (Test-Path -LiteralPath $resolvedTestRoot) { Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force }
}
