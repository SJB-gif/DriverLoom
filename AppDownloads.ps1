# Only this project's published installer is downloaded. Manufacturer actions use their existing routes.
function Assert-AppDownloadInfo($info,[string]$currentVersion) {
    if([string]$info.Tag -cnotmatch '^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*))?$'){throw 'The update version is invalid.'}
    $latest=[version]($info.Tag -replace '^v','');$current=[version]$currentVersion
    $latest=[version]::new($latest.Major,$latest.Minor,[Math]::Max(0,$latest.Build),[Math]::Max(0,$latest.Revision))
    $current=[version]::new($current.Major,$current.Minor,[Math]::Max(0,$current.Build),[Math]::Max(0,$current.Revision))
    if($latest -le $current -or [version]$info.LatestVersion -ne [version]($info.Tag -replace '^v','')){throw 'This installer is not a newer DriverLoom version.'}
    if([string]$info.ReleaseUrl -cne ('https://github.com/SJB-gif/DriverLoom/releases/tag/'+$info.Tag) -or [string]$info.InstallerUrl -cne ('https://github.com/SJB-gif/DriverLoom/releases/download/'+$info.Tag+'/DriverLoom-Setup.exe')){throw 'The installer does not belong to this DriverLoom release.'}
    if([string]$info.InstallerHash -cnotmatch '^[a-f0-9]{64}$' -or $info.InstallerSize -isnot [ValueType] -or [long]$info.InstallerSize -le 0 -or [long]$info.InstallerSize -gt 67108864){throw 'Installer verification metadata is missing or invalid.'}
}

function Test-AppDownloadUri([uri]$uri) {
    return $uri.IsAbsoluteUri -and $uri.Scheme -ceq 'https' -and $uri.Port -eq 443 -and !$uri.UserInfo -and !$uri.Fragment -and $uri.DnsSafeHost -cin @('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com')
}

function Open-AppDownloadResponse([uri]$uri,[string]$referrer='',[long]$rangeStart=-1,[long]$rangeEnd=-1,[string]$etag='') {
    $request=[Net.HttpWebRequest]::Create($uri)
    $request.AllowAutoRedirect=$false;$request.Timeout=15000;$request.ReadWriteTimeout=10000
    $request.UserAgent='DriverLoom app updater';$request.UseDefaultCredentials=$false
    $request.AutomaticDecompression=[Net.DecompressionMethods]::None
    if($referrer){$request.Referer=$referrer}
    if($rangeStart -ge 0){$request.AddRange($rangeStart,$rangeEnd);if($etag){$request.Headers['If-Range']=$etag}}
    return $request.GetResponse()
}

function Get-AppInstallerVersion([string]$path) {
    return [Diagnostics.FileVersionInfo]::GetVersionInfo($path).ProductVersion
}

function Assert-AppInstaller([string]$path,$info,[string]$currentVersion) {
    Assert-AppDownloadInfo $info $currentVersion
    if(!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -ne [long]$info.InstallerSize){throw 'The downloaded installer size does not match the release.'}
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $info.InstallerHash){throw 'The downloaded installer checksum does not match the release.'}
    $actual=$null
    if(![version]::TryParse((Get-AppInstallerVersion $path),[ref]$actual)){throw 'The downloaded file has no valid installer version.'}
    $expected=[version]$info.LatestVersion
    $actual=[version]::new($actual.Major,$actual.Minor,[Math]::Max(0,$actual.Build),[Math]::Max(0,$actual.Revision))
    $expected=[version]::new($expected.Major,$expected.Minor,[Math]::Max(0,$expected.Build),[Math]::Max(0,$expected.Revision))
    if($actual -ne $expected){throw 'The downloaded installer version does not match the release.'}
}

