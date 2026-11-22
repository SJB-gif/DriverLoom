$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'src'
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
. (Join-Path $srcRoot 'Engine.ps1')
. (Join-Path $srcRoot 'AppDownloads.ps1')
Initialize-AsusTrust
function Assert-AsusTest($expected,$actual,[string]$message){if($expected -cne $actual){throw "$message expected '$expected', got '$actual'."}}
function Reject-AsusTest([scriptblock]$action,[string]$message){$failed=$false;try{& $action}catch{$failed=$true};Assert-AsusTest $true $failed $message}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('driverloom-asus-tests-'+[guid]::NewGuid().ToString('N'))
$board=New-HardwareRow 'Motherboard' 'ASUSTeK' 'ROG STRIX X670E-A GAMING WIFI' '' '1.0' '' @()
$script:mode='good';$script:category='LAN';$script:reads=0;$script:starts=0;$script:fixture='';$script:folder=''
$script:devices=@{
    LAN=(New-HardwareRow 'Network driver' 'Intel' 'Intel I225-V' '' '' '1.0.0.0' @('PCI\VEN_8086&DEV_15F3&REV_03'))
    Wireless=(New-HardwareRow 'Network driver' 'MediaTek' 'MediaTek Wi-Fi MT7922 RZ616' '' '' '1.0.0.0' @('PCI\VEN_14C3&DEV_0616&SUBSYS_061614C3'))
    Bluetooth=(New-HardwareRow 'Bluetooth driver' 'MediaTek' 'MediaTek Bluetooth Adapter' '' '' '1.0.0.0' @('USB\VID_0489&PID_E0E2&MI_00'))
    Audio=(New-HardwareRow 'Audio/video driver' 'Microsoft' 'Realtek USB Audio' '' '' '1.0.0.0' @('USB\VID_0B05&PID_1A52&MI_00'))
}
function Get-HardwareInventory {
    $script:reads++;$currentBoard=$board;$device=$script:devices[$script:category]|Select-Object *
    if($script:reads -gt 1 -and $script:mode -eq 'changed-board'){$currentBoard=New-HardwareRow 'Motherboard' 'ASUSTeK' $board.Model '' '2.0' '' @()}
    if($script:reads -gt 1 -and $script:mode -eq 'changed-ids'){$device.IDs=@('USB\VID_1234&PID_5678')}
    [pscustomobject]@{OS='10.0.26300.0';Inventory=@($currentBoard,$device)}
}
function Read-WebSource([string]$url){
    $title=switch($script:category){'LAN'{'Intel I225 / I226 LAN Driver'}'Wireless'{'AMD WiFi Driver RZ616'}'Bluetooth'{'AMD Bluetooth Driver RZ616'}'Audio'{'Realtek USB Audio Driver'}}
    $version=if($script:reads -gt 1 -and $script:mode -eq 'withdrawn'){'2.3.4.6'}else{'2.3.4.5'}
    $hash=(Get-FileHash -LiteralPath $script:fixture -Algorithm SHA256).Hash
    if($script:mode -eq 'bad-published-hash'){$hash='0'*64}
    @{Status='SUCCESS';Result=@{Model=$board.Model;Obj=@(@{Name=$script:category;Files=@(@{Title=$title;Version=$version;DownloadUrl=@{Global='/pub/ASUS/mb/fixture_RZ616.zip'};sha256=$hash})})}}|ConvertTo-Json -Depth 8
}
function Get-AuthenticodeSignature {
    param($LiteralPath)
    $catalog=[IO.Path]::GetExtension($LiteralPath) -eq '.cat'
    $name=if($catalog){'Microsoft Windows Hardware Compatibility Publisher'}else{'ASUSTeK COMPUTER INC.'}
    if(($catalog -and $script:mode -eq 'wrong-catalog-publisher') -or (!$catalog -and $script:mode -eq 'wrong-setup-publisher')){$name='Unrelated Publisher'}
    $cert=[pscustomobject]@{Name=$name};$cert|Add-Member ScriptMethod GetNameInfo {param($type,$issuer)return $this.Name}
    [pscustomobject]@{Status=if(($catalog -and $script:mode -eq 'invalid-catalog-signature') -or (!$catalog -and $script:mode -eq 'invalid-setup-signature')){'HashMismatch'}else{'Valid'};SignerCertificate=$cert}
}
function Test-AsusCatalogMember([string]$path,[string]$catalog){
    if($script:mode -eq 'cancel-after-extract'){[IO.File]::WriteAllText((Join-Path $script:folder 'cancel'),'cancel')}
    return $script:mode -ne 'not-catalog-member'
}
function Start-Process {param($FilePath,$WorkingDirectory,[switch]$PassThru);$script:starts++;Assert-AsusTest 'AsusSetup.exe' ([IO.Path]::GetFileName($FilePath)) 'only ASUS setup is dispatched';Assert-AsusTest ([IO.Path]::GetDirectoryName($FilePath)) $WorkingDirectory 'setup runs from the verified package folder'}
function Save-VerifiedDownload {
    param($url,$folder,$filename,$maxBytes,$expectedBytes,$referrer,$allowedUri,$verify,[switch]$UseRanges)
    Assert-AsusTest $true (& $allowedUri ([uri]$url)) 'only the official ASUS archive is requested'
    if(Test-Path -LiteralPath (Join-Path $folder 'cancel')){throw 'Fixture cancellation.'}
    $path=Join-Path $folder $filename;Copy-Item -LiteralPath $script:fixture -Destination $path
    try{& $verify $path}catch{[IO.File]::Delete($path);throw}
    Set-Content -LiteralPath $path -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3`r`n" -Encoding ASCII
    return $path
}
function New-AsusFixture([string]$path){
    $device=$script:devices[$script:category]
    $id=if($script:mode -eq 'wrong-hardware'){'USB\VID_1234&PID_5678'}else{$device.IDs[0]}
    $class=switch($script:category){'Audio'{'MEDIA'}'Bluetooth'{'Bluetooth'}default{'Net'}}
    if($script:mode -eq 'wrong-class'){$class='System'}
    $arch=if($script:mode -eq 'x86-only'){'NTx86'}else{'NTamd64'}
    $version=if($script:mode -eq 'wrong-inf-version'){'9.0.0.0'}else{'2.3.4.5'}
    $inf=@'
[Version]
Signature="$Windows NT$"
Class=CLASS
ClassGuid={4d36e972-e325-11ce-bfc1-08002be10318}
Provider=%Vendor%
DriverVer=01/01/2026,VERSION
CatalogFile=driver.cat
[Manufacturer]
%Vendor%=Models,ARCH
[Models.ARCH]
%Device%=Install,DEVICEID
[Install]
[Strings]
Vendor="Fixture"
Device="Fixture device"
'@.Replace('CLASS',$class).Replace('VERSION',$version).Replace('ARCH',$arch).Replace('DEVICEID',$id)
    $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
    try{
        $items=@(@('AsusSetup.exe','fixture executable; never run'),@('driver.inf',$inf),@('driver.cat','fixture catalog'),@('AsusSetup.ini','fixture config'))
        if($script:mode -eq 'zip-traversal'){$items+=,@('../escape.txt','unsafe')}
        if($script:mode -eq 'zip-reserved'){$items+=,@('CON.txt','unsafe')}
        if($script:mode -eq 'zip-duplicate'){$items+=,@('ASUSSETUP.INI','duplicate')}
        if($script:mode -eq 'zip-link'){$items+=,@('link','unsafe')}
        foreach($item in $items){if($script:mode -eq 'missing-setup' -and $item[0] -eq 'AsusSetup.exe'){continue};$entry=$zip.CreateEntry($item[0]);if($script:mode -eq 'zip-link' -and $item[0] -eq 'link'){$entry.ExternalAttributes=-1610612736};$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write($item[1])}finally{$writer.Dispose()}}
    }finally{$zip.Dispose()}
}
try{
    [void][IO.Directory]::CreateDirectory($testRoot)
    foreach($category in 'LAN','Wireless','Bluetooth','Audio'){
        $script:category=$category
        foreach($mode in 'good','invalid-setup-signature','wrong-setup-publisher','invalid-catalog-signature','wrong-catalog-publisher','not-catalog-member','wrong-hardware','wrong-inf-version','x86-only','wrong-class','missing-setup','bad-published-hash','zip-traversal','zip-reserved','zip-duplicate','zip-link','cancel-before','cancel-after-extract','withdrawn','changed-board','changed-ids'){
            $script:mode=$mode;$script:reads=0;$script:fixture=Join-Path $testRoot ($category+'-'+$mode+'.zip');New-AsusFixture $script:fixture
            $script:folder=Join-Path $testRoot ($category+'-'+$mode);[void][IO.Directory]::CreateDirectory($script:folder)
            $device=$script:devices[$category];$check=Get-AsusCheck $device @($board,$device) (Get-WindowsDriverTarget '10.0.26300.0') @{}
            Assert-AsusTest $true (Test-ManagedPackageOffer $device $check) 'exact-board feed enables a newer ASUS offer'
            $selection=[pscustomobject]@{Device=$device;Check=$check}
            if($mode -eq 'cancel-before'){[IO.File]::WriteAllText((Join-Path $script:folder 'cancel'),'cancel')}
            if($mode -eq 'good'){
                $result=Receive-ManagedPackage $selection $script:folder
                try{
                    Assert-AsusTest $device.IDs[0] $result.Proof.HardwareId 'proof records the exact matching hardware ID'
                    $null=Start-ManagedPackage $result;$before=$script:starts
                    $ini=Join-Path $result.Root 'AsusSetup.ini';$old=[IO.File]::GetLastWriteTimeUtc($ini)
                    [IO.File]::WriteAllText($ini,'changed config');[IO.File]::SetLastWriteTimeUtc($ini,$old)
                    Reject-AsusTest {Start-ManagedPackage $result} 'changed setup configuration cannot run'
                    Assert-AsusTest $before $script:starts 'tampered extracted files never reach process launch'
                }finally{Remove-AsusRoot $result.Root}
            }else{
                Reject-AsusTest {Receive-ManagedPackage $selection $script:folder} "$category / $mode blocks setup"
                Assert-AsusTest 0 @(Get-ChildItem -LiteralPath $script:folder -File|Where-Object Extension -in '.zip','.part','.exe').Count 'failed package files are removed'
            }
        }
    }
    foreach($name in '..\outside','/root','a\..\b','a:stream','a\NUL.txt','a.\b','a\b ','a\\b'){
        Reject-AsusTest {Get-AsusArchivePath (Join-Path ([IO.Path]::GetTempPath()) ('DriverLoom-ASUS-'+[guid]::NewGuid().ToString('N'))) $name} 'unsafe archive path is rejected'
    }
    $device=$script:devices.LAN;$target=Get-WindowsDriverTarget '10.0.26300.0';$source='https://www.asus.com/supportonly/'+[Uri]::EscapeDataString($board.Model)+'/helpdesk_download/'
    foreach($url in 'http://dlcdnets.asus.com/pub/ASUS/mb/driver.zip','https://example.com/pub/ASUS/mb/driver.zip','https://dlcdnets.asus.com/pub/ASUS/mb/driver.zip?other=1','https://dlcdnets.asus.com/pub/ASUS/mb/driver.exe'){
        $file=[pscustomobject]@{Version='2.3.4.5';DownloadUrl=[pscustomobject]@{Global=$url};sha256=''}
        Assert-AsusTest $true ($null -eq (New-AsusPackage $device $board $target 'LAN' $file $source)) 'non-official/non-ZIP/query URLs cannot become ASUS offers'
    }
    $file=[pscustomobject]@{Version='2.3.4.5';DownloadUrl=[pscustomobject]@{Global='/pub/ASUS/mb/driver.zip'};sha256=''}
    Assert-AsusTest $true ($null -ne (New-AsusPackage $device $board $target 'LAN' $file $source)) 'older official feeds without ZIP hashes use catalog/setup validation'
    $file.sha256='not-a-sha256'
    Assert-AsusTest $true ($null -eq (New-AsusPackage $device $board $target 'LAN' $file $source)) 'a malformed published hash is never ignored'
    $file.sha256='';$noIds=$device|Select-Object *;$noIds.IDs=@('PCI\CC_020000')
    Assert-AsusTest $true ($null -eq (New-AsusPackage $noIds $board $target 'LAN' $file $source)) 'generic class IDs cannot authorise a manufacturer package'
    $oversize=Join-Path $testRoot 'oversize.zip';$script:mode='good';New-AsusFixture $oversize
    $bytes=[IO.File]::ReadAllBytes($oversize)
    for($i=0;$i -lt $bytes.Length-28;$i++){if($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4b -and $bytes[$i+2] -eq 1 -and $bytes[$i+3] -eq 2){[BitConverter]::GetBytes([uint32]1073741825).CopyTo($bytes,$i+24);break}}
    [IO.File]::WriteAllBytes($oversize,$bytes)
    $payload=Join-Path ([IO.Path]::GetTempPath()) ('DriverLoom-ASUS-'+[guid]::NewGuid().ToString('N'))
    Reject-AsusTest {Expand-AsusArchive $oversize $payload (Join-Path $testRoot 'cancel-unused')} 'oversized declared entries are rejected before extraction'
    Assert-AsusTest $false (Test-Path -LiteralPath $payload) 'oversized archives create no extracted payload'
    Assert-AsusTest 4 $script:starts 'only four fully verified fixtures reached the mocked launcher'
    Write-Output 'ASUS package checks passed: four categories, exact board/IDs/INF version/class/x64, trusted setup/catalog, archive bounds and paths, cancellation, changed offers and extracted-file tampering. No installer was executed.'
}finally{
    $resolved=[IO.Path]::GetFullPath($testRoot);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing cleanup outside TEMP.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
