param([switch]$SmokeTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot 'Engine.ps1')
. (Join-Path $PSScriptRoot 'Install.ps1')

$mutexName = if ($SmokeTest) { 'Local\HardwareUpdateLauncher-Smoke-' + [guid]::NewGuid().ToString('N') } else { 'Local\HardwareUpdateLauncher' }
$mutex = [Threading.Mutex]::new($false, $mutexName)
try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
if (!$acquired) {
    [void][Windows.Forms.MessageBox]::Show('Hardware Update Launcher is already open.', 'Hardware Update Launcher')
    $mutex.Dispose()
    return
}

$directory = Join-Path $env:LOCALAPPDATA 'HardwareUpdateLauncher'
$settingsPath = Join-Path $directory 'settings.json'
$inventoryPath = Join-Path $directory 'inventory.json'
[void][IO.Directory]::CreateDirectory($directory)

$script:settings = [pscustomobject]@{ Repo = ''; Bios = $false; Sources = @() }
$startupNotice = ''
if (Test-Path -LiteralPath $settingsPath) {
    try {
        $saved = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        if ($null -eq $saved -or $saved.Bios -isnot [bool] -or ($saved.Repo -and $saved.Repo -notmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$')) { throw 'Invalid settings.' }
        $script:settings = $saved
    } catch { $startupNotice = 'Settings could not be loaded. Edit settings to save a replacement.' }
}
$script:snapshot = $null
if (Test-Path -LiteralPath $inventoryPath) {
    try { $script:snapshot = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json } catch { }
}
$script:job = $null
$script:installer = $null
$script:fresh = $false

function Show-Message([string]$message) {
    [void][Windows.Forms.MessageBox]::Show($form, $message, 'Hardware Update Launcher')
}

function New-Button([string]$label) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $label
    $button.AutoSize = $true
    $button.Padding = New-Object Windows.Forms.Padding(9, 2, 9, 2)
    return $button
}

function Open-Link([string]$link) {
    try { Start-Process -FilePath (Get-HttpsUri $link).AbsoluteUri }
    catch { Show-Message $_.Exception.Message }
}

function New-Grid([System.Collections.IDictionary]$columns) {
    $grid = New-Object Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.ReadOnly = $true
    $grid.MultiSelect = $false
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.BackgroundColor = [Drawing.Color]::White
    $grid.AlternatingRowsDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(244, 248, 249)
    foreach ($name in $columns.Keys) {
        $index = $grid.Columns.Add($name, $name)
        $grid.Columns[$index].FillWeight = $columns[$name]
    }
    return ,$grid
}

function Get-SelectedRow {
    if ($hardware.SelectedRows.Count -gt 0) { return $hardware.SelectedRows[0].Tag }
}

function Refresh-View {
    $hardware.Rows.Clear()
    $drivers.Rows.Clear()
    $details.Text = ''
    $summary.Text = 'No saved scan. Check for updates to inspect Windows Update and manufacturer versions.'
    $repoLink.Enabled = $false
    $install.Enabled = $false
    $bios.Enabled = [bool]$script:settings.Bios
    if (!$script:snapshot) { return }
    $checks = @{}
    foreach ($check in @($script:snapshot.Checks)) { if ($check) { $checks["$($check.Key)|$($check.Current)"] = $check } }
    $system = $script:snapshot.Inventory | Where-Object Kind -eq 'System' | Select-Object -First 1
    $orderedInventory = @($script:snapshot.Inventory | Sort-Object @{ Expression = {
        $itemCheck = $checks["$($_.Key)|$($_.Current)"]
        if ($itemCheck.Status -eq 'Newer at source') { 0 } elseif ($itemCheck.Checked) { 1 } else { 2 }
    } }, Kind, Model)
    foreach ($row in $orderedInventory) {
        if (!$row -or ($row.Kind -eq 'BIOS' -and !$script:settings.Bios)) { continue }
        $check = $checks["$($row.Key)|$($row.Current)"]
        $local = $script:settings.Sources | Where-Object Key -eq $row.Key | Select-Object -First 1
        $report = 'Check required'
        $available = ''
        $url = Get-VendorPortal $row $system
        if ($check) { $report = $check.Status; $available = $check.Available; if ($check.Url) { $url = $check.Url } }
        if ($local -and $local.Url -ne $url) { $url = $local.Url; $report = 'Source saved. Check required.'; $available = '' }
        $i = $hardware.Rows.Add(@($row.Kind, $row.Manufacturer, $row.Model, $row.Current, $available, $report))
        $hardware.Rows[$i].Tag = [pscustomobject]@{ Device = $row; Url = $url; Check = $check }
        if ($check.Status -eq 'Newer at source') { $hardware.Rows[$i].DefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(232, 246, 235) }
    }
    foreach ($offer in @($script:snapshot.Offers)) {
        if ($offer) {
            $i = $drivers.Rows.Add(@($offer.Title, $offer.Class, $offer.Date, 'Eligible', 'Included in Update All after confirmation.'))
            $drivers.Rows[$i].Tag = $offer
        }
    }
    foreach ($offer in @($script:snapshot.ExcludedOffers)) {
        if ($offer) {
            $reason = @($offer.Reasons) -join ' '
            $i = $drivers.Rows.Add(@($offer.Title, $offer.Class, $offer.Date, 'Excluded', $reason))
            $drivers.Rows[$i].Tag = $offer
            $drivers.Rows[$i].DefaultCellStyle.ForeColor = [Drawing.Color]::DimGray
            $drivers.Rows[$i].Cells['Reason'].ToolTipText = $reason
        }
    }
    $repo = $script:snapshot.Repository
    if ($repo -and $script:settings.Repo -and $repo.ReleaseUrl -eq "https://github.com/$($script:settings.Repo)/releases") { $repoLink.Enabled = $true }
    $eligibleCount = @($script:snapshot.Offers | Where-Object { $_ }).Count
    $excludedCount = @($script:snapshot.ExcludedOffers | Where-Object { $_ }).Count
    $install.Enabled = $script:fresh -and $script:snapshot.WindowsUpdateOK -and $eligibleCount -gt 0
    $notes = @("Inventory captured: $($script:snapshot.CapturedAt)   |   Windows: $($script:snapshot.OS)")
    if (!$script:fresh) { $notes += 'Saved scan. Run Check for updates before installing.' }
    if ($script:snapshot.WindowsUpdateOK) {
        if ($script:snapshot.PSObject.Properties['WindowsUpdateOfferCount']) {
            $notes += "Windows Update: $($script:snapshot.WindowsUpdateOfferCount) offered; $eligibleCount eligible; $excludedCount excluded. See the Windows Update offers tab for reasons."
        } else { $notes += "Windows Update: $eligibleCount eligible. This older saved scan did not record exclusions; check again for details." }
    }
    $checkedCount = @($script:snapshot.Checks | Where-Object Checked -eq $true).Count
    $uncheckedCount = @($script:snapshot.Checks | Where-Object { $_.Status -like 'Not checked*' -or $_.Status -like 'Source check failed*' }).Count
    $newerCount = @($script:snapshot.Checks | Where-Object Status -eq 'Newer at source').Count
    $windowsSummary = if (!$script:snapshot.WindowsUpdateOK) { 'Windows Update check failed; see details.' }
        elseif ($script:snapshot.PSObject.Properties['WindowsUpdateOfferCount']) { "Windows Update: $($script:snapshot.WindowsUpdateOfferCount) offered; $eligibleCount eligible; $excludedCount excluded." }
        else { "Windows Update: $eligibleCount eligible; check again to record exclusions." }
    $summary.Text = $windowsSummary + "`r`nManufacturer lookups: $checkedCount completed; $newerCount newer; $uncheckedCount not checked. Select a row, then Open source for vendor packages."
    $notes += "Manufacturer lookups: $checkedCount completed; $uncheckedCount not checked. Manufacturer packages are reviewed through Open source; Update All installs Windows Update offers only."
    if ($repo -and $repo.Release) { $notes += "GitHub release: $($repo.Release)   |   Installed launcher: $script:LauncherVersion" }
    $notes += @($script:snapshot.Warnings)
    $details.Lines = [string[]]$notes
}

function New-Dialog([string]$title, [int]$height) {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = $title
    $dialog.Font = $form.Font
    $dialog.StartPosition = 'CenterParent'
    $dialog.ClientSize = New-Object Drawing.Size(665, $height)
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MinimizeBox = $false; $dialog.MaximizeBox = $false
    return $dialog
}

function Add-Label($parent, [string]$text, [int]$top, [int]$height = 25) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $text
    $label.SetBounds(16, $top, 625, $height)
    $parent.Controls.Add($label)
}

