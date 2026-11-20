function Initialize-AsusTrust {
    if(!('DriverLoom.Security.AsusTrust' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'AsusTrust.cs')}
    if(!('System.IO.Compression.ZipArchiveMode' -as [type])){Add-Type -AssemblyName System.IO.Compression}
    if(!('System.IO.Compression.ZipFile' -as [type])){Add-Type -AssemblyName System.IO.Compression.FileSystem}
}

function Get-AsusHardwareIds($device) {
    @($device.IDs|ForEach-Object{([string]$_).Trim().ToUpperInvariant()}|Where-Object{$_ -match '^(?:PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}|USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4})(?:&[A-Z0-9_]+)*$'}|Sort-Object -Unique)
}

function Assert-AsusPackage($package) {
    $uri=Get-HttpsUri $package.Url;$source=Get-HttpsUri $package.SourceUrl
    if($package.Category -notin 'LAN','Wireless','Bluetooth','Audio' -or !$package.BoardKey -or !$package.BoardModel -or @($package.HardwareIds).Count -eq 0 -or $package.OSBuild -lt 10240){throw 'The ASUS package has no exact board, hardware and Windows match.'}
    if($source.AbsoluteUri -cne ('https://www.asus.com/supportonly/'+[Uri]::EscapeDataString($package.BoardModel)+'/helpdesk_download/')){throw 'The ASUS support source does not match the board.'}
    if($uri.Scheme -cne 'https' -or $uri.Port -ne 443 -or $uri.DnsSafeHost -cnotin @('dlcdnets.asus.com','dlcdnet.asus.com') -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -cnotmatch '^/pub/ASUS/mb/[A-Za-z0-9_./-]+\.zip$'){throw 'The ASUS archive URL is not an approved official package.'}
    if($package.Version -notmatch '^\d+(?:\.\d+){1,3}$' -or ($package.OfficialHash -and $package.OfficialHash -cnotmatch '^[a-f0-9]{64}$')){throw 'The ASUS package version/checksum is invalid.'}
}

function New-AsusPackage($row,$board,$target,[string]$category,$file,[string]$source) {
    $download=[string]$file.DownloadUrl.Global
    if($download.StartsWith('/')){$download='https://dlcdnets.asus.com'+$download}
    $package=[pscustomobject]@{Family='ASUSDriver';DeviceKey=$row.Key;DeviceModel=$row.Model;Current=$row.Current;Version=[string]$file.Version;OSFamily=$target.Family;OSBuild=$target.Build;SourceUrl=$source;Url=$download;BoardKey=$board.Key;BoardModel=$board.Model;Category=$category;HardwareIds=@(Get-AsusHardwareIds $row);OfficialHash=([string]$file.sha256).ToLowerInvariant()}
    try{Assert-AsusPackage $package;return $package}catch{return $null}
}

