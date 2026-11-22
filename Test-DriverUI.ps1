$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
. (Join-Path $PSScriptRoot 'Engine.ps1');. (Join-Path $PSScriptRoot 'Theme.ps1');. (Join-Path $PSScriptRoot 'DriverUI.ps1')
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'App.ps1'),[ref]$tokens,[ref]$errors)
foreach($name in 'Open-HardwareAction','Install-ManufacturerUpdate'){$node=$ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object Name -eq $name;. ([scriptblock]::Create($node.Extent.Text))}
function Assert-DriverUI($expected,$actual,$why){if($expected -cne $actual){throw "$why expected '$expected', got '$actual'."}}
function Update-Controls {}
function Complete-DriverDownload($folder) {}
function Show-Message($message){$script:failure=$message}
function Refresh-View {$hardware.Rows[0].Cells['Source'].Tag='Link';$hardware.Rows[0].Cells['Source'].Value=if($script:entry){'Install update'}else{'Download update'};$hardware.Rows[0].Tag.Ready=$script:entry}
function Start-Job {
    param($ArgumentList,$ScriptBlock)
    Microsoft.PowerShell.Core\Start-Job -ArgumentList $script:mode,$ArgumentList[2] -ScriptBlock {
        param($mode,$folder)
        Write-Progress -Activity 'Fixture' -Status 'Downloading fixture' -PercentComplete 40
        Start-Sleep -Milliseconds 700
        if(Test-Path -LiteralPath (Join-Path $folder 'cancel')){throw 'Cancelled fixture.'}
        if($mode -eq 'failure'){throw 'Fixture signature mismatch.'}
        [pscustomobject]@{Folder=$folder;Kind='Installer';Version='8.09.28.1124'}
    }
}
$realInstall=${function:Install-SavedManufacturerDriver}
function Install-SavedManufacturerDriver($entry){$script:installed++;$script:dispatched=$entry}
function Open-Link($url){throw 'Managed update unexpectedly opened a website.'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('driverloom-inline-ui-'+[guid]::NewGuid().ToString('N'));$oldData=$env:LOCALAPPDATA
$form=[Windows.Forms.Form]::new();$hardware=[DriverLoom.UI.DeviceGrid]::new();$hardware.Decorated=$true
foreach($column in 'Device','Installed','Available','Status','Source'){[void]$hardware.Columns.Add($column,$column)}
try{
    $env:LOCALAPPDATA=$root;$script:installed=0
    $device=New-HardwareRow 'Chipset package' 'AMD' 'AMD Chipset Software' '' '' '7.01.08.129' @()
    $package=New-ManagedPackage 'AMDChipset' $device ([pscustomobject]@{Family='11'}) '8.09.28.1124' 'https://www.amd.com/en/support/downloads/drivers.html/chipsets/am5/x670e.html' 'https://drivers.amd.com/drivers/amd_chipset_software_8.09.28.1124.exe'
    $selection=[pscustomobject]@{Device=$device;Check=[pscustomobject]@{Checked=$true;Status='Newer at source';Available=$package.Version;Url=$package.SourceUrl;Package=$package};Ready=$null}
    $i=$hardware.Rows.Add(@($device.Model,$device.Current,$package.Version,'UPDATE AVAILABLE','Download update'));$hardware.Rows[$i].Tag=$selection
    foreach($mode in 'success','cancel','failure'){
        $script:mode=$mode;$script:entry=$null;$script:failure='';$selection.Ready=$null
        Open-HardwareAction $selection
        Assert-DriverUI $true ([bool]$script:driverDownload) 'download starts on explicit action'
        $watch=[Diagnostics.Stopwatch]::StartNew();$sawProgress=$false
        while($script:driverDownload -and $watch.Elapsed.TotalSeconds -lt 15){
            if($script:driverDownload.Job.State -eq 'Completed'){$script:entry=[pscustomobject]@{Folder=$script:driverDownload.Folder}}
            if(@($script:driverDownload.Job.ChildJobs[0].Progress).Count -and $script:driverDownload.Job.ChildJobs[0].Progress[-1].PercentComplete -eq 40){
                Receive-DriverDownload
                if($script:driverDownload){
                    Assert-DriverUI 40 $hardware.Rows[0].Cells['Source'].Tag.Value 'progress is attached to the action button'
                    $sawProgress=$true
                    if($mode -eq 'cancel'){Open-HardwareAction $selection}
                }
            }
            if($script:driverDownload -and $script:driverDownload.Job.State -eq 'Completed'){$script:entry=[pscustomobject]@{Folder=$script:driverDownload.Folder}}
            Receive-DriverDownload
            [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 50
        }
        Assert-DriverUI $true $sawProgress 'UI receives asynchronous transfer progress'
        Assert-DriverUI $null $script:driverDownload 'download state clears'
        Assert-DriverUI 0 $script:installed 'download never starts installation'
        if($mode -eq 'success'){
            Assert-DriverUI 'Install update' $hardware.Rows[0].Cells['Source'].Value 'download completion changes action'
            Open-HardwareAction $selection;Assert-DriverUI 1 $script:installed 'a second explicit click dispatches installation';$script:installed=0
        }elseif($mode -eq 'failure'){Assert-DriverUI $true ($script:failure -like '*signature mismatch*') 'verification failure is reported'}
        else{Assert-DriverUI '' $script:failure 'cancel is quiet'}
    }
    # Exercise the real installation handoff separately, with every privileged action mocked.
    function Read-DriverLibraryEntry($folder){return [pscustomobject]@{Folder=$folder;DeviceKey=$device.Key;Package=$package}}
    function Assert-LibraryDevice($entry,$data){return $device}
    function Get-HardwareInventory {[pscustomobject]@{OS='10.0.26300.0';Inventory=@()}}
    function Invoke-BackupOperation {param($operation,$entry,$keys,[switch]$DeferRetention)$script:backupCalls++;return [pscustomobject]@{Saved=1;Total=1;Cancelled=$false;Errors=@()}}
    function Invoke-SavedDriverPreparation($entry){return [pscustomobject]@{Path='C:\Fixture\AMD-Setup.exe';Package=$package}}
    function Start-ManagedPackage($result){$script:setupCalls++;$p=[pscustomobject]@{HasExited=$true};$p|Add-Member ScriptMethod Dispose {};return $p}
    function Show-PackageInstallation($selection){$script:handoffCalls++;$lock=$null;Assert-DriverUI $true ([Threading.Mutex]::TryOpenExisting('Local\DriverLoom.DriverInstall',[ref]$lock)) 'setup handoff keeps the installation guard';$lock.Dispose()}
    function Start-Scan {$script:scanCalls++}
    $script:backupCalls=0;$script:setupCalls=0;$script:handoffCalls=0;$script:scanCalls=0
    & $realInstall ([pscustomobject]@{Folder=(Join-Path $root 'fixture')})
    Assert-DriverUI 1 $script:backupCalls 'explicit installation backs up current drivers first'
    Assert-DriverUI 1 $script:setupCalls 'only explicit installation opens vendor setup'
    Assert-DriverUI 1 $script:handoffCalls 'user completes the vendor handoff'
    Assert-DriverUI 1 $script:scanCalls 'installation triggers a fresh check'
    'Driver action UI checks passed: explicit download, button progress, cancellation/failure, no automatic install and second-click install dispatch. No installer was executed.'
}finally{
    if($script:driverDownload -and $script:driverDownload.Job){Remove-Job -Job $script:driverDownload.Job -Force}
    $hardware.Dispose();$form.Dispose();$env:LOCALAPPDATA=$oldData
    $resolved=[IO.Path]::GetFullPath($root);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
