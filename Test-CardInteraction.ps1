$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot 'SteamLibraryManager.CardInteraction.ps1')

$script:selected = @()
$script:activated = @()
function Select-Version([string]$id) { $script:selected += $id }
function Activate-Version([string]$id) { $script:activated += $id }
function Write-Activity([string]$message, [string]$kind) { }

$card = New-Object Windows.Forms.Panel
$name = New-Object Windows.Forms.Label
$detail = New-Object Windows.Forms.Label
$button = New-Object Windows.Forms.Button
$card.Controls.AddRange(@($name, $detail, $button))
$sidebar = New-Object Windows.Forms.Label
try {
    Register-CardClick $card 'version-42'
    $flags = [Reflection.BindingFlags]'Instance,NonPublic'
    $click = [Windows.Forms.Control].GetMethod('OnClick', $flags)
    $doubleClick = [Windows.Forms.Control].GetMethod('OnDoubleClick', $flags)
    [void]$click.Invoke($name, @([EventArgs]::Empty))
    if (($script:selected -join ',') -ne 'version-42' -or $script:activated.Count -ne 0) { throw 'Single click did not only select the version.' }
    [void]$doubleClick.Invoke($card, @([EventArgs]::Empty))
    [void]$doubleClick.Invoke($detail, @([EventArgs]::Empty))
    [void]$doubleClick.Invoke($button, @([EventArgs]::Empty))
    [void]$doubleClick.Invoke($sidebar, @([EventArgs]::Empty))
    if (($script:activated -join ',') -ne 'version-42,version-42') { throw 'Card or child double-click dispatch is incorrect.' }
    if ($script:selected.Count -ne 3) { throw 'Unexpected card or sidebar selection.' }
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'SteamLibraryManager.ps1'), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Main app has a PowerShell parse error.' }
    $activation = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Activate-Version' }, $true)
    if (-not $activation) { throw 'Activate-Version was not found.' }
    Invoke-Expression $activation.Extent.Text
    $script:ActivationInProgress = $false
    $script:switchCount = 0
    function Selected-Game { return [pscustomobject]@{ AppId = '123'; Name = 'Demo'; Versions = @([pscustomobject]@{ Id = 'version-42'; Name = 'Demo build'; Path = 'fake' }) } }
    function Assert-ManagedGameIdentity($game) { }
    function Test-SteamRunning { return $false }
    function Set-ActiveGameVersion($game, $version) {
        $script:switchCount++
        Activate-Version $version.Id
    }
    function Refresh-Versions { }
    function Confirm([string]$message) { return $false }
    Activate-Version 'version-42'
    if ($script:switchCount -ne 1 -or $script:ActivationInProgress) { throw 'Activation reentry guard failed.' }
    Write-Output 'Card interaction PASS: single click, card/label double-click, sidebar isolation, activation reentry guard.'
} finally {
    $card.Dispose(); $sidebar.Dispose()
}
