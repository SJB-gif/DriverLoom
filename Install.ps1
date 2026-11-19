function Install-DriverOffers($approved) {
    Add-Type -AssemblyName System.Windows.Forms
    $lines = [System.Collections.Generic.List[string]]::new()
    $restart = $false
    try {
        $info = New-Object -ComObject Microsoft.Update.SystemInfo
        if ($info.RebootRequired) { throw 'Windows Update is waiting for a restart. Restart and run Check for updates again.' }
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'Hardware Update Launcher'
        $search = Search-WindowsDrivers $session
        $available = @{}
        $found = @(for ($i = 0; $i -lt $search.Updates.Count; $i++) {
            $candidate = $search.Updates.Item($i)
            $offer = Get-DriverOffer $candidate
            if ($offer) {
                $available["$($offer.Id):$($offer.Revision)"] = $candidate
                $offer
            }
        })
        $eligible = @{}
        foreach ($offer in @(Get-UnambiguousOffers $found $lines)) { $eligible["$($offer.Id):$($offer.Revision)"] = $true }
        foreach ($item in $approved) {
            $key = "$([guid]$item.Id):$([int]$item.Revision)"
            if ($restart) { $lines.Add('Remaining updates deferred until after restart.'); break }
            if (!$eligible.ContainsKey($key)) { $lines.Add("Offer $key changed or is no longer eligible."); continue }
            $update = $available[$key]
            try {
                if (!$update.EulaAccepted) {
                    $terms = [string]$update.EulaText
                    if (!$terms -or $terms.Length -gt 1000) {
                        $lines.Add("$($update.Title) requires licence review in Windows Update."); continue
                    }
                    $choice = [Windows.Forms.MessageBox]::Show($terms, "Licence - $($update.Title)", 'YesNo', 'Question', 'Button2')
                    if ($choice -ne 'Yes') { $lines.Add("$($update.Title) skipped."); continue }
                    $update.AcceptEula()
                }
                $list = New-Object -ComObject Microsoft.Update.UpdateColl
                [void]$list.Add($update)
                $downloader = $session.CreateUpdateDownloader()
                $downloader.Updates = $list
                $download = $downloader.Download()
                if ([int]$download.GetUpdateResult(0).ResultCode -ne 2 -or !$update.IsDownloaded) {
                    throw "Download failed (HRESULT $($download.GetUpdateResult(0).HResult))."
                }
                $installer = $session.CreateUpdateInstaller()
                if ($installer.IsBusy) { throw 'Windows Update is already installing an update.' }
                if ($installer.RebootRequiredBeforeInstallation) { $restart = $true; throw 'Restart required before installation.' }
                $installer.Updates = $list
                $installer.AllowSourcePrompts = $false
                $result = $installer.Install()
                $restart = $result.RebootRequired
                $entry = $result.GetUpdateResult(0)
                if ([int]$entry.ResultCode -ne 2) { throw "Install returned code $($entry.ResultCode) (HRESULT $($entry.HResult))." }
                $lines.Add("Installed: $($update.Title)")
            } catch { $lines.Add("$($update.Title): $($_.Exception.Message)") }
        }
    } catch { $lines.Add($_.Exception.Message) }
    if ($restart) { $lines.Add('Restart Windows, then check again.') }
    $report = $lines -join "`r`n"
    $window = New-Object Windows.Forms.Form
    $window.Text = 'Driver installation results'
    $window.Size = New-Object Drawing.Size(740, 420)
    $window.StartPosition = 'CenterScreen'
    $window.TopMost = $true
    $body = New-Object Windows.Forms.TextBox
    $body.Dock = 'Fill'; $body.Multiline = $true; $body.ReadOnly = $true; $body.ScrollBars = 'Vertical'; $body.Text = $report
    $window.Controls.Add($body)
    [void]$window.ShowDialog()
    $window.Dispose()
}
