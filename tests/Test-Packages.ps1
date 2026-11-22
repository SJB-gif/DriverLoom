$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'src'
$ErrorActionPreference='Stop'
. (Join-Path $srcRoot 'Engine.ps1')
. (Join-Path $srcRoot 'AppDownloads.ps1')
function Assert-PackageTest($expected,$actual,[string]$message){if($expected -cne $actual){throw "$message expected '$expected', got '$actual'."}}
function Reject-PackageTest([scriptblock]$action,[string]$message){$rejected=$false;try{& $action}catch{$rejected=$true};Assert-PackageTest $true $rejected $message}
$board=New-HardwareRow 'Motherboard' 'ASUSTeK' 'ROG STRIX X670E-A GAMING WIFI' '' '' '' @()
$cpu=New-HardwareRow 'CPU' 'AuthenticAMD' 'AMD Ryzen 9 7900X3D 12-Core Processor' '' '' '' @()
$chipset=New-HardwareRow 'Chipset package' 'AMD' 'AMD Chipset Software' $board.Model '' '7.01.08.129' @()
$gpu=New-HardwareRow 'GPU driver' 'NVIDIA' 'NVIDIA GeForce RTX 4080 SUPER' '' '' '32.0.16.2124' @()
$radeon=New-HardwareRow 'GPU driver' 'AMD' 'AMD Radeon(TM) Graphics' '' '' '32.0.21030.2001' @()
$adrenalin=New-HardwareRow 'GPU software' 'AMD' 'AMD Software: Adrenalin Edition' '' '' '24.6.1' @()
$script:case='good';$script:reads=0;$script:family='AMDChipset';$script:starts=0;$script:folder=''
function Get-HardwareInventory {
    $script:reads++
    $rows=@($board,$cpu,$chipset,$gpu,$radeon,$adrenalin)|ForEach-Object{$_|Select-Object *}
    if($script:case -eq 'changed-device'){$rows=@($board,$cpu)}
    if($script:case -eq 'changed-installed'){$rows|ForEach-Object{$_.Current='99.0'}}
    if($script:case -eq 'changed-gpu'){$rows|Where-Object Key -eq $radeon.Key|ForEach-Object{$_.Current='32.0.22000.1'}}
    if($script:case -eq 'missing-gpu'){$rows=@($rows|Where-Object Key -ne $radeon.Key)}
    [pscustomobject]@{OS='10.0.26300.0';Inventory=$rows}
}
function Read-WebSource([string]$url){
    if($url -like '*TypeID=2*'){return '<LookupValueSearch><LookupValue><Name>GeForce RTX 40 Series</Name><Value>127</Value></LookupValue></LookupValueSearch>'}
    if($url -like '*TypeID=3*'){return '<LookupValueSearch><LookupValue><Name>NVIDIA GeForce RTX 4080 SUPER</Name><Value>1041</Value></LookupValue></LookupValueSearch>'}
    $withdrawn=$script:case -eq 'withdrawn' -and $script:reads -ge 2
    if($url -like '*DriverManualLookup*'){
        $version=if($withdrawn){'623.11'}else{'622.10'}
        return @{Success='1';IDS=@(@{downloadInfo=@{Success='1';Name='GeForce%20Game%20Ready%20Driver';Version=$version;IsWHQL='1';IsBeta='0';IsActive='1';OSName='Windows 11';DetailsURL='https://www.nvidia.com/en-us/drivers/details/123456/';DownloadURL="https://us.download.nvidia.com/Windows/$version/$version-desktop-win10-win11-64bit-international-dch-whql.exe";series=@(@{products=@(@{productName='NVIDIA GeForce RTX 4080 SUPER'})})}})}|ConvertTo-Json -Depth 10
    }
    if($url -like '*amd.com*'){
        if($url -notlike '*/chipsets/*'){
            $version=if($withdrawn){'26.12.1'}else{'26.11.2'}
            return '<button>Windows 11 - 64-Bit Edition</button><article class="driver-download-details"><h4>AMD Software: Adrenalin Edition</h4><strong>Revision Number</strong><p>Adrenalin '+$version+' WHQL (Recommended)</p><a href="https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-'+$version+'-win11-a.exe">Download</a></article><div class="accordion-item"><button>Windows 10 - 64-Bit Edition</button><article class="driver-download-details"><h4>AMD Software: Adrenalin Edition</h4><strong>Revision Number</strong><p>Adrenalin 99.0.0 WHQL (Recommended)</p><a href="https://example.com/wrong-os.exe">Download</a></article>'
        }
        $version=if($withdrawn){'9.10.30.1234'}else{'8.09.28.1124'}
        return '<button>Windows 11 - 64-Bit Edition</button><article class="driver-download-details"><h4>AMD Chipset Drivers</h4><strong>Revision Number</strong><p>'+$version+'</p><a href="https://drivers.amd.com/drivers/amd_chipset_software_'+$version+'.exe">Download</a></article><div class="accordion-item"><button>Windows 10 - 64-Bit Edition</button><article class="driver-download-details"><h4>AMD Chipset Drivers</h4><strong>Revision Number</strong><p>99.0.0.0</p><a href="https://example.com/unrelated.exe">Download</a></article>'
    }
    throw 'Unexpected fixture source.'
}
function Get-AuthenticodeSignature {
    param($LiteralPath)
    $name=if($script:family -in 'AMDChipset','AMDRadeon'){'Advanced Micro Devices'}else{'NVIDIA Corporation'}
    if($script:case -eq 'wrong-publisher'){$name='Fake '+$name}
    $cert=[pscustomobject]@{Name=$name};$cert|Add-Member ScriptMethod GetNameInfo {param($type,$issuer)return $this.Name}
    [pscustomobject]@{Status=if($script:case -eq 'invalid-signature'){'HashMismatch'}else{'Valid'};SignerCertificate=$cert}
}
function Start-Process {param($FilePath,[switch]$PassThru);$script:starts++;[pscustomobject]@{Path=$FilePath}}
function Get-PackageFileInfo([string]$path){[pscustomobject]@{ProductName=if($script:case -eq 'wrong-product'){'Other AMD software'}elseif($script:family -eq 'AMDRadeon'){'AMD Software: Adrenalin Edition'}else{'AMD Chipset Software'};FileVersion=if($script:case -eq 'wrong-version'){'1.0.0.0'}elseif($script:family -eq 'AMDRadeon'){'26.11.2.0'}else{'8.09.28.1124'}}}
function Open-AppDownloadResponse([uri]$uri){
    if($script:case -eq 'network'){throw 'Fixture download failed.'}
    if($script:case -eq 'cancel'){[IO.File]::WriteAllText((Join-Path $script:folder 'cancel'),'cancel')}
    $location=if($script:case -eq 'foreign-redirect'){'https://example.com/fake.exe'}elseif($script:case -eq 'version-redirect'){$uri.AbsoluteUri.Replace('8.09.28.1124','1.0.0.0').Replace('622.10','500.00').Replace('26.11.2','25.1.1')}else{''}
    $response=[pscustomobject]@{StatusCode=if($location){302}else{200};ContentLength=38;Headers=@{Location=$location};Body=[Text.Encoding]::ASCII.GetBytes('Fixture package bytes; never executed..')}
    $response.ContentLength=$response.Body.Length
    $response|Add-Member ScriptMethod GetResponseStream {return [IO.MemoryStream]::new([byte[]]$this.Body)}
    $response|Add-Member ScriptMethod Dispose {}
    return $response
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('driverloom-packages-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
    foreach($family in 'AMDChipset','NvidiaDesktop','AMDRadeon'){
        $script:family=$family;$script:case='good';$script:reads=0
        $device=switch($family){'AMDChipset'{$chipset}'AMDRadeon'{$adrenalin}default{$gpu}}
        $check=Get-AutomaticManufacturerCheck $device @($board,$cpu,$chipset,$gpu,$radeon,$adrenalin) (Get-WindowsDriverTarget '10.0.26300.0') @{}
        Assert-PackageTest $family $check.Package.Family 'exact official feed produces the expected package family'
        Assert-PackageTest $true (Test-ManagedPackageOffer $device $check) 'only a matching newer version offers managed installation'
        $selection=[pscustomobject]@{Device=$device;Check=$check}
        $modes=@('good','invalid-signature','wrong-publisher','foreign-redirect','version-redirect','network','cancel','withdrawn','changed-device','changed-installed')
        if($family -in 'AMDChipset','AMDRadeon'){$modes+=@('wrong-product','wrong-version')}
        if($family -eq 'AMDRadeon'){$modes+=@('changed-gpu','missing-gpu')}
        foreach($mode in $modes){
            $script:case=$mode;$script:reads=0;$script:folder=Join-Path $root ($family+'-'+$mode);[void][IO.Directory]::CreateDirectory($script:folder)
            if($mode -eq 'good'){
                $result=Receive-ManagedPackage $selection $script:folder
                Assert-PackageTest $true ($script:reads -ge 2) 'device and official offer are checked before and after downloading'
                $null=Start-ManagedPackage $result
                $before=$script:starts;[IO.File]::AppendAllText($result.Path,'tampered')
                Reject-PackageTest {Start-ManagedPackage $result} 'changed downloads are rejected before execution'
                Assert-PackageTest $before $script:starts 'tampered package never starts'
            }else{
                Reject-PackageTest {Receive-ManagedPackage $selection $script:folder} "$family / $mode cannot run a package"
                Assert-PackageTest 0 @(Get-ChildItem -LiteralPath $script:folder -File|Where-Object Extension -in '.exe','.part').Count 'failed package files are removed'
            }
        }
        $script:case='good'
        foreach($mode in 'current','mismatch','custom-source'){
            $copy=$check|Select-Object *
            if($mode -eq 'current'){$copy.Status='Current at source'}
            if($mode -eq 'mismatch'){$copy.Available='999.0'}
            if($mode -eq 'custom-source'){$copy.Url='https://example.com/driver'}
            Assert-PackageTest $false (Test-ManagedPackageOffer $device $copy) "$mode has no managed action"
        }
    }
    foreach($url in 'http://drivers.amd.com/drivers/amd_chipset_software_8.09.28.1124.exe','https://drivers.amd.com.evil.example/drivers/amd_chipset_software_8.09.28.1124.exe','https://drivers.amd.com/drivers/amd_chipset_software_8.09.28.1124.exe?redirect=x','https://drivers.amd.com/drivers/firmware.zip'){
        Assert-PackageTest $false (Test-ManagedPackageUri ([uri]$url) 'AMDChipset') 'non-exact official URLs, firmware and archives are rejected'
    }
    $script:case='good'
    $radeonSource=Get-AmdGraphicsSource @($cpu,$radeon) $radeon
    $html=Read-WebSource $radeonSource
    $target=Get-WindowsDriverTarget '10.0.26300.0'
    foreach($mode in 'optional','beta','foreign-url','wrong-version','ambiguous','wrong-os','old-windows'){
        $attempt=$html;$os=$target
        switch($mode){
            'optional'{$attempt=$attempt.Replace('WHQL (Recommended)','Optional')}
            'beta'{$attempt=$attempt.Replace('WHQL (Recommended)','Beta')}
            'foreign-url'{$attempt=$attempt.Replace('https://drivers.amd.com/','https://example.com/')}
            'wrong-version'{$attempt=$attempt.Replace('edition-26.11.2','edition-25.1.1')}
            'ambiguous'{$attempt=$attempt.Replace('>Download</a>','>Download</a><a href="https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-26.11.2-win11-b.exe">Other download</a>')}
            'wrong-os'{$os=Get-WindowsDriverTarget '10.0.19045.0'}
            'old-windows'{$os=Get-WindowsDriverTarget '10.0.14393.0';$attempt=$attempt.Replace('Windows 11','Windows 10')}
        }
        Assert-PackageTest $true ($null -eq (Get-AmdRadeonPackage $adrenalin $radeon $os '26.11.2' $radeonSource $attempt)) "$mode cannot authorise a Radeon executable"
    }
    $win10=Get-AmdRadeonPackage $adrenalin $radeon (Get-WindowsDriverTarget '10.0.19045.0') '26.11.2' $radeonSource ($html.Replace('Windows 10','Windows 7').Replace('Windows 11','Windows 10'))
    Assert-PackageTest '10' $win10.OSFamily 'the official Windows section decides compatibility, independently of the shared win11 filename'
    $component=Get-AmdCheck $radeon @($cpu,$radeon,$adrenalin) $target @{}
    Assert-PackageTest $false (Test-ManagedPackageOffer $radeon $component) 'display-driver component versions never authorise an Adrenalin package comparison'
    $intel=New-HardwareRow 'CPU' 'GenuineIntel' 'Intel desktop fixture' '' '' '' @()
    $rx=New-HardwareRow 'GPU driver' 'AMD' 'AMD Radeon RX 6800 XT' '' '' '32.0.1.0' @()
    $rxCheck=Get-AmdCheck $adrenalin @($intel,$rx,$adrenalin) $target @{}
    Assert-PackageTest $rx.Key $rxCheck.Package.GpuKey 'Radeon on an Intel CPU resolves its exact discrete GPU'
    $ambiguous=Get-AmdCheck $adrenalin @($cpu,$rx,$radeon,$adrenalin) $target @{}
    Assert-PackageTest $true ($null -eq $ambiguous) 'an unqualified software row cannot choose between two Radeon GPUs'
    $specific=$adrenalin|Select-Object *;$specific.Part=$rx.Model
    $specificCheck=Get-AmdCheck $specific @($cpu,$rx,$radeon,$specific) $target @{}
    Assert-PackageTest $rx.Key $specificCheck.Package.GpuKey 'a qualified software row retains its GPU in a mixed Radeon system'
    Assert-PackageTest 3 $script:starts 'only three verified fixtures reached the mocked process launcher'
    Write-Output 'Manufacturer package checks passed: AMD chipset/Radeon and NVIDIA, exact GPU/OS/stable sources, publisher, changed offers/devices, cancellation, partial cleanup and tampering. No driver installer was executed.'
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing cleanup outside TEMP.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
