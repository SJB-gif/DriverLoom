$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'src'
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationCore, WindowsBase
$root=Join-Path $srcRoot 'assets\manufacturers'
$manifest=Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw|ConvertFrom-Json
foreach($item in $manifest){
    if($item.Slug -notmatch '^[a-z0-9]+$'){throw 'Invalid manufacturer asset name.'}
    $file=Join-Path $root ($item.Slug+'.svg')
    if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.SHA256){throw 'Manufacturer source artwork checksum mismatch.'}
    $xml=[Xml.XmlDocument]::new();$xml.XmlResolver=$null;$xml.Load($file)
    if($xml.DocumentElement.GetAttribute('viewBox') -ne '0 0 24 24'){throw 'Unexpected manufacturer artwork dimensions.'}
    $path=$xml.DocumentElement.GetElementsByTagName('path')
    if($path.Count -ne 1){throw 'Expected one manufacturer artwork path.'}
    $geometry=[Windows.Media.Geometry]::Parse('F1 '+$path[0].GetAttribute('d'))
    foreach($theme in 'dark','light'){
        $color=if($theme -eq 'dark'){'#E5EAF2'}else{'#26313F'}
        $brush=[Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($color))
        $visual=[Windows.Media.DrawingVisual]::new();$drawing=$visual.RenderOpen()
        try{$drawing.PushTransform([Windows.Media.ScaleTransform]::new((64.0/24),(64.0/24)));$drawing.DrawGeometry($brush,$null,$geometry);$drawing.Pop()}finally{$drawing.Close()}
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(64,64,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($visual)
        $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream=[IO.File]::Create((Join-Path $root ($item.Slug+'-'+$theme+'.png')))
        try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }
}
Write-Output ('Rendered '+$manifest.Count+' bundled manufacturer logos for dark/light themes.')
