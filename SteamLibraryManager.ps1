param([switch]$ShowConsole, [switch]$Relaunched)
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA' -and -not $Relaunched) {
    $args = @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Relaunched')
    if ($ShowConsole) { $args += '-ShowConsole' }
    Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $args
    exit
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
. (Join-Path $PSScriptRoot 'SteamLibraryManager.Core.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.Clone.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.View.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.Picker.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.Images.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.CloneDialog.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.CloneProgress.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.CloneStatus.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.CardInteraction.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.Version.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.StartMenu.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.AppFolder.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.About.ps1')
[Windows.Forms.Application]::EnableVisualStyles()

$script:Form = New-Object Windows.Forms.Form
$script:Form.Text = 'Steam Library Manager'
$script:Form.ClientSize = New-Object Drawing.Size(1120, 720)
$script:Form.MinimumSize = New-Object Drawing.Size(900, 600)
$script:Form.StartPosition = 'CenterScreen'
$script:Form.FormBorderStyle = 'None'
$script:Form.BackColor = $script:Theme.Background
$script:Form.ForeColor = $script:Theme.Text
$script:Form.Font = New-Object Drawing.Font('Segoe UI', 10)
$script:Form.KeyPreview = $true
$script:GameSortDescending = $false
$script:ActivationInProgress = $false
$side = New-Object Windows.Forms.Panel
$side.SetBounds(0, 32, 250, 688); $side.BackColor = $script:Theme.Sidebar
$side.Anchor = 'Top,Bottom,Left'
$script:Form.Controls.Add($side)
$main = New-Object Windows.Forms.Panel
$main.SetBounds(250, 32, 870, 688); $main.BackColor = $script:Theme.Background
$main.Anchor = 'Top,Bottom,Left,Right'
$script:Form.Controls.Add($main)
Add-TitleBar $script:Form 'Steam Library Manager' | Out-Null

$gameHeading = New-Label 'GAMES · 0' 16 45 145 24 8 $false $side
$gameHeading.ForeColor = $script:Theme.Muted
$sortGames = New-Label 'A-Z' 175 45 60 24 8.5 $false $side
$sortGames.TextAlign = 'MiddleRight'; $sortGames.Cursor = 'Hand'
$sortGames.ForeColor = $script:Theme.Secondary
$gameRows = New-Object Windows.Forms.FlowLayoutPanel
$gameRows.SetBounds(12, 84, 226, 488)
$gameRows.AutoScroll = $true; $gameRows.WrapContents = $false
$gameRows.FlowDirection = 'TopDown'; $gameRows.BackColor = $script:Theme.Sidebar
$side.Controls.Add($gameRows)

$gameTitle = New-Label 'Steam Library Manager' 24 30 560 43 18 $true $main
$gameSubtitle = New-Label 'Choose which build Steam launches' 25 74 550 24 10 $false $main
$steamStatus = New-Label '' 615 32 228 24 9 $true $main
$steamStatus.TextAlign = 'MiddleRight'
$gameInfo = New-Label '' 535 67 308 24 8.5 $false $main
$gameInfo.TextAlign = 'MiddleRight'
$versionHeading = New-Label 'VERSIONS · 0' 24 120 255 26 8 $false $main
$versionHeading.ForeColor = $script:Theme.Muted
$cards = New-Object Windows.Forms.FlowLayoutPanel
$cards.SetBounds(24, 171, 822, 235)
$cards.AutoScroll = $true; $cards.WrapContents = $false
$cards.FlowDirection = 'TopDown'; $cards.BackColor = $script:Theme.Background
$main.Controls.Add($cards)
$activityHeading = New-Label 'ACTIVITY' 24 469 280 24 8 $false $main
$activityHeading.ForeColor = $script:Theme.Muted
$script:Activity = New-Object Windows.Forms.TextBox
$script:Activity.SetBounds(24, 497, 822, 155)
$script:Activity.Multiline = $true; $script:Activity.ReadOnly = $true
$script:Activity.ScrollBars = 'Vertical'; $script:Activity.BorderStyle = 'None'
$script:Activity.BackColor = $script:Theme.Log; $script:Activity.ForeColor = $script:Theme.Secondary
$script:Activity.Font = New-Object Drawing.Font('Consolas', 8.5)
$main.Controls.Add($script:Activity)
$shortcuts = New-Label 'Double-click a build to activate    1–9 pick build    Enter activate / play    Ctrl+D clone    F2 rename    Del remove    F5 refresh' 24 661 822 22 8 $false $main
$shortcuts.ForeColor = $script:Theme.Muted

