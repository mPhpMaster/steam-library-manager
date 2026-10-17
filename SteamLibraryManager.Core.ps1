$ErrorActionPreference = 'Stop'
$script:DataFile = Join-Path $PSScriptRoot 'SteamLibraryManager.json'
$script:LegacyDataFile = Join-Path $PSScriptRoot 'SteamGameCloner.json'

function Initialize-GameDataPath {
    if ((Test-Path -LiteralPath $script:DataFile) -or -not (Test-Path -LiteralPath $script:LegacyDataFile)) { return }
    $raw = [IO.File]::ReadAllText($script:LegacyDataFile)
    $legacy = $raw | ConvertFrom-Json
    if ($null -eq $legacy.Games) { throw 'Legacy saved data has no Games collection; migration was stopped.' }
    $temporary = "$script:DataFile.migration-" + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporary, $raw, [Text.UTF8Encoding]::new($false))
        try { [IO.File]::Move($temporary, $script:DataFile) }
        catch [IO.IOException] {
            if (-not (Test-Path -LiteralPath $script:DataFile)) { throw }
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Get-SteamRoot {
    $value = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($value -and (Test-Path -LiteralPath $value)) { return [IO.Path]::GetFullPath($value) }
    foreach ($candidate in @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam")) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return [IO.Path]::GetFullPath($candidate) }
    }
    throw 'Steam installation was not found.'
}

function Get-SteamLibraries {
    $root = Get-SteamRoot
    $result = New-Object 'System.Collections.Generic.List[string]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $addLibrary = {
        param([string]$candidate)
        try {
            $decoded = $candidate.Replace('\\', '\').Replace('/', '\')
            $full = [IO.Path]::GetFullPath($decoded)
            $driveRoot = [IO.Path]::GetPathRoot($full)
            if ($full.Length -gt $driveRoot.Length) { $full = $full.TrimEnd('\') }
            if ((Test-Path -LiteralPath (Join-Path $full 'steamapps') -PathType Container) -and $seen.Add($full)) {
                $result.Add($full)
            }
        } catch { }
    }
    & $addLibrary $root
    $file = Join-Path $root 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $file) {
        $raw = [IO.File]::ReadAllText($file)
        foreach ($match in [regex]::Matches($raw, '"path"\s*"([^"]+)"')) {
            & $addLibrary $match.Groups[1].Value
        }
        foreach ($match in [regex]::Matches($raw, '"\d+"\s*"((?:[A-Za-z]:|\\\\)[^"]+)"')) {
            & $addLibrary $match.Groups[1].Value
        }
    }
    return @($result)
}

function Get-ManifestInfo([string]$path) {
    $raw = [IO.File]::ReadAllText($path)
    $id = [regex]::Match([IO.Path]::GetFileName($path), '^appmanifest_(\d+)\.acf$')
    $embeddedId = [regex]::Match($raw, '"appid"\s*"(\d+)"')
    $dir = [regex]::Match($raw, '"installdir"\s*"([^"]+)"')
    if (-not $id.Success -or -not $embeddedId.Success -or $id.Groups[1].Value -ne $embeddedId.Groups[1].Value -or -not $dir.Success) {
        throw "Steam manifest filename and App ID disagree, or required fields are missing: $path"
    }
    $name = [regex]::Match($raw, '"name"\s*"([^"]+)"')
    return [pscustomobject]@{
        AppId = $id.Groups[1].Value
        Name = if ($name.Success) { $name.Groups[1].Value } else { "App $($id.Groups[1].Value)" }
        InstallDir = $dir.Groups[1].Value
        Library = Split-Path (Split-Path $path -Parent) -Parent
        Path = $path
        Raw = $raw
        Exists = Test-Path -LiteralPath (Join-Path (Join-Path (Split-Path (Split-Path $path -Parent) -Parent) 'steamapps\common') $dir.Groups[1].Value) -PathType Container
    }
}

function Find-InstalledGames {
    $games = @()
    foreach ($library in @(Get-SteamLibraries)) {
        foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $library 'steamapps') -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)) {
            try { $games += Get-ManifestInfo $file.FullName } catch { }
        }
    }
    return @($games)
}

function Get-LibraryDrive([string]$library) {
    $match = [regex]::Match($library, '^([A-Za-z]):[\\/]')
    if ($match.Success) { return $match.Groups[1].Value.ToUpperInvariant() }
    return '-'
}

function Find-GameChoices($entries, [string]$query, [string]$library = '') {
    $term = $query.Trim()
    return @($entries | Where-Object {
        ([string]::IsNullOrEmpty($library) -or $_.Library -ieq $library) -and
        (-not $term -or $_.Name.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.AppId.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0)
    })
}

