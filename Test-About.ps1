$ErrorActionPreference = 'Stop'
$ShowConsole = $true
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'SteamLibraryManager.View.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.Version.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.About.ps1')
$script:Form = New-Object Windows.Forms.Form
$script:Form.CreateControl()
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 100
$seen = $false
$timer.Add_Tick({
    foreach ($form in [Windows.Forms.Application]::OpenForms) {
        if ($form.Text -ne 'About Steam Library Manager') { continue }
        $labels = @($form.Controls | Where-Object { $_ -is [Windows.Forms.Label] } | ForEach-Object Text)
        $links = @($form.Controls | Where-Object { $_ -is [Windows.Forms.LinkLabel] } | ForEach-Object Text)
        if ($form.MaximizeBox -or $form.MinimizeBox -or
            "Version $script:AppVersion" -notin $labels -or
            'Copyright © 2026 mPhpMaster' -notin $labels -or $links.Count -ne 2) {
            throw 'About dialog content or window controls are incorrect.'
        }
        $script:seen = $true
        $form.Close()
    }
})
try {
    $timer.Start()
    Show-About
    if (-not $script:seen) { throw 'About dialog was not shown.' }
    Write-Output 'About PASS: version, copyright, links, fixed dialog controls.'
} finally {
    $timer.Stop(); $timer.Dispose(); $script:Form.Dispose()
}
