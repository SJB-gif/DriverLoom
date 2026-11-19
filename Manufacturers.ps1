function Get-VendorPage([string]$url, $cache) {
    if (!$cache.ContainsKey($url)) {
        try { $cache[$url] = Read-WebSource $url }
        catch { $cache[$url] = $_ }
    }
    if ($cache[$url] -is [System.Management.Automation.ErrorRecord]) { throw $cache[$url] }
    return [string]$cache[$url]
}

function Get-WindowsDriverTarget([string]$osVersion) {
    $version = $null
    if (![version]::TryParse($osVersion, [ref]$version) -or $version.Major -ne 10 -or $version.Build -lt 10240) {
        throw 'Automatic manufacturer checks require Windows 10 or 11 x64.'
    }
    if ($version.Build -ge 22000) { return [pscustomobject]@{ Family = '11'; Nvidia = 135; Asus = 52 } }
    return [pscustomobject]@{ Family = '10'; Nvidia = 57; Asus = 45 }
}

function New-ManufacturerCheck($row, [string]$url, [string]$available, [string]$status, [string]$detail, [bool]$checked = $true) {
    [pscustomobject]@{
        Key = $row.Key; Current = $row.Current; Available = $available; Url = $url
        Status = $status; Detail = $detail; Checked = $checked
    }
}

function ConvertFrom-VendorXml([string]$content) {
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = 'Prohibit'
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 2097152
    $reader = [Xml.XmlReader]::Create([IO.StringReader]::new($content), $settings)
    try {
        $document = [Xml.XmlDocument]::new()
        $document.XmlResolver = $null
        $document.Load($reader)
        return ,$document
    } finally { $reader.Dispose() }
}

function Get-NormalizedGpuName([string]$name) {
    return (($name -replace '(?i)^NVIDIA\s+', '') -replace '\s+', ' ').Trim()
}

function Convert-NvidiaInstalledVersion([string]$installed) {
    if ($installed -match '^\d{3}\.\d{2}$') { return $installed }
    $version = $null
    if (![version]::TryParse($installed, [ref]$version) -or $version.Build -lt 13 -or $version.Revision -lt 0 -or $version.Revision -gt 9999) {
        return ''
    }
    $number = ($version.Build % 10) * 10000 + $version.Revision
    return ('{0}.{1:00}' -f [int][math]::Floor($number / 100), ($number % 100))
}

