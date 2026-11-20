# Managed manufacturer packages are deliberately limited to these exact official EXE routes.
function Test-ManagedPackageUri([uri]$uri,[string]$family) {
    if(!$uri.IsAbsoluteUri -or $uri.Scheme -cne 'https' -or $uri.Port -ne 443 -or $uri.UserInfo -or $uri.Fragment -or $uri.Query){return $false}
    switch($family){
        'AMDChipset' {return $uri.DnsSafeHost -ceq 'drivers.amd.com' -and $uri.AbsolutePath -cmatch '^/drivers/amd_chipset_software_\d+(?:\.\d+){3}\.exe$'}
        'NvidiaDesktop' {return $uri.DnsSafeHost -cin @('us.download.nvidia.com','download.nvidia.com') -and $uri.AbsolutePath -cmatch '^/Windows/\d{3}\.\d{2}/\d{3}\.\d{2}-desktop-win10-win11-64bit-international-dch-whql\.exe$'}
    }
    return $false
}

function Assert-ManagedPackage($package) {
    if($package.Family -notin 'AMDChipset','NvidiaDesktop' -or $package.OSFamily -notin '10','11' -or !$package.DeviceKey -or !$package.DeviceModel -or !$package.Current){throw 'The manufacturer package has no supported device and Windows match.'}
    $source=Get-HttpsUri $package.SourceUrl;$uri=Get-HttpsUri $package.Url
    if(!(Test-ManagedPackageUri $uri $package.Family)){throw 'The package has no approved official download URL.'}
    $version=[string]$package.Version
    if($package.Family -eq 'AMDChipset'){
        if($version -notmatch '^\d+(?:\.\d+){3}$' -or $uri.AbsolutePath -cne ('/drivers/amd_chipset_software_'+$version+'.exe') -or $source.DnsSafeHost -cne 'www.amd.com' -or $source.AbsolutePath -cnotmatch '^/en/support/downloads/drivers.html/chipsets/am[45]/[a-z0-9]+\.html$'){throw 'The AMD chipset package does not match its official version/source.'}
    }else{
        if($version -notmatch '^\d{3}\.\d{2}$' -or $uri.AbsolutePath -cne ('/Windows/'+$version+'/'+$version+'-desktop-win10-win11-64bit-international-dch-whql.exe') -or $source.DnsSafeHost -cne 'www.nvidia.com' -or $source.AbsolutePath -cnotmatch '^/en-us/drivers/details/\d+/$'){throw 'The NVIDIA desktop package does not match its official version/source.'}
    }
    if($source.Query -or $source.Fragment -or $source.UserInfo -or $source.Port -ne 443){throw 'The package source URL is invalid.'}
}

function New-ManagedPackage([string]$family,$row,$target,[string]$version,[string]$source,[string]$url) {
    $package=[pscustomobject]@{Family=$family;DeviceKey=$row.Key;DeviceModel=$row.Model;Current=$row.Current;OSFamily=$target.Family;Version=$version;SourceUrl=$source;Url=$url}
    try{Assert-ManagedPackage $package;return $package}catch{return $null}
}

function Get-AmdChipsetPackage($row,$target,[string]$version,[string]$source,[string]$html) {
    $timeout=[timespan]::FromMilliseconds(700)
    $button=[regex]::Match($html,'<button\b[^>]*>\s*Windows\s+'+$target.Family+'\s*-\s*64-Bit Edition\s*</button>','IgnoreCase,Singleline',$timeout)
    if(!$button.Success){return $null}
    $section=$html.Substring($button.Index+$button.Length)
    $next=[regex]::Match($section,'<div\b[^>]*class="accordion-item"','IgnoreCase',$timeout)
    if($next.Success){$section=$section.Substring(0,$next.Index)}
    $links=@(foreach($article in [regex]::Matches($section,'<article\b[^>]*class="[^"]*driver-download-details[^"]*"[^>]*>.*?</article>','IgnoreCase,Singleline',$timeout)){
        if($article.Value -notmatch '<h4>\s*AMD Chipset Drivers\s*</h4>' -or $article.Value -notmatch ('<strong>\s*Revision Number\s*</strong>\s*<p>\s*'+[regex]::Escape($version)+'\s*</p>')){continue}
        foreach($link in [regex]::Matches($article.Value,'href="(?<url>[^"]+)"','IgnoreCase',$timeout)){
            $url=[Net.WebUtility]::HtmlDecode($link.Groups['url'].Value)
            if($url -match '\.exe(?:[?#]|$)'){$url}
        }
    })
    $links=@($links|Select-Object -Unique)
    if($links.Count -ne 1){return $null}
    return New-ManagedPackage 'AMDChipset' $row $target $version $source $links[0]
}

