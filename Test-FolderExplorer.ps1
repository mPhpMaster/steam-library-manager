$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SteamLibraryManager.Core.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.FolderExplorer.ps1')

$script:openedPath = $null
$script:openedArgument = $null
function Start-Process {
    param([string]$FilePath, [string]$ArgumentList)
    $script:openedPath = $FilePath
    $script:openedArgument = $ArgumentList
}

$expectedFolder = $PSScriptRoot
if ((Get-AppFolder) -ine $expectedFolder) { throw 'The app folder is incorrect.' }
Open-AppFolder
if ($script:openedPath -ine (Join-Path $env:WINDIR 'explorer.exe') -or
    $script:openedArgument -ne ('"{0}"' -f $expectedFolder)) {
    throw 'File Explorer did not receive the quoted app folder path.'
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('SteamLibraryManager-folder-' + [guid]::NewGuid().ToString('N'))
$library = Join-Path $testRoot 'Steam Library'
$script:testRegisteredLibrary = $library
$clone = Join-Path $library 'steamapps\common\Cloned Version'
try {
    [IO.Directory]::CreateDirectory($clone) | Out-Null
    function Get-SteamLibraries { return @($script:testRegisteredLibrary) }

    $script:openedArgument = $null
    Open-VersionFolder $clone
    if ($script:openedArgument -ne ('"{0}"' -f $clone)) {
        throw 'Explorer did not receive the selected version folder.'
    }

    $script:openedArgument = $null
    $missingRejected = $false
    try { Open-VersionFolder (Join-Path $library 'steamapps\common\Missing') } catch { $missingRejected = $true }
    if (-not $missingRejected -or $script:openedArgument) { throw 'A missing version folder was opened.' }

    $unregistered = Join-Path $testRoot 'Unregistered\steamapps\common\Other'
    [IO.Directory]::CreateDirectory($unregistered) | Out-Null
    $unregisteredRejected = $false
    try { Open-VersionFolder $unregistered } catch { $unregisteredRejected = $true }
    if (-not $unregisteredRejected -or $script:openedArgument) { throw 'An unregistered folder was opened.' }

    Write-Output 'Folder Explorer PASS: app path, selected clone path, missing and unregistered folders.'
} finally {
    $resolvedRoot = [IO.Path]::GetFullPath($testRoot)
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe test cleanup path: $resolvedRoot"
    }
    if (Test-Path -LiteralPath $resolvedRoot) { Remove-Item -LiteralPath $resolvedRoot -Recurse -Force }
}