function Add-TextInput($parent, [string]$value, [int]$top) {
    $box = New-Object Windows.Forms.TextBox
    $box.Text = $value
    $box.SetBounds(16, $top, 625, 27)
    $parent.Controls.Add($box)
    return $box
}

function Edit-Source {
    $selected = Get-SelectedRow
    if (!$selected) { Show-Message 'Select a hardware row first.'; return }
    $device = $selected.Device
    $existing = $script:settings.Sources | Where-Object Key -eq $device.Key | Select-Object -First 1
    $dialog = New-Dialog 'Edit manufacturer source' 266
    Add-Label $dialog "$($device.Kind) | $($device.Manufacturer) $($device.Model)" 14
    Add-Label $dialog 'Exact manufacturer page or version feed URL' 46
    $urlBox = Add-TextInput $dialog $selected.Url 71
    Add-Label $dialog 'Optional version pattern. Capture one version with a named group such as (?<version>[0-9]+\.[0-9]+).' 111 41
    $patternBox = Add-TextInput $dialog $existing.Pattern 153
    $save = New-Button 'Save'
    $save.Location = New-Object Drawing.Point(16, 211)
    $save.DialogResult = 'OK'
    $forget = New-Button 'Remove override'
    $forget.Location = New-Object Drawing.Point(107, 211)
    $forget.DialogResult = 'Abort'
    $dialog.Controls.AddRange(@($save, $forget))
    $dialog.AcceptButton = $save
    try {
        $result = $dialog.ShowDialog($form)
        if ($result -notin 'OK', 'Abort') { return }
        $sources = @($script:settings.Sources | Where-Object { $_ -and $_.Key -ne $device.Key })
        if ($result -eq 'OK') {
            $url = (Get-HttpsUri $urlBox.Text.Trim()).AbsoluteUri
            $pattern = $patternBox.Text.Trim()
            if ($pattern) { [void](New-VersionPattern $pattern) }
            $sources += [pscustomobject]@{ Key = $device.Key; Url = $url; Pattern = $pattern }
        }
        $next = [pscustomobject]@{ Repo = $script:settings.Repo; Bios = $script:settings.Bios; Sources = $sources }
        Save-Json $settingsPath $next
        $script:settings = $next
        if ($script:snapshot) { $script:snapshot.Checks = @($script:snapshot.Checks | Where-Object { $_ -and $_.Key -ne $device.Key }) }
        Refresh-View
        $status.Text = 'Source saved. Run Check for updates to read the page.'
    } catch { Show-Message $_.Exception.Message }
    finally { $dialog.Dispose() }
}

