$script:Theme = @{
    Background = [Drawing.Color]::FromArgb(0x1C, 0x1C, 0x1F)
    Sidebar = [Drawing.Color]::FromArgb(0x18, 0x18, 0x1B)
    Title = [Drawing.Color]::FromArgb(0x5E, 0x7A, 0x4E)
    Card = [Drawing.Color]::FromArgb(0x2A, 0x2A, 0x2E)
    CardActive = [Drawing.Color]::FromArgb(0x1F, 0x3A, 0x24)
    ActiveBar = [Drawing.Color]::FromArgb(0x4C, 0xC2, 0x4A)
    ActiveText = [Drawing.Color]::FromArgb(0x5B, 0xD1, 0x6A)
    Button = [Drawing.Color]::FromArgb(0x3A, 0x3A, 0x40)
    ButtonDisabled = [Drawing.Color]::FromArgb(0x2E, 0x2E, 0x33)
    Play = [Drawing.Color]::FromArgb(0x2F, 0x74, 0xD0)
    Log = [Drawing.Color]::FromArgb(0x12, 0x12, 0x14)
    Selection = [Drawing.Color]::FromArgb(0x2C, 0x3A, 0x2A)
    Text = [Drawing.Color]::FromArgb(0xF2, 0xF2, 0xF2)
    Secondary = [Drawing.Color]::FromArgb(0xB4, 0xB4, 0xBA)
    Muted = [Drawing.Color]::FromArgb(0x7A, 0x7A, 0x82)
    Warning = [Drawing.Color]::FromArgb(0xE8, 0xA3, 0x3A)
    Danger = [Drawing.Color]::FromArgb(0xD9, 0x53, 0x4F)
    Divider = [Drawing.Color]::FromArgb(0x2F, 0x2F, 0x34)
}

Add-Type -Name NativeWindow -Namespace SteamLibraryManager -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ReleaseCapture();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr SendMessage(System.IntPtr window, int message, System.IntPtr wParam, System.IntPtr lParam);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr window, int command);
'@
if (-not $ShowConsole) {
    $console = [SteamLibraryManager.NativeWindow]::GetConsoleWindow()
    if ($console -ne [IntPtr]::Zero) { [SteamLibraryManager.NativeWindow]::ShowWindow($console, 0) | Out-Null }
}