function Selected-Game {
    if (-not $script:SelectedGameId) { throw 'Select a game first.' }
    $game = $script:Data.Games | Where-Object { $_.AppId -eq $script:SelectedGameId } | Select-Object -First 1
    if (-not $game) { throw 'Select a game first.' }
    return $game
}
function Selected-Version {
    if (-not $script:SelectedVersionId) { throw 'Select a version first.' }
    $version = (Selected-Game).Versions | Where-Object { $_.Id -eq $script:SelectedVersionId } | Select-Object -First 1
    if (-not $version) { throw 'Select a version first.' }
    return $version
}
function Update-Buttons {
    $hasGame = [bool]$script:SelectedGameId
    $hasVersion = $hasGame -and [bool]$script:SelectedVersionId
    $issue = if ($hasGame) { Get-ManagedGameIdentityIssue (Selected-Game) } else { '' }
    foreach ($button in @($renameGame, $removeGame)) { $button.Enabled = $hasGame }
    $play.Enabled = $hasGame -and -not $issue
    $clone.Enabled = $hasVersion -and -not $issue
    foreach ($button in @($renameVersion, $removeVersion)) { $button.Enabled = $hasVersion }
    $running = Test-SteamRunning
    $closeSteam.Enabled = $running; $startSteam.Enabled = -not $running
    $steamStatus.Text = if ($running) { 'Steam is running' } else { 'Steam is closed' }
    $steamStatus.ForeColor = if ($running) { $script:Theme.Warning } else { $script:Theme.Muted }
}
function Select-Version([string]$id) {
    $script:SelectedVersionId = $id
    foreach ($card in $cards.Controls) {
        $item = $card.Tag
        $item.ActivateButton.Visible = ($item.Id -eq $id -and -not $item.IsActive -and $item.Exists -and -not (Get-ManagedGameIdentityIssue (Selected-Game)))
        $card.Invalidate()
    }
    Update-Buttons
}
function Activate-Version([string]$id) {
    if ($script:ActivationInProgress) { return }
    $script:ActivationInProgress = $true
    try {
        $game = Selected-Game
        Assert-ManagedGameIdentity $game
        $version = $game.Versions | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if (-not $version) { throw 'Version was not found.' }
        if (Test-SteamRunning) {
            if (-not (Confirm 'Steam is running. Close it before switching?')) { return }
            Write-Activity 'Shutting Steam down...'; Stop-SteamSafely
        }
        Set-ActiveGameVersion $game $version
        Write-Activity "$($version.Name) is active." 'ok'; Refresh-Versions
        if (Confirm "Launch $($game.Name) now?") { Start-Process "steam://rungameid/$($game.AppId)" }
    } finally {
        $script:ActivationInProgress = $false
    }
}
function Refresh-Versions {
    $cards.Controls.Clear()
    if (-not $script:SelectedGameId) { Update-Buttons; return }
    $game = Selected-Game
    $identityIssue = Get-ManagedGameIdentityIssue $game
    try { $manifest = Find-GameManifest $game.AppId } catch { $manifest = $null }
    $activePath = if ($manifest) { Join-Path (Join-Path $manifest.Library 'steamapps\common') $manifest.InstallDir } else { '' }
    $gameTitle.Text = $game.Name.ToUpperInvariant()
    $gameSubtitle.Text = if ($identityIssue) { 'Identity needs review — Rename game after checking Steam App ID' } else { 'Choose which build Steam launches' }
    $gameSubtitle.ForeColor = if ($identityIssue) { $script:Theme.Danger } else { $script:Theme.Secondary }
    $gameInfo.Text = if ($manifest) { "appid $($game.AppId) · installdir: $($manifest.InstallDir) · $(Get-LibraryDrive $manifest.Library):" } else { "appid $($game.AppId) · manifest unavailable" }
    $versionHeading.Text = "VERSIONS · $(@($game.Versions).Count)"
    $index = 0; $selectionFound = $false
    foreach ($version in @($game.Versions)) {
        $index++
        $exists = Test-Path -LiteralPath $version.Path -PathType Container
        $active = $version.Path -ieq $activePath
        $card = New-Object Windows.Forms.Panel
        $card.Size = New-Object Drawing.Size(798, 100)
        $card.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 12)
        $card.BackColor = if ($active) { $script:Theme.CardActive } else { $script:Theme.Card }
        $card.Cursor = 'Hand'; Set-RoundedRegion $card 10
        $bar = New-Object Windows.Forms.Panel
        $bar.SetBounds(0, 0, 4, 100)
        $bar.BackColor = if ($active) { $script:Theme.ActiveBar } else { $script:Theme.Card }
        $card.Controls.Add($bar)
        $number = New-Label "$index" 23 18 34 28 8.5 $true $card
        $number.ForeColor = if ($active) { $script:Theme.ActiveText } else { $script:Theme.Muted }
        $nameLabel = New-Label $version.Name 58 13 505 33 15 $true $card
        $folder = Split-Path $version.Path -Leaf
        $pathLabel = New-Label "$(Get-LibraryDrive $version.Path):  common\$folder" 58 48 555 20 8.5 $false $card
        $pathLabel.Font = New-Object Drawing.Font('Consolas', 8.5)
        $tip = New-Object Windows.Forms.ToolTip; $tip.SetToolTip($pathLabel, $version.Path)
        $detail = New-Label $(if ($exists) { 'Installed' } else { 'Folder not found' }) 58 71 405 19 8.5 $false $card
        if (-not $exists) { $detail.ForeColor = $script:Theme.Danger }
        $status = $null
        if ($active) {
            $status = New-Label '● ACTIVE' 677 36 103 28 9 $true $card
            $status.ForeColor = $script:Theme.ActiveText; $status.TextAlign = 'MiddleRight'
        }
        $id = $version.Id
        $activateAction = { Activate-Version $id }.GetNewClosure()
        $activateCard = New-Button '✓ Activate' 676 33 104 $card 'normal' $activateAction
        $activateCard.BackColor = $script:Theme.CardActive
        $activateCard.ForeColor = $script:Theme.Text
        $activateCard.Visible = $false
        $card.Tag = [pscustomobject]@{ Id = $id; IsActive = $active; Exists = $exists; ActivateButton = $activateCard; Status = $status; PathLabel = $pathLabel; NameLabel = $nameLabel }
        $card.Add_Paint({
            param($sender, $event)
            if ($sender.Tag.Id -eq $script:SelectedVersionId -and -not $sender.Tag.IsActive) {
                $pen = New-Object Drawing.Pen($script:Theme.Play, 2)
                try { $event.Graphics.DrawRectangle($pen, 1, 1, ($sender.Width - 3), ($sender.Height - 3)) } finally { $pen.Dispose() }
            }
        })
        Register-CardClick $card $id
        $cards.Controls.Add($card)
        if ($id -eq $script:SelectedVersionId) { $selectionFound = $true }
    }
    if (-not $selectionFound) { $script:SelectedVersionId = $null }
    if ($selectionFound) { Select-Version $script:SelectedVersionId } else { Update-Buttons }
}
function Select-Game([string]$id) {
    if ($script:SelectedGameId -ne $id) { $script:SelectedVersionId = $null }
    $script:SelectedGameId = $id
    foreach ($row in $gameRows.Controls) {
        $chosen = $row.Tag -eq $id
        $row.BackColor = if ($chosen) { $script:Theme.Selection } else { $script:Theme.Sidebar }
        $row.Controls[0].BackColor = if ($chosen) { $script:Theme.ActiveBar } else { $row.BackColor }
    }
    Refresh-Versions
}
function Register-GameClick($control, [string]$id) {
    $control.Add_Click({ Select-Game $id }.GetNewClosure())
    foreach ($child in $control.Controls) { Register-GameClick $child $id }
}
function Refresh-Games([string]$preferred = '') {
    $script:Data = Read-GameData
    $gameRows.Controls.Clear()
    $ordered = @(Get-SortedManagedGames $script:Data.Games $script:GameSortDescending)
    $gameHeading.Text = "GAMES · $($ordered.Count)"
    $sortGames.Text = if ($script:GameSortDescending) { 'Z-A' } else { 'A-Z' }
    foreach ($game in $ordered) {
        $row = New-Object Windows.Forms.Panel
        $row.Size = New-Object Drawing.Size(222, 48)
        $row.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 4)
        $row.Tag = $game.AppId; $row.Cursor = 'Hand'
        $row.BackColor = $script:Theme.Sidebar; Set-RoundedRegion $row 7
        $bar = New-Object Windows.Forms.Panel
        $bar.SetBounds(0, 0, 4, 48); $row.Controls.Add($bar)
        $icon = New-Object Windows.Forms.Panel
        $icon.SetBounds(12, 8, 32, 32)
        $palette = @($script:Theme.Title, $script:Theme.Play, $script:Theme.ActiveBar, $script:Theme.Warning)
        $icon.BackColor = $palette[([int64]$game.AppId % $palette.Count)]
        Set-RoundedRegion $icon 5; $row.Controls.Add($icon)
        $art = Get-GameImageBitmap $game.AppId
        if ($art) {
            $picture = New-Object Windows.Forms.PictureBox
            $picture.Dock = 'Fill'; $picture.Image = $art
            $picture.SizeMode = 'Zoom'; $icon.Controls.Add($picture)
        } else {
            $initial = New-Label $game.Name.Substring(0, 1).ToUpperInvariant() 0 4 32 24 11 $true $icon
            $initial.TextAlign = 'MiddleCenter'
        }
        $issue = Get-ManagedGameIdentityIssue $game
        $nameText = if ($issue) { "! $($game.Name)" } else { $game.Name }
        $nameLabel = New-Label $nameText 53 6 135 23 10 $false $row
        if ($issue) { $nameLabel.ForeColor = $script:Theme.Danger; $nameLabel.Tag = $issue }
        $drive = try { Get-LibraryDrive (Find-GameManifest $game.AppId).Library } catch { '-' }
        $meta = New-Label "$($game.AppId) · $drive`:" 53 26 135 17 8.5 $false $row
        $meta.ForeColor = $script:Theme.Muted
        $count = New-Label "$(@($game.Versions).Count)" 195 15 20 20 8.5 $false $row
        $count.TextAlign = 'MiddleCenter'; $count.ForeColor = $script:Theme.Muted
        Register-GameClick $row $game.AppId
        $gameRows.Controls.Add($row)
    }
    $target = if ($preferred -and @($ordered | Where-Object { $_.AppId -eq $preferred }).Count) { $preferred }
        elseif ($script:SelectedGameId -and @($ordered | Where-Object { $_.AppId -eq $script:SelectedGameId }).Count) { $script:SelectedGameId }
        elseif ($ordered.Count) { $ordered[0].AppId } else { '' }
    if ($target) { Select-Game $target }
    else { $script:SelectedGameId = $null; $script:SelectedVersionId = $null; $cards.Controls.Clear(); $gameTitle.Text = 'STEAM LIBRARY MANAGER'; $gameInfo.Text = ''; $versionHeading.Text = 'VERSIONS · 0'; Update-Buttons }
}