function Edit-Settings {
    $dialog = New-Dialog 'Settings' 210
    Add-Label $dialog 'GitHub source catalog (optional). Enter a public owner/repository.' 15
    $repoBox = Add-TextInput $dialog $script:settings.Repo 42
    $biosBox = New-Object Windows.Forms.CheckBox
    $biosBox.Text = 'Show BIOS checks and USB preparation guide'
    $biosBox.Checked = [bool]$script:settings.Bios
    $biosBox.SetBounds(16, 87, 625, 32)
    $save = New-Button 'Save'
    $save.Location = New-Object Drawing.Point(16, 143)
    $save.DialogResult = 'OK'
    $dialog.Controls.AddRange(@($biosBox, $save))
    $dialog.AcceptButton = $save
    try {
        if ($dialog.ShowDialog($form) -ne 'OK') { return }
        $repo = $repoBox.Text.Trim()
        if ($repo -and ($repo -notmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$' -or $repo -match '(^|/)\.{1,2}(/|$)')) { throw 'Use owner/repository.' }
        $next = [pscustomobject]@{ Repo = $repo; Bios = $biosBox.Checked; Sources = @($script:settings.Sources) }
        Save-Json $settingsPath $next
        if ($script:snapshot -and $script:settings.Repo -ne $repo) {
            $script:snapshot.Repository = $null
            $script:snapshot.Checks = @()
        }
        $script:settings = $next
        Refresh-View
        $status.Text = 'Settings saved.'
    } catch { Show-Message $_.Exception.Message } finally { $dialog.Dispose() }
}

function Get-UsbVolumes {
    foreach ($disk in @(Get-Disk | Where-Object { $_.BusType -eq 'USB' -and !$_.IsBoot -and !$_.IsSystem -and !$_.IsOffline -and !$_.IsReadOnly })) {
        foreach ($partition in @(Get-Partition -DiskNumber $disk.Number | Where-Object DriveLetter)) {
            $volume = Get-Volume -DriveLetter $partition.DriveLetter -ErrorAction SilentlyContinue
            if (!$volume -or !$volume.FileSystem -or !$disk.UniqueId) { continue }
            [pscustomobject]@{
                Letter = $partition.DriveLetter; Disk = $disk.UniqueId; Partition = $partition.PartitionNumber
                Display = "$($partition.DriveLetter):  $($volume.FileSystemLabel)  [$($volume.FileSystem)]  $($disk.FriendlyName)"
            }
        }
    }
}

function Copy-FileToBiosUsb($parent) {
    try {
        $volumes = @(Get-UsbVolumes)
        if (!$volumes.Count) { throw 'No writable USB drive with a drive letter was found. Connect the prepared drive and try again.' }
        $file = New-Object Windows.Forms.OpenFileDialog
        $file.Title = 'Select the final file prepared according to the manufacturer instructions'
        $file.CheckFileExists = $true
        try {
            if ($file.ShowDialog($parent) -ne 'OK') { return }
            $inputPath = $file.FileName
        } finally { $file.Dispose() }
        $filename = [IO.Path]::GetFileName($inputPath)
        $dialog = New-Dialog 'Select the BIOS USB drive' 190
        Add-Label $dialog "File: $filename" 17
        Add-Label $dialog 'Select the USB drive specified in the manufacturer instructions.' 46
        $combo = New-Object Windows.Forms.ComboBox
        $combo.DropDownStyle = 'DropDownList'
        $combo.SetBounds(16, 72, 625, 27)
        foreach ($volume in $volumes) { [void]$combo.Items.Add($volume.Display) }
        $copy = New-Button 'Copy file'
        $copy.Location = New-Object Drawing.Point(16, 122)
        $copy.DialogResult = 'OK'
        $dialog.Controls.AddRange(@($combo, $copy))
        try {
            if ($dialog.ShowDialog($parent) -ne 'OK') { return }
            if ($combo.SelectedIndex -lt 0) { throw 'Select a USB drive before copying.' }
            $chosen = $volumes[$combo.SelectedIndex]
            $path = Join-Path "$($chosen.Letter):\" $filename
            $confirm = [Windows.Forms.MessageBox]::Show($parent,
                "Copy '$filename' to '$($chosen.Display)'? Confirm the file and name match the vendor instructions for this exact system.",
                'Copy BIOS file', 'OKCancel', 'Question', 'Button2')
            if ($confirm -ne 'OK') { return }
            $found = @(Get-UsbVolumes | Where-Object { $_.Letter -eq $chosen.Letter -and $_.Disk -eq $chosen.Disk -and $_.Partition -eq $chosen.Partition })
            if ($found.Count -ne 1) { throw 'The selected USB drive changed. Select it again.' }
            [IO.File]::Copy($inputPath, $path, $false)
            [void][Windows.Forms.MessageBox]::Show($parent, "Copied to $path. Eject the drive and follow the vendor's flashing instructions.", 'BIOS USB file copied')
        } finally { $dialog.Dispose() }
    } catch { [void][Windows.Forms.MessageBox]::Show($parent, $_.Exception.Message, 'BIOS USB preparation') }
}

function Show-BiosGuide {
    if (!$script:settings.Bios) { return }
    $board = $script:snapshot.Inventory | Where-Object Kind -eq 'BIOS' | Select-Object -First 1
    $system = $script:snapshot.Inventory | Where-Object Kind -eq 'System' | Select-Object -First 1
    if (!$board) { Show-Message 'Run Check for updates to identify the BIOS and system.'; return }
    $portal = Get-VendorPortal $board $system
    $source = $script:snapshot.Checks | Where-Object Key -eq $board.Key | Select-Object -First 1
    if ($source -and $source.Url) { $portal = $source.Url }
    $savedSource = $script:settings.Sources | Where-Object Key -eq $board.Key | Select-Object -First 1
    if ($savedSource) { $portal = $savedSource.Url }
    $dialog = New-Dialog 'Prepare a BIOS USB drive' 332
    Add-Label $dialog "System: $($system.Manufacturer) $($system.Model) $($system.Part)" 14 38
    Add-Label $dialog "Board: $($board.Manufacturer) $($board.Model) rev $($board.Revision)   |   Installed BIOS: $($board.Current)" 53 43
    Add-Label $dialog '1. Open the official support page. Match the exact PC model or retail motherboard model and physical board revision to the vendor instructions.' 102 45
    Add-Label $dialog '2. Read the release notes for prerequisites and verify the vendor checksum if published. Make sure you can access your BitLocker recovery key if encryption is enabled.' 151 48
    Add-Label $dialog '3. If the vendor specifies USB flashing, use its required file system, extraction and naming steps. The copy button is for vendors that specify copying a file to the USB root.' 204 56
    $open = New-Button 'Open manufacturer support'
    $open.Location = New-Object Drawing.Point(16, 276)
    $open.Enabled = [bool]$portal
    $open.Tag = $portal
    $open.Add_Click({ param($sender, $eventArgs) Open-Link $sender.Tag })
    $copyFile = New-Button 'Copy prepared file to USB'
    $copyFile.Location = New-Object Drawing.Point(252, 276)
    $copyFile.Add_Click({ param($sender, $eventArgs) Copy-FileToBiosUsb $sender.FindForm() })
    $dialog.Controls.AddRange(@($open, $copyFile))
    try { [void]$dialog.ShowDialog($form) } finally { $dialog.Dispose() }
}

function Start-Scan {
    $script:fresh = $false
    $status.Text = 'Checking Windows Update and official manufacturer sources...'
    try {
        $script:job = Start-Job -ArgumentList (Join-Path $PSScriptRoot 'Engine.ps1'), $script:settings -ScriptBlock {
            param($engine, $settings)
            $ErrorActionPreference = 'Stop'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            . $engine
            Invoke-HardwareCheck $settings
        }
        Update-Controls
    } catch { $status.Text = "Could not start the scan. $($_.Exception.Message)" }
}

function Update-Controls {
    $busy = $null -ne $script:job -or $null -ne $script:installer
    foreach ($button in @($scan, $options, $editSource, $openSource)) { $button.Enabled = !$busy }
    $bios.Enabled = !$busy -and [bool]$script:settings.Bios
    $install.Enabled = !$busy -and $script:fresh -and $script:snapshot.WindowsUpdateOK -and @($script:snapshot.Offers | Where-Object { $_ }).Count -gt 0
    $install.BackColor = if ($install.Enabled) { [Drawing.Color]::FromArgb(0, 91, 99) } else { [Drawing.SystemColors]::ControlLight }
    $install.ForeColor = if ($install.Enabled) { [Drawing.Color]::White } else { [Drawing.SystemColors]::GrayText }
}

function Start-DriverInstallation {
    if (!$script:fresh -or $script:job -or $script:installer -or !$script:snapshot.WindowsUpdateOK) { return }
    $offers = @($script:snapshot.Offers)
    if (!$offers.Count) { return }
    $answer = [Windows.Forms.MessageBox]::Show($form,
        "Install $($offers.Count) Windows Update driver package(s) shown in the Windows Update tab? Windows will request administrator approval. Review the results for any restart requirement.",
        'Update all drivers', 'OKCancel', 'Question', 'Button2')
    if ($answer -ne 'OK') { return }
    try {
        $selected = @(
            foreach ($offer in $offers) {
                [pscustomobject]@{ Id = ([guid]$offer.Id).ToString(); Revision = [int]$offer.Revision }
            }
        )
        $json = ConvertTo-Json -InputObject $selected -Compress
        $commands = foreach ($name in 'Get-DriverOfferReasons', 'Get-DriverOffer', 'Search-WindowsDrivers', 'Get-UnambiguousOffers', 'Install-DriverOffers') {
            "function $name {`n$((Get-Item "Function:\$name").ScriptBlock.ToString())`n}"
        }
        $payload = @"
`$ErrorActionPreference = 'Stop'
$($commands -join "`n")
Install-DriverOffers ('$json' | ConvertFrom-Json)
"@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
        if ($encoded.Length -gt 29000) { throw 'Too many updates for this launcher build. Review the offers in Windows Update.' }
        $script:installer = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile', '-STA', '-EncodedCommand', $encoded)
        $script:fresh = $false
        $status.Text = 'Installing drivers. Review the installer results when it finishes.'
        Update-Controls
    } catch { Show-Message $_.Exception.Message }
}

$form = New-Object Windows.Forms.Form
$form.Text = "Hardware Update Launcher $script:LauncherVersion"
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object Drawing.Size(1160, 680)
$form.MinimumSize = New-Object Drawing.Size(870, 500)
$form.AutoScaleMode = 'Dpi'

$layout = New-Object Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.ColumnCount = 1; $layout.RowCount = 5
$layout.Padding = New-Object Windows.Forms.Padding(14, 11, 14, 9)
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 49))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 45))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent', 100))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 87))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 27))
$form.Controls.Add($layout)
$actions = New-Object Windows.Forms.FlowLayoutPanel
$actions.Dock = 'Fill'; $actions.WrapContents = $false; $actions.AutoScroll = $true
$scan = New-Button 'Check for updates'
$install = New-Button 'Update All'
$install.BackColor = [Drawing.Color]::FromArgb(0, 91, 99); $install.ForeColor = [Drawing.Color]::White
$install.FlatStyle = 'Flat'
$editSource = New-Button 'Edit source'
$openSource = New-Button 'Open source'
$bios = New-Button 'BIOS / USB guide'
$options = New-Button 'Settings'
$repoLink = New-Button 'GitHub releases'
$actions.Controls.AddRange(@($scan, $install, $editSource, $openSource, $bios, $options, $repoLink))
$layout.Controls.Add($actions, 0, 0)
$summary = New-Object Windows.Forms.Label
$summary.Dock = 'Fill'
$summary.AutoEllipsis = $true
$layout.Controls.Add($summary, 0, 1)

