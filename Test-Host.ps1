$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Engine.ps1')
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('driverloom-host-'+[guid]::NewGuid().ToString('N'))
$stage=Join-Path $testRoot 'program with spaces'
$originalLocalAppData=$env:LOCALAPPDATA
$script:nativeCall=0
function Invoke-NativeTest([string]$exe,[string[]]$arguments,[int]$expectedExit=0){
    $script:nativeCall++
    $output=Join-Path $testRoot ("output-$script:nativeCall.txt")
    $errorPath=Join-Path $testRoot ("error-$script:nativeCall.txt")
    $process=Start-Process -FilePath $exe -WindowStyle Hidden -ArgumentList $arguments -PassThru -RedirectStandardOutput $output -RedirectStandardError $errorPath
    try{
        $null=$process.Handle
        if(!$process.WaitForExit(30000)){$process.Kill();throw 'Native host timed out.'}
        if($process.ExitCode -ne $expectedExit){throw ('Native host exit '+$process.ExitCode+': '+(Get-Content -LiteralPath $errorPath -Raw))}
    }finally{$process.Dispose()}
    return ([IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)).Trim()
}
try{
    [void][IO.Directory]::CreateDirectory($stage)
    foreach($name in 'App.ps1','Launch.ps1','Engine.ps1','Coverage.ps1','Manufacturers.ps1','Install.ps1','Theme.ps1','Theme.cs'){
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $stage $name)
    }
    [void][IO.Directory]::CreateDirectory((Join-Path $stage 'assets'))
    foreach($name in 'DriverLoom-loops.ico','DriverLoom-brand.png','GitHub-light.png','GitHub-dark.png'){
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('assets\'+$name)) -Destination (Join-Path $stage 'assets')
    }
    $exe=Join-Path $stage 'DriverLoom.exe'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'dist\host\DriverLoom.exe') -Destination $exe
    $env:LOCALAPPDATA=Join-Path $testRoot 'state'
    $result=(Invoke-NativeTest $exe @('-SmokeTest'))|ConvertFrom-Json
    if($result.NativeProcess -ne 'DriverLoom' -or $result.NativeAppID -ne 'SJB.DriverLoom' -or !$result.Is64BitProcess -or $result.ApartmentState -ne 'STA' -or !$result.Visible){throw 'Native application identity, bitness or startup failed.'}
    if($result.TaskbarWindowID -ne 'SJB.DriverLoom' -or $result.TaskbarIcon -ne ((Join-Path $stage 'assets\DriverLoom-loops.ico')+',0') -or $result.TaskbarCommand -ne ('"'+$exe+'"') -or $result.TaskbarName -ne 'DriverLoom'){throw 'Taskbar window icon or relaunch metadata was not applied.'}
    $link=Join-Path $stage 'DriverLoom test.lnk'
    $shell=New-Object -ComObject WScript.Shell
    $shortcut=$shell.CreateShortcut($link);$shortcut.TargetPath=$exe;$shortcut.Save()
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut);[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    $id=Invoke-NativeTest $exe @('--shortcut-id',('"'+$link+'"'))
    $read=Invoke-NativeTest $exe @('--read-shortcut-id',('"'+$link+'"'))
    if($id -ne 'SJB.DriverLoom' -or $read -ne $id){throw "Shortcut taskbar identity was not saved. Wrote '$id', read '$read'."}
    $broken=Join-Path $testRoot 'broken'
    [void][IO.Directory]::CreateDirectory($broken)
    Copy-Item -LiteralPath $exe -Destination (Join-Path $broken 'DriverLoom.exe')
    $null=Invoke-NativeTest (Join-Path $broken 'DriverLoom.exe') @('-SmokeTest') 1
    if(!(Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'HardwareUpdateLauncher\host-error.log'))){throw 'Native startup error was not logged.'}
    Write-Output 'Native host checks passed: explicit taskbar window icon/relaunch metadata, process and shortcut AppID, background jobs, STA, paths with spaces and failure reporting.'
}finally{
    $env:LOCALAPPDATA=$originalLocalAppData
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^driverloom-host-[a-f0-9]{32}$'){throw 'Unsafe test cleanup path.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