function Receive-AppInstaller($info,[string]$currentVersion,[string]$folder) {
    Assert-AppDownloadInfo $info $currentVersion
    return Save-VerifiedDownload $info.InstallerUrl $folder 'DriverLoom-Setup.exe' 67108864 $info.InstallerSize $info.ReleaseUrl {param($uri)Test-AppDownloadUri $uri} {param($path)Assert-AppInstaller $path $info $currentVersion}
}

function Get-VerifiedDownloadRange($response,[long]$start,[long]$end,[long]$length=0,[string]$etag='') {
    if([int]$response.StatusCode -ne 206 -or [string]$response.Headers['Content-Range'] -cnotmatch '^bytes ([0-9]+)-([0-9]+)/([0-9]+)$'){throw 'The server returned an invalid download segment.'}
    $actualStart=[long]$Matches[1];$actualEnd=[long]$Matches[2];$actualLength=[long]$Matches[3]
    $actualTag=[string]$response.Headers['ETag']
    if($actualLength -le 0 -or $actualStart -ne $start -or $actualEnd -ne [Math]::Min($end,$actualLength-1) -or $actualEnd -lt $actualStart -or ($length -gt 0 -and $actualLength -ne $length) -or $actualTag -cnotmatch '^"[!#-~]{1,200}"$' -or ($etag -and $actualTag -cne $etag) -or ($response.ContentLength -ne -1 -and $response.ContentLength -ne ($actualEnd-$actualStart+1))){throw 'The download changed or returned an unexpected segment.'}
    [pscustomobject]@{Length=$actualLength;End=$actualEnd;ETag=$actualTag}
}

