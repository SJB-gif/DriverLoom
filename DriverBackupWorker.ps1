param([Parameter(Mandatory=$true)][string]$JobFolder)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Engine.ps1')
$root=Join-Path (Get-DriverLibraryRoot) 'backups\jobs'
$JobFolder=[IO.Path]::GetFullPath($JobFolder)
if([IO.Path]::GetDirectoryName($JobFolder) -ine $root -or [IO.Path]::GetFileName($JobFolder) -cnotmatch '^[a-f0-9]{32}$'){throw 'Invalid backup operation folder.'}
$part=$JobFolder
while($part.Length -ge (Get-DriverLibraryRoot).Length){if((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Backup operation links are not supported.'};$part=[IO.Path]::GetDirectoryName($part)}
$request=Get-Content -LiteralPath (Join-Path $JobFolder 'request.json') -Raw|ConvertFrom-Json
if($request.UserSid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Use the same Windows account for the backup or restore elevation.'}
$lock=[Threading.Mutex]::new($false,'Local\DriverLoom.DriverInstall')
try{
    if($request.Operation -eq 'Backup'){
        $script:deferDriverRetention=[bool]$request.DeferRetention
        $devices=@(Get-InstalledBackupDevices|Where-Object{!@($request.Keys).Count -or $_.Key -cin @($request.Keys)})
        $saved=0;$errors=[Collections.Generic.List[string]]::new();$i=0
        foreach($device in $devices){
            if(Test-Path -LiteralPath (Join-Path $JobFolder 'cancel')){break}
            Save-Json (Join-Path $JobFolder 'progress.json') @{Percent=if($devices.Count){[int](100*$i/$devices.Count)}else{100};Message=('Backing up '+$device.Model)}
            try{$null=Export-InstalledDriver $device;$saved++}catch{$errors.Add($device.Model+': '+$_.Exception.Message)}
            $i++
        }
        Save-Json (Join-Path $JobFolder 'result.json') @{Success=$true;Saved=$saved;Total=$devices.Count;Errors=$errors.ToArray();Cancelled=(Test-Path -LiteralPath (Join-Path $JobFolder 'cancel'));Reboot=$false}
    }elseif($request.Operation -eq 'Restore'){
        $entry=Read-DriverLibraryEntry $request.EntryFolder
        if($entry.Kind -ne 'WindowsDriver' -or $entry.Class -notin 'NET','MEDIA','BLUETOOTH','DISPLAY' -or $entry.InstanceId -cne $request.InstanceId){throw 'This driver requires Windows or vendor recovery tools.'}
        $devices=@(Get-InstalledBackupDevices|Where-Object{$_.InstanceId -ceq $entry.InstanceId -and $_.Key -ceq $entry.DeviceKey})
        if($devices.Count -ne 1 -or $devices[0].Version -cne $request.CurrentVersion){throw 'The selected device or installed version changed. Refresh before restoring.'}
        $proof=Assert-DriverExport $entry
        if(!@($devices[0].HardwareIds|Where-Object{$_ -in $proof.Facts.Ids}).Count){throw 'The saved INF does not match this device hardware ID.'}
        $script:deferDriverRetention=$true;$null=Export-InstalledDriver $devices[0]
        # Copy verified content into an administrator-only folder before staging it in Windows.
        $secure=Join-Path $env:WINDIR ('Temp\DriverLoom-Restore-'+[guid]::NewGuid().ToString('N'))
        $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
        foreach($sid in 'S-1-5-18','S-1-5-32-544'){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))}
        [void][IO.Directory]::CreateDirectory($secure,$acl)
        try{
            foreach($name in $entry.FileNames){
                $from=Assert-LibraryPath (Get-AsusArchivePath $proof.Root $name);$to=Get-AsusArchivePath $secure $name
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to));Copy-Item -LiteralPath $from -Destination $to
            }
            $files=[DriverLoom.Security.AsusTrust]::Files($secure);$hashes=[DriverLoom.Security.AsusTrust]::HashFiles($secure,$files)
            if($files.Length -ne @($entry.FileNames).Count){throw 'The protected driver copy changed.'}
            for($i=0;$i -lt $files.Length;$i++){if($files[$i] -cne $entry.FileNames[$i] -or $hashes[$i] -cne $entry.FileHashes[$i]){throw 'The protected driver copy changed.'}}
            Add-Type -Path (Join-Path $PSScriptRoot 'DriverRestore.cs')
            $inf=Get-AsusArchivePath $secure $entry.Inf
            $current=@(Get-InstalledBackupDevices|Where-Object InstanceId -CEQ $entry.InstanceId)
            if($current.Count -ne 1 -or $current[0].Version -cne $request.CurrentVersion -or $current[0].Class -ine $entry.Class){throw 'The target driver changed during restore preparation.'}
            $published=[DriverLoom.Security.DriverRestore]::Stage($inf)
            $reboot=[DriverLoom.Security.DriverRestore]::Select($entry.InstanceId,$published,$entry.Version,$true)
            Save-Json (Join-Path $JobFolder 'result.json') @{Success=$true;Reboot=$reboot;Saved=0;Errors=@()}
        }finally{
            $resolved=[IO.Path]::GetFullPath($secure);$prefix=[IO.Path]::GetFullPath((Join-Path $env:WINDIR 'Temp')).TrimEnd('\')+'\'
            if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -cnotmatch '^DriverLoom-Restore-[a-f0-9]{32}$'){throw 'Unsafe restore cleanup path.'}
            Remove-Item -LiteralPath $resolved -Recurse -Force
            Limit-DriverLibrary $entry.DeviceKey
        }
    }else{throw 'Unknown driver operation.'}
}catch{Save-Json (Join-Path $JobFolder 'result.json') @{Success=$false;Error=$_.Exception.Message}}
finally{$lock.Dispose()}