function Get-NvidiaCheck($row, $target, $cache) {
    $model = Get-NormalizedGpuName $row.Model
    $match = [regex]::Match($model, '^GeForce (RTX|GTX|GT|GTS) (\d{1,2})\d{2}(?: (?:Ti|SUPER|Laptop GPU))*$', 'IgnoreCase')
    if (!$match.Success) { return $null }
    $seriesName = if ($match.Groups[1].Value -eq 'RTX') { 'GeForce RTX ' + $match.Groups[2].Value + ' Series' }
        elseif ($match.Groups[2].Value -eq '16') { 'GeForce 16 Series' }
        elseif ($match.Groups[2].Value.Length -eq 1) { 'GeForce ' + $match.Groups[2].Value + '00 Series' }
        else { 'GeForce ' + $match.Groups[2].Value + ' Series' }
    if ($model -match 'Laptop GPU$') { $seriesName += ' (Notebooks)' }
    $seriesXml = ConvertFrom-VendorXml (Get-VendorPage 'https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=2&ParentID=1' $cache)
    $series = @($seriesXml.SelectNodes('//LookupValue') | Where-Object { [string]$_.Name -eq $seriesName })
    if ($series.Count -ne 1 -or [string]$series[0].Value -notmatch '^\d{1,6}$') { throw 'NVIDIA has no unique product series matching this GPU.' }
    $seriesId = [string]$series[0].Value
    $productXml = ConvertFrom-VendorXml (Get-VendorPage ("https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=3&ParentID=$seriesId") $cache)
    $product = @($productXml.SelectNodes('//LookupValue') | Where-Object { (Get-NormalizedGpuName ([string]$_.Name)) -eq $model })
    if ($product.Count -ne 1 -or [string]$product[0].Value -notmatch '^\d{1,6}$') { throw 'NVIDIA has no unique exact product match for this GPU.' }
    $productId = [string]$product[0].Value
    $url = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=$seriesId&pfid=$productId&osID=$($target.Nvidia)&languageCode=1033&isWHQL=1&dltype=-1&dch=1&upCRD=0&numberOfResults=10"
    $response = Get-VendorPage $url $cache | ConvertFrom-Json
    # NVIDIA's top-level Success is the result count; each record has its own success flag.
    if ([string]$response.Success -notmatch '^\d+$' -or [int]$response.Success -lt 1) { throw 'NVIDIA product lookup did not succeed.' }
    $candidates = @(foreach ($entry in $response.IDS) {
        $info = $entry.downloadInfo
        $name = [Uri]::UnescapeDataString([string]$info.Name)
        $osName = [Uri]::UnescapeDataString([string]$info.OSName)
        $supported = @($info.series | ForEach-Object { $_.products } | ForEach-Object { Get-NormalizedGpuName ([Uri]::UnescapeDataString([string]$_.productName)) })
        if ($info.Success -eq '1' -and $name -match '^GeForce (?:Game Ready|Security Update) Driver$' -and $info.IsWHQL -eq '1' -and $info.IsBeta -eq '0' -and
            $info.IsActive -eq '1' -and $osName -match ('^Windows ' + $target.Family + '(?: 64-bit)?$') -and $model -in $supported -and
            $info.Version -match '^\d{3}\.\d{2}$') { $info }
    })
    $latest = $candidates | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
    if (!$latest) { throw 'No non-beta WHQL GeForce driver matches the exact GPU and Windows version.' }
    $details = Get-HttpsUri ([string]$latest.DetailsURL)
    if ($details.DnsSafeHost -ne 'www.nvidia.com' -or $details.AbsolutePath -notmatch '^/en-us/drivers/details/\d+/$') { throw 'NVIDIA returned an unexpected driver details URL.' }
    $installed = Convert-NvidiaInstalledVersion $row.Current
    $status = if ($installed) { Compare-ReportedVersion $installed $latest.Version } else { 'Vendor version found; installed NVIDIA version needs review' }
    $channel=[Uri]::UnescapeDataString([string]$latest.Name)
    New-ManufacturerCheck $row $details.AbsoluteUri $latest.Version $status "NVIDIA WHQL $channel; exact product $model; Windows $($target.Family) x64. Installed Windows driver $($row.Current) corresponds to NVIDIA $installed. Vendor packages are reviewed and installed from the official source."
}

function Get-AmdChipsetSource($inventory) {
    $cpu = $inventory | Where-Object { $_.Kind -eq 'CPU' -and $_.Manufacturer -match 'AMD' } | Select-Object -First 1
    $board = $inventory | Where-Object Kind -eq 'Motherboard' | Select-Object -First 1
    if (!$cpu -or !$board) { return $null }
    $match = [regex]::Match($board.Model, '\b(X870E|X870|X670E|X670|B850|B840|B650E|B650|A620|X570|B550|X470|B450|X370|B350|A320)\b', 'IgnoreCase')
    if (!$match.Success) { return $null }
    $chipset = $match.Value.ToLowerInvariant()
    $socket = if ($chipset -match '^(x[68]70|b[68][45]0|a620)') { 'am5' } else { 'am4' }
    return "https://www.amd.com/en/support/downloads/drivers.html/chipsets/$socket/$chipset.html"
}

