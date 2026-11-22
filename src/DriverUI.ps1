function Get-DriverAction($selection) {
    if($script:driverDownload -and $script:driverDownload.Key -ceq $selection.Device.Key){return 'Cancel download'}
    if($selection.Ready){return 'Install update'}
    return 'Download update'
}
function Update-DriverDownloadButton {
    if(!$script:driverDownload){return}
    foreach($row in $hardware.Rows){if($row.Tag.Device.Key -ceq $script:driverDownload.Key){
        $row.Cells['Source'].Value=if($script:driverDownload.Cancelled){'Cancelling...'}else{'Cancel download'}
        $progress=[DriverLoom.UI.DriverActionProgress]::new();$progress.Value=$script:driverDownload.Percent
        $row.Cells['Source'].Tag=$progress;$row.Cells['Source'].ToolTipText=$script:driverDownload.Message
    }}
    $hardware.Invalidate()
}
function Cancel-DriverDownload {
    if(!$script:driverDownload){return}
    [IO.File]::WriteAllText((Join-Path $script:driverDownload.Folder 'cancel'),'cancel');$script:driverDownload.Cancelled=$true;Update-DriverDownloadButton
}
function Download-ManufacturerUpdate($selection) {
    if($SmokeTest -or $script:driverDownload -or $script:backupOperation -or $script:job -or $script:installer -or $script:packageInstaller -or $script:appDownload -or $script:appSetupProcess){return}
    $folder=''
    try{
        if(!(Test-ManagedPackageOffer $selection.Device $selection.Check)){throw 'This device has no verified direct download.'}
        $setup=$null;if([Threading.Mutex]::TryOpenExisting('Local\DriverLoom.Setup',[ref]$setup)){$setup.Dispose();throw 'Finish DriverLoom setup first.'}
        $folder=New-DriverLibraryFolder $selection.Device.Key
        $script:driverInstallLock=[Threading.Mutex]::new($false,'Local\DriverLoom.DriverInstall')
        $script:driverDownload=[pscustomobject]@{Key=$selection.Device.Key;Folder=$folder;Cancelled=$false;Percent=0;Message='Checking official package';Job=$null}
        $script:driverDownload.Job=Start-Job -ArgumentList $PSScriptRoot,$selection,$folder -ScriptBlock {
            param($root,$selection,$folder)
            $ErrorActionPreference='Stop';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
            . (Join-Path $root 'Engine.ps1');. (Join-Path $root 'AppDownloads.ps1')
            try{
                $result=Receive-ManagedPackage $selection $folder
                if(Test-Path -LiteralPath (Join-Path $folder 'cancel')){if($result.Package.Family -eq 'ASUSDriver'){Remove-AsusRoot $result.Root};throw [OperationCanceledException]::new('Download cancelled.')}
                Save-DriverDownload $result $selection.Device -DeferRetention
            }catch{Remove-DriverLibraryFolder $folder;throw}
        }
        Update-DriverDownloadButton;Update-Controls
    }catch{
        if($folder){Remove-DriverLibraryFolder $folder}
        if($script:driverDownload){$script:driverDownload=$null}
        if($script:driverInstallLock){$script:driverInstallLock.Dispose();$script:driverInstallLock=$null}
        Show-Message ('Could not download this update. '+$_.Exception.Message)
    }
}
function Receive-DriverDownload {
    $state=$script:driverDownload;if(!$state -or !$state.Job){return}
    $records=@($state.Job.ChildJobs[0].Progress)
    if($records.Count -and !$state.Cancelled){$state.Percent=[Math]::Max(0,[Math]::Min(100,$records[-1].PercentComplete));$state.Message=$records[-1].StatusDescription;Update-DriverDownloadButton}
    if($state.Job.State -notin 'Completed','Failed','Stopped'){return}
    $failure='';$entry=$null
    try{$entry=Receive-Job -Job $state.Job -ErrorAction Stop;if(!$entry.Folder -and !$state.Cancelled){throw 'No saved driver was returned.'};if($entry -and !$state.Cancelled){Complete-DriverDownload $entry.Folder}}
    catch{if(!$state.Cancelled){$failure=$_.Exception.Message}}
    finally{
        Remove-Job -Job $state.Job -Force
        if($state.Cancelled){Remove-DriverLibraryFolder $state.Folder}
        $script:driverDownload=$null
        if($script:driverInstallLock){$script:driverInstallLock.Dispose();$script:driverInstallLock=$null}
        Refresh-View;Update-Controls
    }
    if($failure){Show-Message ('Driver download failed. '+$failure)}
}
function Start-BackupOperation([string]$operation='Backup',$entry=$null,[string[]]$keys=@(),[switch]$DeferRetention) {
    if($script:driverDownload -or $script:backupOperation -or $script:installer -or $script:packageInstaller -or $script:appDownload -or $script:appSetupProcess -or $script:job){return $null}
    $folder=Join-Path (Get-DriverLibraryRoot) ('backups\jobs\'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($folder)
    $request=@{Operation=$operation;UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Keys=$keys;DeferRetention=[bool]$DeferRetention}
    if($operation -eq 'Restore'){
        $live=@(Get-InstalledBackupDevices|Where-Object InstanceId -CEQ $entry.InstanceId)
        if($live.Count -ne 1){throw 'The saved device is not currently present.'}
        $request.EntryFolder=$entry.Folder;$request.InstanceId=$entry.InstanceId;$request.CurrentVersion=$live[0].Version
    }
    Save-Json (Join-Path $folder 'request.json') $request
    $worker=Join-Path $PSScriptRoot 'DriverBackupWorker.ps1'
    if($worker.Contains('"') -or $folder.Contains('"')){throw 'Invalid backup worker path.'}
    $process=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$worker+'"'),'-JobFolder',('"'+$folder+'"')) -PassThru
    $script:backupOperation=[pscustomobject]@{Process=$process;Folder=$folder};Update-Controls
    return $script:backupOperation
}
function Invoke-BackupOperation([string]$operation='Backup',$entry=$null,[string[]]$keys=@(),[switch]$DeferRetention) {
    $dialog=New-Dialog $(if($operation -eq 'Restore'){'Restoring saved driver'}else{'Backing up installed drivers'}) 286
    Add-DialogHeading $dialog $dialog.Text 'Windows permission is required. No automatic restart.'
    $label=[Windows.Forms.Label]::new();$label.SetBounds(24,110,617,66);$label.Text='Waiting for Windows permission...';$dialog.Controls.Add($label)
    $progress=[DriverLoom.UI.DownloadProgress]::new();$progress.SetBounds(24,180,617,5);$dialog.Controls.Add($progress)
    $cancel=New-Button 'Cancel';$cancel.SetBounds(531,222,110,36);$cancel.Enabled=$operation -eq 'Backup';$dialog.Controls.Add($cancel)
    $state=[pscustomobject]@{Finished=$false;Result=$null;Failure='';Folder='';Label=$label;Progress=$progress;Cancel=$cancel;Dialog=$dialog}
    $poll=[Windows.Forms.Timer]::new();$poll.Interval=300;$poll.Tag=$state
    $cancel.Tag=$state;$cancel.Add_Click({param($sender,$args)[IO.File]::WriteAllText((Join-Path $sender.Tag.Folder 'cancel'),'cancel');$sender.Enabled=$false;$sender.Tag.Label.Text='Finishing the current export...'} )
    $poll.Add_Tick({param($sender,$args)
        $s=$sender.Tag
        try{
            $p=Join-Path $s.Folder 'progress.json';if(Test-Path -LiteralPath $p){try{$p=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json;$s.Label.Text=$p.Message;$s.Progress.Value=$p.Percent}catch{}}
            if($script:backupOperation.Process.HasExited){
                $s.Result=Get-Content -LiteralPath (Join-Path $s.Folder 'result.json') -Raw|ConvertFrom-Json
                $s.Finished=$true;$sender.Stop();$s.Dialog.Close()
            }
        }catch{$s.Failure=$_.Exception.Message;$s.Finished=$true;$sender.Stop();$s.Dialog.Close()}
    })
    $dialog.Tag=$state;$dialog.Add_FormClosing({param($sender,$args)if(!$sender.Tag.Finished){$args.Cancel=$true;if($sender.Tag.Cancel.Enabled){$sender.Tag.Cancel.PerformClick()}}})
    try{
        $op=Start-BackupOperation $operation $entry $keys -DeferRetention:$DeferRetention
        if(!$op){return $null};$state.Folder=$op.Folder;$poll.Start();[void]$dialog.ShowDialog($form)
        if($state.Failure){throw $state.Failure}
        if(!$state.Result.Success){throw $state.Result.Error}
        return $state.Result
    }finally{
        $poll.Stop();$poll.Dispose();$dialog.Dispose()
        if($script:backupOperation){$script:backupOperation.Process.Dispose();$script:backupOperation=$null}
        Update-Controls
    }
}
function Show-DriverLibrary([switch]$Preview) {
    $dialog=New-Dialog 'Rollback | DriverLoom' 494
    Add-DialogHeading $dialog 'Saved driver versions' 'Choose a device and a saved version. Restore starts only when you select it.'
    $devices=[Windows.Forms.ComboBox]::new();$devices.DropDownStyle='DropDownList';$devices.SetBounds(24,106,617,28);$devices.DisplayMember='Name';$dialog.Controls.Add($devices)
    $list=[Windows.Forms.ListBox]::new();$list.SetBounds(24,148,617,186);$list.DisplayMember='Name';$dialog.Controls.Add($list)
    $note=[Windows.Forms.Label]::new();$note.Tag='Muted';$note.SetBounds(24,344,617,72);$dialog.Controls.Add($note)
    $restore=New-Button 'Restore selected';$restore.SetBounds(421,434,220,36);$restore.Enabled=$false;$dialog.Controls.Add($restore)
    $folder=New-Button 'Open backup folder';$folder.SetBounds(24,434,220,36);$dialog.Controls.Add($folder)
    $folder.Add_Click({$path=Join-Path (Get-DriverLibraryRoot) 'backups';[void][IO.Directory]::CreateDirectory($path);Start-Process -FilePath 'explorer.exe' -ArgumentList ('"'+$path+'"')})
    $entries=@(Get-DriverLibrary)
    foreach($group in $entries|Group-Object DeviceKey|Sort-Object{$_.Group[0].DeviceModel}){[void]$devices.Items.Add([pscustomobject]@{Name=$group.Group[0].DeviceModel;Entries=@($group.Group|Sort-Object SavedAt -Descending)})}
    $devices.Tag=$list;$devices.Add_SelectedIndexChanged({param($sender,$args)$target=$sender.Tag;$target.Items.Clear();foreach($item in $sender.SelectedItem.Entries){[void]$target.Items.Add([pscustomobject]@{Name=($item.Version+'  /  '+$(if($item.Original){'Original backup'}elseif($item.Kind -eq 'WindowsDriver'){'Windows driver backup'}else{'Vendor installer'})+'  /  '+([DateTimeOffset]$item.SavedAt).ToLocalTime().ToString('d'));Entry=$item})};if($target.Items.Count){$target.SelectedIndex=0}})
    $list.Tag=[pscustomobject]@{Restore=$restore;Note=$note}
    $list.Add_SelectedIndexChanged({param($sender,$args)$entry=$sender.SelectedItem.Entry;$sender.Tag.Restore.Enabled=[bool]$entry;$sender.Tag.Note.Text=if(!$entry){'No saved versions for this device.'}elseif($entry.Kind -eq 'Installer'){'Opens the verified vendor installer. The vendor controls reinstall or downgrade options.'}elseif($entry.Class -in 'NET','MEDIA','BLUETOOTH','DISPLAY'){'Restores this saved Windows driver to the selected device. Administrator permission is required; a restart may be needed.'}else{'This driver class needs Windows or vendor recovery. Opens the saved files and Device Manager.'}})
    $restore.Tag=[pscustomobject]@{List=$list;Dialog=$dialog}
    $restore.Add_Click({param($sender,$args)
        $entry=$sender.Tag.List.SelectedItem.Entry
        if(!$entry){return}
        if([Windows.Forms.MessageBox]::Show(('Restore '+$entry.DeviceModel+' to saved version '+$entry.Version+'?'),'Restore saved driver','OKCancel','Warning') -ne 'OK'){return}
        $sender.Tag.Dialog.Close()
        try{
            if($entry.Kind -eq 'Installer'){Install-SavedManufacturerDriver $entry}
            elseif($entry.Class -in 'NET','MEDIA','BLUETOOTH','DISPLAY'){
                $result=Invoke-BackupOperation 'Restore' $entry
                if($result){Show-Message $(if($result.Reboot){'Windows restored the selected driver and requested a restart. Restart when ready.'}else{'Windows completed the restore request. Check the hardware list to confirm the installed version.'});Start-Scan}
            }else{Start-Process -FilePath 'explorer.exe' -ArgumentList ('"'+(Join-Path $entry.Folder 'payload')+'"');Start-Process -FilePath (Join-Path $env:WINDIR 'System32\mmc.exe') -ArgumentList 'devmgmt.msc'}
        }catch{Show-Message ('Could not restore this version. '+$_.Exception.Message)}
    })
    if($devices.Items.Count){$devices.SelectedIndex=0}else{$note.Text='No backups yet. Use Back up installed drivers in Settings, or download a verified driver update.'}
    if($Preview){$dialog.Add_Shown({param($sender,$args)Save-FormPreview $sender 'rollback';$sender.Close()})}
    try{[void]$dialog.ShowDialog($form)}finally{$dialog.Dispose()}
}
function Install-SavedManufacturerDriver($entry) {
    if($SmokeTest -or $script:driverDownload -or $script:backupOperation -or $script:job -or $script:installer -or $script:packageInstaller -or $script:appDownload -or $script:appSetupProcess){return}
    $result=$null;$opened=$false
    try{
        $entry=Read-DriverLibraryEntry $entry.Folder
        $device=Assert-LibraryDevice $entry (Get-HardwareInventory)
        $setup=$null
        if([Threading.Mutex]::TryOpenExisting('Local\DriverLoom.Setup',[ref]$setup)){$setup.Dispose();throw 'Finish DriverLoom setup before opening the vendor installer.'}
        $script:driverInstallLock=[Threading.Mutex]::new($false,'Local\DriverLoom.DriverInstall')
        $result=Invoke-SavedDriverPreparation $entry
        if(!$result){return}
        $script:packageInstaller=Start-ManagedPackage $result
        $opened=$true;$script:fresh=$false
    }catch{Show-Message ('Could not open the saved installer. '+$_.Exception.Message)}
    finally{
        # Keep only the external process guard; setup has its own UI and permissions.
        if(!$opened -and $script:driverInstallLock){$script:driverInstallLock.Dispose();$script:driverInstallLock=$null}
        Refresh-View;Update-Controls
    }
}
function Receive-VendorSetupExit {
    if(!$script:packageInstaller){return}
    try{$value=$script:packageInstaller.HasExited;$exited=$value -isnot [bool] -or $value}catch{$exited=$true}
    if(!$exited){return}
    $script:packageInstaller.Dispose();$script:packageInstaller=$null
    if($script:driverInstallLock){$script:driverInstallLock.Dispose();$script:driverInstallLock=$null}
    # Process exit is not installation success; use normal refresh to read versions again.
    Update-Controls
}
function Invoke-SavedDriverPreparation($entry) {
    $dialog=New-Dialog 'Preparing saved driver' 286
    Add-DialogHeading $dialog 'Preparing saved driver' ($entry.DeviceModel+' / '+$entry.Version)
    $label=[Windows.Forms.Label]::new();$label.Text='Checking saved files and publisher...';$label.SetBounds(24,110,617,54);$dialog.Controls.Add($label)
    $progress=[DriverLoom.UI.DownloadProgress]::new();$progress.SetBounds(24,180,617,5);$dialog.Controls.Add($progress)
    $cancel=New-Button 'Cancel';$cancel.SetBounds(531,222,110,36);$dialog.Controls.Add($cancel)
    $cancelPath=Join-Path $entry.Folder ('prepare-cancel-'+[guid]::NewGuid().ToString('N'))
    try{
        $script:appDownload=[pscustomobject]@{Dialog=$dialog;Progress=$progress;Label=$label;CancelButton=$cancel;CancelPath=$cancelPath;Job=$null;Cancelled=$false;Closing=$false;Path='';Result=$null;Manufacturer=$true;PreserveDownload=$true;Failure=''}
        $cancel.Add_Click({Cancel-AppDownload})
        $dialog.Add_FormClosing({param($sender,$args)if(!$script:appDownload.Closing){$args.Cancel=$true;Cancel-AppDownload}})
        $script:appDownload.Job=Start-Job -ArgumentList $PSScriptRoot,$entry.Folder,$cancelPath -ScriptBlock {
            param($root,$folder,$cancel)
            $ErrorActionPreference='Stop';. (Join-Path $root 'Engine.ps1')
            $result=Prepare-SavedDriver $folder $cancel
            if(Test-Path -LiteralPath $cancel){if($result.Package.Family -eq 'ASUSDriver'){Remove-AsusRoot $result.Root};throw [OperationCanceledException]::new('Preparation cancelled.')}
            return $result
        }
        Update-Controls;[void]$dialog.ShowDialog($form)
        if($script:appDownload.Failure){throw $script:appDownload.Failure}
        if(!$script:appDownload.Cancelled){return $script:appDownload.Result}
    }finally{
        if($script:appDownload.Job){Remove-Job -Job $script:appDownload.Job -Force}
        $script:appDownload=$null;$dialog.Dispose()
        if(Test-Path -LiteralPath $cancelPath){[IO.File]::Delete($cancelPath)}
        Update-Controls
    }
}
