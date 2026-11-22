$ErrorActionPreference='Stop'
$output=Join-Path $PSScriptRoot 'dist\host\DriverLoom.exe'
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output))
$compiler=[Microsoft.CSharp.CSharpCodeProvider]::new()
$options=[CodeDom.Compiler.CompilerParameters]::new()
$options.GenerateExecutable=$true;$options.GenerateInMemory=$false;$options.OutputAssembly=$output
$options.CompilerOptions='/target:winexe /platform:x64 /optimize+ /win32icon:"'+(Join-Path $PSScriptRoot 'assets\DriverLoom-loops.ico')+'" /win32manifest:"'+(Join-Path $PSScriptRoot 'Host.manifest')+'"'
foreach($assembly in @('System.dll','System.Core.dll','System.Windows.Forms.dll',([System.Management.Automation.PowerShell].Assembly.Location))){[void]$options.ReferencedAssemblies.Add($assembly)}
try{
    $result=$compiler.CompileAssemblyFromFile($options,(Join-Path $PSScriptRoot 'Host.cs'))
    if($result.Errors.HasErrors){throw (($result.Errors|ForEach-Object ToString)-join "`r`n")}
}finally{$compiler.Dispose()}
Write-Output "Built native x64 DriverLoom host: $output"
