param([string]$InstallerPath = (Join-Path $PSScriptRoot 'dist\DriverLoom-Setup.exe'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Engine.ps1')
. (Join-Path $PSScriptRoot 'Lifecycle.ps1')
if (![Environment]::Is64BitProcess) { throw 'Run installer checks from 64-bit Windows PowerShell.' }
if (!(Test-Path -LiteralPath $InstallerPath)) { throw 'Build the installer first.' }
$regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\HardwareUpdateLauncher'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'DriverLoom.lnk'
$desktopShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DriverLoom.lnk'
$legacyShortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'Hardware Update Launcher.lnk'
if ((Test-Path -LiteralPath $regPath) -or (Test-Path -LiteralPath $shortcutPath) -or (Test-Path -LiteralPath $legacyShortcutPath) -or (Test-Path -LiteralPath $desktopShortcutPath)) {
    throw 'Installer checks require no existing DriverLoom or Hardware Update Launcher installation. Use a disposable Windows user or clean test machine.'
}
if([Microsoft.Win32.Registry]::GetValue('HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run','DriverLoom',$null)){
    throw 'Installer checks require no existing DriverLoom startup entry. Use a clean test machine.'
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

function Wait-TestProcess($process,[int]$ExpectedExit=0) {
    $null = $process.Handle
    if (!$process.WaitForExit(30000)) { $process.Kill(); throw 'Installer process timed out.' }
    Assert-Installer $ExpectedExit $process.ExitCode 'installer process exit'
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
        Set-StartupRegistration $true (Join-Path $installRoot 'DriverLoom.exe') $true
        $process = Start-Process -FilePath $uninstaller -WindowStyle Hidden -ArgumentList '/S' -PassThru
        Wait-TestProcess $process
    }
    $deadline = [datetime]::UtcNow.AddSeconds(20)
    while (((Test-Path -LiteralPath $regPath) -or (Test-Path -LiteralPath $shortcutPath) -or (Test-Path -LiteralPath $desktopShortcutPath) -or (Test-Path -LiteralPath $installRoot)) -and [datetime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    Assert-Installer $false (Test-Path -LiteralPath $regPath) 'uninstall registration removed'
    Assert-Installer $false (Test-Path -LiteralPath $shortcutPath) 'Start menu shortcut removed'
    Assert-Installer $false (Test-Path -LiteralPath $desktopShortcutPath) 'desktop shortcut removed'
    Assert-Installer $false (Test-Path -LiteralPath $installRoot) 'program payload removed'
    Assert-Installer $null ([Microsoft.Win32.Registry]::GetValue('HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run','DriverLoom',$null)) 'startup entry removed on uninstall'
}

function Assert-Shortcut([string]$path,[string]$label) {
    $shell=New-Object -ComObject WScript.Shell
    $shortcut=$shell.CreateShortcut($path)
    try{
        Assert-Installer (Join-Path $installRoot 'DriverLoom.exe') $shortcut.TargetPath "$label native target"
        Assert-Installer ((Join-Path $installRoot 'assets\DriverLoom-loops.ico')+',0') $shortcut.IconLocation "$label icon"
        Assert-Installer '' $shortcut.Arguments "$label arguments"
    }finally{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut);[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)}
    Assert-Installer 'SJB.DriverLoom' (Invoke-InstalledHost @('--read-shortcut-id',('"'+$path+'"'))) "$label taskbar identity"
}

function Test-LegacyClose {
    $legacyRoot=Join-Path $testRoot 'legacy-tray-fixture'
    $decoyRoot=Join-Path $testRoot 'unrelated-app-fixture'
    $null=[IO.Directory]::CreateDirectory($legacyRoot);$null=[IO.Directory]::CreateDirectory($decoyRoot)
    $source=@'
using System;
using System.IO;
using System.Threading;
using System.Windows.Forms;
static class LegacyTrayFixture {
    [STAThread] static void Main(string[] args) {
        using (Mutex mutex = new Mutex(false, args[1]))
        using (Form window = new Form()) {
            window.Text = "DriverLoom legacy test fixture";
            window.ShowInTaskbar = false;
            window.FormClosing += delegate(object sender, FormClosingEventArgs e) {
                if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; window.Hide(); }
            };
            window.Shown += delegate { File.WriteAllText(args[0], "ready"); window.Hide(); };
            Application.Run(window);
        }
    }
}
'@
    $compiler=[Microsoft.CSharp.CSharpCodeProvider]::new();$options=[CodeDom.Compiler.CompilerParameters]::new()
    $options.GenerateExecutable=$true;$options.CompilerOptions='/target:winexe /platform:x64';$options.OutputAssembly=Join-Path $legacyRoot 'DriverLoom.exe'
    [void]$options.ReferencedAssemblies.Add('System.Windows.Forms.dll');[void]$options.ReferencedAssemblies.Add('System.Drawing.dll');[void]$options.ReferencedAssemblies.Add('System.dll')
    try{$result=$compiler.CompileAssemblyFromSource($options,$source);if($result.Errors.HasErrors){throw 'Could not compile the isolated legacy tray fixture.'}}finally{$compiler.Dispose()}
    Copy-Item -LiteralPath $options.OutputAssembly -Destination (Join-Path $decoyRoot 'DriverLoom.exe')
    $legacy=$null;$decoy=$null
    try{
        $legacyReady=Join-Path $legacyRoot 'ready.txt';$decoyReady=Join-Path $decoyRoot 'ready.txt'
        $legacy=Start-Process -FilePath $options.OutputAssembly -WindowStyle Hidden -ArgumentList @(('"'+$legacyReady+'"'),'Local\HardwareUpdateLauncher') -PassThru
        $decoy=Start-Process -FilePath (Join-Path $decoyRoot 'DriverLoom.exe') -WindowStyle Hidden -ArgumentList @(('"'+$decoyReady+'"'),('Local\DriverLoom.Decoy-'+[guid]::NewGuid().ToString('N'))) -PassThru
        $deadline=[DateTime]::UtcNow.AddSeconds(15)
        while((!(Test-Path -LiteralPath $legacyReady) -or !(Test-Path -LiteralPath $decoyReady)) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
        if(!(Test-Path -LiteralPath $legacyReady) -or !(Test-Path -LiteralPath $decoyReady)){throw 'Legacy close fixtures did not start.'}
        $helper=Start-Process -FilePath (Join-Path $PSScriptRoot 'dist\host\DriverLoom-SetupBridge.exe') -WindowStyle Hidden -ArgumentList @('--close',('"'+$legacyRoot+'"')) -PassThru
        Wait-TestProcess $helper
        Assert-Installer $true ($legacy.WaitForExit(5000)) 'Restart Manager closes legacy tray windows without a force kill'
        Assert-Installer $false $decoy.HasExited 'setup leaves an unrelated executable with the same filename running'
    }finally{
        foreach($fixture in @($legacy,$decoy)){if($fixture){if(!$fixture.HasExited){$fixture.Kill();[void]$fixture.WaitForExit(5000)};$fixture.Dispose()}}
    }
}

function Test-ShortcutChoice([string]$name,[bool]$startMenu,[bool]$desktop,[switch]$Upgrade) {
    $script:installationStarted=$true
    $arguments=@('/S',('/STARTMENU='+[int]$startMenu),('/DESKTOP='+[int]$desktop),('/D='+$installRoot))
    $process=Start-Process -FilePath $InstallerPath -WindowStyle Hidden -ArgumentList $arguments -PassThru
    Wait-TestProcess $process
    Assert-Installer $startMenu (Test-Path -LiteralPath $shortcutPath) "$name Start menu choice"
    Assert-Installer $desktop (Test-Path -LiteralPath $desktopShortcutPath) "$name desktop choice"
    if($startMenu){Assert-Shortcut $shortcutPath "$name Start menu"}
    if($desktop){Assert-Shortcut $desktopShortcutPath "$name desktop"}
    if($Upgrade){
        $process=Start-Process -FilePath $InstallerPath -WindowStyle Hidden -ArgumentList @('/S',('/D='+$installRoot)) -PassThru
        Wait-TestProcess $process
        Assert-Installer $startMenu (Test-Path -LiteralPath $shortcutPath) "$name upgrade retains Start menu choice"
        Assert-Installer $desktop (Test-Path -LiteralPath $desktopShortcutPath) "$name upgrade retains desktop choice"
    }
    Invoke-TestUninstall
    $script:installationStarted=$false
}

try {
    [void][IO.Directory]::CreateDirectory($testRoot)
    $env:LOCALAPPDATA = Join-Path $testRoot 'state'
    $stateRoot = Join-Path $env:LOCALAPPDATA 'HardwareUpdateLauncher'
    [void][IO.Directory]::CreateDirectory($stateRoot)
    $settingsPath = Join-Path $stateRoot 'settings.json'
    Save-Json $settingsPath @{ Repo = ''; Bios = $false; Sources = @();CheckFrequency='Manual';CheckAppUpdates=$false }
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
    Assert-Installer $false (Test-Path -LiteralPath $desktopShortcutPath) 'desktop shortcut is optional by default'
    $registration = Get-ItemProperty -LiteralPath $regPath
    Assert-Installer 'DriverLoom' $registration.DisplayName 'branded installed application name'
    Assert-Installer $false (Test-Path -LiteralPath $legacyShortcutPath) 'legacy shortcut replaced during upgrade'
    Assert-Installer $script:LauncherVersion $registration.DisplayVersion 'installed version'
    Assert-Installer $installRoot $registration.InstallLocation 'installation path with spaces'
    foreach ($name in 'App.ps1', 'Engine.ps1', 'Lifecycle.ps1', 'AppUpdates.ps1', 'Manufacturers.ps1', 'Coverage.ps1', 'Install.ps1', 'Launch.ps1', 'Theme.ps1', 'Theme.cs', 'assets\DriverLoom-loops.ico', 'assets\DriverLoom.png', 'assets\DriverLoom-brand.png', 'assets\GitHub-light.png', 'assets\GitHub-dark.png', 'LICENSE') {
        Assert-Installer (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash (Get-FileHash -LiteralPath (Join-Path $installRoot $name)).Hash "$name payload matches source"
    }
    foreach($file in (Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'assets\manufacturers') -File)){
        Assert-Installer (Get-FileHash -LiteralPath $file.FullName).Hash (Get-FileHash -LiteralPath (Join-Path $installRoot ('assets\manufacturers\'+$file.Name))).Hash 'bundled manufacturer artwork matches its source'
    }
    Assert-Installer (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'dist\host\DriverLoom.exe')).Hash (Get-FileHash -LiteralPath (Join-Path $installRoot 'DriverLoom.exe')).Hash 'native host matches build'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    Assert-Installer ((Join-Path $installRoot 'assets\DriverLoom-loops.ico')+',0') $shortcut.IconLocation 'branded shortcut icon'
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
    Assert-Installer 'SJB.DriverLoom' $startup.TaskbarWindowID 'taskbar window AppID'
    Assert-Installer ((Join-Path $installRoot 'assets\DriverLoom-loops.ico')+',0') $startup.TaskbarIcon 'taskbar window uses fresh loop icon resource'
    Assert-Installer ('"'+(Join-Path $installRoot 'DriverLoom.exe')+'"') $startup.TaskbarCommand 'taskbar relaunch path with spaces'
    Assert-Installer 'DriverLoom' $startup.TaskbarName 'taskbar display name'

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
        $savedPreferences=[IO.File]::ReadAllBytes($settingsPath)
        if($attempt -eq 2){Save-Json $settingsPath @{Repo='';Bios=$false;Sources=@();CheckFrequency='Manual';CheckAppUpdates=$false;KeepRunningInTray=$true}}
        $launchProcess = Start-Process -FilePath $shortcutPath -WindowStyle Hidden -PassThru
        $deadline = [datetime]::UtcNow.AddSeconds(25)
        do {
            Start-Sleep -Milliseconds 200
            $launchProcess.Refresh()
        } while (!$launchProcess.HasExited -and $launchProcess.MainWindowTitle -ne "DriverLoom $script:LauncherVersion" -and [datetime]::UtcNow -lt $deadline)
        Assert-Installer $false $launchProcess.HasExited "shortcut launch $attempt remains running"
        Assert-Installer "DriverLoom $script:LauncherVersion" $launchProcess.MainWindowTitle "shortcut launch $attempt shows app window"
        Assert-Installer $true $launchProcess.Responding "shortcut launch $attempt responds"
        if($attempt -eq 2){
            [void]$launchProcess.CloseMainWindow()
            Start-Sleep -Milliseconds 800
            $launchProcess.Refresh()
            Assert-Installer $false $launchProcess.HasExited 'tray close keeps the app alive before upgrading'
        }
        [IO.File]::WriteAllBytes($settingsPath,$savedPreferences)
        if($attempt -eq 1){
            $busy=[Threading.Mutex]::new($false,'Local\DriverLoom.DriverInstall')
            try{
                $blocked=Start-Process -FilePath $InstallerPath -WindowStyle Hidden -ArgumentList @('/S',('/D='+$installRoot)) -PassThru
                Wait-TestProcess $blocked 3
                Assert-Installer $false $launchProcess.HasExited 'setup refuses to close an app while the driver-install guard is active'
            }finally{$busy.Dispose()}
        }
        $upgrade=Start-Process -FilePath $InstallerPath -WindowStyle Hidden -ArgumentList @('/S',('/D='+$installRoot)) -PassThru
        Wait-TestProcess $upgrade
        Assert-Installer $true ($launchProcess.WaitForExit(10000)) 'upgrade closes the running native/tray app'
        $launchProcess.Dispose()
        $launchProcess = $null
    }
    Test-LegacyClose
    Invoke-TestUninstall
    $installationStarted = $false
    Test-ShortcutChoice 'desktop-only' $false $true -Upgrade
    Test-ShortcutChoice 'both' $true $true
    Test-ShortcutChoice 'neither' $false $false
    Assert-Installer $settingsHash (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash 'uninstall preserves saved user settings'
    Write-Output 'Windows installer checks passed: all shortcut choices and upgrade persistence, native icon/AppID, payload hashes, registration, both launch paths, uninstall and settings retention.'
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
