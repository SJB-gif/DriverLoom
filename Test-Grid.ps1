$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
. (Join-Path $PSScriptRoot 'Theme.ps1')
function Assert-Grid($expected,$actual,[string]$description){if($actual -cne $expected){throw "$description expected '$expected', got '$actual'."}}
function Get-DeviceOrder($grid){return (@($grid.Rows|ForEach-Object{$_.Cells['Device'].Value}) -join '|')}
function Click-GridHeader($grid,[string]$column){
    $mouse=[Windows.Forms.MouseEventArgs]::new([Windows.Forms.MouseButtons]::Left,1,0,0,0)
    $event=[Windows.Forms.DataGridViewCellMouseEventArgs]::new($grid.Columns[$column].Index,-1,0,0,$mouse)
    $method=$grid.GetType().GetMethod('OnColumnHeaderMouseClick',[Reflection.BindingFlags]'Instance,NonPublic')
    $null=$method.Invoke($grid,@($event))
}

$grid=[DriverLoom.UI.DeviceGrid]::new()
try{
    $grid.AllowUserToAddRows=$false;$grid.Decorated=$true
    foreach($name in 'Device','Installed','Available','Status','Source'){[void]$grid.Columns.Add($name,$name)}
    $fixtures=@(
        @('Zeta current','Current at source',''),
        @('Gamma utility','Managed by software','ASUS Armoury Crate'),
        @('Beta update','Newer at source',''),
        @('Delta headset','Managed by software','CORSAIR iCUE'),
        @('Echo installed newer','Installed version is higher',''),
        @('Alpha update','Newer at source',''),
        @('Foxtrot SSD','Managed by software','CORSAIR SSD Toolbox'),
        @('Aardvark failure','Source check failed: test failure',''),
        @('Omega unknown','Different version; verify vendor ordering','')
    )
    foreach($fixture in $fixtures){
        $index=$grid.Rows.Add(@($fixture[0],'1.0','2.0',(Get-DisplayStatus $fixture[1] $fixture[2]),'Vendor details'))
        $grid.Rows[$index].Tag=$fixture[0]
        if($fixture[2]){$grid.Rows[$index].Cells['Status'].Tag='UpdateMethod'}
    }
    $index=$grid.Rows.Add(@('Windows update','','','READY TO INSTALL','In update queue'));$grid.Rows[$index].Tag='Windows update'
    $grid.ConfigureHardwareSorting();$grid.ApplyHardwareSort()
    $alphabetical='Aardvark failure|Alpha update|Beta update|Delta headset|Echo installed newer|Foxtrot SSD|Gamma utility|Omega unknown|Windows update|Zeta current'
    Assert-Grid $alphabetical (Get-DeviceOrder $grid) 'default device A-Z order includes all update methods'
    Click-GridHeader $grid 'Device'
    Assert-Grid 'Zeta current' $grid.Rows[0].Cells['Device'].Value 'Device header toggles descending'
    Click-GridHeader $grid 'Device'
    Assert-Grid $alphabetical (Get-DeviceOrder $grid) 'Device header toggles ascending'
    Click-GridHeader $grid 'Status'
    $byStatus='Alpha update|Beta update|Windows update|Echo installed newer|Zeta current|Gamma utility|Delta headset|Foxtrot SSD|Aardvark failure|Omega unknown'
    Assert-Grid $byStatus (Get-DeviceOrder $grid) 'status order puts updates first, then current, then app A-Z, then unavailable'
    Click-GridHeader $grid 'Status'
    Assert-Grid $byStatus (Get-DeviceOrder $grid) 'repeated Status clicks retain updates first'
    foreach($column in 'Installed','Available','Source'){
        Assert-Grid 'NotSortable' ([string]$grid.Columns[$column].SortMode) "$column has no sorting interaction"
        Click-GridHeader $grid $column
        Assert-Grid $byStatus (Get-DeviceOrder $grid) "$column header leaves ordering unchanged"
        Assert-Grid 'None' ([string]$grid.Columns[$column].HeaderCell.SortGlyphDirection) "$column has no sorting arrow"
    }
    foreach($row in $grid.Rows){Assert-Grid $row.Tag $row.Cells['Device'].Value 'sorting retains the device action metadata'}
    $index=$grid.Rows.Add(@('A second update','1.0','2.0','UPDATE AVAILABLE','Review update'))
    $grid.ApplyHardwareSort()
    Assert-Grid 'A second update' $grid.Rows[0].Cells['Device'].Value 'refresh retains chosen status ordering'
    Assert-Grid 'UP TO DATE' (Get-DisplayStatus 'Installed version is higher') 'installed-newer display is simplified without changing comparison state'
    Assert-Grid 'CHECK UNAVAILABLE' (Get-DisplayStatus 'Vendor package found; compare the AMD Software row') 'incomparable package and driver versions are never green'
    $groupIndex=$grid.Rows.Add(@('Corsair / iCUE','','','iCUE','Open iCUE'))
    $group=[DriverLoom.UI.LauncherGroupInfo]::new();$group.Rank=0
    $group.Devices=[string[]]@('Headset','Virtual input');$group.Statuses=[string[]]@('UPDATE AVAILABLE','Check in iCUE');$group.Installed=[string[]]@('1.0','2.0');$group.Available=[string[]]@('1.1','')
    $groupRow=$grid.Rows[$groupIndex];$groupRow.HeaderCell.Tag=$group;$groupRow.Height=100
    $grid.ApplyHardwareSort()
    Assert-Grid $true ($groupRow.Index -lt ($grid.Rows|Where-Object{$_.Cells['Device'].Value -eq 'Echo installed newer'}).Index) 'group priority follows its available update'
    Assert-Grid 2 $groupRow.HeaderCell.Tag.Devices.Length 'sorting keeps compact children together'
    $grid.Columns.Remove('Source');$action=[DriverLoom.UI.DeviceActionColumn]::new();$action.Name='Source';[void]$grid.Columns.Add($action)
    $bounds=$groupRow.Cells['Source'].GetContentBounds($groupRow.Index)
    Assert-Grid 32 $bounds.Height 'group action exposes a real button hit area'
    Assert-Grid $true ($bounds.Bottom -le [DriverLoom.UI.LauncherGroupInfo]::HeaderHeight) 'only the group header button is clickable'
    $grid.Rows.Clear()
    foreach($fixture in @(@('Storage',1,$true,'Storage',''),@('Storage',1,$false,'SSD','UP TO DATE'),@('Graphics',0,$true,'Graphics',''),@('Graphics',0,$false,'Zeta GPU','UP TO DATE'),@('Graphics',0,$false,'Alpha GPU','UPDATE AVAILABLE'))){
        $i=$grid.Rows.Add(@($fixture[3],'1','2',$fixture[4],'Open'))
        $category=[DriverLoom.UI.HardwareCategoryInfo]::new();$category.Name=$fixture[0];$category.Rank=$fixture[1];$category.IsHeader=$fixture[2];$grid.Rows[$i].HeaderCell.Tag=$category
    }
    $grid.SortHardwareBy('Status')
    Assert-Grid 'Graphics|Alpha GPU|Zeta GPU|Storage|SSD' (Get-DeviceOrder $grid) 'status sorting puts categories with updates first and retains each header with its devices'
    Assert-Grid $true $grid.Rows[0].Cells['Source'].GetContentBounds(0).IsEmpty 'category headers have no action hit area'
    $grid.SortHardwareBy('Device');$grid.SortHardwareBy('Device')
    Assert-Grid 'Storage|SSD|Graphics|Zeta GPU|Alpha GPU' (Get-DeviceOrder $grid) 'descending category/device sorting never separates a heading from its members'
    Write-Output 'Hardware list checks passed: device A-Z/Z-A, fixed status groups, application order, disabled headers, refreshed ordering and comparison labels.'
}finally{$grid.Dispose()}
