$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'AsusPackages.ps1')
Initialize-AsusTrust
$root=Join-Path ([IO.Path]::GetTempPath()) ('driverloom-native-trust-'+[guid]::NewGuid().ToString('N'))
try{
    [void][IO.Directory]::CreateDirectory($root)
    $verified=$false
    foreach($relative in 'System32\drivers\kbdclass.sys','System32\drivers\disk.sys','System32\kernel32.dll','System32\ntdll.dll'){
        $file=Join-Path $env:WINDIR $relative;if(!(Test-Path -LiteralPath $file)){continue}
        $cat=[DriverLoom.Security.AsusTrust]::FindInstalledCatalog($file)
        if(!$cat){continue}
        if(![DriverLoom.Security.AsusTrust]::VerifyCatalogMember($file,$cat)){throw 'A Windows system file did not match its installed trusted catalog.'}
        $copy=Join-Path $root ([IO.Path]::GetFileName($file));Copy-Item -LiteralPath $file -Destination $copy
        $stream=[IO.File]::Open($copy,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite)
        try{$stream.Position=512;$old=$stream.ReadByte();$stream.Position=512;$stream.WriteByte([byte]($old -bxor 1))}finally{$stream.Dispose()}
        if([DriverLoom.Security.AsusTrust]::VerifyCatalogMember($copy,$cat)){throw 'The native catalog check accepted altered file contents.'}
        $verified=$true;break
    }
    if(!$verified){throw 'No standard Windows catalog/member fixture was available for the native trust check.'}
    $inf=Join-Path $root 'fixture.inf'
    $text=@'
[Version]
Signature="$Windows NT$"
Class=Net
ClassGuid={4d36e972-e325-11ce-bfc1-08002be10318}
Provider=%Vendor%
DriverVer=01/01/2026,2.3.4.5
CatalogFile=fixture.cat
[Manufacturer]
%Vendor%=Models,NTamd64
[Models.NTamd64]
%Device%=Install,PCI\VEN_8086&DEV_15F3&REV_03
[Install]
[Strings]
Vendor="Fixture"
Device="Fixture device"
'@
    [IO.File]::WriteAllText($inf,$text)
    $facts=[DriverLoom.Security.AsusTrust]::ReadInf($inf)
    if($facts.Version -ne '2.3.4.5' -or $facts.Catalog -ne 'fixture.cat' -or $facts.DeviceClass -ne 'Net' -or 'PCI\VEN_8086&DEV_15F3&REV_03' -notin $facts.Ids){throw 'Native INF metadata/model parsing failed.'}
    [IO.File]::WriteAllText($inf,$text.Replace('NTamd64','NTx86'))
    if([DriverLoom.Security.AsusTrust]::ReadInf($inf).Ids.Length -ne 0){throw 'An x86-only INF was considered an x64 driver.'}
    Write-Output 'Native ASUS trust checks passed: Windows signed catalog member, changed-file rejection and native x64 INF parsing. No catalog or driver was installed.'
}finally{
    $resolved=[IO.Path]::GetFullPath($root);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing cleanup outside TEMP.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