function Test-ManagedPackageOffer($device,$check) {
    if(!$device -or !$check -or !$check.Checked -or $check.Status -ne 'Newer at source' -or !$check.Package){return $false}
    try{
        Assert-ManagedPackage $check.Package
        if($check.Package.DeviceKey -cne $device.Key -or $check.Package.Current -cne $device.Current -or $check.Package.Version -cne $check.Available -or $check.Package.SourceUrl -cne $check.Url){return $false}
        return ($check.Package.Family -eq 'AMDChipset' -and $device.Kind -eq 'Chipset package' -and (Get-HardwareVendor $device) -eq 'AMD') -or
            ($check.Package.Family -eq 'NvidiaDesktop' -and $device.Kind -eq 'GPU driver' -and (Get-HardwareVendor $device) -eq 'NVIDIA' -and $device.Model -notmatch 'Laptop|Notebook')
    }catch{return $false}
}

function Resolve-ManagedPackage($selection) {
    # Cached scans and user catalogs never authorise executable URLs: detect and resolve afresh.
    $data=Get-HardwareInventory
    $matches=@($data.Inventory|Where-Object Key -CEQ $selection.Device.Key)
    if($matches.Count -ne 1 -or $matches[0].Current -cne $selection.Device.Current){throw 'The device or installed version changed. Refresh the hardware list before downloading.'}
    $target=Get-WindowsDriverTarget $data.OS
    $check=Get-AutomaticManufacturerCheck $matches[0] $data.Inventory $target @{}
    if(!(Test-ManagedPackageOffer $matches[0] $check) -or $check.Available -cne $selection.Check.Available -or $check.Url -cne $selection.Check.Url){throw 'The official update offer changed or cannot be verified. Refresh the hardware list and review it again.'}
    return $check.Package
}

function Get-PackageFileInfo([string]$path) {return [Diagnostics.FileVersionInfo]::GetVersionInfo($path)}

function Assert-PackageSignature([string]$path,$package) {
    $signature=Get-AuthenticodeSignature -LiteralPath $path
    if($signature.Status -ne 'Valid' -or !$signature.SignerCertificate){throw 'Windows could not validate the manufacturer signature. The installer will not run.'}
    $name=$signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false)
    $expected=if($package.Family -eq 'AMDChipset'){'^Advanced Micro Devices(?:,? Inc\.?)?$'}else{'^NVIDIA Corporation$'}
    if($name -cnotmatch $expected){throw 'The installer is signed by an unexpected publisher. The installer will not run.'}
    if($package.Family -eq 'AMDChipset'){
        $metadata=Get-PackageFileInfo $path;$version=$null
        if($metadata.ProductName -cne 'AMD Chipset Software' -or ![version]::TryParse($metadata.FileVersion,[ref]$version) -or $version -ne [version]$package.Version){throw 'The signed AMD installer product/version does not match the official chipset offer.'}
    }
}

function Assert-VerifiedPackage($result) {
    Assert-ManagedPackage $result.Package
    if($result.SHA256 -cnotmatch '^[a-f0-9]{64}$' -or $result.Bytes -le 0 -or $result.Bytes -gt 2147483648 -or !$result.Path -or !(Test-Path -LiteralPath $result.Path -PathType Leaf) -or (Get-Item -LiteralPath $result.Path).Length -ne $result.Bytes){throw 'The verified download is missing or changed.'}
    if((Get-FileHash -LiteralPath $result.Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $result.SHA256){throw 'The installer changed after verification. Download it again.'}
    Assert-PackageSignature $result.Path $result.Package
    if((Get-Content -LiteralPath $result.Path -Stream Zone.Identifier -Raw) -notmatch '(?m)^ZoneId=3\r?$'){throw 'The installer has lost its Internet download marker.'}
}

function Receive-ManagedPackage($selection,[string]$folder) {
    Write-Progress -Activity 'Downloading installer' -Status 'Checking the current device and official package' -PercentComplete 0
    $package=Resolve-ManagedPackage $selection
    $name=if($package.Family -eq 'AMDChipset'){'AMD-Chipset-Setup.exe'}else{'NVIDIA-Driver-Setup.exe'}
    $path=Save-VerifiedDownload $package.Url $folder $name 2147483648 0 $package.SourceUrl {param($uri)(Test-ManagedPackageUri $uri $package.Family) -and $uri.AbsolutePath -ceq ([uri]$package.Url).AbsolutePath} {param($path)Assert-PackageSignature $path $package}
    try{
        if(Test-Path -LiteralPath (Join-Path $folder 'cancel')){throw [OperationCanceledException]::new('Download cancelled.')}
        # Recheck the published offer after a potentially large download, before returning a runnable file.
        $current=Resolve-ManagedPackage $selection
        if($current.Url -cne $package.Url -or $current.Version -cne $package.Version){throw 'The official package changed while downloading. Refresh and try again.'}
        $result=[pscustomobject]@{Path=$path;Package=$package;Bytes=(Get-Item -LiteralPath $path).Length;SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
        Assert-VerifiedPackage $result
        return $result
    }catch{if([IO.File]::Exists($path)){[IO.File]::Delete($path)};throw}
}

function Start-ManagedPackage($result) {
    Assert-VerifiedPackage $result
    # No silent switches, pre-accepted licences, forced restarts or driver-rank overrides.
    Start-Process -FilePath $result.Path -PassThru
}
