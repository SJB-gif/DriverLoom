$ErrorActionPreference = 'Stop'
$script:LauncherVersion = '0.1.14'
. (Join-Path $PSScriptRoot 'Coverage.ps1')
. (Join-Path $PSScriptRoot 'Manufacturers.ps1')

function Save-Json($path, $data) {
    $temp = "$path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temp, ($data | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($path)) { [IO.File]::Replace($temp, $path, [NullString]::Value) }
        else { [IO.File]::Move($temp, $path) }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}

function New-HardwareRow($kind, $manufacturer, $model, $part, $revision, $current, $ids, [string]$provider = '', [string]$infName = '') {
    $fields = @($kind, $manufacturer, $model, $part, $revision)
    $key = ($fields | ForEach-Object { ([string]$_).Trim().ToUpperInvariant() }) -join '|'
    [pscustomobject]@{
        Key = $key; Kind = $kind; Manufacturer = ([string]$manufacturer).Trim()
        Model = ([string]$model).Trim(); Part = ([string]$part).Trim(); Revision = ([string]$revision).Trim()
        Current = ([string]$current).Trim(); IDs = @($ids | Where-Object { $_ } | Select-Object -Unique)
        Provider = $provider; InfName = $infName
    }
}

function Get-HardwareInventory {
    $warnings = [System.Collections.Generic.List[string]]::new()
    $rows = [System.Collections.Generic.List[object]]::new()
    $machine = $null
    $board = $null
    try {
        $machine = Get-CimInstance Win32_ComputerSystem
        $rows.Add((New-HardwareRow 'System' $machine.Manufacturer $machine.Model $machine.SystemSKUNumber '' '' @()))
    } catch { $warnings.Add("System inventory: $_") }
    try {
        $board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
        if ($board) { $rows.Add((New-HardwareRow 'Motherboard' $board.Manufacturer $board.Product $board.PartNumber $board.Version '' @())) }
    } catch { $warnings.Add("Motherboard inventory: $_") }
    try {
        $bios = Get-CimInstance Win32_BIOS
        if ($board) {
            $rows.Add((New-HardwareRow 'BIOS' $board.Manufacturer $board.Product $board.PartNumber $board.Version $bios.SMBIOSBIOSVersion @()))
        } elseif ($machine) {
            $rows.Add((New-HardwareRow 'BIOS' $machine.Manufacturer $machine.Model $machine.SystemSKUNumber '' $bios.SMBIOSBIOSVersion @()))
        }
    } catch { $warnings.Add("BIOS inventory: $_") }
    try {
        foreach ($cpu in Get-CimInstance Win32_Processor) {
            $rows.Add((New-HardwareRow 'CPU' $cpu.Manufacturer $cpu.Name $cpu.PartNumber $cpu.Revision '' @()))
        }
    } catch { $warnings.Add("CPU inventory: $_") }
    try {
        foreach ($ram in Get-CimInstance Win32_PhysicalMemory) {
            $rows.Add((New-HardwareRow 'RAM' $ram.Manufacturer $ram.PartNumber $ram.PartNumber '' '' @()))
        }
    } catch { $warnings.Add("RAM inventory: $_") }
    try {
        foreach ($disk in Get-CimInstance Win32_DiskDrive) {
            $rows.Add((New-HardwareRow 'Storage firmware' $disk.Manufacturer $disk.Model '' '' $disk.FirmwareRevision @($disk.PNPDeviceID)))
        }
    } catch { $warnings.Add("Storage inventory: $_") }
    try {
        $present = @{}
        foreach ($pnp in Get-PnpDevice -PresentOnly) { $present[$pnp.InstanceId] = $true }
        foreach ($driver in Get-CimInstance Win32_PnPSignedDriver) {
            if (!$driver.DeviceID -or !$present.ContainsKey($driver.DeviceID)) { continue }
            $kind = switch ($driver.DeviceClass) {
                'DISPLAY' { 'GPU driver' }
                'NET' { 'Network driver' }
                'MEDIA' { 'Audio/video driver' }
                'HDC' { 'Storage driver' }
                'SCSIADAPTER' { 'Storage driver' }
                'BLUETOOTH' { 'Bluetooth driver' }
                'IMAGE' { 'Camera driver' }
                'CAMERA' { 'Camera driver' }
                'PRINTER' { 'Printer driver' }
                'HIDCLASS' { 'Input device driver' }
                'SYSTEM' { if ($driver.DeviceID -like 'PCI\*') { 'Chipset/system driver' } }
            }
            if (!$kind) { continue }
            $hardwareId = $null
            $compatibleId = $null
            $baseRow = New-HardwareRow $kind $driver.Manufacturer $driver.DeviceName $driver.HardWareID '' $driver.DriverVersion @($driver.HardWareID) $driver.DriverProviderName $driver.InfName
            if (Test-WindowsManagedHardware $baseRow) { $rows.Add($baseRow); continue }
            try {
                $hardwareId = (Get-PnpDeviceProperty -InstanceId $driver.DeviceID -KeyName 'DEVPKEY_Device_HardwareIds').Data
                $compatibleId = (Get-PnpDeviceProperty -InstanceId $driver.DeviceID -KeyName 'DEVPKEY_Device_CompatibleIds' -ErrorAction SilentlyContinue).Data
            } catch { }
            $ids = @($hardwareId) + @($driver.HardWareID) + @($compatibleId) + @($driver.CompatID)
            $rows.Add((New-HardwareRow $kind $driver.Manufacturer $driver.DeviceName $driver.HardWareID '' $driver.DriverVersion $ids $driver.DriverProviderName $driver.InfName))
        }
    } catch { $warnings.Add("Driver inventory: $_") }
    $hardwareRows = $rows.ToArray()
    if ((Get-AmdChipsetSource $hardwareRows) -or (Get-AmdGraphicsSource $hardwareRows)) {
        $packages = Get-InstalledAmdPackages
        if (Get-AmdChipsetSource $hardwareRows) {
            $rows.Add((New-HardwareRow 'Chipset package' 'AMD' 'AMD Chipset Software' $board.Product $board.Version $packages.Chipset @()))
        }
        $amdGpus = @($hardwareRows | Where-Object { $_.Kind -eq 'GPU driver' -and (Get-AmdGraphicsSource $hardwareRows $_) })
        foreach ($gpu in $amdGpus) {
            $targetModel = if ($amdGpus.Count -eq 1) { '' } else { $gpu.Model }
            $rows.Add((New-HardwareRow 'GPU software' 'AMD' 'AMD Software: Adrenalin Edition' $targetModel '' $packages.Graphics @()))
        }
    }
    [pscustomobject]@{
        CapturedAt = [DateTimeOffset]::Now.ToString('o')
        OS = [Environment]::OSVersion.Version.ToString()
        Inventory = @($rows | Group-Object Key, Current | ForEach-Object { $_.Group[0] } | Sort-Object Kind, Model)
        Warnings = @($warnings.ToArray())
    }
}

