$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'src'
$ErrorActionPreference='Stop'
. (Join-Path $srcRoot 'Engine.ps1')
. (Join-Path $srcRoot 'VendorApps.ps1')
function Assert-VendorApp($expected,$actual,[string]$description){if($actual -cne $expected){throw "$description expected '$expected', got '$actual'."}}
$catalog=@{}
foreach($spec in (Get-VendorAppSpecs)){$catalog[$spec.Key]=[pscustomobject]@{Key=$spec.Key;Name=$spec.Name;Vendor=$spec.Vendor;Path='C:\Fixture Apps\'+$spec.Key+'\'+$spec.File}}
$headset=New-HardwareRow 'Audio/video driver' 'Corsair' 'Headset' '' '' '2.4' @()
$input=New-HardwareRow 'Input device driver' 'Corsair' 'Virtual input' '' '' '3.0' @()
$ssd=New-HardwareRow 'Storage firmware' 'Corsair' 'MP600' '' '' 'E1' @()
$gpu=New-HardwareRow 'GPU driver' 'AMD' 'Radeon Graphics' '' '' '32.0' @()
$chipset=New-HardwareRow 'Chipset package' 'AMD' 'AMD Chipset Software' '' '' '7.0' @()
Assert-VendorApp 'icue' (Get-DeviceLauncher $headset $catalog).Key 'Corsair peripheral follows iCUE'
Assert-VendorApp 'corsairSSD' (Get-DeviceLauncher $ssd $catalog).Key 'Corsair SSD does not follow iCUE'
Assert-VendorApp 'amdManager' (Get-DeviceLauncher $gpu $catalog).Key 'AMD Install Manager is preferred to the settings frontend'
Assert-VendorApp 'amdManager' (Get-DeviceLauncher $chipset $catalog).Key 'AMD graphics and chipset can share their verified updater'
$fallback=@{radeon=$catalog.radeon}
Assert-VendorApp 'radeon' (Get-DeviceLauncher $gpu $fallback).Key 'Radeon frontend is a graphics fallback'
Assert-VendorApp $null (Get-DeviceLauncher $chipset $fallback) 'Radeon frontend is not assigned to chipset updates'
$entries=@(foreach($device in $headset,$input,$ssd){[pscustomobject]@{Name=$device.Model;Device=$device;Launcher=Get-DeviceLauncher $device $catalog}})
$groups=@(Get-LauncherDisplayGroups $entries)
Assert-VendorApp 2 $groups.Count 'different Corsair update tools remain separate'
Assert-VendorApp 2 @($groups|Where-Object IsGroup|ForEach-Object Items).Count 'both peripheral records survive grouping'
Assert-VendorApp 3 @(Get-LauncherDisplayGroups @($entries|ForEach-Object{[pscustomobject]@{Name=$_.Name;Launcher=$null}})).Count 'absent apps preserve individual website actions'
Assert-VendorApp 'C:\Apps\iCUE.exe' (ConvertTo-VendorExePath '"C:\Apps\iCUE.exe",0') 'registered icon path is parsed as a path'
Assert-VendorApp '' (ConvertTo-VendorExePath '"C:\Apps\iCUE.exe" --run-something') 'registered command-line arguments are never executed'
$spec=Get-VendorAppSpecs|Where-Object Key -eq 'icue'
Assert-VendorApp $false (Test-VendorExecutable '\\server\share\iCUE.exe' $spec) 'discovery never probes a remote executable'
Assert-VendorApp $false (Test-VendorExecutable 'C:\Windows\System32\notepad.exe' $spec) 'unrelated executables cannot become vendor launchers'
$script:allowed=$true;$script:launchCount=0;$script:opened='';$script:working=''
function Test-VendorExecutable($path,$spec){return $script:allowed}
function Start-Process([string]$FilePath,[string]$WorkingDirectory){$script:launchCount++;$script:opened=$FilePath;$script:working=$WorkingDirectory}
Start-VendorApplication $catalog.icue
Assert-VendorApp $catalog.icue.Path $script:opened 'action uses the detected executable without a shell command'
Assert-VendorApp 'C:\Fixture Apps\icue' $script:working 'app opens with its own working directory'
$script:allowed=$false;$blocked=$false
try{Start-VendorApplication $catalog.icue}catch{$blocked=$true}
Assert-VendorApp $true $blocked 'missing or changed signature blocks launch'
Assert-VendorApp 1 $script:launchCount 'failed revalidation never starts an executable'
Write-Output 'Vendor app checks passed: app routing, launcher-specific groups, registered paths, local-only discovery and revalidated launch dispatch. No vendor app was opened.'
