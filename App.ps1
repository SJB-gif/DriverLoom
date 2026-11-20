param([switch]$SmokeTest,[switch]$Background)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
if($SmokeTest){[Windows.Forms.Application]::SetUnhandledExceptionMode([Windows.Forms.UnhandledExceptionMode]::ThrowException)}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot 'Engine.ps1')
. (Join-Path $PSScriptRoot 'Install.ps1')
. (Join-Path $PSScriptRoot 'Theme.ps1')
. (Join-Path $PSScriptRoot 'Lifecycle.ps1')
. (Join-Path $PSScriptRoot 'AppUpdates.ps1')
. (Join-Path $PSScriptRoot 'AppDownloads.ps1')
. (Join-Path $PSScriptRoot 'VendorApps.ps1')

if(!$SmokeTest){
    $setupLock=$null
    if([Threading.Mutex]::TryOpenExisting('Local\DriverLoom.Setup',[ref]$setupLock)){
        $setupLock.Dispose();[void][Windows.Forms.MessageBox]::Show('DriverLoom setup is running. Finish setup before opening the app.','DriverLoom');return
    }
}

$mutexName = if ($SmokeTest) { 'Local\HardwareUpdateLauncher-Smoke-' + [guid]::NewGuid().ToString('N') } else { 'Local\HardwareUpdateLauncher' }
$mutex = [Threading.Mutex]::new($false, $mutexName)
try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
if (!$acquired) {
    if(!$Background){
        try{$existing=[Threading.EventWaitHandle]::OpenExisting('Local\DriverLoom.ShowWindow');try{[void]$existing.Set()}finally{$existing.Dispose()}}
        catch{[void][Windows.Forms.MessageBox]::Show('DriverLoom is already open. Open it from the tray icon.', 'DriverLoom')}
    }
    $mutex.Dispose()
    return
}
$restoreName=if($SmokeTest){'Local\DriverLoom.RestoreTest-'+[guid]::NewGuid().ToString('N')}else{'Local\DriverLoom.ShowWindow'}
$restoreEvent=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset,$restoreName)
$exitName=if($SmokeTest){'Local\DriverLoom.ExitTest-'+[guid]::NewGuid().ToString('N')}else{Get-SetupExitName $PSScriptRoot}
$exitEvent=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset,$exitName)

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
Initialize-LifecyclePreferences $script:settings
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
$script:lastScanAttempt = $null
$script:nextSchedulePoll = [DateTimeOffset]::MinValue
$script:exitRequested = $false
$script:settingsWindow = $null
$script:appUpdateJob=$null
$script:appUpdateManual=$false
$script:appUpdateInfo=$null
$script:lastNotifiedAppTag=''
$script:showingAppUpdate=$false
$script:appUpdateButton=$null
$script:driverInstallLock=$null
$script:appDownload=$null
$script:appSetupProcess=$null
$script:restoringGroupChoice=$false
$script:vendorApps=@{}
if(!$SmokeTest){$script:vendorApps=Get-InstalledVendorApps}
elseif($env:DRIVERLOOM_TEST_VENDOR_APPS){
    $fixture=Get-Content -LiteralPath $env:DRIVERLOOM_TEST_VENDOR_APPS -Raw|ConvertFrom-Json
    foreach($property in $fixture.PSObject.Properties){$script:vendorApps[$property.Name]=$property.Value}
}

function Receive-SetupExitRequest {
    if(!$exitEvent.WaitOne(0) -or $script:installer){return $false}
    $script:exitRequested=$true
    $form.Close()
    return !$form.Visible
}