function Get-SortedGameChoices($entries, [string]$query, [int]$column, [bool]$descending, [string]$library = '') {
    $filtered = @(Find-GameChoices $entries $query $library)
    $properties = switch ($column) {
        0 { @(@{ Expression = { $_.Name } }, @{ Expression = { [long]$_.AppId } }) }
        1 { @(@{ Expression = { [long]$_.AppId } }, @{ Expression = { $_.Name } }) }
        2 { @(@{ Expression = { Get-LibraryDrive $_.Library } }, @{ Expression = { $_.Name } }) }
        3 { @(@{ Expression = { Join-Path (Join-Path $_.Library 'steamapps\common') $_.InstallDir } }, @{ Expression = { $_.Name } }) }
        default { throw 'Unknown game-list sort column.' }
    }
    return @($filtered | Sort-Object -Property $properties -Descending:$descending)
}

function Get-SortedManagedGames($games, [bool]$descending) {
    return @($games | Sort-Object -Property Name, AppId -Descending:$descending)
}

function Read-GameData {
    Initialize-GameDataPath
    if (-not (Test-Path -LiteralPath $script:DataFile)) { return [pscustomobject]@{ Games = @() } }
    $data = Get-Content -LiteralPath $script:DataFile -Raw | ConvertFrom-Json
    if ($null -eq $data.Games) { throw 'The saved data has no Games collection.' }
    return $data
}

