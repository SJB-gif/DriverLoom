$ErrorActionPreference = 'Stop'
try {
    & (Join-Path $PSScriptRoot 'App.ps1')
} catch {
    $failure = $_
    $log = $null
    $directory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'HardwareUpdateLauncher'
    try {
        [void][IO.Directory]::CreateDirectory($directory)
        $log = Join-Path $directory 'startup-error.log'
        $report = @(
            (Get-Date -Format o)
            "PowerShell: $($PSVersionTable.PSVersion)"
            $failure.ToString()
            $failure.InvocationInfo.PositionMessage
            $failure.ScriptStackTrace
        )
        [IO.File]::WriteAllLines($log, [string[]]$report)
    } catch { $log = $null }
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
