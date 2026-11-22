function Get-AppUpdateInfo([string]$currentVersion=$script:LauncherVersion) {
    $current=$null
    if(![version]::TryParse($currentVersion,[ref]$current)){throw 'The installed DriverLoom version is invalid.'}
    $release=Read-WebSource 'https://api.github.com/repos/SJB-gif/DriverLoom/releases/latest' 524288|ConvertFrom-Json
    if($release.draft -isnot [bool] -or $release.prerelease -isnot [bool] -or $release.draft -or $release.prerelease){throw 'The response is not a published stable DriverLoom release.'}
    $tag=[string]$release.tag_name
    if($tag -notmatch '^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*))?$'){throw 'The published DriverLoom version is not recognised.'}
    $latest=$null
    if(![version]::TryParse(($tag -replace '^v',''),[ref]$latest)){throw 'The published DriverLoom version is invalid.'}
    $releaseUrl='https://github.com/SJB-gif/DriverLoom/releases/tag/'+$tag
    if([string]$release.html_url -cne $releaseUrl){throw 'The release URL does not belong to this DriverLoom project.'}
    $normalizedCurrent=[version]::new($current.Major,$current.Minor,[Math]::Max(0,$current.Build),[Math]::Max(0,$current.Revision))
    $normalizedLatest=[version]::new($latest.Major,$latest.Minor,[Math]::Max(0,$latest.Build),[Math]::Max(0,$latest.Revision))
    $available=$normalizedLatest -gt $normalizedCurrent
    $installerUrl=''
    $installerSize=0;$installerHash=''
    if($available){
        $assets=@($release.assets|Where-Object name -ceq 'DriverLoom-Setup.exe')
        if($assets.Count -ne 1 -or $assets[0].state -ne 'uploaded' -or $assets[0].size -le 0 -or $assets[0].size -gt 67108864){throw 'The release does not contain one completed DriverLoom installer.'}
        $installerUrl='https://github.com/SJB-gif/DriverLoom/releases/download/'+$tag+'/DriverLoom-Setup.exe'
        if([string]$assets[0].browser_download_url -cne $installerUrl){throw 'The installer URL does not belong to this DriverLoom release.'}
        if([string]$assets[0].digest -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'The release installer has no verifiable SHA-256 digest.'}
        $installerSize=[long]$assets[0].size;$installerHash=([string]$assets[0].digest).Substring(7)
    }
    [pscustomobject]@{CurrentVersion=$currentVersion;LatestVersion=$latest.ToString();Tag=$tag;UpdateAvailable=$available;ReleaseUrl=$releaseUrl;InstallerUrl=$installerUrl;InstallerSize=$installerSize;InstallerHash=$installerHash}
}