$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$hardwarePage = New-Object Windows.Forms.TabPage('Hardware and manufacturer sources')
$driverPage = New-Object Windows.Forms.TabPage('Windows Update offers')
$hardware = New-Grid ([ordered]@{ Hardware = 88; Manufacturer = 101; 'Model / device' = 164; Installed = 74; 'Vendor version' = 78; Result = 139 })
$drivers = New-Grid ([ordered]@{ Package = 150; Class = 55; 'Driver date' = 50; Eligibility = 48; Reason = 180 })
$drivers.DefaultCellStyle.WrapMode = 'True'
$drivers.AutoSizeRowsMode = 'AllCells'
$hardwarePage.Controls.Add($hardware)
$driverPage.Controls.Add($drivers)
$tabs.TabPages.AddRange(@($hardwarePage, $driverPage))
$layout.Controls.Add($tabs, 0, 2)

$details = New-Object Windows.Forms.TextBox
$details.Dock = 'Fill'; $details.ReadOnly = $true; $details.Multiline = $true; $details.ScrollBars = 'Vertical'
$layout.Controls.Add($details, 0, 3)
$status = New-Object Windows.Forms.Label
$status.Dock = 'Fill'
$status.Text = if ($startupNotice) { $startupNotice } else { 'Run Check for updates to refresh Windows Update offers and manufacturer versions.' }
$layout.Controls.Add($status, 0, 4)