function Get-VendorPortal($row, $systemRow) {
    $vendor = "$($row.Manufacturer) $($row.Model)"
    if ($row.Kind -in 'BIOS', 'Chipset/system driver' -and $systemRow) {
        $oem = Get-VendorPortal $systemRow $null
        if ($oem) { return $oem }
    }
    switch -Regex ($vendor) {
        'ASUSTeK|\bASUS\b' { return 'https://www.asus.com/support/download-center/' }
        'Micro-Star|\bMSI\b' { return 'https://www.msi.com/support/download' }
        'GIGABYTE|AORUS' { return 'https://www.gigabyte.com/Support' }
        'ASRock' { return 'https://www.asrock.com/support/' }
        '\bDell\b|Alienware' { return 'https://www.dell.com/support/home/en-au?app=drivers' }
        '\bLenovo\b' { return 'https://pcsupport.lenovo.com/au/en/' }
        'Hewlett-Packard|\bHP\b' { return 'https://support.hp.com/au-en/drivers' }
        'NVIDIA|GeForce|Quadro' { return 'https://www.nvidia.com/en-us/drivers/' }
        'Samsung' { return 'https://semiconductor.samsung.com/consumer-storage/support/tools/' }
        'Western Digital|\bWDC\b|WD_BLACK' { return 'https://support-en.wd.com/' }
        'Crucial|Micron|CT\d{3,4}(MX|BX|P)' { return 'https://www.crucial.com/support/ssd-support' }
        'Kingston' { return 'https://www.kingston.com/en/support' }
        'Seagate' { return 'https://www.seagate.com/support/downloads/' }
        '\bAMD\b|AuthenticAMD|Advanced Micro Devices|Radeon' { return 'https://www.amd.com/en/support/download/drivers.html' }
        '\bIntel\b|GenuineIntel' { return 'https://www.intel.com/content/www/us/en/download-center/home.html' }
    }
    return ''
}

