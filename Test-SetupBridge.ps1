$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Lifecycle.ps1')
[void][Reflection.Assembly]::LoadFile((Join-Path $PSScriptRoot 'dist\host\DriverLoom-SetupBridge.exe'))
function Assert-Bridge($expected,$actual,[string]$description){if($actual -cne $expected){throw "$description expected '$expected', got '$actual'."}}
$fixtureRoot=Join-Path $PSScriptRoot '.local\setup-path-fixture'
Assert-Bridge (Join-Path $fixtureRoot 'DriverLoom.exe') ([DriverLoomSetupBridge]::InstallerPath($fixtureRoot)) 'shutdown target is the exact installed native executable'
Assert-Bridge (Get-SetupExitName $fixtureRoot) ([DriverLoomSetupBridge]::ExitEventName($fixtureRoot)) 'app and setup use the same installation-scoped exit signal'
Assert-Bridge (Get-SetupExitName $fixtureRoot) (Get-SetupExitName ($fixtureRoot.ToUpperInvariant()+'\')) 'path case and trailing separators do not change the signal'
Assert-Bridge $false ((Get-SetupExitName $fixtureRoot) -eq (Get-SetupExitName ($fixtureRoot+'-other'))) 'another installation receives a different exit signal'
$rejected=$false
try{$null=[DriverLoomSetupBridge]::InstallerPath([IO.Path]::GetPathRoot($fixtureRoot))}catch{$rejected=$true}
Assert-Bridge $true $rejected 'drive roots cannot be shutdown/install targets'
Assert-Bridge $false ([DriverLoomSetupBridge]::IsDriverInstallCommand('powershell.exe -NoProfile -File "C:\example\unrelated.ps1"')) 'unrelated PowerShell is not identified as a driver installer'
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("function Install-DriverOffers { }; Install-DriverOffers @()"))
Assert-Bridge $true ([DriverLoomSetupBridge]::IsDriverInstallCommand('powershell.exe -EncodedCommand '+$encoded)) 'legacy encoded driver installer is recognised without execution'
Assert-Bridge $true ([DriverLoomSetupBridge]::IsDriverInstallCommand('')) 'inaccessible legacy PowerShell requires a manual close'
Write-Output 'Setup bridge checks passed: exact executable target, rejected drive roots and legacy driver-install guard. No real process was closed.'
