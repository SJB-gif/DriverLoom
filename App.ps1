param([switch]$SmokeTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot 'Engine.ps1')
. (Join-Path $PSScriptRoot 'Install.ps1')
. (Join-Path $PSScriptRoot 'Theme.ps1')

$mutexName = if ($SmokeTest) { 'Local\HardwareUpdateLauncher-Smoke-' + [guid]::NewGuid().ToString('N') } else { 'Local\HardwareUpdateLauncher' }
$mutex = [Threading.Mutex]::new($false, $mutexName)
try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
if (!$acquired) {
    [void][Windows.Forms.MessageBox]::Show('DriverLoom is already open.', 'DriverLoom')
    $mutex.Dispose()
    return
}

$directory = Join-Path $env:LOCALAPPDATA 'HardwareUpdateLauncher'
$settingsPath = Join-Path $directory 'settings.json'
$inventoryPath = Join-Path $directory 'inventory.json'
[void][IO.Directory]::CreateDirectory($directory)

$script:settings = [pscustomobject]@{ Repo = ''; Bios = $false; Sources = @(); Theme = 'Dark'; ShowUnsupported = $false }
$startupNotice = ''
if (Test-Path -LiteralPath $settingsPath) {
    try {
        $saved = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        if ($null -eq $saved -or $saved.Bios -isnot [bool] -or ($saved.Repo -and $saved.Repo -notmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$')) { throw 'Invalid settings.' }
        $script:settings = $saved
    } catch { $startupNotice = 'Settings could not be loaded. Edit settings to save a replacement.' }
}
if (!$script:settings.PSObject.Properties['Theme']) { $script:settings | Add-Member NoteProperty Theme 'Dark' }
if ($script:settings.Theme -notin 'Dark','Light','System') { $script:settings.Theme='Dark' }
if (!$script:settings.PSObject.Properties['ShowUnsupported']) { $script:settings | Add-Member NoteProperty ShowUnsupported $false }
if ($script:settings.ShowUnsupported -isnot [bool]) { $script:settings.ShowUnsupported=$false }
Set-AppTheme $script:settings.Theme
$script:snapshot = $null
if (Test-Path -LiteralPath $inventoryPath) {
    try { $script:snapshot = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json } catch { }
}
$script:job = $null
$script:installer = $null
$script:fresh = $false
$script:applyAfterScan = $false
$script:lastScanError = ''
$script:unsupportedRows = @()
$script:hiddenWindowsCount = 0

function Show-Message([string]$message) {
    $dialog=New-Dialog 'DriverLoom' 340
    Add-Label $dialog 'DRIVERLOOM' 20
    $content=Add-TextInput $dialog $message 58
    $content.Multiline=$true; $content.ReadOnly=$true; $content.ScrollBars='Vertical'; $content.SetBounds(24,58,617,206)
    $done=New-Button 'Done';$done.SetBounds(531,282,110,36);$done.DialogResult='OK';$dialog.Controls.Add($done);$dialog.AcceptButton=$done
    try{[void]$dialog.ShowDialog($form)}finally{$dialog.Dispose()}
}

function New-Button([string]$label) {
    $button = [DriverLoom.UI.ActionButton]::new()
    $button.Text = $label
    $button.AutoSize = $true
    $button.Padding = New-Object Windows.Forms.Padding(9, 2, 9, 2)
    $button.Font=[Drawing.Font]::new('Segoe UI',9,[Drawing.FontStyle]::Bold)
    [DriverLoom.UI.Theme]::Apply($button)
    return $button
}

function Open-Link([string]$link) {
    try { Start-Process -FilePath (Get-HttpsUri $link).AbsoluteUri }
    catch { Show-Message $_.Exception.Message }
}

function Open-WindowsUpdate {
    try { Start-Process -FilePath 'ms-settings:windowsupdate' }
    catch { Show-Message $_.Exception.Message }
}

function Get-GridCopyText($grid, [string]$title) {
    $columns=@($grid.Columns | Where-Object Visible | Sort-Object DisplayIndex)
    $lines=[System.Collections.Generic.List[string]]::new()
    $lines.Add("DriverLoom $script:LauncherVersion - $title")
    $lines.Add(($columns.HeaderText -join "`t"))
    foreach($row in $grid.Rows) {
        if($row.IsNewRow -or !$row.Visible){continue}
        $values=foreach($column in $columns){([string]$row.Cells[$column.Index].Value) -replace '[\r\n\t]+',' '}
        $lines.Add(($values -join "`t"))
    }
    return $lines -join "`r`n"
}

function Add-ListActions($dialog, $grid, [string]$title) {
    $top=$dialog.ClientSize.Height-58
    $copy=New-Button 'Copy list';$copy.SetBounds(24,$top,142,34);$copy.Enabled=$grid.Rows.Count -gt 0
    $feedback=[Windows.Forms.Label]::new();$feedback.Tag='Muted';$feedback.SetBounds(418,$top,410,34);$feedback.TextAlign='MiddleLeft'
    $copy.Tag=[pscustomobject]@{Grid=$grid;Title=$title;Feedback=$feedback}
    $copy.Add_Click({param($sender,$eventArgs)
        try{[Windows.Forms.Clipboard]::SetText((Get-GridCopyText $sender.Tag.Grid $sender.Tag.Title));$sender.Tag.Feedback.Text='Copied to clipboard.'}
        catch{$sender.Tag.Feedback.Text='Clipboard is busy. Please try again.'}
    })
    $windowsUpdate=New-Button 'Open Windows Update';$windowsUpdate.SetBounds(178,$top,228,34);$windowsUpdate.Add_Click({Open-WindowsUpdate})
    $done=New-Button 'Done';$done.SetBounds(846,$top,110,34);$done.DialogResult='Cancel'
    $dialog.Controls.AddRange(@($copy,$windowsUpdate,$feedback,$done));$dialog.CancelButton=$done
}

function New-Grid([System.Collections.IDictionary]$columns) {
    $grid = [DriverLoom.UI.DeviceGrid]::new()
    $grid.Dock = 'Fill'
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.ReadOnly = $true
    $grid.MultiSelect = $false
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.AutoSizeColumnsMode = 'Fill'
    foreach ($name in $columns.Keys) {
        $index = $grid.Columns.Add($name, $name)
        $grid.Columns[$index].FillWeight = $columns[$name]
        $grid.Columns[$index].HeaderText=$name.ToUpperInvariant()
    }
    [DriverLoom.UI.Theme]::Apply($grid)
    return ,$grid
}

function Get-SelectedRow {
    if ($hardware.SelectedRows.Count -gt 0 -and $hardware.SelectedRows[0].Tag.Device) { return $hardware.SelectedRows[0].Tag }
}

function Refresh-View {
    $hardware.Rows.Clear()
    $script:unsupportedRows = @()
    if (!$script:snapshot) { return }
    $checks = @{}
    foreach ($check in @($script:snapshot.Checks)) { if ($check) { $checks["$($check.Key)|$($check.Current)"] = $check } }
    $orderedInventory = @($script:snapshot.Inventory | Sort-Object @{ Expression = {
        $itemCheck = $checks["$($_.Key)|$($_.Current)"]
        if ($itemCheck.Status -eq 'Newer at source') { 0 } elseif ($itemCheck.Checked) { 1 } else { 2 }
    } }, Kind, Model)
    $hiddenWindows = 0
    $unsupported = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $orderedInventory) {
        if (!$row -or ($row.Kind -eq 'BIOS' -and !$script:settings.Bios)) { continue }
        $check = $checks["$($row.Key)|$($row.Current)"]
        $mode = Get-CoverageMode $row $check
        if ($mode -eq 'Windows') { $hiddenWindows++; continue }
        if ($mode -in 'Identity', 'Package component') { continue }
        if ($mode -eq 'Unsupported') {
            $route = Get-OfficialSupportRoute $row $script:snapshot.Inventory
            $item=[pscustomobject]@{ Device=$row.Model; Manufacturer=Get-HardwareVendor $row; Reason=if($check.Detail){$check.Detail}else{$route.Reason}; Url=if($check.Url){$check.Url}else{$route.Url}; Hardware=$row }
            $unsupported.Add($item)
            if(!$script:settings.ShowUnsupported){continue}
            $check=[pscustomobject]@{Status='Unsupported';Detail=$item.Reason;Url=$item.Url;Available='';Checked=$false}
        }
        $name = if ($row.Kind -eq 'GPU software' -and $row.Part) { $row.Model + ' - ' + $row.Part } else { $row.Model }
        $action = if ($mode -eq 'Unsupported') { 'Support details' } elseif ($check.Status -eq 'Newer at source') { 'Review update' } else { 'Vendor details' }
        $i = $hardware.Rows.Add(@($name, $row.Current, $check.Available, (Get-DisplayStatus $check.Status), $action))
        $hardware.Rows[$i].Tag = [pscustomobject]@{ Device=$row; Url=$check.Url; Check=$check }
        $hardware.Rows[$i].Cells['Device'].Tag=(Get-HardwareVendor $row)+'  /  '+$row.Kind
        $hardware.Rows[$i].Cells['Device'].ToolTipText=$name
        $hardware.Rows[$i].Cells['Status'].ToolTipText=$check.Status+"`r`n"+$check.Detail
        $hardware.Rows[$i].Cells['Source'].Tag='Link'
    }
    $script:unsupportedRows = $unsupported.ToArray()
    $script:hiddenWindowsCount = $hiddenWindows
    foreach ($offer in @($script:snapshot.Offers | Where-Object { $_ })) {
        $i = $hardware.Rows.Add(@($offer.Title, '', '', 'READY TO INSTALL', 'In update queue'))
        $hardware.Rows[$i].Tag = [pscustomobject]@{ Offer=$offer; Url=''; Check=$null; Device=$null }
        $hardware.Rows[$i].Cells['Device'].Tag='Microsoft  /  Windows Update'
        $hardware.Rows[$i].Cells['Device'].ToolTipText=$offer.Title
    }
    Update-Footer


}

function Show-UnsupportedItems([switch]$Preview) {
    $dialog = New-Dialog 'Unsupported items | DriverLoom' 530
    $dialog.ClientSize = [Drawing.Size]::new(980,530)
    Add-DialogHeading $dialog 'Unsupported items' 'These devices need a manufacturer utility or an exact supported source. Right-click to edit a source.'
    $grid = New-Grid ([ordered]@{ Device=140; Manufacturer=65; Reason=230 })
    foreach ($item in $script:unsupportedRows) {
        $i = $grid.Rows.Add(@($item.Device,$item.Manufacturer,$item.Reason))
        $grid.Rows[$i].Tag=$item
        $grid.Rows[$i].Cells['Reason'].ToolTipText = $item.Reason
    }
    $grid.DefaultCellStyle.WrapMode='True'; $grid.AutoSizeRowsMode='AllCells'
    $context=[Windows.Forms.ContextMenuStrip]::new()
    $edit=[Windows.Forms.ToolStripMenuItem]::new('Edit official source...')
    $edit.Add_Click({if($grid.SelectedRows.Count -gt 0){$item=$grid.SelectedRows[0].Tag;Edit-Source ([pscustomobject]@{Device=$item.Hardware;Url=$item.Url;Check=$null})}})
    [void]$context.Items.Add($edit); $grid.ContextMenuStrip=$context
    $context.Renderer=[DriverLoom.UI.MenuRenderer]::new()
    $hostPanel=[Windows.Forms.Panel]::new();$hostPanel.SetBounds(24,104,932,340);$hostPanel.Controls.Add($grid);$dialog.Controls.Add($hostPanel)
    Add-ListActions $dialog $grid 'Unsupported items'
    if($Preview){$dialog.Add_Shown({Save-FormPreview $dialog 'unsupported';$dialog.Close()})}
    try { [void]$dialog.ShowDialog($form) } finally { $dialog.Dispose(); $context.Dispose() }
}

function Show-WindowsExclusions([switch]$Preview) {
    $dialog = New-Dialog 'Windows Update exclusions | DriverLoom' 490
    $dialog.ClientSize = [Drawing.Size]::new(980,490)
    Add-DialogHeading $dialog 'Windows Update exclusions' 'These offers are outside the automatic installation rules. Their reasons are listed below.'
    $grid = New-Grid ([ordered]@{ Package=170; Class=60; Reason=240 })
    foreach ($offer in @($script:snapshot.ExcludedOffers | Where-Object { $_ })) { [void]$grid.Rows.Add(@($offer.Title,$offer.Class,(@($offer.Reasons)-join ' '))) }
    $grid.DefaultCellStyle.WrapMode='True'; $grid.AutoSizeRowsMode='AllCells'
    $hostPanel=[Windows.Forms.Panel]::new();$hostPanel.SetBounds(24,104,932,300);$hostPanel.Controls.Add($grid);$dialog.Controls.Add($hostPanel)
    Add-ListActions $dialog $grid 'Windows Update exclusions'
    if($Preview){$dialog.Add_Shown({Save-FormPreview $dialog 'exclusions';$dialog.Close()})}
    try { [void]$dialog.ShowDialog($form) } finally { $dialog.Dispose() }
}

function New-Dialog([string]$title, [int]$height) {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = $title
    $dialog.Font = $form.Font
    $dialog.StartPosition = 'CenterParent'
    $dialog.ClientSize = New-Object Drawing.Size(665, $height)
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MinimizeBox = $false; $dialog.MaximizeBox = $false
    $dialog.Icon=$form.Icon
    $dialog.AutoScaleMode='Dpi'
    $dialog.Add_Shown({param($sender,$eventArgs) [DriverLoom.UI.Theme]::Apply($sender)})
    [DriverLoom.UI.Theme]::Apply($dialog)
    return $dialog
}

function Add-Label($parent, [string]$text, [int]$top, [int]$height = 25) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $text
    $label.SetBounds(16, $top, 625, $height)
    $label.ForeColor=[DriverLoom.UI.Palette]::Text
    $parent.Controls.Add($label)
}

