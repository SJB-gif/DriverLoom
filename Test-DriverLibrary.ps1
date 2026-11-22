$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Engine.ps1')
Initialize-AsusTrust
Add-Type -Path (Join-Path $PSScriptRoot 'DriverRestore.cs')
$oldData=$env:LOCALAPPDATA;$root=Join-Path ([IO.Path]::GetTempPath()) ('driverloom-library-'+[guid]::NewGuid().ToString('N'))
function Assert-LibraryTest($expected,$actual,[string]$why){if($expected -cne $actual){throw "$why expected '$expected', got '$actual'."}}
function Reject-LibraryTest([scriptblock]$action,[string]$why){$rejected=$false;try{$null=& $action}catch{$rejected=$true};if(!$rejected){throw $why}}
function Assert-PackageSignature($path,$package){if($script:badSigner){throw 'Fixture invalid signer.'}}
function Get-HardwareInventory {[pscustomobject]@{OS='10.0.26300.0';Inventory=@($script:board,$script:device)}}
function Get-AuthenticodeSignature {
    param($LiteralPath)
    $cert=[pscustomobject]@{Name=if($LiteralPath -match '\.exe$'){'ASUSTeK COMPUTER INC.'}else{'Microsoft Windows Hardware Compatibility Publisher'}}
    $cert|Add-Member ScriptMethod GetNameInfo {param($type,$issuer)return $this.Name}
    [pscustomobject]@{Status=if($script:badCatalog){'NotTrusted'}else{'Valid'};SignerCertificate=$cert}
}
function Test-AsusCatalogMember {param($path,$catalog)return !$script:badMember}
function Invoke-DriverExportCommand($inf,$folder){
    Assert-LibraryTest 'oem42.inf' $inf 'export uses the exact installed OEM INF'
    [IO.File]::WriteAllText((Join-Path $folder 'driver.inf'),$script:infText)
    [IO.File]::WriteAllText((Join-Path $folder 'driver.cat'),'fixture catalog; never installed')
    [IO.File]::WriteAllText((Join-Path $folder 'driver.sys'),'fixture driver; never installed')
}
function New-LibraryInstaller([string]$version,[switch]$DeferRetention){
    $folder=New-DriverLibraryFolder $script:device.Key;$file=Join-Path $folder 'NVIDIA-Driver-Setup.exe';[IO.File]::WriteAllText($file,('MZ fixture '+$version))
    Set-Content -LiteralPath $file -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII
    $package=New-ManagedPackage 'NvidiaDesktop' $script:device (Get-WindowsDriverTarget '10.0.26300.0') $version 'https://www.nvidia.com/en-us/drivers/details/12345/' ('https://us.download.nvidia.com/Windows/'+$version+'/'+$version+'-desktop-win10-win11-64bit-international-dch-whql.exe')
    Save-DriverDownload ([pscustomobject]@{Path=$file;Package=$package;Bytes=(Get-Item -LiteralPath $file).Length;SHA256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()}) $script:device -DeferRetention:$DeferRetention
}
try{
    $env:LOCALAPPDATA=$root
    $script:driverBootSession='fixture-boot-1'
    $fakeZip=Join-Path $root 'wrong.zip';[void][IO.Directory]::CreateDirectory($root);[IO.File]::WriteAllText($fakeZip,'not a ZIP')
    Reject-LibraryTest {Get-SavedPackageFormat $fakeZip} 'a ZIP extension cannot disguise invalid data'
    Reject-LibraryTest {Start-ManagedPackage ([pscustomobject]@{Path=$fakeZip})} 'ZIP archive cannot be dispatched to Windows'
    $script:board=New-HardwareRow 'Motherboard' 'ASUSTeK' 'Fixture board' '' '' '' @()
    $script:device=New-HardwareRow 'GPU driver' 'NVIDIA' 'NVIDIA GeForce RTX 4080 SUPER' '' '' '31.0.1.0' @('PCI\VEN_10DE&DEV_2702')
    $script:infText=@'
[Version]
Signature="$Windows NT$"
Class=Display
ClassGuid={4d36e968-e325-11ce-bfc1-08002be10318}
Provider=%Vendor%
DriverVer=01/01/2026,31.0.1.0
CatalogFile=driver.cat
[Manufacturer]
%Vendor%=Models,NTamd64
[Models.NTamd64]
%Device%=Install,PCI\VEN_10DE&DEV_2702
[Install]
[Strings]
Vendor="Fixture"
Device="Fixture GPU"
'@
    $backupDevice=[pscustomobject]@{Key=$script:device.Key;Model=$script:device.Model;Version='31.0.1.0';Class='DISPLAY';InfName='oem42.inf';InstanceId='PCI\FIXTURE';HardwareIds=$script:device.IDs}
    $original=Export-InstalledDriver $backupDevice
    Assert-LibraryTest $true $original.Original 'first installed-driver export is the protected original'
    $again=Export-InstalledDriver $backupDevice
    Assert-LibraryTest $original.Folder $again.Folder 'repeat backup reuses an intact identical installed version'
    $first=New-LibraryInstaller '551.01';$second=New-LibraryInstaller '552.01';$third=New-LibraryInstaller '553.01'
    $all=@(Get-DriverLibrary)
    Assert-LibraryTest 3 $all.Count 'retention caps a device at original, previous and latest'
    Assert-LibraryTest $true (Test-Path -LiteralPath $original.Folder) 'original survives newer downloads'
    Assert-LibraryTest $false (Test-Path -LiteralPath $first.Folder) 'unneeded old installer removed'
    Assert-LibraryTest 1 @($all|Where-Object{$_.Folder -like '*\drivers\*'}).Count 'only latest installer is in drivers'
    $previous=$all|Where-Object Version -eq '552.01'
    Assert-LibraryTest $true ($previous.Folder -like '*\backups\*') 'previous installer is in backups'
    $cancelled=New-LibraryInstaller '554.01' -DeferRetention
    Remove-DriverLibraryFolder $cancelled.Folder
    Assert-LibraryTest 3 @(Get-DriverLibrary).Count 'cancelling at completion preserves all previous copies'
    Assert-LibraryTest $true (Test-Path -LiteralPath $previous.Folder) 'cancel does not prune previous installer'
    $check=[pscustomobject]@{Checked=$true;Status='Newer at source';Available='553.01';Url=$third.Package.SourceUrl;Package=$third.Package}
    Assert-LibraryTest $third.Folder (Get-ReadyDriver $script:device $check).Folder 'a ready download is found after restart'
    $prepared=Prepare-SavedDriver $previous.Folder
    Assert-LibraryTest '552.01' $prepared.Package.Version 'saved old version works offline without resolving the latest offer'
    $script:badSigner=$true;Reject-LibraryTest {Prepare-SavedDriver $third.Folder} 'invalid signer accepted';$script:badSigner=$false
    $file=Join-Path $third.Folder $third.FileName;[IO.File]::WriteAllText($file,'altered fixture')
    Reject-LibraryTest {Prepare-SavedDriver $third.Folder} 'tampered installer accepted'
    $script:board=New-HardwareRow 'Motherboard' 'ASUS' 'Different board' '' '' '' @()
    Reject-LibraryTest {Prepare-SavedDriver $previous.Folder} 'different board accepted'
    $script:badCatalog=$true;Reject-LibraryTest {Assert-DriverExport $original} 'untrusted backup catalog accepted';$script:badCatalog=$false
    $script:badMember=$true;Reject-LibraryTest {Assert-DriverExport $original} 'wrong catalog member accepted';$script:badMember=$false
    $payload=Join-Path $original.Folder 'payload\driver.sys';[IO.File]::WriteAllText($payload,'tampered')
    Reject-LibraryTest {Assert-DriverExport $original} 'altered exported driver accepted'
    $script:device=New-HardwareRow 'Network driver' 'Intel' 'Intel I225-V' '' '' '1.0.0.0' @('PCI\VEN_8086&DEV_15F3&REV_03')
    $asusFolder=New-DriverLibraryFolder $script:device.Key;$archive=Join-Path $asusFolder 'ASUS-Driver.zip'
    $zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
    try{
        $inf=$script:infText.Replace('Class=Display','Class=Net').Replace('{4d36e968-e325-11ce-bfc1-08002be10318}','{4d36e972-e325-11ce-bfc1-08002be10318}').Replace('31.0.1.0','2.3.4.5').Replace('PCI\VEN_10DE&DEV_2702','PCI\VEN_8086&DEV_15F3&REV_03')
        foreach($pair in @(@('AsusSetup.exe','fixture setup; never run'),@('driver.inf',$inf),@('driver.cat','fixture catalog'),@('AsusSetup.ini','fixture config'))){$writer=[IO.StreamWriter]::new($zip.CreateEntry($pair[0]).Open());try{$writer.Write($pair[1])}finally{$writer.Dispose()}}
    }finally{$zip.Dispose()}
    Set-Content -LiteralPath $archive -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII
    $asusPackage=New-AsusPackage $script:device $script:board (Get-WindowsDriverTarget '10.0.26300.0') 'LAN' ([pscustomobject]@{Version='2.3.4.5';DownloadUrl=@{Global='/pub/ASUS/mb/fixture.zip'};sha256=''}) ('https://www.asus.com/supportonly/'+[Uri]::EscapeDataString($script:board.Model)+'/helpdesk_download/')
    $asusRoot=Join-Path ([IO.Path]::GetTempPath()) ('DriverLoom-ASUS-'+[guid]::NewGuid().ToString('N'))
    Expand-AsusArchive $archive $asusRoot (Join-Path $asusFolder 'cancel-unused');$setup=Join-Path $asusRoot 'AsusSetup.exe'
    Set-Content -LiteralPath $setup -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII
    $files=[DriverLoom.Security.AsusTrust]::Files($asusRoot)
    $savedAsus=Save-DriverDownload ([pscustomobject]@{Path=$setup;Root=$asusRoot;Package=$asusPackage;ArchivePath=$archive;ArchiveSHA256=(Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant();FileNames=$files;FileHashes=[DriverLoom.Security.AsusTrust]::HashFiles($asusRoot,$files);Proof=Get-AsusDriverProof $asusRoot $asusPackage}) $script:device
    Assert-LibraryTest $false (Test-Path -LiteralPath $asusRoot) 'download keeps only the durable ASUS archive'
    $preparedAsus=Prepare-SavedDriver $savedAsus.Folder
    Assert-LibraryTest 'ZIP' (Get-SavedPackageFormat $archive) 'actual ZIP content is detected'
    Assert-LibraryTest 'PCI\VEN_8086&DEV_15F3&REV_03' $preparedAsus.Proof.HardwareId 'ASUS archive prepares and verifies offline after reload'
    Assert-LibraryTest $savedAsus.Folder ([IO.Path]::GetDirectoryName($preparedAsus.Root)) 'extracted setup stays beside the saved ZIP'
    Assert-LibraryTest $true (Test-PersistentAsusRoot $preparedAsus.Root) 'persistent root is constrained to this library version'
    $script:launches=0
    function Start-Process {param($FilePath,$WorkingDirectory,[switch]$PassThru)
        Assert-LibraryTest (Join-Path $preparedAsus.Root 'AsusSetup.exe') $FilePath 'only extracted setup is dispatched'
        Assert-LibraryTest $preparedAsus.Root $WorkingDirectory 'vendor setup uses the full extracted directory'
        $script:launches++;return [pscustomobject]@{HasExited=$true}
    }
    $null=Start-ManagedPackage $preparedAsus
    Assert-LibraryTest 1 $script:launches 'one verified EXE reaches the mocked launcher'
    Clear-PreparedDriverFolders $savedAsus.Folder
    Assert-LibraryTest $true (Test-Path -LiteralPath $preparedAsus.Path) 'launched payload is retained for vendor child processes'
    Remove-DriverLibraryFolder $savedAsus.Folder
    Assert-LibraryTest $true (Test-Path -LiteralPath $archive) 'retention cannot delete an in-use setup version'
    $beforeMove=$savedAsus.Folder;$notMoved=Move-DriverEntry $savedAsus 'backups'
    Assert-LibraryTest $beforeMove $notMoved.Folder 'retention cannot move an in-use setup version'
    Assert-LibraryTest $true (Test-Path -LiteralPath $preparedAsus.Path) 'external setup retains its original working directory'
    $preparedAgain=Prepare-SavedDriver $savedAsus.Folder
    Assert-LibraryTest $true ($preparedAgain.Root -cne $preparedAsus.Root) 'new preparation never overwrites a launched setup folder'
    Remove-AsusRoot $preparedAgain.Root
    Assert-LibraryTest $true (Test-Path -LiteralPath $archive) 'cancelled preparation leaves the ZIP available'
    $script:driverBootSession='fixture-boot-2'
    Clear-PreparedDriverFolders $savedAsus.Folder -KeepNewest
    Assert-LibraryTest $true (Test-Path -LiteralPath $preparedAsus.Path) 'latest extracted folder persists across restarts'
    Clear-PreparedDriverFolders $savedAsus.Folder
    Assert-LibraryTest $false (Test-Path -LiteralPath $preparedAsus.Root) 'stale preparation can be replaced after a reboot'
    foreach($path in @($root,(Join-Path (Get-DriverLibraryRoot) 'drivers'),(Join-Path (Get-DriverLibraryRoot) 'drivers\..\outside'))){Reject-LibraryTest {Remove-DriverLibraryFolder $path} 'unsafe library cleanup accepted'}
    # Native lookup is read-only: no Stage call and install=false on a present Windows fixture.
    $nativeChecked=$false
    $present=@{};Get-PnpDevice -PresentOnly|ForEach-Object{$present[$_.InstanceId]=$true}
    foreach($driver in Get-CimInstance Win32_PnPSignedDriver|Where-Object{$present.ContainsKey($_.DeviceID) -and $_.InfName -and $_.DriverVersion -match '^\d+\.\d+\.\d+\.\d+$'}|Select-Object -First 60){
        try{[void][DriverLoom.Security.DriverRestore]::Select($driver.DeviceID,(Join-Path $env:WINDIR ('INF\'+$driver.InfName)),$driver.DriverVersion,$false);$nativeChecked=$true;break}catch{if($_.Exception.ToString() -notmatch 'Windows did not offer|not present|0xe000020b|0x800f020b'){throw}}
    }
    if(!$nativeChecked){throw 'No present compatible Windows fixture was found for read-only restore lookup.'}
    'Driver library checks passed: persistence, offline use, retention, exact device/board, signature and tampering rejection, export validation and read-only native restore lookup. No driver was exported, installed or restored.'
}finally{
    $env:LOCALAPPDATA=$oldData
    $resolved=[IO.Path]::GetFullPath($root);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
