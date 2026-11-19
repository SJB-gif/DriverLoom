$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$assets=Join-Path $PSScriptRoot 'assets'
[void][IO.Directory]::CreateDirectory($assets)
$frames=[System.Collections.Generic.List[object]]::new()
$source=[Drawing.Image]::FromFile((Join-Path $assets 'DriverLoom-icon-source.png'))
foreach($size in 16,20,24,32,40,48,64,128,256) {
    $bitmap=[Drawing.Bitmap]::new($size,$size)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    $stream=[IO.MemoryStream]::new()
    try {
        $graphics.SmoothingMode='AntiAlias'
        $graphics.InterpolationMode='HighQualityBicubic'
        $graphics.DrawImage($source,[Drawing.Rectangle]::new(0,0,$size,$size))
        $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
        $frames.Add([pscustomobject]@{Size=$size;Data=$stream.ToArray()})
        if($size -eq 256){[IO.File]::WriteAllBytes((Join-Path $assets 'DriverLoom.png'),$stream.ToArray())}
    } finally {$stream.Dispose();$graphics.Dispose();$bitmap.Dispose()}
}
$file=[IO.File]::Create((Join-Path $assets 'DriverLoom.ico'))
$writer=[IO.BinaryWriter]::new($file)
try {
    $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$frames.Count)
    $offset=6+16*$frames.Count
    foreach($frame in $frames){$dimension=if($frame.Size -eq 256){0}else{$frame.Size};$writer.Write([byte]$dimension);$writer.Write([byte]$dimension);$writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$frame.Data.Length);$writer.Write([uint32]$offset);$offset+=$frame.Data.Length}
    foreach($frame in $frames){$writer.Write([byte[]]$frame.Data)}
} finally {$writer.Dispose()}
$source.Dispose()
Write-Output 'Converted supplied DriverLoom loop artwork to nine Windows icon sizes.'