$about = New-Button 'About' 16 542 218 $side 'normal' { Show-About }
$addGame = New-Button '+ Add Game...' 16 588 218 $side 'normal' {
    $entries = @(Find-InstalledGames)
    if (-not $entries.Count) { throw 'No installed games were found in registered Steam libraries.' }
    $entry = Select-InstalledGame $entries @($script:Data.Games.AppId)
    if (-not $entry) { return }
    $name = Ask-Name 'Display name for this game:' $entry.Name
    if (-not $name) { return }
    Add-ManagedGame $script:Data $entry $name | Out-Null
    Write-Activity "Added $name (appid $($entry.AppId))." 'ok'; Refresh-Games $entry.AppId
}
$renameGame = New-Button 'Rename' 16 636 106 $side 'normal' {
    $game = Selected-Game; $name = Ask-Name 'New game name:' $game.Name
    if ($name) {
        if ($name -match '^\d+$' -and $name -ne $game.AppId) { throw 'A numeric game label must match its Steam App ID.' }
        $previous = $game.Name; $game.Name = $name
        try { Save-GameData $script:Data } catch { $game.Name = $previous; throw }
        Write-Activity "Renamed game to $name." 'ok'; Refresh-Games $game.AppId
    }
}
$removeGame = New-Button 'Remove Game' 128 636 106 $side 'danger' {
    $game = Selected-Game
    if (Confirm "Remove $($game.Name) from this tool?`nGame files remain untouched.") {
        $script:Data.Games = @($script:Data.Games | Where-Object { $_.AppId -ne $game.AppId })
        Save-GameData $script:Data; Write-Activity "Removed game entry $($game.Name)." 'ok'
        $script:SelectedGameId = $null; Refresh-Games
    }
}
$clone = New-Button 'Clone' 443 116 120 $main 'normal' {
    $game = Selected-Game; $source = Selected-Version
    Assert-ManagedGameIdentity $game
    $choice = Select-ClonePlan $game $source
    if (-not $choice) { return }
    $result = Start-CloneJob $game $source $choice
    if ($result.Phase -eq 'Done') {
        Add-ManagedVersion $script:Data $game $result.Name $result.Destination | Out-Null
        Write-Activity "Cloned $($source.Name) to $($result.Destination)." 'ok'; Refresh-Versions
    } elseif ($result.Phase -eq 'Cancelled') {
        Write-Activity 'Clone cancelled; partial files removed.' 'warn'
    } else { throw $result.Message }
}
$renameVersion = New-Button 'Rename' 571 116 118 $main 'normal' {
    $version = Selected-Version; $name = Ask-Name 'New version name:' $version.Name
    if ($name) { $version.Name = $name; Save-GameData $script:Data; Write-Activity "Renamed version to $name." 'ok'; Refresh-Versions }
}
$removeVersion = New-Button 'Delete Entry' 697 116 149 $main 'danger' {
    $game = Selected-Game; $version = Selected-Version
    if (Confirm "Remove $($version.Name) from this tool?`nIts files remain untouched.") {
        $game.Versions = @($game.Versions | Where-Object { $_.Id -ne $version.Id })
        Save-GameData $script:Data; Write-Activity "Removed version entry $($version.Name)." 'ok'
        $script:SelectedVersionId = $null; Refresh-Versions
    }
}
$refresh = New-Button 'Refresh' 24 419 140 $main 'normal' { Write-Activity 'Rescanning...'; Refresh-Games $script:SelectedGameId }
$closeSteam = New-Button 'Close Steam' 174 419 140 $main 'normal' {
    Write-Activity 'Shutting Steam down...'; Stop-SteamSafely
    Write-Activity 'Steam closed.' 'ok'; Update-Buttons
}
$startSteam = New-Button 'Start Steam' 324 419 140 $main 'normal' {
    $exe = Join-Path (Get-SteamRoot) 'steam.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'steam.exe was not found.' }
    Start-Process -FilePath $exe
    Write-Activity 'Steam started.' 'ok'; Update-Buttons
}
$play = New-Button '▶ PLAY' 474 419 372 $main 'play' {
    $game = Selected-Game; Assert-ManagedGameIdentity $game
    $manifest = Find-GameManifest $game.AppId
    Write-Activity "Launching $($game.Name)..." 'ok'
    Start-Process "steam://rungameid/$($manifest.AppId)"
}
$sortGames.Add_Click({
    $script:GameSortDescending = -not $script:GameSortDescending
    Refresh-Games $script:SelectedGameId
})
function Resize-Layout {
    if ($script:Form.WindowState -eq 'Minimized') { return }
    $width = $script:Form.ClientSize.Width; $height = $script:Form.ClientSize.Height
    $contentWidth = $width - 250; $contentHeight = $height - 32
    $side.Height = $contentHeight
    $main.SetBounds(250, 32, $contentWidth, $contentHeight)
    $about.Top = $contentHeight - 146
    $addGame.Top = $contentHeight - 100
    $renameGame.Top = $contentHeight - 52; $removeGame.Top = $contentHeight - 52
    $gameRows.Height = $about.Top - 100
    $steamStatus.Left = $contentWidth - 255
    $gameInfo.Left = $contentWidth - 335
    $gameTitle.Width = $contentWidth - 300
    $small = $contentWidth -lt 730
    $toolbarWidths = if ($small) { @(120, 115, 135) } else { @(155, 145, 160) }
    $toolbar = @($clone, $renameVersion, $removeVersion)
    $toolbarWidth = ($toolbarWidths | Measure-Object -Sum).Sum + 16
    $position = $contentWidth - 24 - $toolbarWidth
    $versionHeading.Width = [Math]::Max(135, ($position - 34))
    for ($i = 0; $i -lt $toolbar.Count; $i++) {
        $toolbar[$i].SetBounds($position, 116, $toolbarWidths[$i], 38)
        Set-RoundedRegion $toolbar[$i] 5
        $position += $toolbarWidths[$i] + 8
    }
    $cardHeight = [Math]::Max(130, [Math]::Min(350, ($contentHeight - 453)))
    $cards.SetBounds(24, 171, ($contentWidth - 48), $cardHeight)
    foreach ($card in $cards.Controls) {
        $card.Width = $cards.ClientSize.Width - 24
        Set-RoundedRegion $card 10
        $card.Tag.ActivateButton.Left = $card.Width - 122
        if ($card.Tag.Status) { $card.Tag.Status.Left = $card.Width - 121 }
        $card.Tag.PathLabel.Width = $card.Width - 225
        $card.Tag.NameLabel.Width = $card.Width - 225
    }
    $available = $contentWidth - 48
    $secondaryWidth = [int](($available - 30) / 5.2)
    $playWidth = $available - (3 * $secondaryWidth) - 30
    $controlsY = 171 + $cardHeight + 13
    $buttons = @($refresh, $closeSteam, $startSteam, $play)
    $position = 24
    for ($i = 0; $i -lt $buttons.Count; $i++) {
        $buttonWidth = if ($i -eq 3) { $playWidth } else { $secondaryWidth }
        $buttons[$i].SetBounds($position, $controlsY, $buttonWidth, 38)
        Set-RoundedRegion $buttons[$i] 5
        $position += $buttonWidth + 10
    }
    $activityHeading.Top = $controlsY + 50
    $logTop = $activityHeading.Top + 28
    $script:Activity.SetBounds(24, $logTop, ($contentWidth - 48), ($contentHeight - $logTop - 36))
    $shortcuts.SetBounds(24, ($contentHeight - 27), ($contentWidth - 48), 22)
}
$script:Form.Add_Resize({ Resize-Layout })
$script:ResizeState = @{ Active = $false; Start = $null; Size = $null }
$grip = New-Label '◢' ($script:Form.ClientSize.Width - 18) ($script:Form.ClientSize.Height - 20) 16 16 8 $false $script:Form
$grip.Anchor = 'Bottom,Right'; $grip.Cursor = 'SizeNWSE'; $grip.ForeColor = $script:Theme.Muted
$grip.Add_MouseDown({
    param($sender, $event)
    if ($event.Button -eq [Windows.Forms.MouseButtons]::Left) {
        $script:ResizeState.Active = $true
        $script:ResizeState.Start = [Windows.Forms.Control]::MousePosition
        $script:ResizeState.Size = $script:Form.Size
    }
})
$grip.Add_MouseMove({
    if (-not $script:ResizeState.Active) { return }
    $point = [Windows.Forms.Control]::MousePosition
    $newWidth = [Math]::Max(900, $script:ResizeState.Size.Width + $point.X - $script:ResizeState.Start.X)
    $newHeight = [Math]::Max(600, $script:ResizeState.Size.Height + $point.Y - $script:ResizeState.Start.Y)
    $script:Form.Size = New-Object Drawing.Size($newWidth, $newHeight)
})
$grip.Add_MouseUp({ $script:ResizeState.Active = $false })
$script:Form.Add_KeyDown({
    param($sender, $event)
    if ($event.Control -and $event.KeyCode -eq 'D') { if ($clone.Enabled) { $clone.PerformClick() }; return }
    switch ($event.KeyCode) {
        'F5' { $refresh.PerformClick() }
        'Escape' { $script:Form.Close() }
        'F2' { if ($renameVersion.Enabled) { $renameVersion.PerformClick() } }
        'Delete' { if ($removeVersion.Enabled) { $removeVersion.PerformClick() } }
        'Return' {
            if ($script:SelectedVersionId) {
                $selected = $cards.Controls | Where-Object { $_.Tag.Id -eq $script:SelectedVersionId } | Select-Object -First 1
                if ($selected -and $selected.Tag.IsActive) { $play.PerformClick() }
                else { Activate-Version $script:SelectedVersionId }
            }
        }
        default {
            if ($event.KeyCode.ToString() -match '^D([1-9])$') {
                $index = [int]$Matches[1] - 1
                if ($index -lt $cards.Controls.Count) { Select-Version $cards.Controls[$index].Tag.Id }
            }
        }
    }
})
try { Refresh-Games; Resize-Layout; Write-Activity 'Ready.' 'ok' } catch { Write-Activity $_.Exception.Message 'err' }
[void]$script:Form.ShowDialog()
$script:Form.Dispose()
Dispose-GameImages
