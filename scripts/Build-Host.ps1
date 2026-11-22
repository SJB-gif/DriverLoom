$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'src'
$ErrorActionPreference='Stop'
$output=Join-Path $repoRoot 'dist\host\DriverLoom.exe'
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output))
$compiler=[Microsoft.CSharp.CSharpCodeProvider]::new()
$options=[CodeDom.Compiler.CompilerParameters]::new()
$options.GenerateExecutable=$true;$options.GenerateInMemory=$false;$options.OutputAssembly=$output
$options.CompilerOptions='/target:winexe /platform:x64 /optimize+ /win32icon:"'+(Join-Path $srcRoot 'assets\DriverLoom-loops.ico')+'" /win32manifest:"'+(Join-Path $srcRoot 'Host.manifest')+'"'
foreach($assembly in @('System.dll','System.Core.dll','System.Windows.Forms.dll',([System.Management.Automation.PowerShell].Assembly.Location))){[void]$options.ReferencedAssemblies.Add($assembly)}
try{
    $result=$compiler.CompileAssemblyFromFile($options,(Join-Path $srcRoot 'Host.cs'))
    if($result.Errors.HasErrors){throw (($result.Errors|ForEach-Object ToString)-join "`r`n")}
}finally{$compiler.Dispose()}
Write-Output "Built native x64 DriverLoom host: $output"
