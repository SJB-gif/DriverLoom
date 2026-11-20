function Get-SetupExitName([string]$root) {
    $target=[IO.Path]::Combine([IO.Path]::GetFullPath($root).TrimEnd('\'),'DriverLoom.exe').ToUpperInvariant()
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$suffix=[BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($target))).Replace('-','').Substring(0,32)}finally{$hash.Dispose()}
    return 'Local\DriverLoom.ExitForSetup.'+$suffix
}

function Initialize-LifecyclePreferences($preferences) {
    $defaults=@{CheckFrequency='On opening';KeepRunningInTray=$false;StartWithWindows=$false;CheckAppUpdates=$true;GroupBy='Application'}
    foreach($name in $defaults.Keys){
        if(!$preferences.PSObject.Properties[$name]){$preferences|Add-Member NoteProperty $name $defaults[$name]}
    }
    if($preferences.CheckFrequency -notin 'Manual','On opening','Daily','Weekly'){$preferences.CheckFrequency='On opening'}
    foreach($name in 'KeepRunningInTray','StartWithWindows'){
        if($preferences.$name -isnot [bool]){$preferences.$name=$false}
    }
    if($preferences.CheckAppUpdates -isnot [bool]){$preferences.CheckAppUpdates=$true}
    if($preferences.GroupBy -notin 'Application','Hardware type'){$preferences.GroupBy='Application'}
}

function Test-AutomaticCheckDue([string]$frequency, [DateTimeOffset]$now, $lastAttempt, $lastSuccess, [bool]$onOpening=$false) {
    if($frequency -eq 'Manual'){return $false}
    if($frequency -eq 'On opening'){return $onOpening}
    if($frequency -notin 'Daily','Weekly'){return $false}
    $latest=$null
    foreach($value in @($lastAttempt,$lastSuccess)){
        $parsed=[DateTimeOffset]::MinValue
        if($value -and [DateTimeOffset]::TryParse([string]$value,[ref]$parsed) -and $parsed -le $now){
            if($null -eq $latest -or $parsed -gt $latest){$latest=$parsed}
        }
    }
    if($null -eq $latest){return $true}
    $days=if($frequency -eq 'Weekly'){7}else{1}
    return ($now-$latest).TotalDays -ge $days
}

function Get-StartupCommand([string]$launcher,[bool]$background) {
    if(!$launcher -or $launcher -match '["\r\n]' -or ![IO.Path]::IsPathRooted($launcher) -or [IO.Path]::GetExtension($launcher) -ne '.exe' -or !(Test-Path -LiteralPath $launcher -PathType Leaf)){
        throw 'Install DriverLoom before enabling Start with Windows.'
    }
    $command='"'+$launcher+'"'
    if($background){$command+=' -Background'}
    if($command.Length -gt 260){throw 'The installation path is too long for Windows startup registration.'}
    return $command
}

function Set-StartupRegistration([bool]$enabled,[string]$launcher,[bool]$background,[string]$subKey='Software\Microsoft\Windows\CurrentVersion\Run') {
    if($enabled){
        $command=Get-StartupCommand $launcher $background
        $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($subKey)
        try{$key.SetValue('DriverLoom',$command,[Microsoft.Win32.RegistryValueKind]::String)}finally{$key.Dispose()}
    }else{
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKey,$true)
        if($key){try{$key.DeleteValue('DriverLoom',$false)}finally{$key.Dispose()}}
    }
}

function Save-LauncherPreferences([string]$path,$previous,$next,[string]$launcher,[string]$subKey='Software\Microsoft\Windows\CurrentVersion\Run') {
    $changeStartup=$previous.StartWithWindows -ne $next.StartWithWindows -or ($next.StartWithWindows -and $previous.KeepRunningInTray -ne $next.KeepRunningInTray)
    $oldCommand=$null
    if($changeStartup){
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKey)
        if($key){try{$oldCommand=$key.GetValue('DriverLoom',$null)}finally{$key.Dispose()}}
        Set-StartupRegistration $next.StartWithWindows $launcher $next.KeepRunningInTray $subKey
    }
    try{Save-Json $path $next}catch{
        if($changeStartup){
            if($null -ne $oldCommand){
                $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($subKey)
                try{$key.SetValue('DriverLoom',$oldCommand,[Microsoft.Win32.RegistryValueKind]::String)}finally{$key.Dispose()}
            }else{Set-StartupRegistration $false '' $false $subKey}
        }
        throw
    }
}
