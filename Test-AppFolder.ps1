$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SteamLibraryManager.AppFolder.ps1')

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

Write-Output 'App folder PASS: current path and Explorer arguments.'