function Get-AmdGraphicsSource($inventory, $gpu = $null) {
    if (!$gpu) {
        foreach ($candidate in @($inventory | Where-Object Kind -eq 'GPU driver')) {
            $source = Get-AmdGraphicsSource $inventory $candidate
            if ($source) { return $source }
        }
        return $null
    }
    $rx = [regex]::Match($gpu.Model, '^(?:AMD )?Radeon(?:\(TM\))? RX ([5-9]\d{3})(?: (XT|XTX|GRE))?$', 'IgnoreCase')
    if ($rx.Success) {
        $family = $rx.Groups[1].Value.Substring(0,1) + '000'
        $product = 'amd-radeon-rx-' + $rx.Groups[1].Value
        if ($rx.Groups[2].Success) { $product += '-' + $rx.Groups[2].Value.ToLowerInvariant() }
        return "https://www.amd.com/en/support/downloads/drivers.html/graphics/radeon-rx/radeon-rx-$family-series/$product.html"
    }
    if ($gpu.Model -notmatch '^AMD Radeon(?:\(TM\))? Graphics$') { return $null }
    $cpu = $inventory | Where-Object Kind -eq 'CPU' | Select-Object -First 1
    if (!$gpu -or !$cpu) { return $null }
    $match = [regex]::Match($cpu.Model, '^AMD Ryzen ([3579]) ([1-9]\d{3}(?:X3D|XT|X|G|GE|F)?)\s+(?:\d+-Core )?Processor\s*$', 'IgnoreCase')
    if (!$match.Success) { return $null }
    $family = $match.Groups[2].Value.Substring(0,1) + '000'
    $product = ('amd-ryzen-' + $match.Groups[1].Value + '-' + $match.Groups[2].Value).ToLowerInvariant()
    return "https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-$family-series/$product.html"
}

function Get-AmdPackageVersion([string]$html, $target, [string]$heading) {
    $timeout = [timespan]::FromMilliseconds(700)
    $button = [regex]::Match($html, '<button\b[^>]*>\s*Windows\s+' + $target.Family + '\s*-\s*64-Bit Edition\s*</button>', 'IgnoreCase, Singleline', $timeout)
    if (!$button.Success) { throw 'AMD did not publish a section for this Windows version.' }
    $section = $html.Substring($button.Index + $button.Length)
    $next = [regex]::Match($section, '<div\b[^>]*class="accordion-item"', 'IgnoreCase', $timeout)
    if ($next.Success) { $section = $section.Substring(0,$next.Index) }
    $articles = [regex]::Matches($section, '<article\b[^>]*class="[^"]*driver-download-details[^"]*"[^>]*>.*?</article>', 'IgnoreCase, Singleline', $timeout)
    $versions = @(foreach ($article in $articles) {
        if ($article.Value -notmatch ('<h4>\s*' + [regex]::Escape($heading) + '\s*</h4>')) { continue }
        $revision = [regex]::Match($article.Value, '<strong>\s*Revision Number\s*</strong>\s*<p>\s*(?:Adrenalin\s+)?(?<version>\d+(?:\.\d+){1,3})(?:\s+WHQL\s*\(Recommended\))?\s*</p>', 'IgnoreCase, Singleline', $timeout)
        if ($revision.Success) { $revision.Groups['version'].Value }
    })
    $versions = @($versions | Select-Object -Unique)
    if ($versions.Count -ne 1) { throw 'Expected one unambiguous AMD package version for this operating system.' }
    return $versions[0]
}

function Get-AmdCheck($row, $inventory, $target, $cache) {
    if ($row.Kind -eq 'Chipset package') {
        $url = Get-AmdChipsetSource $inventory
        if (!$url) { return $null }
        $available = Get-AmdPackageVersion (Get-VendorPage $url $cache) $target 'AMD Chipset Drivers'
        return New-ManufacturerCheck $row $url $available (Compare-ReportedVersion $row.Current $available) "AMD's chipset page matches the detected motherboard chipset and Windows $($target.Family) x64. This compares the installed AMD Chipset Software package, not SMBus/PCI component version numbers. Review the official release notes before installing."
    }
    if ($row.Kind -in 'GPU software', 'GPU driver' -and (Get-HardwareVendor $row) -eq 'AMD') {
        $gpu = if ($row.Kind -eq 'GPU driver') { $row } else {
            $matching = @($inventory | Where-Object { $_.Kind -eq 'GPU driver' -and (!$row.Part -or $_.Model -eq $row.Part) -and (Get-AmdGraphicsSource $inventory $_) })
            if ($matching.Count -ne 1) { return $null }
            $matching[0]
        }
        $url = Get-AmdGraphicsSource $inventory $gpu
        if (!$url) { return $null }
        $available = Get-AmdPackageVersion (Get-VendorPage $url $cache) $target 'AMD Software: Adrenalin Edition'
        $status = if ($row.Kind -eq 'GPU software') { Compare-ReportedVersion $row.Current $available } else { 'Vendor package found; compare the AMD Software row' }
        return New-ManufacturerCheck $row $url $available $status "AMD Adrenalin package for the detected $($gpu.Model) product and Windows $($target.Family) x64. The package version is compared only with installed AMD Software; it is not a Windows display-driver version."
    }
    return $null
}