function Set-RoundedRegion($control, [int]$radius) {
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $diameter = $radius * 2; $w = $control.Width; $h = $control.Height
    $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
    $path.AddArc($w-$diameter-1, 0, $diameter, $diameter, 270, 90)
    $path.AddArc($w-$diameter-1, $h-$diameter-1, $diameter, $diameter, 0, 90)
    $path.AddArc(0, $h-$diameter-1, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    $control.Region = New-Object Drawing.Region($path)
    $path.Dispose()
}

function New-Label([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [double]$size, [bool]$bold, $parent) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $text; $label.SetBounds($x, $y, $w, $h)
    $style = if ($bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $label.Font = New-Object Drawing.Font('Segoe UI', $size, $style)
    $label.ForeColor = if ($bold) { $script:Theme.Text } else { $script:Theme.Secondary }
    $label.BackColor = [Drawing.Color]::Transparent
    $parent.Controls.Add($label)
    return $label
}

function New-Button([string]$text, [int]$x, [int]$y, [int]$w, $parent, [string]$style, [scriptblock]$action) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $text; $button.SetBounds($x, $y, $w, 38)
    $button.FlatStyle = 'Flat'; $button.FlatAppearance.BorderSize = 0
    $button.BackColor = switch ($style) { 'play' { $script:Theme.Play } 'danger' { $script:Theme.Sidebar } default { $script:Theme.Button } }
    $button.ForeColor = if ($style -eq 'danger') { $script:Theme.Danger } else { $script:Theme.Text }
    $button.Font = New-Object Drawing.Font('Segoe UI', $(if ($style -eq 'play') { 11 } else { 10 }), $(if ($style -eq 'play') { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }))
    $button.Cursor = 'Hand'
    Set-RoundedRegion $button 5
    $button.Add_Click({
        try { & $action } catch {
            Write-Activity $_.Exception.Message 'err'
            [Windows.Forms.MessageBox]::Show($script:Form, $_.Exception.Message, 'Steam Library Manager', 'OK', 'Error') | Out-Null
        }
    }.GetNewClosure())
    $parent.Controls.Add($button)
    return $button
}

function Add-TitleBar($window, [string]$title) {
    $isMainWindow = $window -eq $script:Form
    if (-not $isMainWindow) {
        $window.MaximizeBox = $false
        $window.MinimizeBox = $false
    }
    $bar = New-Object Windows.Forms.Panel
    $bar.Dock = 'Top'; $bar.Height = 32; $bar.BackColor = $script:Theme.Title
    $window.Controls.Add($bar)
    $icon = New-Object Windows.Forms.Panel
    $icon.SetBounds(12, 8, 16, 16); $icon.BackColor = $script:Theme.ActiveText
    Set-RoundedRegion $icon 4; $bar.Controls.Add($icon)
    $caption = New-Label $title 38 5 ($window.Width - 150) 24 10 $false $bar
    $caption.ForeColor = $script:Theme.Text
    $caption.Anchor = 'Top,Left,Right'
    $drag = {
        param($sender, $event)
        if ($event.Button -eq [Windows.Forms.MouseButtons]::Left) {
            [SteamLibraryManager.NativeWindow]::ReleaseCapture() | Out-Null
            [SteamLibraryManager.NativeWindow]::SendMessage($window.Handle, 0xA1, [IntPtr]2, [IntPtr]0) | Out-Null
        }
    }.GetNewClosure()
    $bar.Add_MouseDown($drag); $caption.Add_MouseDown($drag)
    if ($isMainWindow) {
        $minimize = New-Object Windows.Forms.Button
        $minimize.Text = '−'; $minimize.SetBounds(($window.Width - 116), 0, 38, 31)
        $minimize.FlatStyle = 'Flat'; $minimize.FlatAppearance.BorderSize = 0
        $minimize.BackColor = $script:Theme.Title; $minimize.ForeColor = $script:Theme.Text
        $minimize.Anchor = 'Top,Right'
        $minimize.Add_Click({ $window.WindowState = 'Minimized' }.GetNewClosure())
        $bar.Controls.Add($minimize)
        $maximize = New-Object Windows.Forms.Button
        $maximize.Text = '□'; $maximize.SetBounds(($window.Width - 78), 0, 38, 31)
        $maximize.FlatStyle = 'Flat'; $maximize.FlatAppearance.BorderSize = 0
        $maximize.BackColor = $script:Theme.Title; $maximize.ForeColor = $script:Theme.Text
        $maximize.Anchor = 'Top,Right'
        $maximize.Add_Click({ $window.WindowState = if ($window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' } }.GetNewClosure())
        $bar.Controls.Add($maximize)
    }
    $close = New-Object Windows.Forms.Button
    $close.Text = '×'; $close.SetBounds(($window.Width - 40), 0, 38, 31)
    $close.FlatStyle = 'Flat'; $close.FlatAppearance.BorderSize = 0
    $close.BackColor = $script:Theme.Title; $close.ForeColor = $script:Theme.Text
    $close.Anchor = 'Top,Right'
    $close.Add_Click({ $window.Close() }.GetNewClosure())
    $bar.Controls.Add($close)
    return $bar
}

function Write-Activity([string]$message, [string]$kind = '') {
    $mark = switch ($kind) { 'ok' { '[ok] ' } 'err' { '[!!] ' } default { '     ' } }
    $script:Activity.AppendText(('{0}  {1}{2}' -f (Get-Date -Format 'HH:mm:ss'), $mark, $message) + [Environment]::NewLine)
    $script:Activity.SelectionStart = $script:Activity.TextLength
    $script:Activity.ScrollToCaret()
}

function Ask-Name([string]$prompt, [string]$default = '') {
    $answer = [Microsoft.VisualBasic.Interaction]::InputBox($prompt, 'Steam Library Manager', $default).Trim()
    if ($answer.Length -gt 100) { throw 'Name exceeds 100 characters.' }
    return $answer
}
function Confirm([string]$prompt) {
    return ([Windows.Forms.MessageBox]::Show($script:Form, $prompt, 'Steam Library Manager', 'YesNo', 'Question') -eq 'Yes')
}
function Pick-Folder([string]$prompt) {
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description = $prompt
    if ($dialog.ShowDialog($script:Form) -eq 'OK') { return $dialog.SelectedPath }
    return $null
}
