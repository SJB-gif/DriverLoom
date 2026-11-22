param([switch]$SmokeTest,[switch]$Background)

$ErrorActionPreference = 'Stop'
try {
    $nativeHost=Join-Path $PSScriptRoot 'DriverLoom.exe'
    # Old pinned shortcuts may still target PowerShell. Forward them to the branded host.
    if(!$SmokeTest -and !('DriverLoom.ShellIdentity' -as [type]) -and (Test-Path -LiteralPath $nativeHost)){
        $start=@{FilePath=$nativeHost;WindowStyle='Hidden'}
        if($Background){$start.ArgumentList='-Background'}
        Start-Process @start
        return
    }
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion -lt [version]'5.1' -or ![Environment]::Is64BitProcess) {
        throw 'Use 64-bit Windows PowerShell 5.1 to open DriverLoom. Reinstall using the current installer to repair the shortcut.'
    }
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'The launcher requires STA mode. Open the installed Start menu shortcut.'
    }
    & (Join-Path $PSScriptRoot 'App.ps1') -SmokeTest:$SmokeTest -Background:$Background
} catch {
    $failure = $_
    $log = $null
    $directory = Join-Path $env:LOCALAPPDATA 'HardwareUpdateLauncher'
    try {
        [void][IO.Directory]::CreateDirectory($directory)
        $log = Join-Path $directory 'startup-error.log'
        $report = @(
            (Get-Date -Format o)
            "PowerShell: $($PSVersionTable.PSVersion)"
            "64-bit process: $([Environment]::Is64BitProcess)"
            "Apartment: $([Threading.Thread]::CurrentThread.GetApartmentState())"
            $failure.Exception.ToString()
            $failure.InvocationInfo.PositionMessage
            $failure.ScriptStackTrace
        )
        [IO.File]::WriteAllLines($log, [string[]]$report)
    } catch { $log = $null }
    if ($SmokeTest) { [Console]::Error.WriteLine($failure.Exception.Message); exit 1 }
    $message = "DriverLoom could not start.`r`n`r`n$($failure.Exception.Message)"
    if ($log) { $message += "`r`n`r`nDetails saved to $log" }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($message, 'DriverLoom', 'OK', 'Error')
    } catch {
        try { (New-Object -ComObject WScript.Shell).Popup($message, 0, 'DriverLoom', 16) | Out-Null }
        catch { Write-Error -ErrorRecord $failure }
    }
    exit 1
}
