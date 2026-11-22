# Persistent, verified local packages. Manifest paths never authorise arbitrary executables.
function Get-DriverLibraryRoot {Join-Path $env:LOCALAPPDATA 'HardwareUpdateLauncher'}
function Get-DriverDeviceId([string]$key) {
    $hash=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($key))).Replace('-','').ToLowerInvariant().Substring(0,24)}finally{$hash.Dispose()}
}
function Assert-LibraryPath([string]$path) {
    $root=[IO.Path]::GetFullPath((Get-DriverLibraryRoot)).TrimEnd('\');$path=[IO.Path]::GetFullPath($path)
    $relative=$path.Substring([Math]::Min($root.Length+1,$path.Length))
    if(!$path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or $relative -cnotmatch '^(drivers|backups)\\[a-f0-9]{24}\\[a-f0-9]{32}(?:\\[^<>:"|?*\x00-\x1f]+)*$'){throw 'Invalid driver library path.'}
    $part=$path
    while($part.Length -ge $root.Length){
        if((Test-Path -LiteralPath $part) -and ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Driver library links are not supported.'}
        if($part -eq $root){break};$part=[IO.Path]::GetDirectoryName($part)
    }
    return $path
}
function New-DriverLibraryFolder([string]$key,[string]$area='drivers') {
    if($area -notin 'drivers','backups'){throw 'Invalid driver library area.'}
    $path=Assert-LibraryPath (Join-Path (Get-DriverLibraryRoot) ($area+'\'+(Get-DriverDeviceId $key)+'\'+[guid]::NewGuid().ToString('N')))
    [void][IO.Directory]::CreateDirectory($path);return $path
}
function Remove-DriverLibraryFolder([string]$folder) {
    $folder=Assert-LibraryPath $folder
    if($folder -cnotmatch '\\[a-f0-9]{24}\\[a-f0-9]{32}$'){throw 'Refusing to remove a library parent.'}
    if(Test-Path -LiteralPath $folder){if(Test-DriverFolderInUse $folder){return};Initialize-AsusTrust;$null=[DriverLoom.Security.AsusTrust]::Files($folder);Remove-Item -LiteralPath $folder -Recurse -Force}
}
function Get-DriverBootSession {
    if(!$script:driverBootSession){
        try{$script:driverBootSession=(Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o')}
        catch{$script:driverBootSession='unknown'}
    }
    return $script:driverBootSession
}
function Test-PreparedSetupInUse([string]$root) {
    $marker=$root+'.started.json'
    if(!(Test-Path -LiteralPath $marker -PathType Leaf)){return $false}
    try{
        if((Get-Item -LiteralPath $marker).Length -gt 4096){return $true}
        $session=(Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json).BootSession
        $current=Get-DriverBootSession
        return !$session -or $session -eq 'unknown' -or $current -eq 'unknown' -or $session -ceq $current
    }catch{return $true}
}
function Test-DriverFolderInUse([string]$folder) {
    foreach($setup in Get-ChildItem -LiteralPath $folder -Directory -Force|Where-Object Name -cmatch '^setup-[a-f0-9]{8}$'){
        if(Test-PreparedSetupInUse $setup.FullName){return $true}
    }
    return $false
}
function Clear-PreparedDriverFolders([string]$folder,[switch]$KeepNewest) {
    $folder=Assert-LibraryPath $folder
    $setups=@(Get-ChildItem -LiteralPath $folder -Directory -Force|Where-Object Name -cmatch '^setup-[a-f0-9]{8}$'|Sort-Object CreationTimeUtc -Descending)
    foreach($setup in $setups){
        if(($KeepNewest -and $setup.FullName -ceq $setups[0].FullName) -or (Test-PreparedSetupInUse $setup.FullName)){continue}
        Remove-AsusRoot $setup.FullName
        $marker=$setup.FullName+'.started.json';if(Test-Path -LiteralPath $marker){[IO.File]::Delete($marker)}
    }
}
function Maintain-DriverLibrary {
    $busy=$null
    if([Threading.Mutex]::TryOpenExisting('Local\DriverLoom.DriverInstall',[ref]$busy)){$busy.Dispose();return}
    $entries=@(Get-DriverLibrary)
    foreach($entry in $entries){Clear-PreparedDriverFolders $entry.Folder -KeepNewest}
    foreach($key in $entries.DeviceKey|Select-Object -Unique){Limit-DriverLibrary $key}
}
function Register-PreparedSetupLaunch($result) {
    if(!(Test-PersistentAsusRoot $result.Root)){return}
    Save-Json ($result.Root+'.started.json') @{BootSession=Get-DriverBootSession;OpenedAt=[DateTimeOffset]::UtcNow.ToString('o')}
}
function Get-SavedPackageFormat([string]$path) {
    $stream=[IO.File]::OpenRead($path)
    try{$header=[byte[]]::new(4);$count=$stream.Read($header,0,4)}finally{$stream.Dispose()}
    if($count -ge 2 -and $header[0] -eq 0x4d -and $header[1] -eq 0x5a){return 'EXE'}
    if($count -eq 4 -and $header[0] -eq 0x50 -and $header[1] -eq 0x4b -and (($header[2] -eq 3 -and $header[3] -eq 4) -or ($header[2] -eq 5 -and $header[3] -eq 6) -or ($header[2] -eq 7 -and $header[3] -eq 8))){return 'ZIP'}
    throw 'The saved download is not a supported EXE or ZIP package.'
}
function Read-DriverLibraryEntry([string]$folder) {
    $folder=Assert-LibraryPath $folder;$path=Join-Path $folder 'package.json'
    if(!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -gt 4194304){throw 'Saved driver metadata is missing or too large.'}
    $entry=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    $date=[DateTimeOffset]::MinValue
    if($entry.Schema -ne 1 -or $entry.Kind -notin 'Installer','WindowsDriver' -or !$entry.DeviceKey -or !$entry.DeviceModel -or !$entry.Version -or $entry.Original -isnot [bool] -or ![DateTimeOffset]::TryParse($entry.SavedAt,[ref]$date) -or (Split-Path (Split-Path $folder -Parent) -Leaf) -cne (Get-DriverDeviceId $entry.DeviceKey)){throw 'Saved driver metadata is invalid.'}
    $entry|Add-Member NoteProperty Folder $folder -Force;return $entry
}
function Get-DriverLibrary {
    foreach($area in 'drivers','backups'){
        $root=Join-Path (Get-DriverLibraryRoot) $area
        if(!(Test-Path -LiteralPath $root)){continue}
        foreach($device in Get-ChildItem -LiteralPath $root -Directory -Force|Where-Object Name -cmatch '^[a-f0-9]{24}$'){
            if($device.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            foreach($folder in Get-ChildItem -LiteralPath $device.FullName -Directory -Force|Where-Object Name -cmatch '^[a-f0-9]{32}$'){
                try{Read-DriverLibraryEntry $folder.FullName}catch{Write-Verbose ('Unreadable saved driver: '+$_.Exception.Message)}
            }
        }
    }
}
function Move-DriverEntry($entry,[string]$area) {
    $folder=Assert-LibraryPath $entry.Folder
    $target=Assert-LibraryPath (Join-Path (Get-DriverLibraryRoot) ($area+'\'+(Get-DriverDeviceId $entry.DeviceKey)+'\'+[IO.Path]::GetFileName($folder)))
    if($folder -ine $target){if(Test-DriverFolderInUse $folder){return $entry};[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target));Move-Item -LiteralPath $folder -Destination $target;$entry.Folder=$target}
    return $entry
}
function Limit-DriverLibrary([string]$key) {
    $entries=@(Get-DriverLibrary|Where-Object DeviceKey -CEQ $key|Sort-Object {[DateTimeOffset]$_.SavedAt} -Descending)
    $latest=$entries|Where-Object Kind -eq 'Installer'|Select-Object -First 1
    $original=$entries|Where-Object Original|Sort-Object {[DateTimeOffset]$_.SavedAt}|Select-Object -First 1
    $previous=$entries|Where-Object{$_.Folder -cne $latest.Folder -and $_.Folder -cne $original.Folder}|Select-Object -First 1
    $keep=@($latest,$original,$previous|Where-Object{$_})
    foreach($entry in $entries){
        if($entry.Folder -cin @($keep.Folder)){$null=Move-DriverEntry $entry $(if($entry.Folder -ceq $latest.Folder){'drivers'}else{'backups'})}
        else{Remove-DriverLibraryFolder $entry.Folder}
    }
}
function Save-DriverDownload($result,$device,[switch]$DeferRetention) {
    Assert-VerifiedPackage $result
    $file=if($result.Package.Family -eq 'ASUSDriver'){$result.ArchivePath}else{$result.Path}
    $folder=Assert-LibraryPath ([IO.Path]::GetDirectoryName($file))
    $boards=@((Get-HardwareInventory).Inventory|Where-Object Kind -eq 'Motherboard'|ForEach-Object Key|Sort-Object)
    $entry=[pscustomobject]@{Schema=1;Kind='Installer';DeviceKey=$device.Key;DeviceModel=$device.Model;Version=$result.Package.Version;SavedAt=[DateTimeOffset]::UtcNow.ToString('o');Original=$false;Package=$result.Package;HardwareIds=@($device.IDs);BoardKeys=$boards;FileName=[IO.Path]::GetFileName($file);SHA256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant();Bytes=(Get-Item -LiteralPath $file).Length}
    Save-Json (Join-Path $folder 'package.json') $entry
    if($result.Package.Family -eq 'ASUSDriver'){Remove-AsusRoot $result.Root}
    if(!$DeferRetention){Complete-DriverDownload $folder}
    return (Read-DriverLibraryEntry $folder)
}
function Complete-DriverDownload([string]$folder) {
    $entry=Read-DriverLibraryEntry $folder
    if($entry.Kind -ne 'Installer'){throw 'Only downloaded installers can become ready.'}
    foreach($old in @(Get-DriverLibrary|Where-Object{$_.Kind -eq 'Installer' -and $_.DeviceKey -ceq $entry.DeviceKey -and $_.Version -ceq $entry.Version -and $_.Folder -cne $folder})){Remove-DriverLibraryFolder $old.Folder}
    Limit-DriverLibrary $entry.DeviceKey
}
function Get-ReadyDriver($device,$check,$entries=$null) {
    if(!(Test-ManagedPackageOffer $device $check)){return $null}
    if($null -eq $entries){$entries=@(Get-DriverLibrary)}
    return $entries|Where-Object{$_.Kind -eq 'Installer' -and $_.DeviceKey -ceq $device.Key -and $_.Version -ceq $check.Available -and $_.Package.Url -ceq $check.Package.Url -and $_.Package.SourceUrl -ceq $check.Url}|Sort-Object SavedAt -Descending|Select-Object -First 1
}
function Assert-LibraryDevice($entry,$data) {
    $target=Get-WindowsDriverTarget $data.OS
    if($entry.Kind -eq 'Installer'){
        Assert-ManagedPackage $entry.Package
        if($entry.Package.DeviceKey -cne $entry.DeviceKey -or $entry.Package.DeviceModel -cne $entry.DeviceModel -or $entry.Package.Version -cne $entry.Version -or (@($entry.BoardKeys)-join '|') -cne (@($data.Inventory|Where-Object Kind -eq 'Motherboard'|ForEach-Object Key|Sort-Object)-join '|')){throw 'Saved installer device or board metadata does not match.'}
        if($entry.Package.OSFamily -cne $target.Family){throw 'The saved installer targets a different Windows version.'}
        $device=@($data.Inventory|Where-Object Key -CEQ $entry.DeviceKey)
        if($device.Count -ne 1 -or $device[0].Model -cne $entry.DeviceModel){throw 'The saved device no longer matches this PC.'}
        if($entry.Package.Family -eq 'ASUSDriver'){
            if(@($data.Inventory|Where-Object{$_.Kind -eq 'Motherboard' -and $_.Key -ceq $entry.Package.BoardKey}).Count -ne 1 -or (@(Get-AsusHardwareIds $device[0])-join '|') -cne (@($entry.Package.HardwareIds)-join '|')){throw 'The ASUS board or hardware IDs changed.'}
        }elseif($entry.Package.Family -eq 'AMDRadeon'){
            if(@($data.Inventory|Where-Object{$_.Key -ceq $entry.Package.GpuKey -and $_.Model -ceq $entry.Package.GpuModel}).Count -ne 1){throw 'The saved Radeon GPU no longer matches.'}
        }
        return $device[0]
    }
}
function Assert-LibraryFile($entry) {
    if($entry.FileName -cnotmatch '^[a-zA-Z0-9._-]+\.(exe|zip)$' -or $entry.SHA256 -cnotmatch '^[a-f0-9]{64}$' -or $entry.Bytes -le 0 -or $entry.Bytes -gt 2147483648){throw 'Invalid saved installer metadata.'}
    $path=Assert-LibraryPath (Join-Path $entry.Folder $entry.FileName)
    if(!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -ne $entry.Bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.SHA256){throw 'The saved installer is missing or changed. Download it again.'}
    if($entry.Package.Family -ne 'ASUSDriver'){Assert-PackageSignature $path $entry.Package}
    if((Get-Content -LiteralPath $path -Stream Zone.Identifier -Raw) -notmatch '(?m)^ZoneId=3\r?$'){throw 'The saved installer lost its Internet marker.'}
    return $path
}
function Prepare-SavedDriver([string]$folder,[string]$cancel='') {
    $entry=Read-DriverLibraryEntry $folder
    if($entry.Kind -ne 'Installer'){throw 'This saved version is a Windows driver export.'}
    $null=Assert-LibraryDevice $entry (Get-HardwareInventory);$path=Assert-LibraryFile $entry
    $format=Get-SavedPackageFormat $path
    if($format -eq 'EXE'){
        if($entry.Package.Family -eq 'ASUSDriver' -or [IO.Path]::GetExtension($path) -ine '.exe'){throw 'This saved package does not match its expected installer format.'}
        return [pscustomobject]@{Path=$path;Package=$entry.Package;Bytes=$entry.Bytes;SHA256=$entry.SHA256}
    }
    if($entry.Package.Family -ne 'ASUSDriver' -or [IO.Path]::GetExtension($path) -ine '.zip'){throw 'This ZIP has no verified setup adapter. Use its official vendor source.'}
    Clear-PreparedDriverFolders $entry.Folder
    $root=Join-Path $entry.Folder ('setup-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    try{
        if(!$cancel){$cancel=Join-Path $entry.Folder 'cancel-unused'}
        Expand-AsusArchive $path $root $cancel
        $setup=Join-Path $root 'AsusSetup.exe';Assert-AsusSetup $setup
        Set-Content -LiteralPath $setup -Stream Zone.Identifier -Value (Get-Content -LiteralPath $path -Stream Zone.Identifier -Raw) -Encoding ASCII -NoNewline
        $files=[DriverLoom.Security.AsusTrust]::Files($root)
        $result=[pscustomobject]@{Path=$setup;Root=$root;Package=$entry.Package;ArchivePath=$path;ArchiveSHA256=$entry.SHA256;FileNames=$files;FileHashes=[DriverLoom.Security.AsusTrust]::HashFiles($root,$files);Proof=Get-AsusDriverProof $root $entry.Package}
        Assert-VerifiedPackage $result;return $result
    }catch{Remove-AsusRoot $root;throw}
}
function Get-InstalledBackupDevices {
    $present=@{};Get-PnpDevice -PresentOnly|ForEach-Object{$present[$_.InstanceId]=$true}
    $inventory=Get-HardwareInventory
    foreach($driver in Get-CimInstance Win32_PnPSignedDriver|Where-Object{$present.ContainsKey($_.DeviceID) -and $_.InfName -match '^oem\d+\.inf$' -and $_.DriverVersion}){
        $row=$inventory.Inventory|Where-Object InstanceId -EQ $driver.DeviceID|Select-Object -First 1
        if(!$row){$row=New-HardwareRow 'Windows driver' $driver.Manufacturer $driver.DeviceName $driver.HardWareID '' $driver.DriverVersion @($driver.HardWareID)}
        [pscustomobject]@{Key=$row.Key;Model=$row.Model;Version=$driver.DriverVersion;InfName=$driver.InfName;InstanceId=$driver.DeviceID;Class=$driver.DeviceClass;HardwareIds=@($row.IDs)}
    }
}
function Assert-DriverExport($entry) {
    Initialize-AsusTrust
    $root=Assert-LibraryPath (Join-Path $entry.Folder 'payload')
    $files=[DriverLoom.Security.AsusTrust]::Files($root)
    if($files.Length -ne @($entry.FileNames).Count -or $files.Length -ne @($entry.FileHashes).Count){throw 'The Windows backup file list changed.'}
    $hashes=[DriverLoom.Security.AsusTrust]::HashFiles($root,$files)
    for($i=0;$i -lt $files.Length;$i++){if($files[$i] -cne $entry.FileNames[$i] -or $hashes[$i] -cne $entry.FileHashes[$i]){throw 'A Windows backup file changed.'}}
    $inf=Get-AsusArchivePath $root $entry.Inf
    $facts=Read-AsusInf $inf
    if([version]$facts.Version -ne [version]$entry.Version -or $facts.DeviceClass -ine $entry.Class -or $facts.Catalog -notmatch '^[a-zA-Z0-9_.-]+\.cat$'){throw 'The Windows backup INF class/version/catalog does not match.'}
    $cat=Join-Path ([IO.Path]::GetDirectoryName($inf)) $facts.Catalog
    if((Get-AuthenticodeSignature -LiteralPath $cat).Status -ne 'Valid' -or !(Test-AsusCatalogMember $inf $cat)){throw 'Windows could not verify the backup driver catalog.'}
    return [pscustomobject]@{Root=$root;Inf=$inf;Facts=$facts}
}
function Export-InstalledDriver($device) {
    $existing=Get-DriverLibrary|Where-Object{$_.Kind -eq 'WindowsDriver' -and $_.DeviceKey -ceq $device.Key -and $_.Version -ceq $device.Version}|Select-Object -First 1
    if($existing){$null=Assert-DriverExport $existing;return $existing}
    $folder=New-DriverLibraryFolder $device.Key 'backups';$payload=Join-Path $folder 'payload';[void][IO.Directory]::CreateDirectory($payload)
    try{
        if($device.InfName -notmatch '^oem\d+\.inf$'){throw 'Only installed third-party OEM driver packages can be exported.'}
        Invoke-DriverExportCommand $device.InfName $payload
        Initialize-AsusTrust
        $files=[DriverLoom.Security.AsusTrust]::Files($payload);$inf=''
        foreach($file in $files|Where-Object{$_ -match '\.inf$'}){try{$facts=Read-AsusInf (Join-Path $payload $file);if([version]$facts.Version -eq [version]$device.Version -and $facts.DeviceClass -ieq $device.Class){$inf=$file;break}}catch{}}
        if(!$inf){throw 'The exported driver has no matching INF version.'}
        $entry=[pscustomobject]@{Schema=1;Kind='WindowsDriver';DeviceKey=$device.Key;DeviceModel=$device.Model;Version=$device.Version;SavedAt=[DateTimeOffset]::UtcNow.ToString('o');Original=@(Get-DriverLibrary|Where-Object{$_.DeviceKey -ceq $device.Key -and $_.Original}).Count -eq 0;InstanceId=$device.InstanceId;Class=$device.Class;HardwareIds=$device.HardwareIds;Inf=$inf;FileNames=$files;FileHashes=[DriverLoom.Security.AsusTrust]::HashFiles($payload,$files);Folder=$folder}
        $null=Assert-DriverExport $entry
        Save-Json (Join-Path $folder 'package.json') ($entry|Select-Object * -ExcludeProperty Folder)
        if(!$script:deferDriverRetention){Limit-DriverLibrary $device.Key}
        return (Read-DriverLibraryEntry $folder)
    }catch{Remove-DriverLibraryFolder $folder;throw}
}
function Invoke-DriverExportCommand([string]$inf,[string]$folder) {
    if($inf -notmatch '^oem\d+\.inf$'){throw 'Invalid installed INF name.'}
    $log=& (Join-Path $env:WINDIR 'System32\pnputil.exe') /export-driver $inf $folder 2>&1
    if($LASTEXITCODE -ne 0){throw 'Windows could not export this installed driver.'}
}