function Get-AsusCheck($row, $inventory, $target, $cache) {
    $board = $inventory | Where-Object { $_.Kind -eq 'Motherboard' -and $_.Manufacturer -match 'ASUS|ASUSTeK' } | Select-Object -First 1
    if (!$board) { return $null }
    $category = ''; $pattern = ''; $packageModel = ''
    if ($row.Kind -eq 'Network driver') {
        $intel = [regex]::Match($row.Model, '\b(I225|I226)-[A-Z0-9]+\b', 'IgnoreCase')
        if ($intel.Success -and $row.Manufacturer -match 'Intel') { $category = 'LAN'; $pattern = '\b' + $intel.Groups[1].Value + '\b' }
        elseif ($row.Model -match 'MediaTek.*(?:MT7922|RZ616)') { $category = 'Wireless'; $pattern = '(?:AMD\s+Wi-?Fi|MediaTek.*(?:7922|RZ616))' }
    } elseif ($row.Kind -eq 'Audio/video driver' -and $row.Model -eq 'Realtek USB Audio' -and ($row.IDs -join ' ') -match 'USB\\(?:VID_0BDA&PID_40(?:80|82)|VID_0B05&PID_1A52)') {
        $category = 'Audio'; $pattern = 'Realtek\s+USB\s+Audio'
    } elseif ($row.Kind -eq 'Bluetooth driver' -and (Get-HardwareVendor $row) -eq 'MediaTek' -and ($row.IDs -join ' ') -match 'USB\\(?:VID_0E8D&PID_061[68]|VID_0489&PID_E0E2)(?:&|\s|$)') {
        $category = 'Bluetooth'; $pattern = '(?:AMD\s+Bluetooth|MediaTek.*(?:7922|RZ616))'
        # This OEM ID was verified in the official RZ616 mtkbtfilter.inf package.
        if(($row.IDs -join ' ') -match 'VID_0489&PID_E0E2(?:&|\s|$)'){$packageModel='RZ616'}
    }
    if (!$category) { return $null }
    $url = 'https://www.asus.com/supportonly/' + [Uri]::EscapeDataString($board.Model) + '/helpdesk_download/'
    $api = 'https://www.asus.com/support/webapi/ProductV2/GetPDDrivers?website=global&model=' + [Uri]::EscapeDataString($board.Model) + '&pdhashedid=&pdid=&cpu=&osid=' + $target.Asus
    $feed = Get-VendorPage $api $cache | ConvertFrom-Json
    if ($feed.Status -ne 'SUCCESS' -or [string]$feed.Result.Model -ne $board.Model) { throw 'ASUS feed does not match the exact motherboard model.' }
    $files = @($feed.Result.Obj | Where-Object Name -eq $category | ForEach-Object { $_.Files } | Where-Object {
        $_.Title -match $pattern -and $_.Title -notmatch '(?i)\b(beta|preview)\b' -and $_.Version -match '^\d+(?:\.\d+){1,3}$' -and
        (!$packageModel -or ($_.Title+' '+$_.DownloadUrl.Global) -match ('\b'+[regex]::Escape($packageModel)+'\b|_'+[regex]::Escape($packageModel)+'_'))
    })
    # Select a numeric driver version, not a package date or a driver for another board variant.
    $latest = $files | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
    if (!$latest) { throw 'No unambiguous component driver version was published for this board and Windows version.' }
    New-ManufacturerCheck $row $url $latest.Version (Compare-ReportedVersion $row.Current $latest.Version) "ASUS exact-board $category feed for Windows $($target.Family) x64: $([Net.WebUtility]::HtmlDecode(($latest.Title -replace '<[^>]+>',' '))). Released $($latest.ReleaseDate). Board packages are for manual vendor review; check the board revision before installation."
}

