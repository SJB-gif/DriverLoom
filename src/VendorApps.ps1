function Get-VendorAppSpecs {
    @(
        @{Key='amdManager';Name='AMD Install Manager';Vendor='AMD';File='AMDInstallManager.exe';Company='Advanced Micro Devices|\bAMD\b';Publisher='Advanced Micro Devices';Registration='AMD';Paths=@('AMD\AMDInstallManager\AMDInstallManager.exe','AMDInstallManager\AMDInstallManager.exe','AMDInstallManager.exe')},
        @{Key='radeon';Name='AMD Software';Vendor='AMD';File='RadeonSoftware.exe';Company='Advanced Micro Devices|\bAMD\b';Publisher='Advanced Micro Devices';Registration='AMD';Paths=@('AMD\CNext\CNext\RadeonSoftware.exe','CNext\CNext\RadeonSoftware.exe','RadeonSoftware.exe')},
        @{Key='icue';Name='iCUE';Vendor='Corsair';File='iCUE.exe';Company='Corsair';Publisher='Corsair';Registration='Corsair|iCUE';Paths=@('Corsair\Corsair iCUE5 Software\iCUE.exe','Corsair\CORSAIR iCUE4 Software\iCUE.exe','Corsair\CORSAIR iCUE Software\iCUE.exe','Corsair iCUE5 Software\iCUE.exe','CORSAIR iCUE4 Software\iCUE.exe','iCUE.exe')},
        @{Key='nvidia';Name='NVIDIA App';Vendor='NVIDIA';File='NVIDIA App.exe';Company='NVIDIA';Publisher='NVIDIA';Registration='NVIDIA';Paths=@('NVIDIA Corporation\NVIDIA app\CEF\NVIDIA App.exe','NVIDIA app\CEF\NVIDIA App.exe','CEF\NVIDIA App.exe','NVIDIA App.exe')},
        @{Key='corsairSSD';Name='CORSAIR SSD Toolbox';Vendor='Corsair';File='SSDtoolbox.exe';Company='Corsair';Publisher='Corsair';Registration='Corsair.*SSD|SSD.*Toolbox';Paths=@('Corsair\Corsair SSD Toolbox\SSDtoolbox.exe','Corsair SSD Toolbox\SSDtoolbox.exe','SSDtoolbox.exe')},
        @{Key='magician';Name='Samsung Magician';Vendor='Samsung';File='SamsungMagician.exe';Company='Samsung';Publisher='Samsung Electronics';Registration='Samsung.*Magician';Paths=@('Samsung\Samsung Magician\SamsungMagician.exe','Samsung Magician\SamsungMagician.exe','SamsungMagician.exe')}
    )
}

function Get-VendorAppRegistrations {
    foreach($hive in [Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryHive]::CurrentUser){
        foreach($view in [Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32){
            $base=$null;$uninstall=$null;$appPaths=$null
            try{
                $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
                $uninstall=$base.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall')
                if($uninstall){foreach($name in $uninstall.GetSubKeyNames()){
                    $key=$uninstall.OpenSubKey($name)
                    if($key){try{[pscustomobject]@{Name=[string]$key.GetValue('DisplayName');Publisher=[string]$key.GetValue('Publisher');Root=[string]$key.GetValue('InstallLocation');Icon=[string]$key.GetValue('DisplayIcon');AppPath=''}}finally{$key.Dispose()}}
                }}
                $appPaths=$base.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\App Paths')
                if($appPaths){foreach($spec in (Get-VendorAppSpecs)){
                    $key=$appPaths.OpenSubKey($spec.File)
                    if($key){try{[pscustomobject]@{Name=$spec.Name;Publisher='';Root='';Icon='';AppPath=[string]$key.GetValue('')}}finally{$key.Dispose()}}
                }}
            }catch{}finally{if($uninstall){$uninstall.Dispose()};if($appPaths){$appPaths.Dispose()};if($base){$base.Dispose()}}
        }
    }
}

function ConvertTo-VendorExePath([string]$value) {
    if(!$value){return ''}
    $value=[Environment]::ExpandEnvironmentVariables($value.Trim())
    if($value -match '^"([^"\r\n]+\.exe)"(?:,\s*-?\d+)?$'){return $Matches[1]}
    if($value -match '^([^"\r\n]+\.exe)(?:,\s*-?\d+)?$'){return $Matches[1]}
    return ''
}

function Test-VendorExecutable([string]$path,$spec) {
    try{
        if(!$path -or $path.StartsWith('\\') -or ![IO.Path]::IsPathRooted($path)){return $false}
        $path=[IO.Path]::GetFullPath($path)
        if([IO.Path]::GetFileName($path) -ine $spec.File){return $false}
        $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($path))
        if($drive.DriveType -notin [IO.DriveType]::Fixed,[IO.DriveType]::Removable){return $false}
        if(!(Test-Path -LiteralPath $path -PathType Leaf)){return $false}
        if((Get-Item -LiteralPath $path).VersionInfo.CompanyName -notmatch $spec.Company){return $false}
        $signature=Get-AuthenticodeSignature -LiteralPath $path
        return $signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match $spec.Publisher
    }catch{return $false}
}