function Save-VerifiedDownload([string]$url,[string]$folder,[string]$filename,[long]$maxBytes,[long]$expectedBytes,[string]$referrer,[scriptblock]$allowedUri,[scriptblock]$verify,[switch]$UseRanges,[int]$RangeBytes=1048576) {
    if($filename -notmatch '^[a-zA-Z0-9._-]+\.(?:exe|zip)$' -or $maxBytes -le 0 -or $expectedBytes -lt 0 -or $expectedBytes -gt $maxBytes -or $RangeBytes -lt 1 -or $RangeBytes -gt 8388608){throw 'Invalid download bounds.'}
    # The UI creates a new unique folder for each attempt; never overwrite another download.
    $part=Join-Path $folder ($filename -replace '\.(?:exe|zip)$','.part');$target=Join-Path $folder $filename;$cancel=Join-Path $folder 'cancel'
    if(!(Test-Path -LiteralPath $folder -PathType Container) -or (Test-Path -LiteralPath $part) -or (Test-Path -LiteralPath $target)){throw 'The download folder is not ready.'}
    $response=$null;$stream=$null;$output=$null;$success=$false;$uri=[uri]$url
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try{
        for($redirect=0;$redirect -le 5;$redirect++){
            if(Test-Path -LiteralPath $cancel){throw [OperationCanceledException]::new('Download cancelled.')}
            if(!(& $allowedUri $uri)){throw 'The download redirected outside its approved official source.'}
            if($UseRanges){$response=Open-AppDownloadResponse $uri $referrer 0 ($RangeBytes-1)}else{$response=Open-AppDownloadResponse $uri $referrer}
            $code=[int]$response.StatusCode
            if($code -in 301,302,303,307,308){
                $location=[string]$response.Headers['Location'];$response.Dispose();$response=$null
                if(!$location -or $redirect -eq 5){throw 'The installer download has too many redirects.'}
                $uri=[uri]::new($uri,$location);continue
            }
            if($code -ne 200 -and !($UseRanges -and $code -eq 206)){throw 'The installer server did not return a download.'}
            break
        }
        $range=$null
        if([int]$response.StatusCode -eq 206){$range=Get-VerifiedDownloadRange $response 0 ($RangeBytes-1);$length=$range.Length}
        else{$length=if($expectedBytes -gt 0){$expectedBytes}else{$response.ContentLength}}
        if($length -gt $maxBytes -or ($expectedBytes -gt 0 -and $length -ne $expectedBytes) -or (!$range -and $expectedBytes -gt 0 -and $response.ContentLength -ne -1 -and $response.ContentLength -ne $expectedBytes)){throw 'The installer server reported an unexpected file size.'}
        $stream=$response.GetResponseStream();$output=[IO.File]::Open($part,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=[byte[]]::new(65536);$total=0L;$lastProgress=-200L
        while($true){
            if(Test-Path -LiteralPath $cancel){throw [OperationCanceledException]::new('Download cancelled.')}
            if($watch.Elapsed.TotalMinutes -ge 30){throw 'The installer download timed out. Please try again.'}
            $count=$stream.Read($buffer,0,$buffer.Length)
            if($count -eq 0){
                if(!$range){break}
                if($total -ne $range.End+1){throw 'The download segment is incomplete.'}
                if($total -eq $length){break}
                $stream.Dispose();$stream=$null;$response.Dispose();$response=$null
                if(Test-Path -LiteralPath $cancel){throw [OperationCanceledException]::new('Download cancelled.')}
                $end=[Math]::Min($total+$RangeBytes-1,$length-1)
                $response=Open-AppDownloadResponse $uri $referrer $total $end $range.ETag
                $range=Get-VerifiedDownloadRange $response $total $end $length $range.ETag
                $stream=$response.GetResponseStream();continue
            }
            $total+=$count
            if($total -gt $maxBytes -or ($length -gt 0 -and $total -gt $length) -or ($range -and $total -gt $range.End+1)){throw 'The download exceeded the expected installer size.'}
            $output.Write($buffer,0,$count)
            if($watch.ElapsedMilliseconds-$lastProgress -ge 200 -or $total -eq $length){
                $description=if($length -gt 0){'{0:N1} of {1:N1} MB' -f ($total/1MB),($length/1MB)}else{'{0:N1} MB downloaded' -f ($total/1MB)}
                Write-Progress -Activity 'Downloading installer' -Status $description -PercentComplete $(if($length -gt 0){[int](100*$total/$length)}else{0})
                $lastProgress=$watch.ElapsedMilliseconds
            }
        }
        $output.Dispose();$output=$null;$stream.Dispose();$stream=$null;$response.Dispose();$response=$null
        if($total -le 0 -or ($length -gt 0 -and $total -ne $length)){throw 'The installer download is incomplete.'}
        Write-Progress -Activity 'Downloading installer' -Status 'Verifying installer' -PercentComplete 100
        & $verify $part
        if(Test-Path -LiteralPath $cancel){throw [OperationCanceledException]::new('Download cancelled.')}
        [IO.File]::Move($part,$target)
        # Preserve Internet origin so normal Windows attachment/reputation checks still apply.
        $zone="[ZoneTransfer]`r`nZoneId=3`r`nReferrerUrl=$referrer`r`nHostUrl=$url`r`n"
        Set-Content -LiteralPath $target -Stream Zone.Identifier -Value $zone -Encoding ASCII -NoNewline
        if((Get-Content -LiteralPath $target -Stream Zone.Identifier -Raw) -cne $zone){throw 'Windows could not mark the installer as an Internet download.'}
        $success=$true
        return $target
    }finally{
        if($output){$output.Dispose()};if($stream){$stream.Dispose()};if($response){$response.Dispose()}
        if(!$success){foreach($file in @($part,$target)){if([IO.File]::Exists($file)){[IO.File]::Delete($file)}}}
        Write-Progress -Activity 'Downloading installer' -Completed
    }
}

function Start-AppInstaller([string]$path,$info,[string]$currentVersion) {
    Assert-AppInstaller $path $info $currentVersion
    $zone=Get-Content -LiteralPath $path -Stream Zone.Identifier -Raw
    if($zone -notmatch '(?m)^ZoneId=3\r?$'){throw 'The installer has lost its Internet download marker. Download it again.'}
    # Shell execution retains Windows security prompts and normal interactive setup options.
    return Start-Process -FilePath $path -PassThru
}
