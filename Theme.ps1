if (!('DriverLoom.UI.Palette' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'Theme.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing
}

function Set-AppTheme([string]$preference = 'Dark', $root = $null) {
    if ($preference -notin 'Dark','Light','System') { $preference = 'Dark' }
    [DriverLoom.UI.Palette]::Select($preference)
    if ($root) { [DriverLoom.UI.Theme]::Apply($root) }
}

function Get-DisplayStatus([string]$status) {
    switch ($status) {
        'Newer at source' { 'UPDATE AVAILABLE' }
        'Current at source' { 'UP TO DATE' }
        'Installed version is higher' { 'INSTALLED IS NEWER' }
        'Unsupported' { 'UNSUPPORTED' }
        'Managed by software' { 'VENDOR APP' }
        'Manual check required' { 'MANUAL CHECK' }
        default { 'PACKAGE DETAILS' }
    }
}

function Add-DialogHeading($dialog, [string]$title, [string]$description) {
    $heading = [Windows.Forms.Label]::new()
    $heading.Text=$title; $heading.Font=[Drawing.Font]::new('Segoe UI',20,[Drawing.FontStyle]::Bold)
    $heading.SetBounds(24,18,850,38)
    $descriptionLabel=[Windows.Forms.Label]::new()
    $descriptionLabel.Text=$description; $descriptionLabel.Tag='Muted'; $descriptionLabel.SetBounds(26,62,850,30)
    $dialog.Controls.AddRange(@($heading,$descriptionLabel))
}

function Add-SettingsCard($parent,[string]$title,[int]$left,[int]$top,[int]$width,[int]$height) {
    $card=[Windows.Forms.Panel]::new(); $card.Tag='Card'; $card.SetBounds($left,$top,$width,$height)
    $card.Add_Paint({param($sender,$eventArgs) $pen=[Drawing.Pen]::new([DriverLoom.UI.Palette]::Border);try{$eventArgs.Graphics.DrawRectangle($pen,0,0,$sender.ClientSize.Width-1,$sender.ClientSize.Height-1)}finally{$pen.Dispose()}})
    $label=[Windows.Forms.Label]::new(); $label.Text=$title; $label.Tag='Muted'; $label.Font=[Drawing.Font]::new('Consolas',9,[Drawing.FontStyle]::Bold)
    $label.SetBounds(18,16,($width-36),22); $card.Controls.Add($label); $parent.Controls.Add($card)
    return ,$card
}

function Save-FormPreview($dialog,[string]$suffix) {
    $dialog.Refresh()
    $image=[Drawing.Bitmap]::new($dialog.Width,$dialog.Height)
    try { $dialog.DrawToBitmap($image,[Drawing.Rectangle]::new(0,0,$dialog.Width,$dialog.Height)); $image.Save(($env:HARDWARE_LAUNCHER_TEST_PREVIEW+'-'+$suffix+'.png'),[Drawing.Imaging.ImageFormat]::Png) }
    finally { $image.Dispose() }
}