function Get-HttpsUri([string]$value) {
    $uri = $null
    if (![Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or
        $uri.UserInfo -or $uri.HostNameType -ne [UriHostNameType]::Dns -or !$uri.IsDefaultPort -or
        $uri.DnsSafeHost -notmatch '^[a-z0-9.-]+\.[a-z]{2,}$') {
        throw 'Enter a public HTTPS URL.'
    }
    return $uri
}

function Read-WebSource([string]$url, [int]$limit = 2097152) {
    $uri = Get-HttpsUri $url
    $request = [Net.HttpWebRequest]::Create($uri)
    $request.UserAgent = 'DriverLoom/0.1.14'
    $request.AllowAutoRedirect = $false
    $request.Timeout = 12000
    $request.ReadWriteTimeout = 12000
    $request.AutomaticDecompression = [Net.DecompressionMethods]'GZip, Deflate'
    $response = $request.GetResponse()
    try {
        if ([int]$response.StatusCode -ne 200) { throw "HTTP $([int]$response.StatusCode). Save the final URL if the page redirects." }
        $stream = $response.GetResponseStream()
        $reader = [IO.StreamReader]::new($stream)
        try {
            $buffer = New-Object char[] 8192
            $output = [Text.StringBuilder]::new()
            $deadline = [datetime]::UtcNow.AddSeconds(16)
            while (($read = $reader.Read($buffer, 0, $buffer.Length)) -gt 0) {
                if ($output.Length + $read -gt $limit -or [datetime]::UtcNow -gt $deadline) { throw 'Response exceeded the scan limit.' }
                [void]$output.Append($buffer, 0, $read)
            }
            return $output.ToString()
        } finally { $reader.Dispose() }
    } finally { $response.Dispose() }
}

function New-VersionPattern([string]$pattern) {
    if (!$pattern -or $pattern.Length -gt 300) { throw 'A version pattern must contain 1 to 300 characters.' }
    $regex = [regex]::new($pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase, [timespan]::FromMilliseconds(300))
    if ('version' -notin $regex.GetGroupNames()) { throw 'Use a named version capture, for example (?<version>[0-9]+\.[0-9]+).' }
    return $regex
}

function Compare-ReportedVersion([string]$installed, [string]$available) {
    if (!$installed) { return 'Installed version unavailable' }
    if ($installed -eq $available) { return 'Current at source' }
    if ($installed -notmatch '^\d+(\.\d+){1,3}$' -or $available -notmatch '^\d+(\.\d+){1,3}$') { return 'Different version; verify vendor ordering' }
    $a = $null
    $b = $null
    if (![version]::TryParse($installed, [ref]$a) -or ![version]::TryParse($available, [ref]$b)) { return 'Different version; verify vendor ordering' }
    $a = [version]::new($a.Major, $a.Minor, [Math]::Max(0, $a.Build), [Math]::Max(0, $a.Revision))
    $b = [version]::new($b.Major, $b.Minor, [Math]::Max(0, $b.Build), [Math]::Max(0, $b.Revision))
    if ($b -gt $a) { return 'Newer at source' }
    if ($b -lt $a) { return 'Installed version is higher' }
    return 'Current at source'
}

function Get-RepositoryCatalog([string]$repo, $warnings) {
    if (!$repo) { return $null }
    if ($repo -eq 'SJB-gif/HardwareUpdateLauncher') { $repo = 'SJB-gif/DriverLoom' }
    $result = [pscustomobject]@{ Release = ''; ReleaseUrl = "https://github.com/$repo/releases"; Sources = @() }
    if ($repo -notmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$' -or $repo -match '(^|/)\.{1,2}(/|$)') {
        $warnings.Add('GitHub configuration requires an owner/repository name.')
        return $null
    }
    try {
        $release = Read-WebSource "https://api.github.com/repos/$repo/releases/latest" 524288 | ConvertFrom-Json
        $result.Release = [string]$release.tag_name
    } catch { $warnings.Add("GitHub release: $_") }
    try {
        $catalog = Read-WebSource "https://raw.githubusercontent.com/$repo/main/catalog.json" 524288 | ConvertFrom-Json
        if ($catalog.schema -ne 1 -or @($catalog.sources).Count -gt 250) { throw 'Unsupported catalog format.' }
        $result.Sources = @($catalog.sources | Where-Object { $_ })
    } catch { $warnings.Add("GitHub catalog: $_") }
    return $result
}

function Get-SamsungSource($row) {
    if ($row.Kind -ne 'Storage firmware') { return }
    $disk = [regex]::Match($row.Model, '^(?:(?:NVMe|ATA)\s+)?Samsung SSD (990 PRO|990 EVO Plus|990 EVO|980 PRO|980|970 EVO Plus|970 EVO|970 PRO|960 EVO|960 PRO|950 PRO)(?: with Heatsink)?(?:\s+\d+(?:GB|TB))?(?:\s+(?:SCSI|ATA|NVMe) Disk Device)?$', 'IgnoreCase')
    if (!$disk.Success) { return }
    $model = [regex]::Escape($disk.Groups[1].Value).Replace('\ ', '\s+')
    [pscustomobject]@{
        Url = 'https://semiconductor.samsung.com/consumer-storage/support/tools/'
        Pattern = "$model\s+(?:Series\s+)?Firmware\s+ISO\s+(?<version>[A-Z0-9]{8,12})\b"
        VisibleText = $true
    }
}

function Convert-HtmlToText([string]$html) {
    $timeout = [timespan]::FromMilliseconds(800)
    $options = [Text.RegularExpressions.RegexOptions]'IgnoreCase, Singleline'
    $content = [regex]::Replace($html, '<(?:script|style)\b[^>]*>.*?</(?:script|style)\s*>', ' ', $options, $timeout)
    $content = [regex]::Replace($content, '<[^>]+>', ' ', $options, $timeout)
    return [Net.WebUtility]::HtmlDecode($content)
}

function Get-VendorResults($inventory, $settings, $warnings, [string]$osVersion = ([Environment]::OSVersion.Version.ToString())) {
    $system = $inventory | Where-Object Kind -eq 'System' | Select-Object -First 1
    $repo = Get-RepositoryCatalog $settings.Repo $warnings
    $pageCache = @{}
    $target = $null
    try { $target = Get-WindowsDriverTarget $osVersion } catch { $warnings.Add($_.Exception.Message) }
    $checks = foreach ($row in $inventory) {
        if ($row.Kind -eq 'BIOS' -and !$settings.Bios) { continue }
        if (Test-WindowsManagedHardware $row) { continue }
        $portal = Get-VendorPortal $row $system
        $source = @($settings.Sources | Where-Object { $_ -and $_.Key -eq $row.Key }) | Select-Object -First 1
        $localSource = [bool]$source
        if (!$source -and $repo) {
            $matches = @($repo.Sources | Where-Object {
                $_.Kind -eq $row.Kind -and $_.Manufacturer -eq $row.Manufacturer -and
                $_.Model -eq $row.Model -and $_.Part -eq $row.Part -and $_.Revision -eq $row.Revision -and
                ($row.Kind -notin 'BIOS', 'Chipset/system driver', 'GPU driver' -or
                    ($system -and $_.SystemManufacturer -eq $system.Manufacturer -and $_.SystemModel -eq $system.Model -and $_.SystemPart -eq $system.Part))
            })
            if ($matches.Count -eq 1) { $source = $matches[0] }
        }
        $builtInSource = $false
        if (!$source) {
            if ($target -and $row.Kind -notin 'BIOS', 'CPU', 'RAM', 'System', 'Motherboard') {
                $automatic = Get-AutomaticManufacturerCheck $row $inventory $target $pageCache
                if ($automatic) { $automatic; continue }
            }
            $source = Get-SamsungSource $row
            $builtInSource = [bool]$source
        }
        $route = Get-OfficialSupportRoute $row $inventory
        $method = Get-UpdateMethod $row $inventory $route
        $check = [pscustomobject]@{ Key = $row.Key; Current = $row.Current; Available = ''; Url = $method.Url; Status = 'Unsupported automatic check'; Detail = $method.Reason; Checked = $false }
        if ($row.Kind -in 'CPU', 'RAM', 'System', 'Motherboard' -and !$source) { $check.Status = 'Inventory only'; $check.Detail = 'This identity is used for hardware and package matching.' }
        elseif (!$source -and $row.Kind -eq 'Chipset/system driver' -and $row.Manufacturer -match 'AMD|Advanced Micro Devices' -and (Get-AmdChipsetSource $inventory)) {
            $check.Status = 'See AMD Chipset Software package check'; $check.Url = Get-AmdChipsetSource $inventory
            $check.Detail = 'Chipset package versions differ from individual SMBus, PCI and power-management driver versions.'
        } elseif (!$source -and $row.Model -match '^(Microsoft |WAN Miniport|PCI Express |PCI standard |High Definition Audio Controller$)') {
            $check.Status = 'Windows-managed; see Windows Update offers'; $check.Detail = 'No standalone manufacturer version comparison is made for this Windows component.'
        } elseif (!$source -and $row.Kind -eq 'Audio/video driver' -and $row.Model -match '^(AMD|NVIDIA).*Audio') {
            $check.Status = 'See GPU package check'; $check.Detail = 'The audio component has its own version; do not compare it with the GPU package number.'
        }
        if ($source) {
            try {
                $uri = Get-HttpsUri $source.Url
                if (!$localSource -and !$builtInSource) {
                    if (!$portal) { throw 'No built-in vendor domain for this catalog entry.' }
                    $domain = (Get-HttpsUri $portal).DnsSafeHost -replace '^www\.', '' -replace '^pcsupport\.', '' -replace '^semiconductor\.', '' -replace '^support(-en)?\.', ''
                    if ($uri.DnsSafeHost -ne $domain -and !$uri.DnsSafeHost.EndsWith(".$domain")) { throw 'Catalog URL differs from the device vendor domain.' }
                }
                $check.Url = $uri.AbsoluteUri
                if (!$source.Pattern) { $check.Status = 'Saved support link; manual version check'; $check; continue }
                $pattern = New-VersionPattern $source.Pattern
                if (!$pageCache.ContainsKey($check.Url)) {
                    try { $pageCache[$check.Url] = Read-WebSource $check.Url }
                    catch { $pageCache[$check.Url] = $_ }
                }
                $page = $pageCache[$check.Url]
                if ($page -is [System.Management.Automation.ErrorRecord]) { throw $page }
                if ($builtInSource -and $source.VisibleText) { $page = Convert-HtmlToText $page }
                $versions = @($pattern.Matches($page) | ForEach-Object { $_.Groups['version'].Value.Trim() } | Where-Object { $_ } | Select-Object -Unique)
                if ($versions.Count -ne 1 -or $versions[0] -notmatch '^[a-z0-9][a-z0-9._+ -]{0,39}$') { throw 'Expected one unambiguous version in the vendor response.' }
                $check.Available = $versions[0]
                $check.Checked = $true
                $check.Detail = 'Version read from the saved, catalog or built-in manufacturer source.'
                $check.Status = Compare-ReportedVersion $row.Current $check.Available
                if ($builtInSource -and $row.Current -match '^[0-9]([A-Z0-9]+)$' -and
                    $check.Available -match "^[0-9]$($Matches[1])$" -and $row.Current -ne $check.Available) {
                    $check.Status = if ($check.Available[0] -gt $row.Current[0]) { 'Newer at source' } else { 'Installed version is higher' }
                }
            } catch { $check.Status = "Source check failed: $($_.Exception.Message)"; $check.Detail = $_.Exception.Message; $check.Checked = $false }
        }
        $check
    }
    [pscustomobject]@{ Checks = @($checks); Repository = $repo }
}

function Get-DriverOfferReasons($update) {
    $class = ([string]$update.DriverClass).Trim()
    $title = [string]$update.Title
    $hardwareId = [string]$update.DriverHardwareID
    if (!$hardwareId) { 'Windows Update did not expose a hardware ID.' }
    if ($class -eq 'Firmware' -or "$title $hardwareId" -match '(?i)\b(firmware|bios|uefi|microcode|capsule|flash)\b|UEFI\\|RES_[\{]') {
        'Firmware/BIOS is excluded from Update All; use the manufacturer workflow.'
    } elseif ($class -notin @('Display','Net','Media','HDC','SCSIAdapter','System','Extension','SoftwareComponent','Bluetooth','USB','HIDClass','Mouse','Keyboard','Printer','Camera','Image','Monitor','Sensor','AudioEndpoint','Ports','DiskDrive')) {
        "Unsupported automatic-install class: $class."
    }
    if ($update.InstallationBehavior.CanRequestUserInput) { 'Package may request user interaction; review in Windows Update.' }
}

function Get-DriverOffer($update) {
    if (@(Get-DriverOfferReasons $update).Count) { return }
    [pscustomobject]@{
        Id = ([guid]$update.Identity.UpdateID).ToString()
        Revision = [int]$update.Identity.RevisionNumber
        Title = [string]$update.Title; Class = ([string]$update.DriverClass).Trim(); HardwareId = [string]$update.DriverHardwareID
        Date = if ($update.DriverVerDate) { ([datetime]$update.DriverVerDate).ToString('yyyy-MM-dd') } else { '' }
    }
}

function Get-WindowsOfferReport($updates, $warnings) {
    $candidates = [System.Collections.Generic.List[object]]::new()
    $excluded = [System.Collections.Generic.List[object]]::new()
    foreach ($update in @($updates)) {
        $reasons = @(Get-DriverOfferReasons $update)
        if ($reasons.Count) {
            $excluded.Add([pscustomobject]@{
                Title = [string]$update.Title; Class = ([string]$update.DriverClass).Trim(); HardwareId = [string]$update.DriverHardwareID
                Date = if ($update.DriverVerDate) { ([datetime]$update.DriverVerDate).ToString('yyyy-MM-dd') } else { '' }
                Reasons = $reasons
            })
        } else { $candidates.Add((Get-DriverOffer $update)) }
    }
    $eligible = @(Get-UnambiguousOffers $candidates.ToArray() $warnings)
    foreach ($group in @($candidates.ToArray() | Group-Object Class, HardwareId | Where-Object Count -gt 1)) {
        foreach ($offer in $group.Group) {
            $excluded.Add([pscustomobject]@{
                Title = $offer.Title; Class = $offer.Class; HardwareId = $offer.HardwareId; Date = $offer.Date
                Reasons = @('Multiple offers target this hardware and class; review in Windows Update.')
            })
        }
    }
    [pscustomobject]@{ Offers = $eligible; ExcludedOffers = $excluded.ToArray(); Total = @($updates).Count }
}

function Test-CanInstallSnapshot($snapshot, [bool]$fresh, [bool]$busy) {
    return (!$busy -and $fresh -and $snapshot.WindowsUpdateOK -and @($snapshot.Offers | Where-Object { $_ }).Count -gt 0)
}

function Get-UpdateAction($snapshot, [bool]$fresh, [bool]$busy) {
    $vendorCount=@($snapshot.Checks|Where-Object{$_.Checked -and $_.Status -eq 'Newer at source'}).Count
    $windowsCount=if($snapshot.WindowsUpdateOK){@($snapshot.Offers|Where-Object{$_}).Count}else{0}
    $available=$fresh -and ($vendorCount+$windowsCount) -gt 0 -and !$busy
    [pscustomobject]@{Visible=$available;Enabled=$available;VendorCount=$vendorCount;WindowsCount=$windowsCount}
}

function Get-CheckCaption([string]$capturedAt,[datetimeoffset]$now=([datetimeoffset]::UtcNow)) {
    $captured=[datetimeoffset]::MinValue
    if(![datetimeoffset]::TryParse($capturedAt,[ref]$captured)){return 'NOT CHECKED YET'}
    $minutes=[math]::Max(0,[math]::Floor(($now-$captured).TotalMinutes))
    if($minutes -lt 1){return 'CHECKED JUST NOW'}
    if($minutes -lt 60){return "CHECKED $minutes MIN AGO"}
    $hours=[math]::Floor($minutes/60)
    if($hours -lt 24){return "CHECKED $hours HR AGO"}
    return ('CHECKED '+[math]::Floor($hours/24)+' DAYS AGO')
}

function Search-WindowsDrivers($session) {
    $searcher = $session.CreateUpdateSearcher()
    $search = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Driver'")
    if ([int]$search.ResultCode -ne 2) { throw "Windows Update scan returned result code $($search.ResultCode)." }
    return ,$search
}

function Invoke-HardwareCheck($settings) {
    $data = Get-HardwareInventory
    $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($warning in $data.Warnings) { $warnings.Add($warning) }
    $offers = @()
    $excludedOffers = @()
    $offerCount = 0
    $wuOk = $false
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'Hardware Update Launcher'
        $search = Search-WindowsDrivers $session
        $updates = @(for ($i = 0; $i -lt $search.Updates.Count; $i++) { $search.Updates.Item($i) })
        $report = Get-WindowsOfferReport $updates $warnings
        $offers = $report.Offers
        $excludedOffers = $report.ExcludedOffers
        $offerCount = $report.Total
        $wuOk = $true
    } catch { $warnings.Add("Windows Update: $_") }
    $vendor = Get-VendorResults $data.Inventory $settings $warnings $data.OS
    [pscustomobject]@{
        CapturedAt = $data.CapturedAt; OS = $data.OS; Inventory = $data.Inventory; Warnings = $warnings.ToArray()
        Offers = @($offers); ExcludedOffers = @($excludedOffers); WindowsUpdateOfferCount = $offerCount
        WindowsUpdateOK = $wuOk; Checks = $vendor.Checks; Repository = $vendor.Repository
    }
}

function Get-UnambiguousOffers($offers, $warnings) {
    foreach ($group in @($offers | Group-Object Class, HardwareId)) {
        if ($group.Count -eq 1) { $group.Group[0]; continue }
        $warnings.Add("Multiple Windows Update offers for $($group.Group[0].HardwareId). Review these in Windows Update.")
    }
}
