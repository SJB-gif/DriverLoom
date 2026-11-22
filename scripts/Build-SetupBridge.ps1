$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'src'
$ErrorActionPreference='Stop'
$output=Join-Path $repoRoot 'dist\host\DriverLoom-SetupBridge.exe'
$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output))
$compiler=[Microsoft.CSharp.CSharpCodeProvider]::new()
$options=[CodeDom.Compiler.CompilerParameters]::new()
$options.GenerateExecutable=$true;$options.OutputAssembly=$output;$options.CompilerOptions='/target:winexe /platform:x64 /optimize+'
foreach($assembly in 'System.dll','System.Core.dll','System.Management.dll'){[void]$options.ReferencedAssemblies.Add($assembly)}
try{$result=$compiler.CompileAssemblyFromFile($options,(Join-Path $repoRoot 'installer\SetupBridge.cs'));if($result.Errors.HasErrors){throw (($result.Errors|ForEach-Object ToString)-join "`r`n")}}finally{$compiler.Dispose()}
Write-Output 'Built the setup helper for scoped, graceful DriverLoom shutdown.'