function Add-TextInput($parent, [string]$value, [int]$top) {
    $box = New-Object Windows.Forms.TextBox
    $box.Text = $value
    $box.SetBounds(16, $top, 625, 27)
    [DriverLoom.UI.Theme]::Apply($box)
    $parent.Controls.Add($box)
    return $box
}

function Edit-Source($selection = $null) {
    $selected = if($selection){$selection}else{Get-SelectedRow}
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
        $next = [pscustomobject]@{ Repo = $script:settings.Repo; Bios = $script:settings.Bios; Sources = $sources; Theme=$script:settings.Theme }
        Save-Json $settingsPath $next
        $script:settings = $next
        if ($script:snapshot) { $script:snapshot.Checks = @($script:snapshot.Checks | Where-Object { $_ -and $_.Key -ne $device.Key }) }
        Refresh-View
        $status.Text = 'Source saved. Run Check for updates to read the page.'
    } catch { Show-Message $_.Exception.Message }
    finally { $dialog.Dispose() }
}

function Edit-Settings([switch]$Preview) {
    $dialog = New-Dialog 'Settings | DriverLoom' 618
    $dialog.ClientSize=[Drawing.Size]::new(940,618)
    Add-DialogHeading $dialog 'Settings' "DRIVERLOOM $script:LauncherVersion  /  MAKE IT YOURS"
    $appearance=Add-SettingsCard $dialog 'APPEARANCE' 24 110 432 142
    $appearanceText=[Windows.Forms.Label]::new();$appearanceText.Text='Choose how DriverLoom looks.';$appearanceText.SetBounds(18,48,390,26);$appearance.Controls.Add($appearanceText)
    $themeButtons=@();$themeIndex=0
    foreach($choice in @(@('System','Match system'),@('Dark','Dark'),@('Light','Light'))){
        $radio=[Windows.Forms.RadioButton]::new();$radio.Appearance='Button';$radio.Text=$choice[1];$radio.Tag=$choice[0];$radio.TextAlign='MiddleCenter';$radio.Font=[Drawing.Font]::new('Segoe UI',9,[Drawing.FontStyle]::Bold);$radio.SetBounds((18+132*$themeIndex),84,130,32)
        $radio.Checked=$script:settings.Theme -eq $choice[0]
        $radio.Add_CheckedChanged({param($sender,$eventArgs)[DriverLoom.UI.Theme]::Apply($sender.Parent)})
        $appearance.Controls.Add($radio);$themeButtons+=$radio;$themeIndex++
    }
    $updates=Add-SettingsCard $dialog 'UPDATES' 24 268 432 114
    $updateText=[Windows.Forms.Label]::new();$updateText.Text='Checks run automatically when DriverLoom opens.';$updateText.SetBounds(18,44,394,24);$updates.Controls.Add($updateText)
    $windowsUpdate=New-Button 'Open Windows Update';$windowsUpdate.SetBounds(18,74,394,30);$windowsUpdate.Add_Click({Open-WindowsUpdate});$updates.Controls.Add($windowsUpdate)
    $firmware=Add-SettingsCard $dialog 'BIOS & FIRMWARE' 24 398 432 142
    $biosBox = New-Object Windows.Forms.CheckBox
    $biosBox.Text = 'Enable BIOS checks and the USB guide'
    $biosBox.Checked = [bool]$script:settings.Bios
    $biosBox.SetBounds(18,44,394,30);$firmware.Controls.Add($biosBox)
    $biosGuide=New-Button 'Open USB guide';$biosGuide.SetBounds(18,86,178,34);$biosGuide.Enabled=[bool]$script:settings.Bios
    $biosGuide.Add_Click({Show-BiosGuide});$firmware.Controls.Add($biosGuide)
    $coverage=Add-SettingsCard $dialog 'CHECK COVERAGE' 476 110 440 236
    $coverageText=[Windows.Forms.Label]::new();$coverageText.Text='Windows components stay hidden. Review devices and Windows Update offers that need a manual step.';$coverageText.SetBounds(18,44,404,46);$coverage.Controls.Add($coverageText)
    $showUnsupported=[Windows.Forms.CheckBox]::new();$showUnsupported.Text='Show unsupported devices in the hardware list';$showUnsupported.Checked=$script:settings.ShowUnsupported;$showUnsupported.SetBounds(18,94,404,28);$coverage.Controls.Add($showUnsupported)
    $unsupportedButton=New-Button ("Unsupported items ($($script:unsupportedRows.Count))")
    $unsupportedButton.SetBounds(18,132,404,32);$unsupportedButton.Add_Click({Show-UnsupportedItems})
    $excludedCount=@($script:snapshot.ExcludedOffers|Where-Object{$_}).Count
    $excludedButton=New-Button ("Windows Update exclusions ($excludedCount)")
    $excludedButton.SetBounds(18,172,404,32);$excludedButton.Add_Click({Show-WindowsExclusions})
    $coverage.Controls.AddRange(@($unsupportedButton,$excludedButton))
    $advanced=Add-SettingsCard $dialog 'ADVANCED SOURCES' 476 362 440 178
    $catalogLabel=[Windows.Forms.Label]::new();$catalogLabel.Text='Optional public GitHub catalog (owner/repository)';$catalogLabel.SetBounds(18,46,404,26);$advanced.Controls.Add($catalogLabel)
    $repoBox=[Windows.Forms.TextBox]::new();$repoBox.Text=$script:settings.Repo;$repoBox.SetBounds(18,78,404,29);$advanced.Controls.Add($repoBox)
    $editButton=New-Button 'Edit selected device source';$editButton.SetBounds(18,122,404,34);$editButton.Enabled=[bool](Get-SelectedRow);$editButton.Add_Click({Edit-Source});$advanced.Controls.Add($editButton)
    $save = New-Button 'Save changes';$save.Primary=$true
    $save.SetBounds(762,566,154,36)
    $save.DialogResult = 'OK'
    $cancel=New-Button 'Cancel';$cancel.SetBounds(644,566,100,36);$cancel.DialogResult='Cancel'
    $footer=[Windows.Forms.Label]::new();$footer.Text='Your preferences are saved on this PC.';$footer.Tag='Muted';$footer.SetBounds(24,575,590,25)
    $aboutButton=New-Button 'About';$aboutButton.SetBounds(24,566,80,36);$aboutButton.Add_Click({Show-About})
    $helpButton=New-Button 'Help';$helpButton.SetBounds(116,566,80,36);$helpButton.Add_Click({Show-Help})
    $footer.Visible=$false
    $dialog.Controls.AddRange(@($save,$cancel,$footer,$aboutButton,$helpButton))
    $dialog.AcceptButton = $save
    $dialog.CancelButton=$cancel
    if($Preview){$dialog.Add_Shown({Save-FormPreview $dialog 'settings';$dialog.Close()})}
    try {
        if ($dialog.ShowDialog($form) -ne 'OK') { return }
        $repo = $repoBox.Text.Trim()
        if ($repo -and ($repo -notmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$' -or $repo -match '(^|/)\.{1,2}(/|$)')) { throw 'Use owner/repository.' }
        $preference=[string]($themeButtons|Where-Object Checked|Select-Object -First 1).Tag
        $next = [pscustomobject]@{ Repo = $repo; Bios = $biosBox.Checked; Sources = @($script:settings.Sources); Theme=$preference; ShowUnsupported=$showUnsupported.Checked }
        Save-Json $settingsPath $next
        if ($script:snapshot -and $script:settings.Repo -ne $repo) {
            $script:snapshot.Repository = $null
            $script:snapshot.Checks = @()
        }
        $script:settings = $next
        Set-AppTheme $preference $form
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
    if ($script:job -or $script:installer) { return }
    $script:fresh = $false
    $script:lastScanError = ''
    try {
        $script:job = Start-Job -ArgumentList (Join-Path $PSScriptRoot 'Engine.ps1'), $script:settings -ScriptBlock {
            param($engine, $settings)
            $ErrorActionPreference = 'Stop'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            . $engine
            Invoke-HardwareCheck $settings
        }
    } catch { $script:lastScanError=$_.Exception.Message }
    Update-Controls
}

function Update-Footer {
    $caption=Get-CheckCaption $script:snapshot.CapturedAt
    $state=if($script:job){'CHECKING'}elseif($script:installer){'UPDATING'}elseif($script:lastScanError){'CHECK FAILED - USE REFRESH'}else{$caption}
    $status.Text=$state+'  '+[char]0x00B7+'  USING WINDOWS UPDATE & MANUFACTURER SOURCES'
    $tooltips.SetToolTip($status,($script:lastScanError+(@($script:snapshot.Warnings)-join "`r`n")))
    if($repoButton){$repoButton.Image=if([DriverLoom.UI.Palette]::Dark){$githubLight}else{$githubDark}}
}

function Update-Controls {
    $busy = $null -ne $script:job -or $null -ne $script:installer
    $action=Get-UpdateAction $script:snapshot $script:fresh $busy
    $primary.Visible=$action.Visible -or $null -ne $script:installer
    $primary.Enabled=$action.Enabled
    $primary.Text=if($script:installer){'Updating...'}else{'Update All'}
    $refresh.Enabled=!$busy
    $settingsMenu.Enabled=!$busy
    Update-Footer
}

function Show-UpdateReview([switch]$Preview) {
    if(!$script:fresh){return}
    $dialog=New-Dialog 'Available updates | DriverLoom' 490
    $dialog.ClientSize=[Drawing.Size]::new(980,490)
    Add-DialogHeading $dialog 'Available updates' 'Windows Update drivers can be installed together. Vendor packages require review on their official pages.'
    $grid=New-Grid ([ordered]@{Device=210;Available=80;Method=160;Source=90})
    $grid.DefaultCellStyle.WrapMode='True';$grid.AutoSizeRowsMode='AllCells';$grid.RowTemplate.MinimumHeight=42
    $grid.Columns.Remove('Source')
    $link=[Windows.Forms.DataGridViewLinkColumn]::new();$link.Name='Source';$link.HeaderText='ACTION';$link.FillWeight=90
    $link.LinkColor=[DriverLoom.UI.Palette]::Accent;$link.ActiveLinkColor=$link.LinkColor;$link.VisitedLinkColor=$link.LinkColor
    [void]$grid.Columns.Add($link)
    foreach($check in @($script:snapshot.Checks|Where-Object Status -eq 'Newer at source')){
        $device=$script:snapshot.Inventory|Where-Object Key -eq $check.Key|Select-Object -First 1
        $i=$grid.Rows.Add(@($device.Model,$check.Available,'Manual vendor installation','Review update'))
        $grid.Rows[$i].Tag=$check.Url
    }
    foreach($offer in @($script:snapshot.Offers|Where-Object{$_})){
        [void]$grid.Rows.Add(@($offer.Title,'','Install through Windows Update','In update queue'))
    }
    $grid.Add_CellContentClick({param($sender,$eventArgs)if($eventArgs.RowIndex -ge 0 -and $eventArgs.ColumnIndex -eq 3 -and $sender.Rows[$eventArgs.RowIndex].Tag){Open-Link $sender.Rows[$eventArgs.RowIndex].Tag}})
    $hostPanel=[Windows.Forms.Panel]::new();$hostPanel.SetBounds(24,104,932,310);$hostPanel.Controls.Add($grid);$dialog.Controls.Add($hostPanel)
    $install=New-Button 'Install Windows drivers';$install.Primary=$true;$install.SetBounds(710,436,246,36);$install.DialogResult='OK'
    $install.Enabled=Test-CanInstallSnapshot $script:snapshot $script:fresh $false
    if(!$install.Enabled){$install.Text='Vendor review required';$install.DialogResult='None'}
    $done=New-Button 'Done';$done.SetBounds(590,436,104,36);$done.DialogResult='Cancel'
    $dialog.Controls.AddRange(@($install,$done));$dialog.CancelButton=$done
    if($Preview){$dialog.Add_Shown({Save-FormPreview $dialog 'updates';$dialog.Close()})}
    try{$result=$dialog.ShowDialog($form)}finally{$dialog.Dispose()}
    if($result -eq 'OK'){Start-DriverInstallation}
}

function Show-DeviceDetails {
    $selected=Get-SelectedRow
    if($selected.Check){Show-Message ($selected.Device.Model+"`r`n`r`n"+$selected.Check.Status+"`r`n"+$selected.Check.Detail+"`r`n`r`n"+$selected.Check.Url)}
}

function Show-About {
    $identity=@($script:snapshot.Inventory|Where-Object Kind -in 'System','Motherboard','CPU','RAM'|ForEach-Object {$_.Kind+': '+$_.Model})
    Show-Message ("DriverLoom $script:LauncherVersion`r`nHardware updates, brought together.`r`nMIT-licensed Windows 10/11 x64 utility.`r`n`r`n"+($identity -join "`r`n"))
}

function Show-Help {
    Show-Message "DriverLoom checks automatically when it opens. Use the refresh arrow to check again.`r`n`r`nUpdate All appears when a fresh check finds updates. It opens a review list; eligible Windows Update drivers can then be installed together. Manufacturer packages use official Review update links.`r`n`r`nDouble-click a device for source details. Unsupported items, excluded offers, About and Help are in Settings. Firmware flashing and reboots are never automatic."
}

function Start-DriverInstallation {
    if (!(Test-CanInstallSnapshot $script:snapshot $script:fresh ($script:job -or $script:installer))) { return }
    $offers = @($script:snapshot.Offers)
    if (!$offers.Count) { return }
    $answer = [Windows.Forms.MessageBox]::Show($form,
        "Install $($offers.Count) supported Windows Update driver package(s)? Excluded offers and manufacturer packages requiring manual review are not included. Windows will request administrator approval. Review the results for any restart requirement.",
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
        $script:installer = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile', '-STA', '-EncodedCommand', $encoded)
        $script:fresh = $false
        $status.Text = 'Installing drivers. Review the installer results when it finishes.'
        Update-Controls
    } catch { Show-Message $_.Exception.Message }
}

$form = [DriverLoom.UI.MainWindow]::new()
$form.Add_HandleCreated({param($sender,$eventArgs)if('DriverLoom.ShellIdentity' -as [type]){[DriverLoom.ShellIdentity]::BindWindow($sender.Handle)}})
$form.Text = "DriverLoom $script:LauncherVersion"
$form.Icon=[Drawing.Icon]::new((Join-Path $PSScriptRoot 'assets\DriverLoom-loops.ico'))
$form.Font=[Drawing.Font]::new('Segoe UI',10)
$form.StartPosition='CenterScreen';$form.ClientSize=[Drawing.Size]::new(1240,850);$form.MinimumSize=[Drawing.Size]::new(1040,660);$form.AutoScaleMode='Dpi'
$tooltips=[Windows.Forms.ToolTip]::new()
$header=[DriverLoom.UI.TitleBar]::new();$header.Dock='Top'
$header.Artwork=[Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'assets\DriverLoom-brand.png'))
$chrome=[Windows.Forms.FlowLayoutPanel]::new();$chrome.Dock='Right';$chrome.Width=196;$chrome.WrapContents=$false;$chrome.Margin=[Windows.Forms.Padding]::new(0)
$settingsMenu=[DriverLoom.UI.IconButton]::new();$settingsMenu.Glyph='Settings';$settingsMenu.AccessibleName='Settings'
$minimize=[DriverLoom.UI.IconButton]::new();$minimize.Glyph='Minimize';$minimize.AccessibleName='Minimize'
$maximize=[DriverLoom.UI.IconButton]::new();$maximize.Glyph='Maximize';$maximize.AccessibleName='Maximize or restore'
$close=[DriverLoom.UI.IconButton]::new();$close.Glyph='Close';$close.AccessibleName='Close'
foreach($button in @($settingsMenu,$minimize,$maximize,$close)){$button.Chrome=$true;$button.Size=[Drawing.Size]::new(48,55);$button.Margin=[Windows.Forms.Padding]::new(0);$chrome.Controls.Add($button);$tooltips.SetToolTip($button,$button.AccessibleName)}
$header.Controls.Add($chrome)
$minimize.Add_Click({$form.WindowState='Minimized'})
$maximize.Add_Click({$form.WindowState=if($form.WindowState -eq 'Maximized'){'Normal'}else{'Maximized'}})
$close.Add_Click({$form.Close()})
$layout=[Windows.Forms.TableLayoutPanel]::new();$layout.Dock='Fill';$layout.ColumnCount=1;$layout.RowCount=2;$layout.Padding=[Windows.Forms.Padding]::new(24,10,24,0)
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',66));[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100))
$form.Controls.Add($layout)
$toolbar=[Windows.Forms.TableLayoutPanel]::new();$toolbar.Dock='Fill';$toolbar.ColumnCount=3;$toolbar.RowCount=1
[void]$toolbar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',42));[void]$toolbar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100));[void]$toolbar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',168))
$refresh=[DriverLoom.UI.IconButton]::new();$refresh.Glyph='Refresh';$refresh.AccessibleName='Check for updates';$refresh.Size=[Drawing.Size]::new(32,36);$refresh.Margin=[Windows.Forms.Padding]::new(0,12,0,0);$toolbar.Controls.Add($refresh,0,0);$tooltips.SetToolTip($refresh,'Check for updates')
$title=[Windows.Forms.Label]::new();$title.Text='Your hardware';$title.Font=[Drawing.Font]::new('Segoe UI',18,[Drawing.FontStyle]::Bold);$title.Dock='Fill';$title.TextAlign='MiddleLeft';$toolbar.Controls.Add($title,1,0)
$primary=New-Button 'Update All';$primary.Primary=$true;$primary.AutoSize=$false;$primary.Size=[Drawing.Size]::new(162,36);$primary.Margin=[Windows.Forms.Padding]::new(0,14,0,0);$toolbar.Controls.Add($primary,2,0)
$form.AcceptButton=$primary
$layout.Controls.Add($toolbar,0,0)
$hardware=New-Grid ([ordered]@{Device=220;Installed=76;Available=76;Status=130;Source=96})
$hardware.Decorated=$true;$hardware.RowTemplate.Height=70;$hardware.Columns['Status'].DisplayIndex=1
$hardware.Columns['Installed'].DefaultCellStyle.Font=[Drawing.Font]::new('Consolas',10);$hardware.Columns['Available'].DefaultCellStyle.Font=[Drawing.Font]::new('Consolas',10)
$hardware.Columns.Remove('Source');$sourceColumn=[Windows.Forms.DataGridViewButtonColumn]::new();$sourceColumn.FlatStyle='Flat';$sourceColumn.Name='Source';$sourceColumn.HeaderText='ACTION';$sourceColumn.FillWeight=96;[void]$hardware.Columns.Add($sourceColumn)
$hardware.DefaultCellStyle.WrapMode='False';$hardware.AutoSizeRowsMode='None';$layout.Controls.Add($hardware,0,1)
$footer=[Windows.Forms.TableLayoutPanel]::new();$footer.Dock='Bottom';$footer.Height=36;$footer.ColumnCount=2;$footer.RowCount=1;$footer.Padding=[Windows.Forms.Padding]::new(22,0,15,0)
[void]$footer.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100));[void]$footer.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',34))
$status=[Windows.Forms.Label]::new();$status.Dock='Fill';$status.Tag='Muted';$status.AutoEllipsis=$true;$status.TextAlign='MiddleLeft';$status.Font=[Drawing.Font]::new('Consolas',8.5,[Drawing.FontStyle]::Bold);$footer.Controls.Add($status,0,0)
$githubLight=[Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'assets\GitHub-light.png'));$githubDark=[Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'assets\GitHub-dark.png'))
$repoButton=[DriverLoom.UI.IconButton]::new();$repoButton.Glyph='GitHub';$repoButton.Dock='Fill';$repoButton.AccessibleName='Open DriverLoom source on GitHub';$footer.Controls.Add($repoButton,1,0);$tooltips.SetToolTip($repoButton,'DriverLoom on GitHub')
$footer.Add_Paint({param($sender,$eventArgs)$pen=[Drawing.Pen]::new([DriverLoom.UI.Palette]::Border);try{$eventArgs.Graphics.DrawLine($pen,0,0,$sender.Width,0)}finally{$pen.Dispose()}})
$form.Controls.Add($footer);$form.Controls.Add($header)
$primary.Add_Click({Show-UpdateReview})
$refresh.Add_Click({Start-Scan})
$repoButton.Add_Click({Open-Link 'https://github.com/SJB-gif/DriverLoom'})
$settingsMenu.Add_Click({Edit-Settings;Update-Controls})
$hardware.Add_CellContentClick({param($sender,$eventArgs)if($eventArgs.RowIndex -ge 0 -and $eventArgs.ColumnIndex -ge 0 -and $sender.Columns[$eventArgs.ColumnIndex].Name -eq 'Source'){$selected=$sender.Rows[$eventArgs.RowIndex].Tag;if($selected.Url){Open-Link $selected.Url}elseif($selected.Device){Show-DeviceDetails}}})
$hardware.Add_CellDoubleClick({param($sender,$eventArgs)if($eventArgs.RowIndex -ge 0 -and $eventArgs.ColumnIndex -ne $hardware.Columns['Source'].Index){Show-DeviceDetails}})

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    if ($script:job -and $script:job.State -in @('Completed', 'Failed', 'Stopped')) {
        try {
            $result=Receive-Job -Job $script:job -ErrorAction Stop
            if(!$result -or !$result.CapturedAt){throw 'No inventory was returned.'}
            Save-Json $inventoryPath $result
            $script:snapshot=$result;$script:fresh=$true
            Refresh-View
        }catch{$script:lastScanError=$_.Exception.Message}
        finally{Remove-Job -Job $script:job -Force;$script:job=$null;Update-Controls}
    }
    Update-Footer


    if ($script:installer) {
        try { $finished = $script:installer.HasExited } catch { $finished = $true }
        if ($finished) {
            $script:installer.Dispose()
            $script:installer = $null
            Update-Controls
            Start-Scan
        }
    }
})
$form.Add_Shown({
    if ($SmokeTest) {
        if ($env:HARDWARE_LAUNCHER_TEST_PREVIEW) {
            Save-FormPreview $form 'hardware'
            Edit-Settings -Preview
            Show-UnsupportedItems -Preview
            Show-WindowsExclusions -Preview
        }
        $script:smokeResult = [pscustomobject]@{
            Version = $script:LauncherVersion
            Visible = $form.Visible
            HardwareRows = $hardware.Rows.Count
            DriverRows = @($script:snapshot.Offers | Where-Object { $_ }).Count
            ExcludedDriverRows = @($script:snapshot.ExcludedOffers | Where-Object { $_ }).Count
            BiosEnabled = [bool]$script:settings.Bios
            UpdateAllEnabled = Test-CanInstallSnapshot $script:snapshot $script:fresh $false
            UnsupportedCount = $script:unsupportedRows.Count
            ShowUnsupported = $script:settings.ShowUnsupported
            WindowsManagedHidden = $script:hiddenWindowsCount
            MainDevices = @($hardware.Rows | ForEach-Object { $_.Cells[0].Value })
            MainButtonCount = 1
            MainActionText = $primary.Text
            MainActionUsesMnemonic = $primary.UseMnemonic
            MainActionEnabled = $primary.Enabled
            MenuItems = @('Settings')
            Borderless = $form.FormBorderStyle -eq 'None'
            MainActionVisible = $primary.Visible
            RefreshEnabled = $refresh.Enabled
            Footer = $status.Text
            NativeProcess = [Diagnostics.Process]::GetCurrentProcess().ProcessName
            NativeAppID = if('DriverLoom.ShellIdentity' -as [type]){[DriverLoom.ShellIdentity]::CurrentId()}else{''}
            TaskbarWindowID = if('DriverLoom.ShellIdentity' -as [type]){[DriverLoom.ShellIdentity]::WindowProperty($form.Handle,5)}else{''}
            TaskbarIcon = if('DriverLoom.ShellIdentity' -as [type]){[DriverLoom.ShellIdentity]::WindowProperty($form.Handle,3)}else{''}
            TaskbarCommand = if('DriverLoom.ShellIdentity' -as [type]){[DriverLoom.ShellIdentity]::WindowProperty($form.Handle,2)}else{''}
            TaskbarName = if('DriverLoom.ShellIdentity' -as [type]){[DriverLoom.ShellIdentity]::WindowProperty($form.Handle,4)}else{''}
            ProductName = 'DriverLoom'
            WindowTitle = $form.Text
            ThemePreference = [DriverLoom.UI.Palette]::Preference
            ResolvedTheme = if([DriverLoom.UI.Palette]::Dark){'Dark'}else{'Light'}
            Background = $form.BackColor.ToArgb()
            TextColor = $form.ForeColor.ToArgb()
            HasIcon = $null -ne $form.Icon
            Is64BitProcess = [Environment]::Is64BitProcess
            ApartmentState = [string][Threading.Thread]::CurrentThread.GetApartmentState()
            ScanStarted = $null -ne $script:job
            ApplyOnStartup = $script:applyAfterScan
            FreshActionVisible = $false
            FreshActionEnabled = $false
            FreshUpdateAllEnabled = $false
        }
        $script:fresh = $true
        Update-Controls
        $script:smokeResult.FreshUpdateAllEnabled = Test-CanInstallSnapshot $script:snapshot $script:fresh $false
        $script:smokeResult.FreshActionVisible=$primary.Visible
        $script:smokeResult.FreshActionEnabled=$primary.Enabled
        if($env:HARDWARE_LAUNCHER_TEST_PREVIEW){Save-FormPreview $form 'checked';Show-UpdateReview -Preview}
        if($env:DRIVERLOOM_UI_REVIEW -eq '1'){$timer.Start();return}
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
    Set-AppTheme $script:settings.Theme $form
    [void]$form.ShowDialog()
    if ($SmokeTest) { $script:smokeResult | ConvertTo-Json -Compress }
} finally {
    $timer.Stop()
    if ($script:job) { Remove-Job -Job $script:job -Force }
    $timer.Dispose()
    $header.Artwork.Dispose()
    $githubLight.Dispose();$githubDark.Dispose();$tooltips.Dispose()
    $form.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
