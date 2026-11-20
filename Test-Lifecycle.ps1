$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Engine.ps1')
. (Join-Path $PSScriptRoot 'Lifecycle.ps1')
function Assert-Lifecycle($expected,$actual,[string]$message){if($expected -cne $actual){throw "$message expected '$expected', got '$actual'."}}
$old=[pscustomobject]@{}
Initialize-LifecyclePreferences $old
Assert-Lifecycle 'On opening' $old.CheckFrequency 'legacy default frequency'
Assert-Lifecycle $false $old.KeepRunningInTray 'tray opt-in default'
Assert-Lifecycle $false $old.StartWithWindows 'login opt-in default'
Assert-Lifecycle $true $old.CheckAppUpdates 'app release checks default to on opening'
Assert-Lifecycle 'Application' $old.GroupBy 'existing application grouping remains the default'
$invalid=[pscustomobject]@{CheckFrequency='Hourly';KeepRunningInTray='yes';StartWithWindows=1;GroupBy='invalid'}
Initialize-LifecyclePreferences $invalid
Assert-Lifecycle 'On opening' $invalid.CheckFrequency 'invalid frequency fallback'
Assert-Lifecycle $false $invalid.KeepRunningInTray 'invalid tray preference cannot opt in'
Assert-Lifecycle $false $invalid.StartWithWindows 'invalid startup preference cannot opt in'
Assert-Lifecycle 'Application' $invalid.GroupBy 'invalid grouping preference falls back to existing view'
$now=[DateTimeOffset]::Parse('2026-11-19T00:00:00Z')
Assert-Lifecycle $false (Test-AutomaticCheckDue 'Manual' $now $null $null $true) 'manual never checks automatically'
Assert-Lifecycle $true (Test-AutomaticCheckDue 'On opening' $now $null $null $true) 'on-opening startup'
Assert-Lifecycle $false (Test-AutomaticCheckDue 'On opening' $now $null $null) 'on-opening has no recurring schedule'
Assert-Lifecycle $true (Test-AutomaticCheckDue 'Daily' $now $null $null $true) 'daily first launch'
Assert-Lifecycle $false (Test-AutomaticCheckDue 'Daily' $now $null $now.AddHours(-23).ToString('o') $true) 'reopening does not bypass daily interval'
Assert-Lifecycle $true (Test-AutomaticCheckDue 'Daily' $now $null $now.AddDays(-1).ToString('o')) 'daily exact interval'
Assert-Lifecycle $false (Test-AutomaticCheckDue 'Daily' $now $now.AddMinutes(-2).ToString('o') $now.AddDays(-3).ToString('o')) 'failed scan does not retry every timer tick'
Assert-Lifecycle $false (Test-AutomaticCheckDue 'Weekly' $now $null $now.AddDays(-6).ToString('o')) 'weekly interval respected'
Assert-Lifecycle $true (Test-AutomaticCheckDue 'Weekly' $now $null $now.AddDays(-7).ToString('o')) 'weekly exact interval'
Assert-Lifecycle $true (Test-AutomaticCheckDue 'Daily' $now $null $now.AddDays(1).ToString('o')) 'clock rollback does not suppress checking indefinitely'
Assert-Lifecycle $true (Test-AutomaticCheckDue 'Daily' $now $null 'invalid') 'corrupt capture timestamp'

# Startup registration is exercised only in an isolated test key, never the Windows Run key.
$id=[guid]::NewGuid().ToString('N')
$subKey='Software\DriverLoom-Tests\'+$id
$root=Join-Path ([IO.Path]::GetTempPath()) ('driverloom-lifecycle-'+$id)
try{
    [void][IO.Directory]::CreateDirectory($root)
    $launcher=Join-Path $root 'DriverLoom test.exe';[IO.File]::WriteAllText($launcher,'fixture, not executable')
    $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($subKey)
    try{$key.SetValue('OtherApp','untouched')}finally{$key.Dispose()}
    $next=[pscustomobject]@{CheckFrequency='Weekly';KeepRunningInTray=$true;StartWithWindows=$true}
    $preferences=Join-Path $root 'settings.json'
    Save-LauncherPreferences $preferences $old $next $launcher $subKey
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKey)
    try{Assert-Lifecycle ('"'+$launcher+'" -Background') $key.GetValue('DriverLoom') 'quoted hidden login command'}finally{$key.Dispose()}
    $roundtrip=Get-Content -LiteralPath $preferences -Raw|ConvertFrom-Json
    Assert-Lifecycle 'Weekly' $roundtrip.CheckFrequency 'schedule persists'
    Assert-Lifecycle $true $roundtrip.KeepRunningInTray 'tray preference persists'
    $visible=[pscustomobject]@{CheckFrequency='Weekly';KeepRunningInTray=$false;StartWithWindows=$true}
    Save-LauncherPreferences $preferences $next $visible $launcher $subKey
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKey)
    try{Assert-Lifecycle ('"'+$launcher+'"') $key.GetValue('DriverLoom') 'login is visible when tray is off'}finally{$key.Dispose()}
    $failed=$false
    try{Save-LauncherPreferences (Join-Path $root 'missing\settings.json') $visible $next $launcher $subKey}catch{$failed=$true}
    Assert-Lifecycle $true $failed 'failed preference write reports error'
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKey)
    try{Assert-Lifecycle ('"'+$launcher+'"') $key.GetValue('DriverLoom') 'failed save restores exact previous startup command'}finally{$key.Dispose()}
    Save-LauncherPreferences $preferences $visible $old '' $subKey
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKey)
    try{Assert-Lifecycle $null $key.GetValue('DriverLoom') 'opt-out removes only the app entry';Assert-Lifecycle 'untouched' $key.GetValue('OtherApp') 'unrelated entry preserved'}finally{$key.Dispose()}
    Write-Output 'Lifecycle checks passed: defaults, manual/on-opening/daily/weekly timing, retry/clock handling, preference persistence, opt-in startup command and rollback.'
}finally{
    if($subKey -notmatch '^Software\\DriverLoom-Tests\\[a-f0-9]{32}$'){throw 'Unsafe test registry cleanup.'}
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($subKey,$false)
    $resolved=[IO.Path]::GetFullPath($root);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^driverloom-lifecycle-[a-f0-9]{32}$'){throw 'Unsafe lifecycle test cleanup.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