function Get-AutomaticManufacturerCheck($row, $inventory, $target, $cache) {
    try {
        if ($row.Kind -eq 'GPU driver' -and (Get-HardwareVendor $row) -eq 'NVIDIA') {
            $check = Get-NvidiaCheck $row $target $cache
            if ($check) { return $check }
        }
        $check = Get-AmdCheck $row $inventory $target $cache
        if ($check) { return $check }
        $check = Get-IntelWirelessCheck $row $target $cache
        if ($check) { return $check }
        return Get-AsusCheck $row $inventory $target $cache
    } catch {
        $route = Get-OfficialSupportRoute $row $inventory
        New-ManufacturerCheck $row $route.Url '' 'Unsupported automatic check; source unavailable' $_.Exception.Message $false
    }
}

function Get-IntelWirelessCheck($row, $target, $cache) {
    if ($row.Kind -ne 'Network driver' -or (Get-HardwareVendor $row) -ne 'Intel') { return $null }
    $model = [regex]::Match($row.Model, '\b(AX\d{3}|BE\d{3}|9[2456]\d{2})\b', 'IgnoreCase')
    if (!$model.Success) { return $null }
    $token = $model.Value.ToUpperInvariant()
    $url = if ($token -eq 'AX200') { 'https://www.intel.com/content/www/us/en/download/915475/intel-wireless-wi-fi-drivers-for-intel-wi-fi-6-ax200.html' }
        else { 'https://www.intel.com/content/www/us/en/download/19351/intel-wireless-wi-fi-drivers-for-windows-10-and-windows-11.html' }
    $text = (Convert-HtmlToText (Get-VendorPage $url $cache)) -replace '\s+', ' '
    $start = $text.IndexOf('This download is valid for the product', [StringComparison]::OrdinalIgnoreCase)
    if ($start -lt 0) { throw 'Intel did not expose an explicit supported-products list.' }
    $supported = $text.Substring($start)
    $end = $supported.IndexOf('Documentation', [StringComparison]::OrdinalIgnoreCase)
    if ($end -ge 0) { $supported = $supported.Substring(0,$end) }
    if ($supported -notmatch ('\b' + [regex]::Escape($token) + '\b')) { throw "Intel's current package does not list $token; a legacy or OEM package is required." }
    if ($text -notmatch ('Windows\W{0,5}' + $target.Family + '\b')) { throw 'Intel package does not list the detected Windows family.' }
    $versions = @([regex]::Matches($text, 'package\s+installs\s+the\s+Wi.?Fi\s+driver\s+version\s+(?<version>\d+(?:\.\d+){3})', 'IgnoreCase') | ForEach-Object { $_.Groups['version'].Value } | Select-Object -Unique)
    if ($versions.Count -ne 1) { throw 'Intel did not expose one unambiguous installed driver version; package numbering is not substituted.' }
    New-ManufacturerCheck $row $url $versions[0] (Compare-ReportedVersion $row.Current $versions[0]) "Intel driver-version metadata explicitly lists $token and Windows $($target.Family). OEM systems may require their customised driver; review the official source before installation."
}

function Get-InstalledAmdPackages {
    $paths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $result = @{ Chipset = ''; Graphics = '' }
    foreach ($package in @(Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue)) {
        if ($package.DisplayName -eq 'AMD Chipset Software') { $result.Chipset = [string]$package.DisplayVersion }
        elseif ($package.DisplayName -eq 'AMD Software') { $result.Graphics = [string]$package.DisplayVersion }
    }
    return $result
}
