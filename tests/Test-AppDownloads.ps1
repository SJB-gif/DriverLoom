$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'src'
$ErrorActionPreference='Stop'
. (Join-Path $srcRoot 'AppDownloads.ps1')
function Assert-Download($expected,$actual,[string]$message){if($expected -cne $actual){throw "$message expected '$expected', got '$actual'."}}
function Assert-DownloadRejected([scriptblock]$action,[string]$message){$rejected=$false;try{& $action}catch{$rejected=$true};Assert-Download $true $rejected $message}
$root=Join-Path ([IO.Path]::GetTempPath()) ('driverloom-downloads-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$script:body=[Text.Encoding]::UTF8.GetBytes('Fixture installer bytes, never executed.')
$sha=[Security.Cryptography.SHA256]::Create()
try{$digest=[BitConverter]::ToString($sha.ComputeHash($script:body)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
$info=[pscustomobject]@{Tag='v0.2.0';LatestVersion='0.2.0';ReleaseUrl='https://github.com/SJB-gif/DriverLoom/releases/tag/v0.2.0';InstallerUrl='https://github.com/SJB-gif/DriverLoom/releases/download/v0.2.0/DriverLoom-Setup.exe';InstallerHash=$digest;InstallerSize=$script:body.Length}
$script:case='good';$script:requestCount=0;$script:fixtureFolder='';$script:launchCount=0
function Get-AppInstallerVersion([string]$path){if($script:case -eq 'wrong-version'){return '0.1.0.0'};return '0.2.0.0'}
function Start-Process {param($FilePath,[switch]$PassThru);$script:launchCount++;return [pscustomobject]@{Path=$FilePath}}
function Open-AppDownloadResponse([uri]$uri){
    $script:requestCount++
    $bytes=$script:body
    if($script:case -eq 'oversize'){$bytes=[byte[]]@($bytes+1)}
    if($script:case -eq 'truncated'){$bytes=[byte[]]@($bytes[0..3])}
    if($script:case -eq 'cancel-during'){[IO.File]::WriteAllText((Join-Path $script:fixtureFolder 'cancel'),'cancel')}
    if($script:case -eq 'network'){throw 'Fixture connection failure.'}
    $code=200;$headers=@{}
    if($script:requestCount -eq 1 -and $script:case -in 'good','redirect','unsafe-redirect'){$code=302;$headers['Location']=if($script:case -eq 'unsafe-redirect'){'https://example.com/fake.exe'}else{'https://release-assets.githubusercontent.com/github-production-release-asset/fixture'}}
    if($script:case -eq 'redirect-loop'){$code=302;$headers['Location']='https://github.com/loop'}
    if($script:case -eq 'server-error'){$code=503}
    $response=[pscustomobject]@{StatusCode=$code;Headers=$headers;ContentLength=if($script:case -eq 'wrong-length'){100}else{-1};Body=$bytes;Disposed=$false}
    $response|Add-Member ScriptMethod GetResponseStream {return [IO.MemoryStream]::new([byte[]]$this.Body)}
    $response|Add-Member ScriptMethod Dispose {$this.Disposed=$true}
    return $response
}
try{
    foreach($uri in 'http://github.com/file','https://github.com:444/file','https://github.com.evil.example/file','https://user@github.com/file','https://example.com/file','https://github.com/file#fragment'){
        Assert-Download $false (Test-AppDownloadUri ([uri]$uri)) 'foreign or ambiguous download URI is rejected'
    }
    foreach($case in 'good','redirect','unsafe-redirect','redirect-loop','network','wrong-length','truncated','oversize','wrong-version','cancel-before','cancel-during','server-error','bad-hash'){
        $script:case=$case;$script:requestCount=0
        $script:fixtureFolder=Join-Path $root $case;[void][IO.Directory]::CreateDirectory($script:fixtureFolder)
        if($case -eq 'cancel-before'){[IO.File]::WriteAllText((Join-Path $script:fixtureFolder 'cancel'),'cancel')}
        $attempt=$info|Select-Object *;if($case -eq 'bad-hash'){$attempt.InstallerHash='0'*64}
        if($case -in 'good','redirect'){
            $path=Receive-AppInstaller $attempt '0.1.16' $script:fixtureFolder
            Assert-Download $true ([IO.File]::Exists($path)) 'complete verified download returns executable'
            Assert-Download $false ([IO.File]::Exists((Join-Path $script:fixtureFolder 'DriverLoom-Setup.part'))) 'successful download has no partial file'
            Assert-Download $true ((Get-Content -LiteralPath $path -Stream Zone.Identifier -Raw).Contains('ZoneId=3')) 'Windows Internet origin is preserved'
            $null=Start-AppInstaller $path $attempt '0.1.16'
            $prior=$script:launchCount
            [IO.File]::AppendAllText($path,'tampered')
            Assert-DownloadRejected {Start-AppInstaller $path $attempt '0.1.16'} 'installer is reverified immediately before launch'
            Assert-Download $prior $script:launchCount 'tampered installer never starts'
        }else{
            Assert-DownloadRejected {Receive-AppInstaller $attempt '0.1.16' $script:fixtureFolder} "$case blocks installation"
            Assert-Download 0 @(Get-ChildItem -LiteralPath $script:fixtureFolder -File|Where-Object Extension -in '.exe','.part').Count "$case cleans up executable/partial files"
            if($case -eq 'unsafe-redirect'){Assert-Download 1 $script:requestCount 'foreign redirect is never requested'}
            if($case -eq 'cancel-before'){Assert-Download 0 $script:requestCount 'cancelled download makes no network request'}
        }
    }
    foreach($case in 'downgrade','equal','foreign-url','missing-hash','too-large','invalid-tag'){
        $attempt=$info|Select-Object *;$current='0.1.16'
        switch($case){
            'downgrade'{$current='0.3.0'}
            'equal'{$current='0.2.0.0'}
            'foreign-url'{$attempt.InstallerUrl='https://example.com/DriverLoom-Setup.exe'}
            'missing-hash'{$attempt.InstallerHash=''}
            'too-large'{$attempt.InstallerSize=67108865}
            'invalid-tag'{$attempt.Tag='../../evil'}
        }
        Assert-DownloadRejected {Assert-AppDownloadInfo $attempt $current} "$case cannot start a download"
    }
    Assert-Download 2 $script:launchCount 'only verified fixtures reached the mocked launcher; no executable was run'
    Write-Output 'Managed app download checks passed: GitHub redirects, progress stream, cancellation, size/hash/version, partial cleanup, Internet marker, revalidation and no downgrade.'
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing cleanup outside TEMP.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
