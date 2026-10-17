$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SteamLibraryManager.StartMenu.ps1')

$testFolder = Join-Path ([IO.Path]::GetTempPath()) ('Steam Library Manager Test ' + [guid]::NewGuid().ToString('N'))
$shortcutPath = Join-Path $testFolder 'Steam Library Manager.lnk'
$shell = New-Object -ComObject WScript.Shell
try {
    $created = Add-StartMenuShortcut $testFolder
    if ($created -ne $shortcutPath) { throw 'Shortcut path is incorrect.' }

    $shortcut = $shell.CreateShortcut($shortcutPath)
    $expectedTarget = (Get-Command powershell.exe -ErrorAction Stop).Source
    $expectedApp = Join-Path $PSScriptRoot 'SteamLibraryManager.ps1'
    if ($shortcut.TargetPath -ine $expectedTarget -or
        $shortcut.Arguments -ne ('-STA -NoProfile -ExecutionPolicy Bypass -File "{0}" -Relaunched' -f $expectedApp) -or
        $shortcut.WorkingDirectory -ine $PSScriptRoot) {
        throw 'Shortcut target, arguments, or working directory is incorrect.'
    }

    if ((Add-StartMenuShortcut $testFolder) -ne $shortcutPath) { throw 'Shortcut update failed.' }
    $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\notepad.exe'
    $shortcut.Save()
    $collisionRejected = $false
    try { Add-StartMenuShortcut $testFolder | Out-Null } catch { $collisionRejected = $true }
    if (-not $collisionRejected) { throw 'An unrelated shortcut was overwritten.' }

    Write-Output 'Start Menu shortcut PASS: target, arguments, idempotence, collision protection.'
} finally {
    if (Test-Path -LiteralPath $testFolder) { Remove-Item -LiteralPath $testFolder -Recurse -Force }
}
