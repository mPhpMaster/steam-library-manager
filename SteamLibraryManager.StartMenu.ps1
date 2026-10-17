function Add-StartMenuShortcut([string]$programsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)) {
    if ([string]::IsNullOrWhiteSpace($programsPath)) { throw 'The Start Menu folder is unavailable.' }

    $appPath = Join-Path $PSScriptRoot 'SteamLibraryManager.ps1'
    if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) { throw "App launcher is missing: $appPath" }

    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $shortcutPath = Join-Path $programsPath 'Steam Library Manager.lnk'
    $arguments = '-STA -NoProfile -ExecutionPolicy Bypass -File "{0}" -Relaunched' -f $appPath
    $shell = New-Object -ComObject WScript.Shell

    if (Test-Path -LiteralPath $shortcutPath) {
        $existing = $shell.CreateShortcut($shortcutPath)
        if ($existing.TargetPath -ine $powershell) {
            throw "Another shortcut already uses this name: $shortcutPath"
        }
    } else {
        [IO.Directory]::CreateDirectory($programsPath) | Out-Null
    }

    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = $arguments
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.Description = 'Launch Steam Library Manager'
    $shortcut.Save()

    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
        throw "The Start Menu shortcut was not created: $shortcutPath"
    }
    return $shortcutPath
}
