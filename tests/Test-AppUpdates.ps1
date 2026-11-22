$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'src'
$ErrorActionPreference='Stop'
. (Join-Path $srcRoot 'Engine.ps1')
. (Join-Path $srcRoot 'AppUpdates.ps1')
function Assert-AppUpdate($expected,$actual,[string]$description){if($actual -cne $expected){throw "$description expected '$expected', got '$actual'."}}
$script:releaseFixture=[pscustomobject]@{tag_name='v0.2.0';draft=$false;prerelease=$false;html_url='https://github.com/SJB-gif/DriverLoom/releases/tag/v0.2.0';assets=@([pscustomobject]@{name='DriverLoom-Setup.exe';state='uploaded';size=1200000;digest='sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';browser_download_url='https://github.com/SJB-gif/DriverLoom/releases/download/v0.2.0/DriverLoom-Setup.exe'})}
$script:fixtureFailure=$false
function Read-WebSource([string]$url,[int]$limit){
    Assert-AppUpdate 'https://api.github.com/repos/SJB-gif/DriverLoom/releases/latest' $url 'app updates use the fixed DriverLoom release API'
    if($script:fixtureFailure){throw 'Fixture network failure.'}
    return $script:releaseFixture|ConvertTo-Json -Depth 5
}
$info=Get-AppUpdateInfo '0.1.14'
Assert-AppUpdate $true $info.UpdateAvailable 'new stable release is announced'
Assert-AppUpdate '0.2.0' $info.LatestVersion 'published version is displayed without the tag prefix'
Assert-AppUpdate $false (Get-AppUpdateInfo '0.2.0').UpdateAvailable 'equal versions do not repeat an update prompt'
Assert-AppUpdate $false (Get-AppUpdateInfo '0.2.0.0').UpdateAvailable 'three/four part versions normalise'
Assert-AppUpdate $false (Get-AppUpdateInfo '0.3.0').UpdateAvailable 'development/test builds never offer a downgrade'
$script:releaseFixture.tag_name='v0.2.0.0';$script:releaseFixture.html_url='https://github.com/SJB-gif/DriverLoom/releases/tag/v0.2.0.0'
Assert-AppUpdate $false (Get-AppUpdateInfo '0.2.0').UpdateAvailable 'a trailing zero in the release does not create an update loop'
$script:releaseFixture.tag_name='v0.2.0';$script:releaseFixture.html_url='https://github.com/SJB-gif/DriverLoom/releases/tag/v0.2.0'
foreach($case in 'draft','prerelease','foreign-release','foreign-installer','missing-installer','duplicate-installer','incomplete-installer','missing-digest','invalid-version','network'){
    $copy=$script:releaseFixture|ConvertTo-Json -Depth 5
    switch($case){
        'draft'{$script:releaseFixture.draft=$true}
        'prerelease'{$script:releaseFixture.prerelease=$true}
        'foreign-release'{$script:releaseFixture.html_url='https://github.com/example/other/releases/tag/v0.2.0'}
        'foreign-installer'{$script:releaseFixture.assets[0].browser_download_url='https://example.com/DriverLoom-Setup.exe'}
        'missing-installer'{$script:releaseFixture.assets=@()}
        'duplicate-installer'{$script:releaseFixture.assets+=@($script:releaseFixture.assets[0])}
        'incomplete-installer'{$script:releaseFixture.assets[0].state='new'}
        'missing-digest'{$script:releaseFixture.assets[0].digest=''}
        'invalid-version'{$script:releaseFixture.tag_name='v0.2.0-rc1'}
        'network'{$script:fixtureFailure=$true}
    }
    $rejected=$false
    try{$null=Get-AppUpdateInfo '0.1.14'}catch{$rejected=$true}
    Assert-AppUpdate $true $rejected "$case cannot create an update/download offer"
    $script:releaseFixture=$copy|ConvertFrom-Json;$script:fixtureFailure=$false
}
Write-Output 'App release checks passed: stable-only versions, no downgrade, fixed project links, completed installer, malformed metadata and network failure.'
