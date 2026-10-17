function Get-DirectoryByteCount([string]$path) {
    $size = [long]0
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($path)
    while ($pending.Count -gt 0) {
        foreach ($item in @(Get-ChildItem -LiteralPath ($pending.Pop()) -Force -ErrorAction Stop)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Clone source contains a link or junction: $($item.FullName)"
            }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            else { $size += $item.Length }
        }
    }
    return $size
}

function Get-FreeSpaceBytes([string]$library) {
    $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($library))
    if (-not $root) { throw 'Cannot determine destination drive capacity.' }
    return ([IO.DriveInfo]::new($root)).AvailableFreeSpace
}

function Assert-CloneSpace([string]$sourcePath, [string]$library) {
    $size = Get-DirectoryByteCount $sourcePath
    $free = Get-FreeSpaceBytes $library
    $reserve = [long][Math]::Max(64MB, [Math]::Ceiling($size * 0.02))
    if ($free -lt ($size + $reserve)) {
        throw "Not enough free space in $library. Required: $([Math]::Ceiling(($size + $reserve) / 1GB)) GB; available: $([Math]::Round($free / 1GB, 2)) GB."
    }
    return [pscustomobject]@{ Size = $size; Free = $free }
}

function Get-CloneFolderName([string]$sourceFolder, [string]$common, [string]$requested) {
    if ($requested.Trim()) {
        $folder = $requested.Trim()
        if ($folder.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
            $folder -match '[\\/:*?"<>|]' -or $folder -match '[. ]$' -or $folder -in @('.', '..') -or
            $folder -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw 'Invalid destination folder name.'
        }
        if (Test-Path -LiteralPath (Join-Path $common $folder)) { throw 'Destination folder already exists.' }
        return $folder
    }
    $base = "$sourceFolder-copy"
    $folder = $base; $number = 2
    while (Test-Path -LiteralPath (Join-Path $common $folder)) {
        $folder = "$base-$number"; $number++
        if ($number -gt 10000) { throw 'Cannot find an unused clone folder name.' }
    }
    return $folder
}

function Get-ClonePlan($game, $source, [string]$library, [string]$folderInput, [string]$nameInput) {
    Assert-ManagedGameIdentity $game
    $src = Assert-VersionPath $source.Path
    $known = @(Get-SteamLibraries | Where-Object { $_ -ieq $library })
    if ($known.Count -ne 1) { throw 'Choose one registered Steam library.' }
    $common = Join-Path (Join-Path $known[0] 'steamapps') 'common'
    if (-not (Test-Path -LiteralPath $common -PathType Container)) { throw "The library has no steamapps\common folder: $common" }
    $folder = Get-CloneFolderName $src.Folder $common $folderInput
    $destination = Join-Path $common $folder
    $capacity = Assert-CloneSpace $src.Path $known[0]
    $name = $nameInput.Trim()
    if (-not $name) {
        $base = "Copy of $($source.Name)"; $name = $base; $number = 2
        while (@($game.Versions | Where-Object { $_.Name -ieq $name }).Count) {
            $name = "$base ($number)"; $number++
        }
    }
    if ($name.Length -gt 100) { throw 'Version name exceeds 100 characters.' }
    return [pscustomobject]@{
        Library = $known[0]; Folder = $folder; Destination = $destination
        Name = $name; Size = $capacity.Size
        SizeText = if ($capacity.Size -ge 1GB) { "$([Math]::Round($capacity.Size / 1GB, 2)) GB" } else { "$([Math]::Round($capacity.Size / 1MB, 1)) MB" }
        Free = $capacity.Free
    }
}
