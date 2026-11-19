param([switch]$SmokeTest)

$ErrorActionPreference = 'Stop'
try {
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion -lt [version]'5.1' -or ![Environment]::Is64BitProcess) {
        throw 'Use 64-bit Windows PowerShell 5.1 to open Hardware Update Launcher. Reinstall using the current installer to repair the shortcut.'
    }
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'The launcher requires STA mode. Open the installed Start menu shortcut.'
    }
    & (Join-Path $PSScriptRoot 'App.ps1') -SmokeTest:$SmokeTest
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
    $message = "Hardware Update Launcher could not start.`r`n`r`n$($failure.Exception.Message)"
    if ($log) { $message += "`r`n`r`nDetails saved to $log" }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($message, 'Hardware Update Launcher', 'OK', 'Error')
    } catch {
        try { (New-Object -ComObject WScript.Shell).Popup($message, 0, 'Hardware Update Launcher', 16) | Out-Null }
        catch { Write-Error -ErrorRecord $failure }
    }
    exit 1
}
