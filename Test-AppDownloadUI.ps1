$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
[Windows.Forms.Application]::SetUnhandledExceptionMode([Windows.Forms.UnhandledExceptionMode]::ThrowException)
. (Join-Path $PSScriptRoot 'Theme.ps1')
. (Join-Path $PSScriptRoot 'AppDownloads.ps1')
. (Join-Path $PSScriptRoot 'Engine.ps1')
# Import the real UI functions without starting the app or touching its preferences.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'App.ps1'),[ref]$tokens,[ref]$errors)
foreach($name in 'New-Dialog','New-Button','New-AppDownloadDialog','Cancel-AppDownload','Receive-AppDownload','Invoke-DownloadDialog','Install-AppUpdate','Install-ManufacturerUpdate','Show-PackageInstallation'){
    $node=$ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -eq $name|Select-Object -First 1
    if(!$node){throw "Missing UI function: $name"};. ([scriptblock]::Create($node.Extent.Text))
}
function Assert-DownloadUI($expected,$actual,[string]$message){if($expected -cne $actual){throw "$message expected '$expected', got '$actual'."}}
function Update-Controls {if($script:appDownload -or $script:packageInstaller){$script:sawBusy=$true}}
function Show-Message([string]$message){$script:failure=$message}
function Start-AppInstaller([string]$path,$info,[string]$version){$script:starts++;Assert-DownloadUI 'DriverLoom-Setup.exe' ([IO.Path]::GetFileName($path)) 'only the completed worker result is dispatched'}
function Start-ManagedPackage($result){
    $script:vendorStarts++;Assert-DownloadUI $script:expectedVendorFile ([IO.Path]::GetFileName($result.Path)) 'manufacturer worker result is dispatched'
    if($result.Package.Family -eq 'ASUSDriver'){$script:lastAsusRoot=$result.Root}
    $process=[pscustomobject]@{HasExited=$true};$process|Add-Member ScriptMethod Dispose {};return $process
}
function Start-Scan {$script:rescans++}
function Start-Job {
    param($ArgumentList,$ScriptBlock)
    # Replace only the network worker: real job/progress/cancellation and UI event handlers remain in use.
    Microsoft.PowerShell.Core\Start-Job -ArgumentList $script:case,$script:appDownload.CancelPath,$ArgumentList[3],$ArgumentList[4],$script:expectedVendorFile,$ArgumentList[1].Check.Package.Family -ScriptBlock {
        param($mode,$cancel,$folder,$manufacturer,$vendorFile,$family)
        Write-Progress -Activity 'Fixture download' -Status 'Fixture progress' -PercentComplete 50
        if($mode -in 'cancel','window-close'){
            $watch=[Diagnostics.Stopwatch]::StartNew()
            while(![IO.File]::Exists($cancel) -and $watch.Elapsed.TotalSeconds -lt 5){Start-Sleep -Milliseconds 20}
            throw 'Fixture cancellation.'
        }
        Start-Sleep -Milliseconds 700
        if($mode -eq 'failure'){throw 'Fixture checksum mismatch.'}
        if($family -eq 'ASUSDriver'){
            $root=Join-Path ([IO.Path]::GetTempPath()) ('DriverLoom-ASUS-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
            $path=Join-Path $root 'AsusSetup.exe';[IO.File]::WriteAllText($path,'fixture; never executed')
            [pscustomobject]@{Path=$path;Root=$root;Package=[pscustomobject]@{Family='ASUSDriver'}}
        }elseif($manufacturer){[pscustomobject]@{Path=(Join-Path $folder $vendorFile)}}else{Join-Path $folder 'DriverLoom-Setup.exe'}
    }
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('driverloom-download-ui-'+[guid]::NewGuid().ToString('N'))
$directory=$root;$script:LauncherVersion='0.1.16';$SmokeTest=$false
$form=[Windows.Forms.Form]::new();$timer=[Windows.Forms.Timer]::new();$timer.Interval=40
$info=[pscustomobject]@{Tag='v0.2.0';LatestVersion='0.2.0';ReleaseUrl='https://github.com/SJB-gif/DriverLoom/releases/tag/v0.2.0';InstallerUrl='https://github.com/SJB-gif/DriverLoom/releases/download/v0.2.0/DriverLoom-Setup.exe';InstallerHash=('a'*64);InstallerSize=100}
$timer.Add_Tick({
    if($script:packageInstaller){
        $script:sawVendorSession=$true;$script:sawInstallLock=$null -ne $script:driverInstallLock
        foreach($window in $form.OwnedForms){if($window.Text -eq 'Driver setup opened'){$script:vendorDeviceShown=@($window.Controls|Where-Object Text -eq $script:expectedVendorDevice).Count -eq 1;($window.Controls|Where-Object Text -eq 'Check again').PerformClick()}}
    }
    if($script:appDownload -and $script:appDownload.Progress.Value -eq 50){
        $script:sawProgress=$true
        if(!$script:appDownload.Cancelled){
            if($script:case -eq 'cancel'){$script:appDownload.CancelButton.PerformClick()}
            if($script:case -eq 'window-close'){$script:appDownload.Dialog.Close();$script:closeWaited=!$script:appDownload.Closing}
        }
    }
    Receive-AppDownload
})
try{
    $timer.Start();$script:starts=0
    foreach($mode in 'success','cancel','window-close','failure'){
        $script:case=$mode;$script:sawProgress=$false;$script:sawBusy=$false;$script:failure='';$script:closeWaited=$false;$before=$script:starts
        Install-AppUpdate $info
        Assert-DownloadUI $true $script:sawProgress "$mode displays worker progress while responsive"
        Assert-DownloadUI $true $script:sawBusy "$mode pauses other operations"
        Assert-DownloadUI $true ($null -eq $script:appDownload) "$mode clears download UI state"
        if($mode -eq 'success'){Assert-DownloadUI ($before+1) $script:starts 'success opens setup once'}else{Assert-DownloadUI $before $script:starts "$mode never opens setup"}
        if($mode -eq 'failure'){Assert-DownloadUI $true ($script:failure -like '*Fixture checksum mismatch*') 'failure reports a retryable error'}
        elseif($mode -in 'cancel','window-close'){Assert-DownloadUI '' $script:failure 'cancellation does not show an error'}
        if($mode -eq 'window-close'){Assert-DownloadUI $true $script:closeWaited 'closing the dialog waits for worker cancellation'}
    }
    $device=New-HardwareRow 'Chipset package' 'AMD' 'AMD Chipset Software' '' '' '7.01.08.129' @()
    $package=New-ManagedPackage 'AMDChipset' $device ([pscustomobject]@{Family='11'}) '8.09.28.1124' 'https://www.amd.com/en/support/downloads/drivers.html/chipsets/am5/x670e.html' 'https://drivers.amd.com/drivers/amd_chipset_software_8.09.28.1124.exe'
    $selection=[pscustomobject]@{Device=$device;Check=[pscustomobject]@{Checked=$true;Status='Newer at source';Available=$package.Version;Url=$package.SourceUrl;Package=$package}}
    $script:vendorStarts=0;$script:rescans=0
    $script:expectedVendorFile='AMD-Chipset-Setup.exe';$script:expectedVendorDevice='AMD Chipset Software'
    foreach($family in 'AMDChipset','AMDRadeon','ASUSDriver'){
        if($family -eq 'AMDRadeon'){
            $gpu=New-HardwareRow 'GPU driver' 'AMD' 'AMD Radeon(TM) Graphics' '' '' '32.0.21030.2001' @()
            $device=New-HardwareRow 'GPU software' 'AMD' 'AMD Software: Adrenalin Edition' '' '' '24.6.1' @()
            $package=New-ManagedPackage 'AMDRadeon' $device (Get-WindowsDriverTarget '10.0.26300.0') '26.11.2' 'https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-7000-series/amd-ryzen-9-7900x3d.html' 'https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-26.11.2-win11-a.exe' $gpu
            $selection=[pscustomobject]@{Device=$device;Check=[pscustomobject]@{Checked=$true;Status='Newer at source';Available=$package.Version;Url=$package.SourceUrl;Package=$package}}
            $script:expectedVendorFile='AMD-Radeon-Setup.exe';$script:expectedVendorDevice=$device.Model
        }elseif($family -eq 'ASUSDriver'){
            $device=New-HardwareRow 'Bluetooth driver' 'MediaTek' 'MediaTek Bluetooth Adapter' '' '' '1.0.0.0' @('USB\VID_0489&PID_E0E2&MI_00')
            $board=New-HardwareRow 'Motherboard' 'ASUSTeK' 'ROG STRIX X670E-A GAMING WIFI' '' '' '' @()
            $package=New-AsusPackage $device $board (Get-WindowsDriverTarget '10.0.26300.0') 'Bluetooth' ([pscustomobject]@{Version='1.1037.0.399';DownloadUrl=[pscustomobject]@{Global='/pub/ASUS/mb/02BT/fixture_RZ616.zip'};sha256=''}) ('https://www.asus.com/supportonly/'+[Uri]::EscapeDataString($board.Model)+'/helpdesk_download/')
            $selection=[pscustomobject]@{Device=$device;Check=[pscustomobject]@{Checked=$true;Status='Newer at source';Available=$package.Version;Url=$package.SourceUrl;Package=$package}}
            $script:expectedVendorFile='AsusSetup.exe';$script:expectedVendorDevice=$device.Model
        }
    foreach($mode in 'success','cancel','window-close','failure'){
        $script:case=$mode;$script:sawProgress=$false;$script:sawBusy=$false;$script:failure='';$script:sawVendorSession=$false;$script:sawInstallLock=$false;$before=$script:vendorStarts
        Install-ManufacturerUpdate $selection
        Assert-DownloadUI $true $script:sawProgress "manufacturer $mode displays worker progress"
        Assert-DownloadUI $true ($null -eq $script:appDownload -and $null -eq $script:packageInstaller -and $null -eq $script:driverInstallLock) "manufacturer $mode releases UI and installation guards"
        if($mode -eq 'success'){
            Assert-DownloadUI ($before+1) $script:vendorStarts 'verified manufacturer result opens setup once'
            Assert-DownloadUI $true $script:sawVendorSession 'user completes the vendor handoff before rechecking'
            Assert-DownloadUI $true $script:sawInstallLock 'app replacement is blocked during vendor installation'
            Assert-DownloadUI $true $script:vendorDeviceShown 'handoff identifies the device being updated'
            Assert-DownloadUI $true ($script:rescans -gt 0) 'manufacturer setup leads to a fresh hardware check'
            if($family -eq 'ASUSDriver'){Assert-DownloadUI $true (Test-Path -LiteralPath $script:lastAsusRoot) 'ASUS setup payload stays available to vendor child processes';Remove-AsusRoot $script:lastAsusRoot}
        }else{Assert-DownloadUI $before $script:vendorStarts 'cancel/failure never starts vendor setup'}
    }
    }
    Write-Output 'App and manufacturer update UI checks passed: asynchronous progress, cancellation, error recovery, verified setup dispatch, installation guard and recheck. No installer was executed.'
}finally{
    $timer.Stop();$timer.Dispose();$form.Dispose()
    if($script:appDownload -and $script:appDownload.Job){Remove-Job -Job $script:appDownload.Job -Force}
    $resolved=[IO.Path]::GetFullPath($root);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing cleanup outside TEMP.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
