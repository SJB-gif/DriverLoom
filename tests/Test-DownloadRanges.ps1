$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'src'
$ErrorActionPreference='Stop'
. (Join-Path $srcRoot 'AppDownloads.ps1')
function Assert-Range($expected,$actual,[string]$message){if($expected -cne $actual){throw "$message expected '$expected', got '$actual'."}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('driverloom-ranges-'+[guid]::NewGuid().ToString('N'))
$script:bytes=[Text.Encoding]::ASCII.GetBytes('Fixture bytes split into bounded ranges.')
$sha=[Security.Cryptography.SHA256]::Create()
try{$expected=[BitConverter]::ToString($sha.ComputeHash($script:bytes)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
$script:mode='good';$script:requests=0;$script:folder=''
function Open-AppDownloadResponse([uri]$uri,[string]$referrer,[long]$start=-1,[long]$end=-1,[string]$etag=''){
    $script:requests++
    Assert-Range 'https://drivers.amd.com/drivers/fixture.exe' $uri.AbsoluteUri 'every segment uses the same allowed URL'
    Assert-Range $true ($start -ge 0 -and $end -ge $start -and ($end-$start+1) -le 4) 'requests stay within the selected segment size'
    if($start -gt 0){Assert-Range '"fixture-v1"' $etag 'later requests bind to the original strong ETag'}
    $last=[Math]::Min($end,$script:bytes.Length-1);$tag='"fixture-v1"';$first=$start;$length=$script:bytes.Length;$status=206
    $body=[byte[]]@($script:bytes[$start..$last])
    switch($script:mode){
        'etag-change'{if($start -gt 0){$tag='"fixture-v2"'}}
        'range-gap'{if($start -gt 0){$first++}}
        'length-change'{if($start -gt 0){$length++}}
        'missing-etag'{$tag=''}
        'weak-etag'{$tag='W/"fixture-v1"'}
        'truncated'{if($start -eq 0){$body=[byte[]]@($body[0..1])}}
        'range-ignored'{if($start -gt 0){$status=200}}
        'cancel-between'{if($start -gt 0){[IO.File]::WriteAllText((Join-Path $script:folder 'cancel'),'cancel')}}
        'whole-file'{$status=200;$body=$script:bytes}
    }
    $response=[pscustomobject]@{StatusCode=$status;ContentLength=$last-$start+1;Headers=@{'Content-Range'="bytes $first-$last/$length";ETag=$tag};Body=$body}
    if($script:mode -eq 'whole-file'){$response.ContentLength=$body.Length}
    if($script:mode -eq 'wrong-content-length'){$response.ContentLength++}
    $response|Add-Member ScriptMethod GetResponseStream {return [IO.MemoryStream]::new([byte[]]$this.Body)}
    $response|Add-Member ScriptMethod Dispose {}
    return $response
}
try{
    [void][IO.Directory]::CreateDirectory($root)
    foreach($mode in 'good','whole-file','etag-change','range-gap','length-change','missing-etag','weak-etag','truncated','range-ignored','wrong-content-length','cancel-between'){
        $script:mode=$mode;$script:requests=0;$script:folder=Join-Path $root $mode;[void][IO.Directory]::CreateDirectory($script:folder)
        $path='';$failure=$false
        try{
            $path=Save-VerifiedDownload 'https://drivers.amd.com/drivers/fixture.exe' $script:folder 'Fixture.exe' 1024 $script:bytes.Length 'https://www.amd.com/' {param($uri)$uri.AbsoluteUri -ceq 'https://drivers.amd.com/drivers/fixture.exe'} {
                param($path)
                Assert-Range $expected (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() 'only the complete original byte sequence reaches verification'
            } -UseRanges -RangeBytes 4
        }catch{$failure=$true;if($mode -in 'good','whole-file'){throw}}
        if($mode -in 'good','whole-file'){
            Assert-Range $false $failure 'valid downloads are accepted'
            Assert-Range $true ([IO.File]::Exists($path)) 'completed range download is promoted only after verification'
            Assert-Range $true ((Get-Content -LiteralPath $path -Stream Zone.Identifier -Raw) -match 'ZoneId=3') 'assembled downloads keep the Internet marker'
            if($mode -eq 'good'){Assert-Range $true ($script:requests -gt 1) 'a full multi-segment transfer completes'}
        }else{
            Assert-Range $true $failure "$mode blocks completion"
            Assert-Range 0 @(Get-ChildItem -LiteralPath $script:folder -File|Where-Object Extension -in '.part','.exe').Count "$mode cleans incomplete files"
        }
    }
    Write-Output 'Segmented download checks passed: exact byte assembly, strong validators, contiguous ranges, stable size, truncation, cancelled segments, full-file fallback and cleanup. No executable was run.'
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing cleanup outside TEMP.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
