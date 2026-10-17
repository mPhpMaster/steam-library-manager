function Select-InstalledGame($entries, $managedIds) {
    $picker = New-Object Windows.Forms.Form
    $picker.Text = 'Add Game'
    $picker.ClientSize = New-Object Drawing.Size(680, 540)
    $picker.StartPosition = 'CenterParent'
    $picker.FormBorderStyle = 'None'
    $picker.BackColor = $script:Theme.Background
    $picker.ForeColor = $script:Theme.Text
    $picker.Font = New-Object Drawing.Font('Segoe UI', 10)
    Add-TitleBar $picker 'Add Game' | Out-Null
    [void](New-Label 'Add a Steam game' 22 55 500 42 18 $true $picker)
    $drives = @($entries | ForEach-Object { Get-LibraryDrive $_.Library } | Sort-Object -Unique)
    $subtitle = New-Label "Pick an installed game. Libraries scanned: $(($drives | ForEach-Object { "$_`:" }) -join ', ')" 22 99 630 24 9 $false $picker
    $subtitle.ForeColor = $script:Theme.Secondary
    $search = New-Object Windows.Forms.TextBox
    $search.SetBounds(22, 135, 636, 36)
    $search.BackColor = $script:Theme.Log; $search.ForeColor = $script:Theme.Text
    $search.BorderStyle = 'FixedSingle'; $search.Font = New-Object Drawing.Font('Segoe UI', 11)
    $picker.Controls.Add($search)
    $count = New-Label '' 535 144 110 20 8.5 $false $picker
    $count.TextAlign = 'MiddleRight'; $count.BackColor = $script:Theme.Log
    $count.ForeColor = $script:Theme.Muted
    $filter = New-Object Windows.Forms.ComboBox
    $filter.SetBounds(22, 184, 636, 30)
    $filter.DropDownStyle = 'DropDownList'; $filter.DisplayMember = 'Text'
    $filter.BackColor = $script:Theme.Sidebar; $filter.ForeColor = $script:Theme.Text
    [void]$filter.Items.Add([pscustomobject]@{ Text = 'All libraries'; Path = '' })
    foreach ($library in @(Get-SteamLibraries)) {
        [void]$filter.Items.Add([pscustomobject]@{ Text = "$(Get-LibraryDrive $library):  $library"; Path = $library })
    }
    $picker.Controls.Add($filter)
    $list = New-Object Windows.Forms.ListView
    $list.SetBounds(22, 225, 636, 219)
    $list.View = 'Details'; $list.FullRowSelect = $true; $list.MultiSelect = $false
    $list.HideSelection = $false
    $list.BackColor = $script:Theme.Sidebar; $list.ForeColor = $script:Theme.Text
    $list.BorderStyle = 'FixedSingle'; $list.Font = New-Object Drawing.Font('Segoe UI', 10)
    [void]$list.Columns.Add('NAME', 345)
    [void]$list.Columns.Add('APP ID', 150)
    [void]$list.Columns.Add('DRIVE', 137)
    $list.OwnerDraw = $true
    $list.Add_DrawColumnHeader({
        param($sender, $event)
        $brush = New-Object Drawing.SolidBrush($script:Theme.Log)
        try { $event.Graphics.FillRectangle($brush, $event.Bounds) } finally { $brush.Dispose() }
        $rectangle = New-Object Drawing.Rectangle(($event.Bounds.X + 10), $event.Bounds.Y, ($event.Bounds.Width - 12), $event.Bounds.Height)
        [Windows.Forms.TextRenderer]::DrawText($event.Graphics, $event.Header.Text, $list.Font, $rectangle, $script:Theme.Muted, [Windows.Forms.TextFormatFlags]::VerticalCenter)
    })
    $list.Add_DrawItem({ param($sender, $event) })
    $list.Add_DrawSubItem({
        param($sender, $event)
        $background = if ($event.Item.Selected) { [Drawing.Color]::FromArgb(38, 65, 105) } else { $script:Theme.Sidebar }
        $brush = New-Object Drawing.SolidBrush($background)
        try { $event.Graphics.FillRectangle($brush, $event.Bounds) } finally { $brush.Dispose() }
        $rectangle = New-Object Drawing.Rectangle(($event.Bounds.X + 10), $event.Bounds.Y, ($event.Bounds.Width - 12), $event.Bounds.Height)
        $color = if ($event.Item.Tag.Disabled) { $script:Theme.Muted } else { $script:Theme.Text }
        [Windows.Forms.TextRenderer]::DrawText($event.Graphics, $event.SubItem.Text, $list.Font, $rectangle, $color, ([Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::EndEllipsis))
    })
    $picker.Controls.Add($list)
    $selected = New-Label 'Select a game to see its install folder.' 22 459 420 48 8.5 $false $picker
    $selected.ForeColor = $script:Theme.Secondary
    $cancel = New-Button 'Cancel' 448 488 98 $picker 'normal' { $picker.Close() }
    $choose = New-Button 'Add Game' 554 488 104 $picker 'play' {
        if ($list.SelectedItems.Count -and -not $list.SelectedItems[0].Tag.Disabled) {
            $sortState.Selected = $list.SelectedItems[0].Tag.Manifest
            $picker.DialogResult = 'OK'; $picker.Close()
        }
    }
    $choose.Enabled = $false
    $sortState = @{ Column = 0; Descending = $false; Selected = $null }
    $headers = @('NAME', 'APP ID', 'DRIVE')
    $duplicateIds = @( $entries | Group-Object AppId | Where-Object Count -gt 1 | ForEach-Object Name )
    $populate = {
        $selectedPath = if ($list.SelectedItems.Count) { [string]$list.SelectedItems[0].Tag.Manifest.Path } else { '' }
        $list.BeginUpdate()
        try {
            $list.Items.Clear()
            for ($i = 0; $i -lt $headers.Count; $i++) {
                $list.Columns[$i].Text = $headers[$i] + $(if ($i -eq $sortState.Column) { if ($sortState.Descending) { ' ▼' } else { ' ▲' } } else { '' })
            }
            $library = if ($filter.SelectedItem) { [string]$filter.SelectedItem.Path } else { '' }
            $results = @(Get-SortedGameChoices $entries $search.Text $sortState.Column $sortState.Descending $library)
            foreach ($entry in $results) {
                $item = New-Object Windows.Forms.ListViewItem($entry.Name)
                [void]$item.SubItems.Add($entry.AppId)
                [void]$item.SubItems.Add("$(Get-LibraryDrive $entry.Library):")
                $reason = if (@($managedIds) -contains $entry.AppId) { 'Already added to Steam Library Manager.' }
                    elseif ($duplicateIds -contains $entry.AppId) { 'Multiple manifests found for this App ID.' }
                    elseif (-not $entry.Exists) { 'Installed folder is missing.' } else { '' }
                $item.Tag = [pscustomobject]@{ Manifest = $entry; Disabled = [bool]$reason; Reason = $reason }
                [void]$list.Items.Add($item)
                if ($selectedPath -and $entry.Path -eq $selectedPath) { $item.Selected = $true }
            }
            $count.Text = "$($results.Count) of $($entries.Count)"
            $choose.Enabled = $list.SelectedItems.Count -gt 0 -and -not $list.SelectedItems[0].Tag.Disabled
            if (-not $choose.Enabled) { $selected.Text = 'Select a game to see its install folder.' }
        } finally { $list.EndUpdate() }
    }.GetNewClosure()
    $search.Add_TextChanged($populate)
    $filter.Add_SelectedIndexChanged($populate)
    $list.Add_ColumnClick({
        param($sender, $event)
        if ($sortState.Column -eq $event.Column) { $sortState.Descending = -not $sortState.Descending }
        else { $sortState.Column = $event.Column; $sortState.Descending = $false }
        & $populate
    }.GetNewClosure())
    $list.Add_SelectedIndexChanged({
        $choose.Enabled = $list.SelectedItems.Count -gt 0 -and -not $list.SelectedItems[0].Tag.Disabled
        if ($list.SelectedItems.Count) {
            $item = $list.SelectedItems[0].Tag
            $entry = $item.Manifest
            $selected.Text = if ($item.Disabled) { "$($entry.Name) · $($item.Reason)" }
                else { "$($entry.Name) · $(Join-Path (Join-Path $entry.Library 'steamapps\common') $entry.InstallDir)" }
        }
    }.GetNewClosure())
    $list.Add_DoubleClick({
        if ($list.SelectedItems.Count -and -not $list.SelectedItems[0].Tag.Disabled) {
            $sortState.Selected = $list.SelectedItems[0].Tag.Manifest; $picker.DialogResult = 'OK'; $picker.Close()
        }
    }.GetNewClosure())
    $filter.SelectedIndex = 0
    & $populate
    $picker.Add_Shown({ $search.Focus() | Out-Null }.GetNewClosure())
    $choice = $null
    if ($picker.ShowDialog($script:Form) -eq 'OK') { $choice = $sortState.Selected }
    $picker.Dispose()
    return $choice
}
