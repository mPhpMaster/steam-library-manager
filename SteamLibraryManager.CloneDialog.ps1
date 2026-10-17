function Select-ClonePlan($game, $source) {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = 'Clone Version'
    $dialog.ClientSize = New-Object Drawing.Size(700, 510)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'None'
    $dialog.BackColor = $script:Theme.Background
    $dialog.ForeColor = $script:Theme.Text
    $dialog.Font = New-Object Drawing.Font('Segoe UI', 10)
    Add-TitleBar $dialog 'Clone Version' | Out-Null
    [void](New-Label "Clone $($source.Name)" 24 52 610 37 17 $true $dialog)
    [void](New-Label 'Choose the Steam library where the new folder will be created.' 24 92 635 24 9 $false $dialog)
    $libraryLabel = New-Label 'DESTINATION LIBRARY' 24 126 400 23 8 $false $dialog
    $libraryLabel.ForeColor = $script:Theme.Muted
    $libraries = New-Object Windows.Forms.ListView
    $libraries.SetBounds(24, 155, 652, 157)
    $libraries.View = 'Details'; $libraries.FullRowSelect = $true; $libraries.MultiSelect = $false
    $libraries.HideSelection = $false; $libraries.BorderStyle = 'FixedSingle'
    $libraries.BackColor = $script:Theme.Sidebar; $libraries.ForeColor = $script:Theme.Text
    [void]$libraries.Columns.Add('DRIVE', 90)
    [void]$libraries.Columns.Add('LIBRARY PATH', 415)
    [void]$libraries.Columns.Add('FREE', 140)
    $libraries.OwnerDraw = $true
    $libraries.Add_DrawColumnHeader({
        param($sender, $event)
        $brush = New-Object Drawing.SolidBrush($script:Theme.Log)
        try { $event.Graphics.FillRectangle($brush, $event.Bounds) } finally { $brush.Dispose() }
        $rectangle = New-Object Drawing.Rectangle(($event.Bounds.X + 10), $event.Bounds.Y, ($event.Bounds.Width - 12), $event.Bounds.Height)
        [Windows.Forms.TextRenderer]::DrawText($event.Graphics, $event.Header.Text, $libraries.Font, $rectangle, $script:Theme.Muted, [Windows.Forms.TextFormatFlags]::VerticalCenter)
    })
    $libraries.Add_DrawItem({ param($sender, $event) })
    $libraries.Add_DrawSubItem({
        param($sender, $event)
        $background = if ($event.Item.Selected) { [Drawing.Color]::FromArgb(38, 65, 105) } else { $script:Theme.Sidebar }
        $brush = New-Object Drawing.SolidBrush($background)
        try { $event.Graphics.FillRectangle($brush, $event.Bounds) } finally { $brush.Dispose() }
        $rectangle = New-Object Drawing.Rectangle(($event.Bounds.X + 10), $event.Bounds.Y, ($event.Bounds.Width - 12), $event.Bounds.Height)
        [Windows.Forms.TextRenderer]::DrawText($event.Graphics, $event.SubItem.Text, $libraries.Font, $rectangle, $script:Theme.Text, ([Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::EndEllipsis))
    })
    $dialog.Controls.Add($libraries)
    $sourceLibrary = (Assert-VersionPath $source.Path).Library
    foreach ($library in @(Get-SteamLibraries)) {
        $item = New-Object Windows.Forms.ListViewItem("$(Get-LibraryDrive $library):")
        [void]$item.SubItems.Add($library)
        try { $free = "$([Math]::Round((Get-FreeSpaceBytes $library) / 1GB, 1)) GB" }
        catch { $free = 'Unknown' }
        [void]$item.SubItems.Add($free)
        $item.Tag = $library
        [void]$libraries.Items.Add($item)
        if ($library -ieq $sourceLibrary) { $item.Selected = $true }
    }
    [void](New-Label 'VERSION / FOLDER NAME (OPTIONAL)' 24 331 620 21 8 $false $dialog)
    $nameInput = New-Object Windows.Forms.TextBox
    $nameInput.SetBounds(24, 356, 652, 30)
    $nameInput.BackColor = $script:Theme.Log; $nameInput.ForeColor = $script:Theme.Text
    $dialog.Controls.Add($nameInput)
    $hint = New-Label 'Leave blank for a safe, unique copy name. Existing folders are never overwritten.' 24 397 650 37 8.5 $false $dialog
    $hint.ForeColor = $script:Theme.Muted
    $state = @{ Plan = $null }
    $cancel = New-Button 'Cancel' 453 450 100 $dialog 'normal' { $dialog.Close() }
    $create = New-Button 'Continue' 563 450 113 $dialog 'play' {
        if (-not $libraries.SelectedItems.Count) { throw 'Select a destination Steam library.' }
        $state.Plan = [pscustomobject]@{ Library = $libraries.SelectedItems[0].Tag; Name = $nameInput.Text.Trim() }
        $dialog.DialogResult = 'OK'; $dialog.Close()
    }
    $create.Enabled = $libraries.SelectedItems.Count -gt 0
    $libraries.Add_SelectedIndexChanged({ $create.Enabled = $libraries.SelectedItems.Count -gt 0 }.GetNewClosure())
    $result = $null
    if ($dialog.ShowDialog($script:Form) -eq 'OK') { $result = $state.Plan }
    $dialog.Dispose()
    return $result
}
