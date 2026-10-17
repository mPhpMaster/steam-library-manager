function Show-About {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = 'About Steam Library Manager'
    $dialog.ClientSize = New-Object Drawing.Size(510, 365)
    $dialog.StartPosition = 'CenterParent'; $dialog.FormBorderStyle = 'None'
    $dialog.BackColor = $script:Theme.Background; $dialog.ForeColor = $script:Theme.Text
    Add-TitleBar $dialog 'About' | Out-Null
    [void](New-Label 'Steam Library Manager' 24 55 450 42 18 $true $dialog)
    $version = New-Label "Version $script:AppVersion" 24 104 440 25 10 $false $dialog
    $version.ForeColor = $script:Theme.ActiveText
    [void](New-Label 'Copyright © 2026 mPhpMaster' 24 145 450 26 10 $false $dialog)
    $repositoryUrl = 'https://github.com/mPhpMaster/steam-library-manager'
    $releasesUrl = "$repositoryUrl/releases"
    $repository = New-Object Windows.Forms.LinkLabel
    $repository.Text = 'GitHub repository'; $repository.SetBounds(24, 196, 450, 26)
    $repository.LinkColor = $script:Theme.ActiveText
    $repository.ActiveLinkColor = $script:Theme.Text
    $repository.Add_LinkClicked({ Start-Process -FilePath $repositoryUrl }.GetNewClosure())
    $dialog.Controls.Add($repository)
    $releases = New-Object Windows.Forms.LinkLabel
    $releases.Text = 'Releases and downloads'; $releases.SetBounds(24, 231, 450, 26)
    $releases.LinkColor = $script:Theme.ActiveText
    $releases.ActiveLinkColor = $script:Theme.Text
    $releases.Add_LinkClicked({ Start-Process -FilePath $releasesUrl }.GetNewClosure())
    $dialog.Controls.Add($releases)
    [void](New-Button 'Add to Start Menu' 24 300 200 $dialog 'normal' {
        $shortcutPath = Add-StartMenuShortcut
        [Windows.Forms.MessageBox]::Show($dialog, "Shortcut added to Start Menu > All apps.`n$shortcutPath", 'Steam Library Manager', 'OK', 'Information') | Out-Null
    }.GetNewClosure())
    [void](New-Button 'Open App Folder' 234 300 140 $dialog 'normal' { Open-AppFolder })
    [void](New-Button 'Close' 386 300 100 $dialog 'normal' { $dialog.Close() })
    try { [void]$dialog.ShowDialog($script:Form) } finally { $dialog.Dispose() }
}