function Get-InstalledVendorApps {
    $catalog=@{};$registrations=@(Get-VendorAppRegistrations)
    $programRoots=@([Environment]::GetFolderPath('ProgramFiles'),[Environment]::GetFolderPath('ProgramFilesX86'))|Where-Object{$_}|Select-Object -Unique
    foreach($spec in (Get-VendorAppSpecs)){
        $paths=[System.Collections.Generic.List[string]]::new()
        foreach($registration in $registrations){
            if($registration.Name -notmatch $spec.Registration){continue}
            foreach($value in $registration.AppPath,$registration.Icon){$candidate=ConvertTo-VendorExePath $value;if($candidate){$paths.Add($candidate)}}
            if($registration.Root -and !$registration.Root.StartsWith('\\') -and [IO.Path]::IsPathRooted($registration.Root) -and (!$registration.Publisher -or $registration.Publisher -match $spec.Publisher)){
                foreach($relative in $spec.Paths){try{$paths.Add((Join-Path $registration.Root $relative))}catch{}}
            }
        }
        foreach($root in $programRoots){foreach($relative in $spec.Paths){$paths.Add((Join-Path $root $relative))}}
        foreach($path in @($paths|Select-Object -Unique)){
            if(Test-VendorExecutable $path $spec){$catalog[$spec.Key]=[pscustomobject]@{Key=$spec.Key;Name=$spec.Name;Vendor=$spec.Vendor;Path=[IO.Path]::GetFullPath($path)};break}
        }
    }
    return $catalog
}

function Get-DeviceLauncher($device,[hashtable]$catalog) {
    $vendor=Get-HardwareVendor $device;$key=''
    if($vendor -eq 'Corsair'){$key=if($device.Kind -eq 'Storage firmware'){'corsairSSD'}else{'icue'}}
    elseif($vendor -eq 'NVIDIA' -and $device.Kind -in 'GPU driver','GPU software'){$key='nvidia'}
    elseif($vendor -eq 'AMD'){
        if($device.Kind -in 'GPU driver','GPU software','Chipset package','Chipset/system driver'){
            if($catalog.ContainsKey('amdManager')){$key='amdManager'}elseif($device.Kind -in 'GPU driver','GPU software'){$key='radeon'}
        }
    }elseif($vendor -eq 'Samsung' -and $device.Kind -eq 'Storage firmware'){$key='magician'}
    if($key -and $catalog.ContainsKey($key)){return $catalog[$key]}
    return $null
}

function Start-VendorApplication($launcher) {
    $spec=Get-VendorAppSpecs|Where-Object Key -eq $launcher.Key|Select-Object -First 1
    if(!$spec -or !(Test-VendorExecutable $launcher.Path $spec)){throw 'The installed application is no longer available or could not be verified.'}
    Start-Process -FilePath $launcher.Path -WorkingDirectory ([IO.Path]::GetDirectoryName($launcher.Path))
}

function Get-LauncherDisplayGroups([object[]]$entries) {
    $standalone=[System.Collections.Generic.List[object]]::new();$shared=@{}
    foreach($entry in $entries){
        if(!$entry.Launcher){$standalone.Add([pscustomobject]@{IsGroup=$false;Items=@($entry)});continue}
        $key=$entry.Launcher.Key+'|'+$entry.Launcher.Path.ToUpperInvariant()
        if(!$shared.ContainsKey($key)){$shared[$key]=[System.Collections.Generic.List[object]]::new()}
        $shared[$key].Add($entry)
    }
    foreach($group in $standalone){$group}
    foreach($key in @($shared.Keys|Sort-Object)){
        $items=@($shared[$key]|Sort-Object Name)
        [pscustomobject]@{IsGroup=$items.Count -gt 1;Items=$items}
    }
}

function Get-HardwareCategory($device) {
    switch -Regex ([string]$device.Kind) {
        '^GPU' {return 'Graphics'}
        'Audio|Media|Camera' {return 'Audio & media'}
        'Network|Bluetooth' {return 'Network & Bluetooth'}
        'Storage' {return 'Storage'}
        'Chipset|BIOS|CPU|Motherboard|System' {return 'System & chipset'}
        'Input|USB|HID|Peripheral|Printer' {return 'Peripherals'}
        default {return 'Other hardware'}
    }
}
