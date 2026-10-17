function Get-AppFolder {
    $folder = $PSScriptRoot
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        throw "The application folder is missing: $folder"
    }
    return $folder
}

function Open-AppFolder {
    $folder = Get-AppFolder
    $explorer = Join-Path $env:WINDIR 'explorer.exe'
    if (-not (Test-Path -LiteralPath $explorer -PathType Leaf)) {
        throw "File Explorer was not found: $explorer"
    }
    Start-Process -FilePath $explorer -ArgumentList ('"{0}"' -f $folder)
}