$scan.Add_Click({ Start-Scan })
$install.Add_Click({ Start-DriverInstallation })
$editSource.Add_Click({ Edit-Source })
$openSource.Add_Click({
    $selected = Get-SelectedRow
    if ($selected -and $selected.Url) { Open-Link $selected.Url }
    else { Show-Message 'Select a hardware row with a manufacturer link, or add one using Edit source.' }
})
$options.Add_Click({ Edit-Settings })
$bios.Add_Click({ Show-BiosGuide })
$repoLink.Add_Click({ Open-Link $script:snapshot.Repository.ReleaseUrl })
$drivers.Add_SelectionChanged({
    if ($drivers.SelectedRows.Count -gt 0 -and !$script:job) {
        $offer = $drivers.SelectedRows[0].Tag
        if ($offer) {
            $reason = if ($offer.Reasons) { @($offer.Reasons) -join ' ' } else { 'Eligible for Update All after confirmation.' }
            $details.Lines = [string[]]@($offer.Title, $reason, "Windows Update class: $($offer.Class)   |   Hardware ID: $($offer.HardwareId)", 'Excluded offers can be reviewed in Windows Update. Manufacturer packages use the hardware tab and Open source.')
        }
    }
})
$hardware.Add_SelectionChanged({
    $selected = Get-SelectedRow
    if ($selected -and !$script:job -and !$script:installer) {
        $row = $selected.Device
        $modelInfo = @("Part number: $($row.Part)", "Revision: $($row.Revision)") -join '   |   '
        $status.Text = $modelInfo.TrimEnd() + $(if ($row.IDs.Count) { "   |   $($row.IDs[0])" })
        if ($selected.Check) {
            $details.Lines = [string[]]@($selected.Check.Status, $selected.Check.Detail, $selected.Check.Url)
        }
    }
})
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    if ($script:job -and $script:job.State -in @('Completed', 'Failed', 'Stopped')) {
        try {
            $result = Receive-Job -Job $script:job -ErrorAction Stop
            if (!$result -or !$result.CapturedAt) { throw 'No inventory was returned.' }
            Save-Json $inventoryPath $result
            $script:snapshot = $result
            $script:fresh = $true
            Refresh-View
            $eligibleCount = @($script:snapshot.Offers | Where-Object { $_ }).Count
            $excludedCount = @($script:snapshot.ExcludedOffers | Where-Object { $_ }).Count
            $status.Text = "Check complete. Windows Update: $eligibleCount eligible, $excludedCount excluded. Manufacturer results are in the hardware tab."
        } catch { $status.Text = "Scan failed. $($_.Exception.Message)" }
        finally {
            Remove-Job -Job $script:job -Force
            $script:job = $null
            Update-Controls
        }
    }
    if ($script:installer) {
        try { $finished = $script:installer.HasExited } catch { $finished = $true }
        if ($finished) {
            $script:installer.Dispose()
            $script:installer = $null
            Update-Controls
            $status.Text = 'Installation process ended. Run Check for updates to refresh the inventory.'
        }
    }
})
$form.Add_Shown({
    if ($SmokeTest) {
        if ($env:HARDWARE_LAUNCHER_TEST_PREVIEW) {
            $previewPath = $env:HARDWARE_LAUNCHER_TEST_PREVIEW
            $bitmap = [Drawing.Bitmap]::new($form.Width, $form.Height)
            try {
                $form.DrawToBitmap($bitmap, [Drawing.Rectangle]::new(0, 0, $form.Width, $form.Height))
                $bitmap.Save(($previewPath + '-hardware.png'), [Drawing.Imaging.ImageFormat]::Png)
                $tabs.SelectedTab = $driverPage
                [Windows.Forms.Application]::DoEvents()
                $form.DrawToBitmap($bitmap, [Drawing.Rectangle]::new(0, 0, $form.Width, $form.Height))
                $bitmap.Save(($previewPath + '-offers.png'), [Drawing.Imaging.ImageFormat]::Png)
            } finally { $bitmap.Dispose() }
        }
        $script:smokeResult = [pscustomobject]@{
            Version = $script:LauncherVersion
            Visible = $form.Visible
            HardwareRows = $hardware.Rows.Count
            DriverRows = $drivers.Rows.Count
            ExcludedDriverRows = @($script:snapshot.ExcludedOffers | Where-Object { $_ }).Count
            Summary = $summary.Text
            BiosEnabled = $bios.Enabled
            UpdateAllEnabled = $install.Enabled
            Is64BitProcess = [Environment]::Is64BitProcess
            ApartmentState = [string][Threading.Thread]::CurrentThread.GetApartmentState()
            ScanStarted = $null -ne $script:job
            FreshUpdateAllEnabled = $false
        }
        $script:fresh = $true
        Update-Controls
        $script:smokeResult.FreshUpdateAllEnabled = $install.Enabled
        $form.Close()
        return
    }
    $timer.Start()
    Start-Scan
})
$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:installer) { $eventArgs.Cancel = $true }
})
try {
    Refresh-View
    Update-Controls
    [void]$form.ShowDialog()
    if ($SmokeTest) { $script:smokeResult | ConvertTo-Json -Compress }
} finally {
    $timer.Stop()
    if ($script:job) { Remove-Job -Job $script:job -Force }
    $timer.Dispose()
    $form.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