function Get-AsusArchivePath([string]$root,[string]$name) {
    $relative=$name.Replace('/','\').TrimEnd('\')
    if(!$relative -or $relative.StartsWith('\') -or $relative.Length -gt 190){throw 'The ASUS archive contains an invalid path.'}
    foreach($segment in $relative.Split('\')){
        if(!$segment -or $segment -in '.','..' -or $segment -match '[<>:"|?*\x00-\x1f]' -or $segment -match '[. ]$' -or $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw 'The ASUS archive contains an unsafe path.'}
    }
    $path=[IO.Path]::GetFullPath((Join-Path $root $relative))
    if(!$path.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $path.Length -gt 245){throw 'The ASUS archive path is outside its extraction folder or too long.'}
    return $path
}

function Assert-AsusRoot([string]$root) {
    $root=[IO.Path]::GetFullPath($root)
    $prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$root.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($root) -cnotmatch '^DriverLoom-ASUS-[a-f0-9]{32}$' -or ((Test-Path -LiteralPath $root) -and ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint))){throw 'The ASUS extraction folder is invalid.'}
}

function Remove-AsusRoot([string]$root) {
    Assert-AsusRoot $root
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}

function Expand-AsusArchive([string]$archive,[string]$root,[string]$cancel) {
    Initialize-AsusTrust;Assert-AsusRoot $root
    if(Test-Path -LiteralPath $root){throw 'The ASUS extraction folder is not empty.'}
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    try{
        if($zip.Entries.Count -eq 0 -or $zip.Entries.Count -gt 10000){throw 'The ASUS archive has an unsupported file count.'}
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$total=0L
        foreach($entry in $zip.Entries){
            $path=Get-AsusArchivePath $root $entry.FullName
            if(!$seen.Add($path) -or (($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000 -or ($entry.ExternalAttributes -band 0x400)){throw 'The ASUS archive contains duplicate paths or links.'}
            $total+=$entry.Length
            if($entry.Length -gt 1073741824 -or $total -gt 2147483648){throw 'The expanded ASUS package exceeds the supported size.'}
        }
        [void][IO.Directory]::CreateDirectory($root)
        $watch=[Diagnostics.Stopwatch]::StartNew();$last=-200L;$done=0
        foreach($entry in $zip.Entries){
            if(Test-Path -LiteralPath $cancel){throw [OperationCanceledException]::new('Download cancelled.')}
            $path=Get-AsusArchivePath $root $entry.FullName
            if($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')){[void][IO.Directory]::CreateDirectory($path)}
            else{
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
                $inputStream=$entry.Open();$outputStream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                try{
                    $buffer=[byte[]]::new(65536);$written=0L
                    while(($count=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0){
                        $written+=$count;if($written -gt $entry.Length){throw 'An ASUS archive entry exceeded its declared size.'}
                        $outputStream.Write($buffer,0,$count)
                        if(Test-Path -LiteralPath $cancel){throw [OperationCanceledException]::new('Download cancelled.')}
                    }
                    if($written -ne $entry.Length){throw 'The ASUS archive contains an incomplete file.'}
                }finally{$inputStream.Dispose();$outputStream.Dispose()}
            }
            $done++
            if($watch.ElapsedMilliseconds-$last -ge 200){Write-Progress -Activity 'ASUS driver package' -Status 'Extracting and verifying package' -PercentComplete ([int](100*$done/$zip.Entries.Count));$last=$watch.ElapsedMilliseconds}
        }
    }finally{$zip.Dispose()}
}

function Assert-AsusSetup([string]$path) {
    if([IO.Path]::GetFileName($path) -cne 'AsusSetup.exe' -or !(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -le 0){throw 'The archive has no supported ASUS setup entry point.'}
    $signature=Get-AuthenticodeSignature -LiteralPath $path
    if($signature.Status -ne 'Valid' -or !$signature.SignerCertificate -or $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false) -cne 'ASUSTeK COMPUTER INC.'){throw 'Windows could not verify the ASUS setup publisher.'}
}

function Get-AsusDriverProof([string]$root,$package) {
    Initialize-AsusTrust
    $expectedClass=switch($package.Category){'Audio'{'MEDIA'}'Bluetooth'{'Bluetooth'}default{'Net'}}
    $proofs=[Collections.Generic.List[object]]::new()
    foreach($relative in [DriverLoom.Security.AsusTrust]::Files($root)|Where-Object{$_ -match '\.inf$'}){
        $path=Join-Path $root $relative
        if((Get-Item -LiteralPath $path).Length -gt 4194304){throw 'An ASUS driver INF exceeds the supported size.'}
        try{$facts=Read-AsusInf $path}catch{continue}
        $version=$null
        if($facts.DeviceClass -ine $expectedClass -or ![version]::TryParse($facts.Version,[ref]$version) -or $version -ne [version]$package.Version){continue}
        $matchingIds=@($package.HardwareIds|Where-Object{$_ -in $facts.Ids})
        if(!$matchingIds.Count){continue}
        if($facts.Catalog -notmatch '^[a-zA-Z0-9_.-]+\.cat$'){throw 'The matching driver has no supported catalog.'}
        $cat=Join-Path ([IO.Path]::GetDirectoryName($path)) $facts.Catalog
        if(!(Test-Path -LiteralPath $cat -PathType Leaf)){throw 'The matching ASUS driver catalog is missing.'}
        $signature=Get-AuthenticodeSignature -LiteralPath $cat
        if($signature.Status -ne 'Valid' -or !$signature.SignerCertificate -or $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false) -cne 'Microsoft Windows Hardware Compatibility Publisher' -or !(Test-AsusCatalogMember $path $cat)){throw 'Windows could not verify the matching driver INF against its trusted catalog.'}
        $proofs.Add([pscustomobject]@{Inf=$relative;Catalog=$cat.Substring($root.Length+1);HardwareId=$matchingIds[0]})
    }
    if(!$proofs.Count){throw 'The archive has no catalog-verified x64 driver matching this device, class and version.'}
    return $proofs[0]
}

function Read-AsusInf([string]$path) {Initialize-AsusTrust;return [DriverLoom.Security.AsusTrust]::ReadInf($path)}
function Test-AsusCatalogMember([string]$path,[string]$catalog) {Initialize-AsusTrust;return [DriverLoom.Security.AsusTrust]::VerifyCatalogMember($path,$catalog)}

function Assert-AsusResult($result) {
    Assert-AsusRoot $result.Root;Initialize-AsusTrust
    if($result.Path -cne (Join-Path $result.Root 'AsusSetup.exe')){throw 'The ASUS setup path changed.'}
    if(!(Test-Path -LiteralPath $result.ArchivePath -PathType Leaf) -or (Get-FileHash -LiteralPath $result.ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $result.ArchiveSHA256 -or ($result.Package.OfficialHash -and $result.Package.OfficialHash -cne $result.ArchiveSHA256)){throw 'The ASUS archive changed after download.'}
    $files=[DriverLoom.Security.AsusTrust]::Files($result.Root)
    if($files.Length -ne @($result.FileNames).Count -or @($result.FileHashes).Count -ne $files.Length){throw 'The extracted ASUS package changed.'}
    for($i=0;$i -lt $files.Length;$i++){if($files[$i] -cne $result.FileNames[$i]){throw 'The extracted ASUS file list changed.'}}
    $hashes=[DriverLoom.Security.AsusTrust]::HashFiles($result.Root,$files)
    for($i=0;$i -lt $hashes.Length;$i++){if($hashes[$i] -cne $result.FileHashes[$i]){throw 'An extracted ASUS file changed after verification.'}}
    Assert-AsusSetup $result.Path
    $proof=Get-AsusDriverProof $result.Root $result.Package
    if($proof.Inf -cne $result.Proof.Inf -or $proof.Catalog -cne $result.Proof.Catalog -or $proof.HardwareId -cne $result.Proof.HardwareId){throw 'The verified ASUS driver changed.'}
    if((Get-Content -LiteralPath $result.Path -Stream Zone.Identifier -Raw) -notmatch '(?m)^ZoneId=3\r?$'){throw 'The ASUS setup has lost its Internet download marker.'}
}

function Receive-AsusPackage($selection,[string]$folder,$package) {
    $root=Join-Path ([IO.Path]::GetTempPath()) ('DriverLoom-ASUS-'+[guid]::NewGuid().ToString('N'))
    $archive=''
    try{
        $archive=Save-VerifiedDownload $package.Url $folder 'ASUS-Driver.zip' 1073741824 0 $package.SourceUrl {param($uri)(Test-ManagedPackageUri $uri 'ASUSDriver') -and $uri.AbsolutePath -ceq ([uri]$package.Url).AbsolutePath} {
            param($path)
            if($package.OfficialHash -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $package.OfficialHash){throw 'The ASUS archive does not match its published SHA-256.'}
        } -UseRanges
        $cancel=Join-Path $folder 'cancel'
        Expand-AsusArchive $archive $root $cancel
        $setup=Join-Path $root 'AsusSetup.exe';Assert-AsusSetup $setup
        $proof=Get-AsusDriverProof $root $package
        $zone=Get-Content -LiteralPath $archive -Stream Zone.Identifier -Raw
        Set-Content -LiteralPath $setup -Stream Zone.Identifier -Value $zone -Encoding ASCII -NoNewline
        $files=[DriverLoom.Security.AsusTrust]::Files($root)
        Write-Progress -Activity 'ASUS driver package' -Status 'Verifying extracted files' -PercentComplete 100
        $result=[pscustomobject]@{Path=$setup;Root=$root;Package=$package;ArchivePath=$archive;ArchiveSHA256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant();FileNames=$files;FileHashes=[DriverLoom.Security.AsusTrust]::HashFiles($root,$files);Proof=$proof}
        $current=Resolve-ManagedPackage $selection
        if($current.Url -cne $package.Url -or $current.OfficialHash -cne $package.OfficialHash){throw 'The official ASUS package changed while downloading.'}
        if(Test-Path -LiteralPath $cancel){throw [OperationCanceledException]::new('Download cancelled.')}
        Assert-AsusResult $result
        return $result
    }catch{
        Remove-AsusRoot $root
        if($archive -and [IO.File]::Exists($archive)){[IO.File]::Delete($archive)}
        throw
    }
}