function Save-GameData($data) {
    Initialize-GameDataPath
    $temp = "$script:DataFile.tmp"
    $json = ConvertTo-Json -InputObject $data -Depth 12
    [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
    try {
        if (Test-Path -LiteralPath $script:DataFile) {
            Replace-FileWithRetry $temp $script:DataFile "$script:DataFile.bak" 'saved game data'
        } else { [IO.File]::Move($temp, $script:DataFile) }
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}

function Replace-FileWithRetry([string]$source, [string]$target, [string]$backup, [string]$description) {
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try { [IO.File]::Replace($source, $target, $backup); return }
        catch [IO.IOException] {
            if ($attempt -eq 5) { throw "Could not update $description because the file is in use: $target. The existing file was kept. Close the program holding it and retry." }
            Start-Sleep -Milliseconds 100
        }
    }
}

function Get-ManagedGameIdentityIssue($game) {
    if ([string]$game.AppId -notmatch '^\d+$') { return 'Saved game App ID is invalid.' }
    if ([string]$game.Name -match '^\d+$' -and [string]$game.Name -ne [string]$game.AppId) {
        return "Saved label '$($game.Name)' looks like a different App ID; this record is App ID $($game.AppId). Verify the Steam manifest and rename this entry."
    }
    try { $manifest = Find-GameManifest ([string]$game.AppId) }
    catch { return "Cannot verify the Steam manifest for App ID $($game.AppId): $($_.Exception.Message)" }
    $activePath = Join-Path (Join-Path $manifest.Library 'steamapps\common') $manifest.InstallDir
    if (-not @($game.Versions | Where-Object { $_.Path -ieq $activePath }).Count) {
        return "The active Steam folder for App ID $($game.AppId) is not among this entry's saved versions."
    }
    return ''
}

function Assert-ManagedGameIdentity($game) {
    $issue = Get-ManagedGameIdentityIssue $game
    if ($issue) { throw "Game identity needs review. $issue No Steam files were changed." }
}

function Assert-VersionPath([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Folder does not exist: $path" }
    $full = [IO.Path]::GetFullPath($path).TrimEnd('\')
    $common = Split-Path $full -Parent
    if ((Split-Path $common -Leaf) -ne 'common') { throw 'A version must be a direct child of steamapps\common.' }
    $steamapps = Split-Path $common -Parent
    if ((Split-Path $steamapps -Leaf) -ne 'steamapps') { throw 'The folder must be inside a Steam library.' }
    $library = Split-Path $steamapps -Parent
    if (@(Get-SteamLibraries) -notcontains $library) { throw "Steam does not list this library: $library" }
    return [pscustomobject]@{ Path = $full; Folder = Split-Path $full -Leaf; Library = $library }
}

function Add-ManagedGame($data, $manifest, [string]$displayName) {
    if ($displayName -match '^\d+$' -and $displayName -ne $manifest.AppId) { throw 'A numeric game label must match its Steam App ID.' }
    if (@($data.Games | Where-Object { $_.AppId -eq $manifest.AppId }).Count) { throw 'This game is already managed.' }
    $path = Join-Path (Join-Path $manifest.Library 'steamapps\common') $manifest.InstallDir
    $version = Assert-VersionPath $path
    $game = [pscustomobject]@{
        AppId = $manifest.AppId; Name = $displayName
        Versions = @([pscustomobject]@{ Id = [guid]::NewGuid().ToString(); Name = 'Original'; Path = $version.Path })
    }
    $data.Games = @($data.Games) + @($game)
    Save-GameData $data
    return $game
}

function Add-ManagedVersion($data, $game, [string]$name, [string]$path) {
    Assert-ManagedGameIdentity $game
    $version = Assert-VersionPath $path
    if (@($game.Versions | Where-Object { $_.Path -ieq $version.Path }).Count) { throw 'This folder is already registered.' }
    $item = [pscustomobject]@{ Id = [guid]::NewGuid().ToString(); Name = $name; Path = $version.Path }
    $game.Versions = @($game.Versions) + @($item)
    Save-GameData $data
    return $item
}

function Copy-GameVersion($data, $game, $source, [string]$name, [string]$destination) {
    $src = Assert-VersionPath $source.Path
    $parent = Split-Path ([IO.Path]::GetFullPath($destination).TrimEnd('\')) -Parent
    if ((Split-Path $parent -Leaf) -ne 'common' -or (Split-Path (Split-Path $parent -Parent) -Leaf) -ne 'steamapps') {
        throw 'Destination must be a direct child of steamapps\common.'
    }
    $library = Split-Path (Split-Path $parent -Parent) -Parent
    if (@(Get-SteamLibraries) -notcontains $library) { throw 'Destination library is not registered in Steam.' }
    $destination = [IO.Path]::GetFullPath($destination).TrimEnd('\')
    if (Test-Path -LiteralPath $destination) { throw 'Destination already exists.' }
    if ($destination -ieq $src.Path) { throw 'Source and destination are identical.' }
    Assert-CloneSpace $src.Path $library | Out-Null
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    try {
        foreach ($entry in @(Get-ChildItem -LiteralPath $src.Path -Force -ErrorAction Stop)) {
            Copy-Item -LiteralPath $entry.FullName -Destination $destination -Recurse -Force -ErrorAction Stop
        }
    } catch {
        [IO.Directory]::Delete($destination, $true)
        throw
    }
    return Add-ManagedVersion $data $game $name $destination
}

function Find-GameManifest([string]$appId) {
    $matches = @(Find-InstalledGames | Where-Object { $_.AppId -eq $appId })
    if ($matches.Count -ne 1) { throw "Expected one manifest for app $appId; found $($matches.Count)." }
    return $matches[0]
}

function Test-SteamRunning { return [bool](Get-Process -Name steam -ErrorAction SilentlyContinue) }

function Stop-SteamSafely {
    if (-not (Test-SteamRunning)) { return }
    $exe = Join-Path (Get-SteamRoot) 'steam.exe'
    Start-Process -FilePath $exe -ArgumentList '-shutdown' -ErrorAction Stop
    $deadline = (Get-Date).AddSeconds(30)
    while ((Test-SteamRunning) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 350 }
    if (Test-SteamRunning) { throw 'Steam did not close within 30 seconds.' }
    Start-Sleep -Milliseconds 1200
}

function Set-ActiveGameVersion($game, $version) {
    Assert-ManagedGameIdentity $game
    if (Test-SteamRunning) { throw 'Close Steam before switching versions.' }
    $target = Assert-VersionPath $version.Path
    $manifest = Find-GameManifest $game.AppId
    if ($manifest.Library -ieq $target.Library -and $manifest.InstallDir -eq $target.Folder) { return }
    $targetManifest = Join-Path (Join-Path $target.Library 'steamapps') "appmanifest_$($game.AppId).acf"
    if ($manifest.Path -ine $targetManifest -and (Test-Path -LiteralPath $targetManifest)) {
        throw 'A manifest for this app already exists in the target library.'
    }
    $pattern = [regex]'("installdir"\s*")[^"]*(")'
    $updated = $pattern.Replace($manifest.Raw, ('${1}' + $target.Folder + '${2}'), 1)
    if ($updated -eq $manifest.Raw -and $manifest.InstallDir -ne $target.Folder) { throw 'Could not update installdir.' }
    $backup = "$($manifest.Path).switcher-backup"
    if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $manifest.Path -Destination $backup }
    $temp = "$targetManifest.switcher-tmp"
    try {
        [IO.File]::WriteAllText($temp, $updated, (New-Object Text.UTF8Encoding($false)))
        if ($manifest.Path -ieq $targetManifest) {
            Replace-FileWithRetry $temp $targetManifest "$targetManifest.switcher-previous" 'Steam manifest'
        } else {
            [IO.File]::Move($temp, $targetManifest)
            try { [IO.File]::Delete($manifest.Path) } catch {
                [IO.File]::Delete($targetManifest)
                throw
            }
        }
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}
