$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$assets=Join-Path $PSScriptRoot 'assets'
[void][IO.Directory]::CreateDirectory($assets)
$frames=[System.Collections.Generic.List[object]]::new()
foreach($size in 16,20,24,32,40,48,64,128,256) {
    $bitmap=[Drawing.Bitmap]::new($size,$size)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    $stream=[IO.MemoryStream]::new()
    try {
        $graphics.SmoothingMode='AntiAlias'
        $graphics.ScaleTransform(($size/64.0),($size/64.0))
        $shape=[Drawing.Drawing2D.GraphicsPath]::new()
        $brush=[Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#4F7CFF'))
        $pen=[Drawing.Pen]::new([Drawing.Color]::White,3.5)
        $pen.StartCap='Round';$pen.EndCap='Round';$pen.LineJoin='Round'
        try {
            $shape.AddArc(4,4,24,24,180,90);$shape.AddArc(36,4,24,24,270,90);$shape.AddArc(36,36,24,24,0,90);$shape.AddArc(4,36,24,24,90,90);$shape.CloseFigure()
            $graphics.FillPath($brush,$shape)
            $shape.Reset()
            $shape.AddArc(17,17,6,6,180,90);$shape.AddArc(41,17,6,6,270,90);$shape.AddArc(41,41,6,6,0,90);$shape.AddArc(17,41,6,6,90,90);$shape.CloseFigure()
            $graphics.DrawPath($pen,$shape)
            foreach($position in 23,32,41) {
                $graphics.DrawLine($pen,$position,11,$position,17);$graphics.DrawLine($pen,$position,47,$position,53)
                $graphics.DrawLine($pen,11,$position,17,$position);$graphics.DrawLine($pen,47,$position,53,$position)
            }
            $graphics.DrawLines($pen,[Drawing.PointF[]]@([Drawing.PointF]::new(24,32),[Drawing.PointF]::new(32,24),[Drawing.PointF]::new(40,32)))
            $graphics.DrawLine($pen,32,24,32,40)
        } finally {$shape.Dispose();$brush.Dispose();$pen.Dispose()}
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
Write-Output 'Built DriverLoom icon: nine sizes from 16 to 256 pixels, plus PNG and SVG source.'