function Start-AppUpdateCheck([switch]$Manual) {
    if($SmokeTest -or $script:appDownload -or $script:appSetupProcess){return}
    if($Manual){$script:appUpdateManual=$true}
    if($script:appUpdateJob){return}
    try{
        $script:appUpdateJob=Start-Job -ArgumentList $PSScriptRoot,$script:LauncherVersion -ScriptBlock {
            param($root,$version)
            $ErrorActionPreference='Stop'
            [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
            . (Join-Path $root 'Engine.ps1');. (Join-Path $root 'AppUpdates.ps1')
            Get-AppUpdateInfo $version
        }
        if($script:appUpdateButton -and !$script:appUpdateButton.IsDisposed){$script:appUpdateButton.Enabled=$false}
    }catch{if($Manual){Show-Message ('Could not check DriverLoom releases. '+$_.Exception.Message)};$script:appUpdateManual=$false}
}

function Show-AppUpdateNotice($info,[switch]$Preview) {
    $dialog=New-Dialog 'DriverLoom update available' 286
    Add-DialogHeading $dialog 'A new DriverLoom is available' ('Installed '+$info.CurrentVersion+'  /  Available '+$info.LatestVersion)
    Add-Label $dialog 'DriverLoom will download and verify its official installer, then open setup. Choose your normal installation options. Setup closes DriverLoom and keeps your settings.' 112 64
    $download=New-Button 'Download and install';$download.Primary=$true;$download.SetBounds(24,222,216,36);$download.DialogResult='OK'
    $notes=New-Button 'Release notes';$notes.SetBounds(252,222,178,36);$notes.Tag=$info.ReleaseUrl;$notes.Add_Click({param($sender,$eventArgs)Open-Link $sender.Tag})
    $later=New-Button 'Later';$later.SetBounds(531,222,110,36);$later.DialogResult='Cancel'
    $dialog.Controls.AddRange(@($download,$notes,$later));$dialog.CancelButton=$later
    if($Preview){$dialog.Add_Shown({param($sender,$eventArgs)Save-FormPreview $sender 'app-update';$sender.Close()})}
    try{$choice=$dialog.ShowDialog($form)}finally{$dialog.Dispose()}
    if(!$Preview -and $choice -eq 'OK'){Install-AppUpdate $info}
}

function Cancel-AppDownload {
    if(!$script:appDownload -or !$script:appDownload.Job){return}
    [IO.File]::WriteAllText($script:appDownload.CancelPath,'cancel')
    $script:appDownload.Cancelled=$true;$script:appDownload.Label.Text='Cancelling download...'
    $script:appDownload.CancelButton.Enabled=$false
}

function Receive-AppDownload {
    $state=$script:appDownload
    if(!$state -or !$state.Job){return}
    $records=@($state.Job.ChildJobs[0].Progress)
    if($records.Count -and !$state.Cancelled){$progress=$records[-1];$state.Progress.Value=[Math]::Max(0,[Math]::Min(100,$progress.PercentComplete));$state.Label.Text=([string]$state.Progress.Value+'%  '+$progress.StatusDescription)}
    if($state.Job.State -notin 'Completed','Failed','Stopped'){return}
    $job=$state.Job;$state.Job=$null
    try{$state.Path=[string](Receive-Job -Job $job -ErrorAction Stop);if(!$state.Path -and !$state.Cancelled){throw 'No verified installer was returned.'}}
    catch{if(!$state.Cancelled){$state.Failure=$_.Exception.Message}}
    finally{Remove-Job -Job $job -Force}
    if($state.Cancelled -and $state.Path){[IO.File]::Delete($state.Path);$state.Path=''}
    $state.Closing=$true;$state.Dialog.Close()
}

function New-AppDownloadDialog($info) {
    $dialog=New-Dialog 'Updating DriverLoom' 286
    Add-DialogHeading $dialog 'Updating DriverLoom' ('Downloading version '+$info.LatestVersion)
    $label=[Windows.Forms.Label]::new();$label.Text='Connecting to the official GitHub release...';$label.SetBounds(24,108,617,40);$dialog.Controls.Add($label)
    $progress=[DriverLoom.UI.DownloadProgress]::new();$progress.SetBounds(24,158,617,10);$dialog.Controls.Add($progress)
    $cancel=New-Button 'Cancel';$cancel.SetBounds(531,222,110,36);$dialog.Controls.Add($cancel)
    $dialog.Tag=[pscustomobject]@{Progress=$progress;Label=$label;CancelButton=$cancel}
    return $dialog
}

function Install-AppUpdate($info) {
    if($SmokeTest -or $script:job -or $script:installer -or $script:appDownload -or $script:appSetupProcess){return}
    $dialog=$null;$path='';$failure=''
    try{
        Assert-AppDownloadInfo $info $script:LauncherVersion
        $folder=Join-Path $directory ('downloads\'+$info.LatestVersion+'-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($folder)
        $dialog=New-AppDownloadDialog $info
        $script:appDownload=[pscustomobject]@{Dialog=$dialog;Progress=$dialog.Tag.Progress;Label=$dialog.Tag.Label;CancelButton=$dialog.Tag.CancelButton;CancelPath=(Join-Path $folder 'cancel');Job=$null;Cancelled=$false;Closing=$false;Path='';Failure=''}
        $dialog.Tag.CancelButton.Add_Click({Cancel-AppDownload})
        $dialog.Add_FormClosing({param($sender,$eventArgs)if($script:appDownload -and !$script:appDownload.Closing){$eventArgs.Cancel=$true;Cancel-AppDownload}})
        $script:appDownload.Job=Start-Job -ArgumentList $PSScriptRoot,$info,$script:LauncherVersion,$folder -ScriptBlock {
            param($root,$info,$version,$folder)
            $ErrorActionPreference='Stop';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
            . (Join-Path $root 'AppDownloads.ps1')
            Receive-AppInstaller $info $version $folder
        }
        Update-Controls
        [void]$dialog.ShowDialog($form)
        $path=$script:appDownload.Path;$failure=$script:appDownload.Failure
    }catch{$failure=$_.Exception.Message}
    finally{
        if($script:appDownload -and $script:appDownload.Job){Cancel-AppDownload;Remove-Job -Job $script:appDownload.Job -Force}
        $script:appDownload=$null;if($dialog){$dialog.Dispose()}
    }
    if($path){
        try{$script:appSetupProcess=Start-AppInstaller $path $info $script:LauncherVersion}
        catch{$failure='Setup could not be opened. '+$_.Exception.Message}
    }
    Update-Controls
    if($failure){Show-Message ('DriverLoom could not complete the update. '+$failure+"`r`nUse Check app updates to try again.")}
}

function Receive-AppUpdateCheck {
    if($script:appUpdateJob -and $script:appUpdateJob.State -in 'Completed','Failed','Stopped'){
        $job=$script:appUpdateJob;$script:appUpdateJob=$null
        $manual=$script:appUpdateManual;$script:appUpdateManual=$false
        $info=$null;$failure=''
        try{$info=Receive-Job -Job $job -ErrorAction Stop;if(!$info.Tag){throw 'No release version was returned.'}}
        catch{$failure=$_.Exception.Message}
        finally{Remove-Job -Job $job -Force}
        if($script:appUpdateButton -and !$script:appUpdateButton.IsDisposed){$script:appUpdateButton.Enabled=$true}
        if($failure){if($manual){Show-Message ('Could not check DriverLoom releases. '+$failure)}}
        elseif($info.UpdateAvailable){$script:appUpdateInfo=$info;if($manual){$script:lastNotifiedAppTag=''}}
        else{$script:appUpdateInfo=$null;if($manual){Show-Message ('No newer published DriverLoom release is available.'+"`r`n`r`nInstalled: "+$info.CurrentVersion+"`r`nLatest published: "+$info.LatestVersion)}}
    }
    if($script:appUpdateInfo -and $script:appUpdateInfo.Tag -ne $script:lastNotifiedAppTag -and !$script:showingAppUpdate -and !$script:job -and !$script:installer -and !$script:appDownload -and !$script:appSetupProcess -and !$script:settingsWindow -and $form.Visible -and $form.Enabled){
        $script:lastNotifiedAppTag=$script:appUpdateInfo.Tag;$script:showingAppUpdate=$true
        try{Show-AppUpdateNotice $script:appUpdateInfo}finally{$script:showingAppUpdate=$false}
    }
}

function Restore-Window {
    $form.Show()
    if($form.WindowState -eq 'Minimized'){$form.WindowState='Normal'}
    $form.Activate();$form.BringToFront()
}

function Set-StartupVisibility {
    if($Background -and $script:settings.KeepRunningInTray){$form.Hide()}
}

function Receive-RestoreRequest {
    if($restoreEvent.WaitOne(0)){Restore-Window}
}

function Invoke-ScheduledCheck {
    if($SmokeTest){return}
    $now=[DateTimeOffset]::UtcNow
    if($now -lt $script:nextSchedulePoll){return}
    $script:nextSchedulePoll=$now.AddMinutes(1)
    if($script:job -or $script:installer -or $script:appDownload -or $script:appSetupProcess){return}
    if(Test-AutomaticCheckDue $script:settings.CheckFrequency $now $script:lastScanAttempt $script:snapshot.CapturedAt){Start-Scan}
}

function Handle-AppClosing($eventArgs) {
    if($eventArgs.CloseReason -ne [Windows.Forms.CloseReason]::UserClosing){return}
    if($script:installer){$eventArgs.Cancel=$true;$script:exitRequested=$false;return}
    if(!(Close-SettingsWindow)){$eventArgs.Cancel=$true;return}
    if($script:settings.KeepRunningInTray -and !$script:exitRequested){$eventArgs.Cancel=$true;$form.Hide()}
}

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

function Add-ListActions($dialog, $grid, [string]$title, [string]$copyText='') {
    $top=$dialog.ClientSize.Height-58
    $copy=New-Button 'Copy list';$copy.SetBounds(24,$top,142,34);$copy.Enabled=$grid.Rows.Count -gt 0
    $feedback=[Windows.Forms.Label]::new();$feedback.Tag='Muted';$feedback.SetBounds(418,$top,410,34);$feedback.TextAlign='MiddleLeft'
    $copy.Tag=[pscustomobject]@{Grid=$grid;Title=$title;Feedback=$feedback;CopyText=$copyText}
    $copy.Add_Click({param($sender,$eventArgs)
        try{$text=if($sender.Tag.CopyText){$sender.Tag.CopyText}else{Get-GridCopyText $sender.Tag.Grid $sender.Tag.Title};[Windows.Forms.Clipboard]::SetText($text);$sender.Tag.Feedback.Text='Copied to clipboard.'}
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
    $orderedInventory = @($script:snapshot.Inventory)
    $hiddenWindows = 0
    $unsupported = [System.Collections.Generic.List[object]]::new()
    $entries=[System.Collections.Generic.List[object]]::new()
    foreach ($row in $orderedInventory) {
        if (!$row -or ($row.Kind -eq 'BIOS' -and !$script:settings.Bios)) { continue }
        $check = $checks["$($row.Key)|$($row.Current)"]
        $mode = Get-CoverageMode $row $check
        if ($mode -eq 'Windows') { $hiddenWindows++; continue }
        if ($mode -in 'Identity', 'Package component') { continue }
        if($mode -eq 'Unsupported' -and ($check.Status -like 'Source check failed:*' -or $check.Status -like '*source unavailable*')){$mode='Unavailable'}
        if ($mode -eq 'Unsupported') {
            $route = Get-OfficialSupportRoute $row $script:snapshot.Inventory
            $method=Get-UpdateMethod $row $script:snapshot.Inventory $route
            $reason=if($method.Kind -in 'Utility','Application','Portal'){$method.Reason}elseif($check.Detail){$check.Detail}else{$method.Reason}
            if($check.Status -like '*source unavailable*' -and $check.Detail){$reason+="`r`nLast automatic check: "+$check.Detail}
            $item=[pscustomobject]@{ Device=$row.Model; Manufacturer=Get-HardwareVendor $row; Manager=$method.Name; MethodKind=$method.Kind; Reason=$reason; Url=$method.Url; Hardware=$row }
            $unsupported.Add($item)
            if(!$script:settings.ShowUnsupported){continue}
            $check=[pscustomobject]@{Status=if($method.Kind -in 'Utility','Application'){'Managed by software'}else{'Manual check required'};Detail=$method.Name+"`r`n"+$item.Reason;Url=$item.Url;Available='';Checked=$false}
        }
        $name = if ($row.Kind -eq 'GPU software' -and $row.Part) { $row.Model + ' - ' + $row.Part } else { $row.Model }
        $action = if ($mode -eq 'Unsupported') {if($check.Url){'Open update page'}else{'View details'}} elseif ($check.Status -eq 'Newer at source') { 'Review update' } else { 'Vendor details' }
        $manager=if($mode -eq 'Unsupported'){$method.Name}else{''}
        $launcher=Get-DeviceLauncher $row $script:vendorApps
        if($launcher){$action='Open '+$launcher.Name}
        $entries.Add([pscustomobject]@{Name=$name;Device=$row;Url=$check.Url;Check=$check;Launcher=$launcher;DisplayStatus=Get-DisplayStatus $check.Status $manager;Manager=$manager;Action=$action})
    }
    $displays=if($script:settings.GroupBy -eq 'Hardware type'){@($entries|ForEach-Object{[pscustomobject]@{IsGroup=$false;Items=@($_)}})}else{@(Get-LauncherDisplayGroups $entries.ToArray())}
    foreach($display in $displays){
        $items=@($display.Items);$first=$items[0]
        if($display.IsGroup){
            $launcher=$first.Launcher
            $name=if($launcher.Name.StartsWith($launcher.Vendor,[StringComparison]::OrdinalIgnoreCase)){$launcher.Name}else{$launcher.Vendor+' '+[char]0x00B7+' '+$launcher.Name}
            $statuses=@($items.DisplayStatus)
            $state=if($statuses -contains 'UPDATE AVAILABLE'){'UPDATE AVAILABLE'}elseif(@($statuses|Where-Object{$_ -ne 'UP TO DATE'}).Count -eq 0){'UP TO DATE'}elseif($statuses -contains 'CHECK UNAVAILABLE'){'CHECK UNAVAILABLE'}else{$launcher.Name}
            $rank=if($state -eq 'UPDATE AVAILABLE'){0}elseif($state -eq 'UP TO DATE'){1}elseif($state -eq 'CHECK UNAVAILABLE'){3}else{2}
            $i=$hardware.Rows.Add(@($name,'','',$state,('Open '+$launcher.Name)))
            $hardware.Rows[$i].Tag=[pscustomobject]@{IsGroup=$true;Items=$items;Launcher=$launcher;Device=$null;Check=$null;Url=''}
            $info=[DriverLoom.UI.LauncherGroupInfo]::new();$info.Rank=$rank
            $info.Devices=[string[]]@($items.Name);$info.Statuses=[string[]]@($items|ForEach-Object{if($_.Manager){'Check in '+$launcher.Name}else{$_.DisplayStatus}})
            $info.Installed=[string[]]@($items|ForEach-Object{[string]$_.Device.Current});$info.Available=[string[]]@($items|ForEach-Object{[string]$_.Check.Available})
            $hardware.Rows[$i].HeaderCell.Tag=$info
            $hardware.Rows[$i].Height=[DriverLoom.UI.LauncherGroupInfo]::HeaderHeight+$items.Count*[DriverLoom.UI.LauncherGroupInfo]::ItemHeight
            $hardware.Rows[$i].Cells['Device'].Tag=$launcher.Vendor+'  /  '+$launcher.Name
            $tip=(@($items|ForEach-Object{$_.Name+' | '+$_.DisplayStatus+' | Installed: '+$_.Device.Current}) -join "`r`n")+"`r`nDouble-click for individual device details and official links."
            foreach($cell in $hardware.Rows[$i].Cells){$cell.ToolTipText=$tip}
            if($rank -eq 2){$hardware.Rows[$i].Cells['Status'].Tag='UpdateMethod'}
        }else{
            $i=$hardware.Rows.Add(@($first.Name,$first.Device.Current,$first.Check.Available,$first.DisplayStatus,$first.Action))
            $hardware.Rows[$i].Tag=$first
            $hardware.Rows[$i].Cells['Device'].Tag=(Get-HardwareVendor $first.Device)+'  /  '+$first.Device.Kind
            $hardware.Rows[$i].Cells['Device'].ToolTipText=$first.Name
            $hardware.Rows[$i].Cells['Status'].ToolTipText=$first.Check.Status+"`r`n"+$first.Check.Detail
            if($first.Manager){$hardware.Rows[$i].Cells['Status'].Tag='UpdateMethod'}
        }
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
    if($script:settings.GroupBy -eq 'Hardware type'){
        $categories=@{}
        foreach($gridRow in @($hardware.Rows)){
            $category=if($gridRow.Tag.Offer){'Windows Update'}else{Get-HardwareCategory $gridRow.Tag.Device}
            if(!$categories.ContainsKey($category)){$categories[$category]=[Collections.Generic.List[object]]::new()}
            $categories[$category].Add($gridRow)
        }
        foreach($category in $categories.Keys){
            $rank=3
            foreach($gridRow in $categories[$category]){
                $state=[string]$gridRow.Cells['Status'].Value
                $priority=if($state -in 'UPDATE AVAILABLE','READY TO INSTALL'){0}elseif($state -eq 'UP TO DATE'){1}elseif($gridRow.Cells['Status'].Tag -eq 'UpdateMethod'){2}else{3}
                $rank=[Math]::Min($rank,$priority)
            }
            foreach($gridRow in $categories[$category]){
                $info=[DriverLoom.UI.HardwareCategoryInfo]::new();$info.Name=$category;$info.Rank=$rank;$gridRow.HeaderCell.Tag=$info
            }
            $index=$hardware.Rows.Add(@($category,'','','',''))
            $headerRow=$hardware.Rows[$index];$headerRow.Height=32;$headerRow.Tag=[pscustomobject]@{IsCategory=$true}
            $info=[DriverLoom.UI.HardwareCategoryInfo]::new();$info.Name=$category;$info.Rank=$rank;$info.IsHeader=$true;$headerRow.HeaderCell.Tag=$info
        }
    }
    $hardware.ApplyHardwareSort()
    Update-Footer


}

function Show-UnsupportedItems([switch]$Preview) {
    $dialog = New-Dialog 'Other update methods | DriverLoom' 530
    $dialog.ClientSize = [Drawing.Size]::new(980,530)
    Add-DialogHeading $dialog 'Other update methods' 'Grouped by the software or support page used to check them. These are not confirmed update offers.'
    $grid = New-Grid ([ordered]@{'Managed by'=100;Devices=150;'Next step'=220})
    $source=[Windows.Forms.DataGridViewLinkColumn]::new();$source.Name='Webpage';$source.HeaderText='WEBPAGE';$source.FillWeight=80
    $source.LinkColor=[DriverLoom.UI.Palette]::Accent;$source.ActiveLinkColor=$source.LinkColor;$source.VisitedLinkColor=$source.LinkColor
    [void]$grid.Columns.Add($source)
    foreach ($group in @(Get-UpdateMethodGroups $script:unsupportedRows)) {
        $action=if($group.Url){'Open website'}else{''}
        $i = $grid.Rows.Add(@($group.Manager,$group.Devices,$group.Reason,$action))
        $grid.Rows[$i].Tag=$group
        $grid.Rows[$i].Cells['Next step'].ToolTipText = $group.Reason
    }
    $grid.DefaultCellStyle.WrapMode='True'; $grid.AutoSizeRowsMode='AllCells'
    $grid.RowTemplate.MinimumHeight=66
    $grid.Add_CellContentClick({param($sender,$eventArgs)if($eventArgs.RowIndex -ge 0 -and $eventArgs.ColumnIndex -eq $sender.Columns['Webpage'].Index){$url=$sender.Rows[$eventArgs.RowIndex].Tag.Url;if($url){Open-Link $url}}})
    $grid.Add_CellMouseDown({param($sender,$eventArgs)if($eventArgs.Button -eq 'Right' -and $eventArgs.RowIndex -ge 0){$sender.CurrentCell=$sender.Rows[$eventArgs.RowIndex].Cells[0]}})
    $context=[Windows.Forms.ContextMenuStrip]::new()
    $edit=[Windows.Forms.ToolStripMenuItem]::new('Edit device source')
    $context.Add_Opening({param($sender,$eventArgs)
        $edit.DropDownItems.Clear()
        if(!$grid.SelectedRows.Count){$eventArgs.Cancel=$true;return}
        foreach($item in $grid.SelectedRows[0].Tag.Items){
            $entry=[Windows.Forms.ToolStripMenuItem]::new($item.Device);$entry.Tag=$item
            $entry.Add_Click({param($sender,$eventArgs)$item=$sender.Tag;Edit-Source ([pscustomobject]@{Device=$item.Hardware;Url=$item.Url;Check=$null})})
            [void]$edit.DropDownItems.Add($entry)
        }
    })
    [void]$context.Items.Add($edit); $grid.ContextMenuStrip=$context
    $context.Renderer=[DriverLoom.UI.MenuRenderer]::new()
    $hostPanel=[Windows.Forms.Panel]::new();$hostPanel.SetBounds(24,104,932,340);$hostPanel.Controls.Add($grid);$dialog.Controls.Add($hostPanel)
    Add-ListActions $dialog $grid 'Other update methods' (Get-UpdateMethodsCopyText $script:unsupportedRows)
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

function New-Dialog([string]$title, [int]$height, [switch]$ClickAway) {
    $dialog = if($ClickAway){[DriverLoom.UI.SettingsWindow]::new()}else{[Windows.Forms.Form]::new()}
    $dialog.Text = $title
    $dialog.Font = $form.Font
    $dialog.StartPosition = 'CenterParent'
    $dialog.ClientSize = New-Object Drawing.Size(665, $height)
    $dialog.FormBorderStyle = if($ClickAway){'None'}else{'FixedDialog'}
    if($ClickAway){$dialog.ControlBox=$false;$dialog.ShowInTaskbar=$false;$dialog.KeyPreview=$true}
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
        $next = $script:settings | Select-Object *
        $next.Sources = $sources
        Save-Json $settingsPath $next
        $script:settings = $next
        if ($script:snapshot) { $script:snapshot.Checks = @($script:snapshot.Checks | Where-Object { $_ -and $_.Key -ne $device.Key }) }
        Refresh-View
        $status.Text = 'Source saved. Run Check for updates to read the page.'
    } catch { Show-Message $_.Exception.Message }
    finally { $dialog.Dispose() }
}

function Save-SettingsWindow($window, [bool]$closingWithOwner=$false) {
    $controls=$window.Tag
    $repo=$controls.Repository.Text.Trim()
    if($repo -and ($repo -notmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$' -or $repo -match '(^|/)\.{1,2}(/|$)')){
        if($closingWithOwner){$repo=$script:settings.Repo}else{throw 'Use owner/repository for the optional catalog, or leave it blank.'}
    }
    $preference=[string]($controls.Themes|Where-Object Checked|Select-Object -First 1).Tag
    $next=[pscustomobject]@{Repo=$repo;Bios=$controls.Bios.Checked;Sources=@($script:settings.Sources);Theme=$preference;ShowUnsupported=$controls.ShowUnsupported.Checked;CheckFrequency=[string]$controls.Frequency.SelectedItem;KeepRunningInTray=$controls.Tray.Checked;StartWithWindows=$controls.Startup.Checked;CheckAppUpdates=$controls.AppUpdates.Checked;GroupBy=$script:settings.GroupBy}
    Save-LauncherPreferences $settingsPath $script:settings $next $controls.Launcher
    if($script:snapshot -and $script:settings.Repo -ne $repo){$script:snapshot.Repository=$null;$script:snapshot.Checks=@()}
    $script:settings=$next
    $tray.Visible=$script:settings.KeepRunningInTray
    $script:nextSchedulePoll=[DateTimeOffset]::MinValue
    Set-AppTheme $preference $form
    Refresh-View
    Update-Controls
}

function Close-SettingsWindow {
    $window=$script:settingsWindow
    if(!$window -or $window.IsDisposed){return $true}
    $window.Close()
    return $window.IsDisposed
}

function Edit-Settings([switch]$Preview) {
    if($script:settingsWindow -and !$script:settingsWindow.IsDisposed){$script:settingsWindow.Activate();return}
    $dialog = New-Dialog 'Settings | DriverLoom' 740 -ClickAway
    $height=[Math]::Min(740,[Math]::Min(($form.ClientSize.Height-48),([Windows.Forms.Screen]::FromControl($form).WorkingArea.Height-90)))
    $dialog.ClientSize=[Drawing.Size]::new(940,$height)
    $dialog.StartPosition='Manual'
    $dialog.Location=[Drawing.Point]::new(($form.Left+[Math]::Max(0,($form.Width-$dialog.Width)/2)),($form.Top+[Math]::Max(0,($form.Height-$dialog.Height)/2)))
    Add-DialogHeading $dialog 'Settings' "DRIVERLOOM $script:LauncherVersion  /  MAKE IT YOURS"
    foreach($label in $dialog.Controls){if($label -is [Windows.Forms.Label]){$label.Width=650}}
    $checkApp=New-Button 'Check app updates';$checkApp.SetBounds(716,26,200,34);$checkApp.Enabled=!$script:appUpdateJob;$checkApp.Add_Click({if(Close-SettingsWindow){Start-AppUpdateCheck -Manual}});$dialog.Controls.Add($checkApp);$script:appUpdateButton=$checkApp
    $body=[Windows.Forms.Panel]::new();$body.SetBounds(1,110,938,($dialog.ClientSize.Height-174));$body.AutoScroll=$true;$body.AutoScrollMinSize=[Drawing.Size]::new(0,562);$dialog.Controls.Add($body)
    $appearance=Add-SettingsCard $body 'APPEARANCE' 24 0 432 142
    $appearanceText=[Windows.Forms.Label]::new();$appearanceText.Text='Choose how DriverLoom looks.';$appearanceText.SetBounds(18,48,390,26);$appearance.Controls.Add($appearanceText)
    $themeButtons=@();$themeIndex=0
    foreach($choice in @(@('System','Match system'),@('Dark','Dark'),@('Light','Light'))){
        $radio=[Windows.Forms.RadioButton]::new();$radio.Appearance='Button';$radio.Text=$choice[1];$radio.Tag=$choice[0];$radio.TextAlign='MiddleCenter';$radio.Font=[Drawing.Font]::new('Segoe UI',9,[Drawing.FontStyle]::Bold);$radio.SetBounds((18+132*$themeIndex),84,130,32)
        $radio.Checked=$script:settings.Theme -eq $choice[0]
        $radio.Add_CheckedChanged({param($sender,$eventArgs)[DriverLoom.UI.Theme]::Apply($sender.Parent)})
        $appearance.Controls.Add($radio);$themeButtons+=$radio;$themeIndex++
    }
    $updates=Add-SettingsCard $body 'UPDATES' 24 158 432 208
    $frequencyLabel=[Windows.Forms.Label]::new();$frequencyLabel.Text='Hardware checks';$frequencyLabel.SetBounds(18,46,160,28);$updates.Controls.Add($frequencyLabel)
    $frequency=[Windows.Forms.ComboBox]::new();$frequency.DropDownStyle='DropDownList';$frequency.SetBounds(190,44,222,28)
    foreach($choice in 'Manual','On opening','Daily','Weekly'){[void]$frequency.Items.Add($choice)}
    $frequency.SelectedItem=$script:settings.CheckFrequency;$updates.Controls.Add($frequency)
    $appUpdates=[Windows.Forms.CheckBox]::new();$appUpdates.Text='Check app updates on opening';$appUpdates.Checked=$script:settings.CheckAppUpdates;$appUpdates.SetBounds(18,78,394,28);$updates.Controls.Add($appUpdates)
    $updateText=[Windows.Forms.Label]::new();$updateText.Text='Daily and weekly hardware checks run only while DriverLoom is open or in the tray.';$updateText.Tag='Muted';$updateText.SetBounds(18,112,394,40);$updates.Controls.Add($updateText)
    $windowsUpdate=New-Button 'Open Windows Update';$windowsUpdate.SetBounds(18,160,394,30);$windowsUpdate.Add_Click({if(Close-SettingsWindow){Open-WindowsUpdate}});$updates.Controls.Add($windowsUpdate)
    $firmware=Add-SettingsCard $body 'BIOS & FIRMWARE' 476 210 440 142
    $biosBox = New-Object Windows.Forms.CheckBox
    $biosBox.Text = 'Enable BIOS checks and the USB guide'
    $biosBox.Checked = [bool]$script:settings.Bios
    $biosBox.SetBounds(18,44,394,30);$firmware.Controls.Add($biosBox)
    $biosGuide=New-Button 'Open USB guide';$biosGuide.SetBounds(18,86,178,34);$biosGuide.Enabled=[bool]$script:settings.Bios
    $biosGuide.Add_Click({if(Close-SettingsWindow){Show-BiosGuide}});$firmware.Controls.Add($biosGuide)
    $biosBox.Tag=$biosGuide;$biosBox.Add_CheckedChanged({param($sender,$eventArgs)$sender.Tag.Enabled=$sender.Checked})
    $coverage=Add-SettingsCard $body 'CHECK COVERAGE' 476 0 440 194
    $coverageText=[Windows.Forms.Label]::new();$coverageText.Text='Show devices managed by another app or support page. Windows components stay hidden.';$coverageText.SetBounds(18,44,404,46);$coverage.Controls.Add($coverageText)
    $showUnsupported=[Windows.Forms.CheckBox]::new();$showUnsupported.Text='Show items without automatic checks';$showUnsupported.Checked=$script:settings.ShowUnsupported;$showUnsupported.SetBounds(18,94,404,28);$coverage.Controls.Add($showUnsupported)
    $excludedCount=@($script:snapshot.ExcludedOffers|Where-Object{$_}).Count
    $excludedButton=New-Button ("Windows Update exclusions ($excludedCount)")
    $excludedButton.SetBounds(18,136,404,32);$excludedButton.Add_Click({if(Close-SettingsWindow){Show-WindowsExclusions}})
    $coverage.Controls.Add($excludedButton)
    $background=Add-SettingsCard $body 'RUNNING IN THE BACKGROUND' 24 382 432 154
    $keepInTray=[Windows.Forms.CheckBox]::new();$keepInTray.Text='Keep running in the tray when the window is closed';$keepInTray.Checked=$script:settings.KeepRunningInTray;$keepInTray.SetBounds(18,44,404,28);$background.Controls.Add($keepInTray)
    $startWithWindows=[Windows.Forms.CheckBox]::new();$startWithWindows.Text='Start DriverLoom when I sign in to Windows';$startWithWindows.Checked=$script:settings.StartWithWindows;$startWithWindows.SetBounds(18,78,404,28);$background.Controls.Add($startWithWindows)
    $nativeLauncher=Join-Path $PSScriptRoot 'DriverLoom.exe';$startWithWindows.Enabled=(Test-Path -LiteralPath $nativeLauncher -PathType Leaf) -or $script:settings.StartWithWindows
    $backgroundNote=[Windows.Forms.Label]::new();$backgroundNote.Text=if($startWithWindows.Enabled){'Use the tray menu to open DriverLoom or exit.'}else{'Start with Windows is available after installation.'};$backgroundNote.Tag='Muted';$backgroundNote.SetBounds(18,114,404,26);$background.Controls.Add($backgroundNote)
    $advanced=Add-SettingsCard $body 'ADVANCED SOURCES' 476 368 440 178
    $catalogLabel=[Windows.Forms.Label]::new();$catalogLabel.Text='Optional public GitHub catalog (owner/repository)';$catalogLabel.SetBounds(18,46,404,26);$advanced.Controls.Add($catalogLabel)
    $repoBox=[Windows.Forms.TextBox]::new();$repoBox.Text=$script:settings.Repo;$repoBox.SetBounds(18,78,404,29);$advanced.Controls.Add($repoBox)
    $editButton=New-Button 'Edit selected device source';$editButton.SetBounds(18,122,404,34);$editButton.Enabled=[bool](Get-SelectedRow);$editButton.Add_Click({$selected=Get-SelectedRow;if(Close-SettingsWindow){Edit-Source $selected}});$advanced.Controls.Add($editButton)
    $aboutButton=New-Button 'About';$aboutButton.SetBounds(24,($dialog.ClientSize.Height-50),80,34);$aboutButton.Add_Click({if(Close-SettingsWindow){Show-About}})
    $helpButton=New-Button 'Help';$helpButton.SetBounds(116,($dialog.ClientSize.Height-50),80,34);$helpButton.Add_Click({if(Close-SettingsWindow){Show-Help}})
    $footer=[Windows.Forms.Label]::new();$footer.Text='Click on the main window to save and return. Esc also works.';$footer.Tag='Muted';$footer.SetBounds(216,($dialog.ClientSize.Height-50),700,36);$footer.TextAlign='MiddleLeft'
    $dialog.Controls.AddRange(@($footer,$aboutButton,$helpButton))
    $dialog.Tag=[pscustomobject]@{Preview=[bool]$Preview;Body=$body;Themes=$themeButtons;Repository=$repoBox;Bios=$biosBox;ShowUnsupported=$showUnsupported;Frequency=$frequency;Tray=$keepInTray;Startup=$startWithWindows;AppUpdates=$appUpdates;Launcher=$nativeLauncher;Feedback=$footer;FirmwareCard=$firmware;BackgroundCard=$background;CoverageCard=$coverage}
    $dialog.Add_FormClosing({param($sender,$eventArgs)
        if($sender.Tag.Preview){return}
        try{Save-SettingsWindow $sender ($eventArgs.CloseReason -ne [Windows.Forms.CloseReason]::UserClosing)}
        catch{
            if($eventArgs.CloseReason -eq [Windows.Forms.CloseReason]::UserClosing){
                $eventArgs.Cancel=$true;$sender.Tag.Feedback.Text=$_.Exception.Message;$sender.Tag.Feedback.ForeColor=[Drawing.Color]::IndianRed
                $sender.Tag.Repository.Focus()|Out-Null
            }
        }
    })
    $dialog.Add_FormClosed({param($sender,$eventArgs)$script:settingsWindow=$null;$sender.Dispose()})
    if($Preview){$dialog.Add_Shown({param($sender,$eventArgs)Save-FormPreview $sender 'settings';$sender.Tag.Body.AutoScrollPosition=[Drawing.Point]::new(0,200);Save-FormPreview $sender 'settings-scrolled';$sender.Close()})}
    $script:settingsWindow=$dialog
    $dialog.Show($form)
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
    if ($script:job -or $script:installer -or $script:appDownload -or $script:appSetupProcess) { return }
    if(!$SmokeTest){$script:vendorApps=Get-InstalledVendorApps}
    $script:lastScanAttempt=[DateTimeOffset]::UtcNow.ToString('o')
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
    $state=if($script:appDownload){'DOWNLOADING DRIVERLOOM'}elseif($script:appSetupProcess){'DRIVERLOOM SETUP OPEN'}elseif($script:job){'CHECKING'}elseif($script:installer){'UPDATING'}elseif($script:lastScanError){'CHECK FAILED - USE REFRESH'}else{$caption}
    $status.Text=$state+'  '+[char]0x00B7+'  USING WINDOWS UPDATE & MANUFACTURER SOURCES'
    $tooltips.SetToolTip($status,($script:lastScanError+(@($script:snapshot.Warnings)-join "`r`n")))
    if($repoButton){$repoButton.Image=if([DriverLoom.UI.Palette]::Dark){$githubLight}else{$githubDark}}
}

function Update-Controls {
    $busy = $null -ne $script:job -or $null -ne $script:installer -or $null -ne $script:appDownload -or $null -ne $script:appSetupProcess
    $action=Get-UpdateAction $script:snapshot $script:fresh $busy
    $primary.Visible=$action.Visible -or $null -ne $script:installer
    $primary.Enabled=$action.Enabled
    $primary.Text=if($script:installer){'Updating...'}else{'Update All'}
    $refresh.Enabled=!$busy
    $groupView.Enabled=!$busy
    $settingsMenu.Enabled=!$busy
    $trayCheck.Enabled=!$busy
    $trayExit.Enabled=$null -eq $script:installer
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
        $launcher=Get-DeviceLauncher $device $script:vendorApps
        $action=if($launcher){'Open '+$launcher.Name}else{'Review update'}
        $i=$grid.Rows.Add(@($device.Model,$check.Available,'Manual vendor installation',$action))
        $grid.Rows[$i].Tag=[pscustomobject]@{Device=$device;Launcher=$launcher;Url=$check.Url;Check=$check}
    }
    foreach($offer in @($script:snapshot.Offers|Where-Object{$_})){
        [void]$grid.Rows.Add(@($offer.Title,'','Install through Windows Update','In update queue'))
    }
    $grid.Add_CellContentClick({param($sender,$eventArgs)if($eventArgs.RowIndex -ge 0 -and $eventArgs.ColumnIndex -eq 3 -and $sender.Rows[$eventArgs.RowIndex].Tag){Open-HardwareAction $sender.Rows[$eventArgs.RowIndex].Tag}})
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

function Open-HardwareAction($selection) {
    if($script:appDownload -or $script:appSetupProcess){return}
    if($selection.Launcher){
        if($SmokeTest){return}
        if($script:installer){Show-Message 'Finish the current driver installation before opening another updater.';return}
        try{Start-VendorApplication $selection.Launcher}catch{$script:vendorApps=Get-InstalledVendorApps;Refresh-View;Show-Message 'The application could not be opened or verified. The list has been refreshed; use its official website action or device details.'}
    }elseif($selection.Url){Open-Link $selection.Url}elseif($selection.Device){Show-DeviceInfo $selection}
}

function Show-DeviceInfo($selection) {
    if($selection.Check){Show-Message ($selection.Device.Model+"`r`n`r`n"+$selection.Check.Status+"`r`n"+$selection.Check.Detail+"`r`n`r`n"+$selection.Url)}
}

function Show-LauncherGroup($selection,[switch]$Preview) {
    $dialog=New-Dialog ($selection.Launcher.Name+' devices | DriverLoom') 490
    $dialog.ClientSize=[Drawing.Size]::new(980,490)
    Add-DialogHeading $dialog ($selection.Launcher.Vendor+' / '+$selection.Launcher.Name) 'Individual device versions and comparison details. App versions are separate from driver and firmware versions.'
    $grid=New-Grid ([ordered]@{Device=220;Status=150;Installed=100;Available=100})
    $grid.RowTemplate.Height=44
    foreach($column in $grid.Columns){$column.SortMode='NotSortable'}
    foreach($item in $selection.Items){$i=$grid.Rows.Add(@($item.Name,$item.DisplayStatus,$item.Device.Current,$item.Check.Available));$grid.Rows[$i].Tag=$item;$grid.Rows[$i].Cells['Status'].ToolTipText=$item.Check.Detail}
    $panel=[Windows.Forms.Panel]::new();$panel.SetBounds(24,104,932,298);$panel.Controls.Add($grid);$dialog.Controls.Add($panel)
    $open=New-Button ('Open '+$selection.Launcher.Name);$open.SetBounds(24,430,240,34);$open.Tag=$selection;$open.Add_Click({param($sender,$eventArgs)Open-HardwareAction $sender.Tag})
    $details=New-Button 'Device details';$details.SetBounds(276,430,152,34);$details.Tag=$grid;$details.Add_Click({param($sender,$eventArgs)if($sender.Tag.SelectedRows.Count){Show-DeviceInfo $sender.Tag.SelectedRows[0].Tag}})
    $website=New-Button 'Official website';$website.SetBounds(440,430,152,34);$website.Tag=$grid;$website.Add_Click({param($sender,$eventArgs)if($sender.Tag.SelectedRows.Count -and $sender.Tag.SelectedRows[0].Tag.Url){Open-Link $sender.Tag.SelectedRows[0].Tag.Url}})
    $edit=New-Button 'Edit source';$edit.SetBounds(604,430,132,34);$edit.Tag=$grid;$edit.Add_Click({param($sender,$eventArgs)if($sender.Tag.SelectedRows.Count){Edit-Source $sender.Tag.SelectedRows[0].Tag}})
    $done=New-Button 'Done';$done.SetBounds(846,430,110,34);$done.DialogResult='Cancel';$dialog.CancelButton=$done
    $dialog.Controls.AddRange(@($open,$details,$website,$edit,$done))
    if($Preview){$dialog.Add_Shown({param($sender,$eventArgs)Save-FormPreview $sender 'launcher-group';$sender.Close()})}
    try{[void]$dialog.ShowDialog($form)}finally{$dialog.Dispose()}
}

function Show-DeviceDetails {
    if(!$hardware.SelectedRows.Count){return}
    $selected=$hardware.SelectedRows[0].Tag
    if($selected.IsGroup){Show-LauncherGroup $selected}else{Show-DeviceInfo $selected}
}

function Show-About {
    $identity=@($script:snapshot.Inventory|Where-Object Kind -in 'System','Motherboard','CPU','RAM'|ForEach-Object {$_.Kind+': '+$_.Model})
    Show-Message ("DriverLoom $script:LauncherVersion`r`nHardware updates, brought together.`r`nMIT-licensed Windows 10/11 x64 utility.`r`n`r`n"+($identity -join "`r`n"))
}

function Show-Help {
    Show-Message "Checks default to On opening. Choose Manual, Daily or Weekly in Settings, or use the refresh arrow at any time. Scheduled checks run only while DriverLoom is open or kept in the tray.`r`n`r`nTray mode and Start with Windows are off by default. When tray mode is enabled, closing hides the window; use the tray menu to open it or exit.`r`n`r`nUpdate All opens a review list. Eligible Windows Update drivers require confirmation; manufacturer packages use official Review update links. Double-click a device for source details. Firmware flashing and reboots are never automatic."
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
        $script:driverInstallLock=[Threading.Mutex]::new($false,'Local\DriverLoom.DriverInstall')
        $script:installer = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile', '-STA', '-EncodedCommand', $encoded)
        $script:fresh = $false
        $status.Text = 'Installing drivers. Review the installer results when it finishes.'
        Update-Controls
    } catch { if($script:driverInstallLock){$script:driverInstallLock.Dispose();$script:driverInstallLock=$null};Show-Message $_.Exception.Message }
}

$form = [DriverLoom.UI.MainWindow]::new()
$form.Add_HandleCreated({param($sender,$eventArgs)if('DriverLoom.ShellIdentity' -as [type]){[DriverLoom.ShellIdentity]::BindWindow($sender.Handle)}})
$form.Text = "DriverLoom $script:LauncherVersion"
$form.Icon=[Drawing.Icon]::new((Join-Path $PSScriptRoot 'assets\DriverLoom-loops.ico'))
$form.Font=[Drawing.Font]::new('Segoe UI',10)
$form.StartPosition='CenterScreen';$form.ClientSize=[Drawing.Size]::new(1240,850);$form.MinimumSize=[Drawing.Size]::new(1040,660);$form.AutoScaleMode='Dpi'
$tray=[Windows.Forms.NotifyIcon]::new();$tray.Icon=$form.Icon;$tray.Text='DriverLoom';$tray.Visible=$script:settings.KeepRunningInTray
$trayMenu=[Windows.Forms.ContextMenuStrip]::new();$trayMenu.Renderer=[DriverLoom.UI.MenuRenderer]::new()
$trayOpen=[Windows.Forms.ToolStripMenuItem]::new('Open DriverLoom');$trayOpen.Add_Click({Restore-Window})
$trayCheck=[Windows.Forms.ToolStripMenuItem]::new('Check for updates');$trayCheck.Add_Click({Start-Scan})
$trayExit=[Windows.Forms.ToolStripMenuItem]::new('Exit');$trayExit.Add_Click({$script:exitRequested=$true;$form.Close()})
[void]$trayMenu.Items.Add($trayOpen);[void]$trayMenu.Items.Add($trayCheck);[void]$trayMenu.Items.Add([Windows.Forms.ToolStripSeparator]::new());[void]$trayMenu.Items.Add($trayExit)
$tray.ContextMenuStrip=$trayMenu;$tray.Add_DoubleClick({Restore-Window})
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
$toolbar=[Windows.Forms.TableLayoutPanel]::new();$toolbar.Dock='Fill';$toolbar.ColumnCount=4;$toolbar.RowCount=1
[void]$toolbar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',42));[void]$toolbar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100));[void]$toolbar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',202));[void]$toolbar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',168))
$refresh=[DriverLoom.UI.IconButton]::new();$refresh.Glyph='Refresh';$refresh.AccessibleName='Check for updates';$refresh.Size=[Drawing.Size]::new(32,36);$refresh.Margin=[Windows.Forms.Padding]::new(0,12,0,0);$toolbar.Controls.Add($refresh,0,0);$tooltips.SetToolTip($refresh,'Check for updates')
$title=[Windows.Forms.Label]::new();$title.Text='Your hardware';$title.Font=[Drawing.Font]::new('Segoe UI',18,[Drawing.FontStyle]::Bold);$title.Dock='Fill';$title.TextAlign='MiddleLeft';$toolbar.Controls.Add($title,1,0)
$groupView=[Windows.Forms.ComboBox]::new();$groupView.DropDownStyle='DropDownList';$groupView.AccessibleName='Group devices by';$groupView.Width=186;$groupView.Margin=[Windows.Forms.Padding]::new(0,17,12,0);[void]$groupView.Items.AddRange(@('By application','By hardware type'));$groupView.SelectedIndex=if($script:settings.GroupBy -eq 'Hardware type'){1}else{0};$toolbar.Controls.Add($groupView,2,0);$tooltips.SetToolTip($groupView,'Group devices by application or hardware type')
$groupView.Add_SelectedIndexChanged({
    if($script:restoringGroupChoice){return}
    $next=$script:settings|Select-Object *;$next.GroupBy=if($groupView.SelectedIndex -eq 1){'Hardware type'}else{'Application'}
    try{Save-LauncherPreferences $settingsPath $script:settings $next (Join-Path $PSScriptRoot 'DriverLoom.exe');$script:settings=$next;Refresh-View}
    catch{
        $failure=$_.Exception.Message;$script:restoringGroupChoice=$true
        try{$groupView.SelectedIndex=if($script:settings.GroupBy -eq 'Hardware type'){1}else{0}}finally{$script:restoringGroupChoice=$false}
        Show-Message ('The grouping preference could not be saved. '+$failure)
    }
})
$primary=New-Button 'Update All';$primary.Primary=$true;$primary.AutoSize=$false;$primary.Size=[Drawing.Size]::new(162,36);$primary.Margin=[Windows.Forms.Padding]::new(0,14,0,0);$toolbar.Controls.Add($primary,3,0)
$form.AcceptButton=$primary
$layout.Controls.Add($toolbar,0,0)
$hardware=New-Grid ([ordered]@{Device=220;Installed=76;Available=76;Status=130;Source=96})
$hardware.Decorated=$true;$hardware.RowTemplate.Height=70;$hardware.Columns['Status'].DisplayIndex=1
$hardware.Columns['Installed'].DefaultCellStyle.Font=[Drawing.Font]::new('Consolas',10);$hardware.Columns['Available'].DefaultCellStyle.Font=[Drawing.Font]::new('Consolas',10)
$hardware.Columns.Remove('Source');$sourceColumn=[DriverLoom.UI.DeviceActionColumn]::new();$sourceColumn.Name='Source';$sourceColumn.HeaderText='ACTION';$sourceColumn.FillWeight=96;[void]$hardware.Columns.Add($sourceColumn)
$hardware.ConfigureHardwareSorting()
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
$hardware.Add_CellContentClick({param($sender,$eventArgs)if($eventArgs.RowIndex -ge 0 -and $eventArgs.ColumnIndex -ge 0 -and $sender.Columns[$eventArgs.ColumnIndex].Name -eq 'Source'){Open-HardwareAction $sender.Rows[$eventArgs.RowIndex].Tag}})
$hardware.Add_CellDoubleClick({param($sender,$eventArgs)if($eventArgs.RowIndex -ge 0 -and $eventArgs.ColumnIndex -ne $hardware.Columns['Source'].Index){Show-DeviceDetails}})
$hardware.Add_CellMouseDown({param($sender,$eventArgs)if($eventArgs.Button -eq 'Right' -and $eventArgs.RowIndex -ge 0){$sender.CurrentCell=$sender.Rows[$eventArgs.RowIndex].Cells['Device']}})
$hardwareContext=[Windows.Forms.ContextMenuStrip]::new();$hardwareContext.Renderer=[DriverLoom.UI.MenuRenderer]::new()
$deviceDetailsItem=[Windows.Forms.ToolStripMenuItem]::new('Device details');$deviceDetailsItem.Add_Click({Show-DeviceDetails})
$officialItem=[Windows.Forms.ToolStripMenuItem]::new('Official website');$officialItem.Add_Click({if($hardware.SelectedRows.Count){$selected=$hardware.SelectedRows[0].Tag;if($selected.IsGroup){Show-LauncherGroup $selected}elseif($selected.Url){Open-Link $selected.Url}}})
$hardwareContext.Add_Opening({param($sender,$eventArgs)$selected=if($hardware.SelectedRows.Count){$hardware.SelectedRows[0].Tag}else{$null};$deviceDetailsItem.Enabled=[bool]($selected.Device -or $selected.IsGroup);$officialItem.Enabled=[bool]($selected.Url -or $selected.IsGroup)})
[void]$hardwareContext.Items.Add($deviceDetailsItem);[void]$hardwareContext.Items.Add($officialItem);$hardware.ContextMenuStrip=$hardwareContext

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    Receive-AppDownload
    if($script:appSetupProcess -and $script:appSetupProcess.HasExited){$script:appSetupProcess.Dispose();$script:appSetupProcess=$null;Update-Controls}
    if(Receive-SetupExitRequest){return}
    Receive-RestoreRequest
    Receive-AppUpdateCheck
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
            if($script:driverInstallLock){$script:driverInstallLock.Dispose();$script:driverInstallLock=$null}
            Update-Controls
            Start-Scan
        }
    }
    Invoke-ScheduledCheck
})
$form.Add_Shown({
    if ($SmokeTest) {
        if ($env:HARDWARE_LAUNCHER_TEST_PREVIEW) {
            Save-FormPreview $form 'hardware'
            $hardware.SortHardwareBy('Status');Save-FormPreview $form 'hardware-status'
            $hardware.SortHardwareBy('Device')
            Edit-Settings -Preview
            Show-UnsupportedItems -Preview
            Show-WindowsExclusions -Preview
            $group=$hardware.Rows|Where-Object{$_.Tag.IsGroup}|Select-Object -First 1
            if($group){Show-LauncherGroup $group.Tag -Preview}
            Show-AppUpdateNotice ([pscustomobject]@{CurrentVersion=$script:LauncherVersion;LatestVersion='0.2.0';ReleaseUrl='https://github.com/SJB-gif/DriverLoom/releases';InstallerUrl=''}) -Preview
            $progressPreview=New-AppDownloadDialog ([pscustomobject]@{LatestVersion='0.2.0'})
            $progressPreview.Tag.Progress.Value=64;$progressPreview.Tag.Label.Text='0.8 of 1.2 MB'
            $progressPreview.Add_Shown({param($sender,$eventArgs)Save-FormPreview $sender 'app-download';$sender.Close()})
            try{[void]$progressPreview.ShowDialog($form)}finally{$progressPreview.Dispose()}
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
            UpdateMethodGroupCount = @(Get-UpdateMethodGroups $script:unsupportedRows).Count
            ShowUnsupported = $script:settings.ShowUnsupported
            CheckFrequency = $script:settings.CheckFrequency
            KeepRunningInTray = $script:settings.KeepRunningInTray
            StartWithWindows = $script:settings.StartWithWindows
            TrayVisible = $tray.Visible
            BackgroundRequested = [bool]$Background
            AutomaticCheckOnOpening = Test-AutomaticCheckDue $script:settings.CheckFrequency ([DateTimeOffset]::UtcNow) $null $script:snapshot.CapturedAt $true
            CloseHidesToTray = $false
            RestoreRequestShowsWindow = $false
            ShutdownAllowsExit = $false
            BackgroundStartsHidden = $false
            WindowsManagedHidden = $script:hiddenWindowsCount
            MainDevices = @($hardware.Rows | ForEach-Object { $_.Cells[0].Value })
            MainStatuses = @($hardware.Rows | ForEach-Object { $_.Cells['Status'].Value })
            ManufacturerLogoCount = [DriverLoom.UI.DeviceGrid]::ManufacturerLogoCount
            CheckAppUpdates = $script:settings.CheckAppUpdates
            GroupBy = $script:settings.GroupBy
            HardwareCategories = @($hardware.Rows|Where-Object{$_.Tag.IsCategory}|ForEach-Object{$_.Cells['Device'].Value})
            AppUpdateCheckStarted = $null -ne $script:appUpdateJob
            SetupExitDeferredWhileBusy = $false
            SetupExitClosesWindow = $false
            MainItems = @($hardware.Rows | ForEach-Object { [pscustomobject]@{Device=$_.Cells['Device'].Value;Status=$_.Cells['Status'].Value;Action=$_.Cells['Source'].Value;Url=$_.Tag.Url;Comparison=$_.Tag.Check.Status} })
            LauncherGroups = @($hardware.Rows|Where-Object{$_.Tag.IsGroup}|ForEach-Object{[pscustomobject]@{Name=$_.Cells['Device'].Value;Status=$_.Cells['Status'].Value;Height=$_.Height;Members=@($_.Tag.Items.Name);Versions=@($_.Tag.Items|ForEach-Object{$_.Device.Current});Launcher=$_.Tag.Launcher.Key}})
            SettingsProbe = $null
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
        if($env:DRIVERLOOM_TEST_SETTINGS -eq '1'){
            $originalVisibility=$script:settings.ShowUnsupported
            $originalGroupIndex=$groupView.SelectedIndex;$groupView.SelectedIndex=1
            $groupSaved=(Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json).GroupBy -eq 'Hardware type'
            $groupSwitched=@($hardware.Rows|Where-Object{$_.Tag.IsCategory}).Count -gt 0
            Edit-Settings
            $window=$script:settingsWindow
            $modeless=$form.Enabled -and !$window.Modal -and $window.Owner -eq $form
            $noClose=$window.FormBorderStyle -eq 'None' -and !$window.ControlBox -and !$window.AcceptButton -and !$window.CancelButton
            $noOtherMethods=@($window.Tag.CoverageCard.Controls|Where-Object Text -like 'Other update methods*').Count -eq 0
            $swapped=$window.Tag.BackgroundCard.Left -lt $window.Tag.FirmwareCard.Left
            $inside=[Windows.Forms.Message]::Create($window.Tag.Repository.Handle,0x0201,[IntPtr]::Zero,[IntPtr]::Zero)
            $insideIgnored=!$window.PreFilterMessage([ref]$inside) -and !$window.IsDisposed
            $window.Tag.ShowUnsupported.Checked=!$originalVisibility
            $window.Tag.Repository.Text='invalid/catalog/path'
            $outside=[Windows.Forms.Message]::Create($refresh.Handle,0x0201,[IntPtr]::Zero,[IntPtr]::Zero)
            $blocked=$window.PreFilterMessage([ref]$outside) -and !$window.IsDisposed -and $script:settings.ShowUnsupported -eq $originalVisibility
            $window.Tag.Repository.Text=$script:settings.Repo
            $consumed=$window.PreFilterMessage([ref]$outside)
            $dismissed=$window.IsDisposed
            $saved=Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json
            $persisted=$saved.ShowUnsupported -eq !$originalVisibility
            $groupKept=$saved.GroupBy -eq 'Hardware type'
            Edit-Settings
            $reopened=$script:settingsWindow
            $reloaded=$reopened.Tag.ShowUnsupported.Checked -eq !$originalVisibility
            $reopened.Tag.ShowUnsupported.Checked=$originalVisibility
            $escape=[Windows.Forms.KeyEventArgs]::new([Windows.Forms.Keys]::Escape)
            $keyHandler=$reopened.GetType().GetMethod('OnKeyDown',[Reflection.BindingFlags]'Instance,NonPublic')
            $null=$keyHandler.Invoke($reopened,@($escape))
            $groupView.SelectedIndex=$originalGroupIndex
            $script:smokeResult.SettingsProbe=[pscustomobject]@{GroupChoiceSaved=$groupSaved;GroupViewSwitches=$groupSwitched;SettingsKeepGroupChoice=$groupKept;Modeless=$modeless;NoCloseButtons=$noClose;NoOtherMethodsButton=$noOtherMethods;CardsSwapped=$swapped;InsideClickIgnored=$insideIgnored;InvalidCatalogBlocksDismiss=$blocked;OutsideClickConsumed=$consumed;OutsideClickDismisses=$dismissed;PreferencesPersist=$persisted;ReopenLoadsPreferences=$reloaded;EscapeDismisses=$reopened.IsDisposed -and $escape.Handled}
        }
        $script:fresh = $true
        Update-Controls
        $script:smokeResult.FreshUpdateAllEnabled = Test-CanInstallSnapshot $script:snapshot $script:fresh $false
        $script:smokeResult.FreshActionVisible=$primary.Visible
        $script:smokeResult.FreshActionEnabled=$primary.Enabled
        Set-StartupVisibility
        $script:smokeResult.BackgroundStartsHidden=!$form.Visible
        $closeProbe=[Windows.Forms.FormClosingEventArgs]::new([Windows.Forms.CloseReason]::UserClosing,$false)
        Handle-AppClosing $closeProbe
        $script:smokeResult.CloseHidesToTray=$closeProbe.Cancel -and !$form.Visible
        [void]$restoreEvent.Set();Receive-RestoreRequest
        $script:smokeResult.RestoreRequestShowsWindow=$form.Visible
        $shutdownProbe=[Windows.Forms.FormClosingEventArgs]::new([Windows.Forms.CloseReason]::WindowsShutDown,$false)
        Handle-AppClosing $shutdownProbe
        $script:smokeResult.ShutdownAllowsExit=!$shutdownProbe.Cancel
        if($env:HARDWARE_LAUNCHER_TEST_PREVIEW){Save-FormPreview $form 'checked';Show-UpdateReview -Preview}
        if($env:DRIVERLOOM_UI_REVIEW -eq '1'){$timer.Start();return}
        $script:installer=[object]::new();[void]$exitEvent.Set()
        $script:smokeResult.SetupExitDeferredWhileBusy=!(Receive-SetupExitRequest) -and $form.Visible
        $script:installer=$null;[void]$exitEvent.Set()
        $script:smokeResult.SetupExitClosesWindow=Receive-SetupExitRequest
        return
    }
    $timer.Start()
    Set-StartupVisibility
    if($script:settings.CheckAppUpdates){Start-AppUpdateCheck}
    if(Test-AutomaticCheckDue $script:settings.CheckFrequency ([DateTimeOffset]::UtcNow) $script:lastScanAttempt $script:snapshot.CapturedAt $true){Start-Scan}
})
$form.Add_FormClosing({
    param($sender, $eventArgs)
    Handle-AppClosing $eventArgs
})
try {
    Refresh-View
    Update-Controls
    Set-AppTheme $script:settings.Theme $form
    [Windows.Forms.Application]::Run($form)
    if ($SmokeTest) { $script:smokeResult | ConvertTo-Json -Compress -Depth 6 }
} finally {
    $timer.Stop()
    if ($script:job) { Remove-Job -Job $script:job -Force }
    if ($script:appUpdateJob) { Remove-Job -Job $script:appUpdateJob -Force }
    if ($script:appDownload -and $script:appDownload.Job) { Cancel-AppDownload;Remove-Job -Job $script:appDownload.Job -Force }
    if ($script:appSetupProcess) { $script:appSetupProcess.Dispose() }
    $timer.Dispose()
    $hardwareContext.Dispose()
    $tray.Visible=$false;$tray.Dispose();$trayMenu.Dispose()
    $restoreEvent.Dispose()
    $exitEvent.Dispose()
    if($script:driverInstallLock){$script:driverInstallLock.Dispose()}
    [DriverLoom.UI.DeviceGrid]::DisposeManufacturerLogos()
    $header.Artwork.Dispose()
    $githubLight.Dispose();$githubDark.Dispose();$tooltips.Dispose()
    $form.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
