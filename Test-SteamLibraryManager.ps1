$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'SteamLibraryManager.Core.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.Clone.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.Images.ps1')
function Test-SteamRunning { return $false }
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("sgc-test-" + [guid]::NewGuid())
$root = Join-Path $sandbox 'Steam'
$other = Join-Path $PSScriptRoot ('.steamlibrarymanager-test-' + [guid]::NewGuid())
$legacy = Join-Path $PSScriptRoot ('.steamlibrarymanager-test-' + [guid]::NewGuid())
try {
    foreach ($path in @($root, $other, $legacy)) {
        [IO.Directory]::CreateDirectory((Join-Path $path 'steamapps\common')) | Out-Null
    }
    $vdf = '"libraryfolders" { "0" { "path" "' + $root.Replace('\','\\') + '" } "1" { "path" "' + $other.Replace('\','\\') + '" } "2" "' + $legacy.Replace('\','\\') + '" }'
    [IO.File]::WriteAllText((Join-Path $root 'steamapps\libraryfolders.vdf'), $vdf)
    function Get-SteamRoot { return $root }
    if (@(Get-SteamLibraries).Count -ne 3) { throw 'Modern/legacy library discovery or path deduplication failed.' }
    $script:DataFile = Join-Path $sandbox 'data.json'
    $script:LegacyDataFile = Join-Path $sandbox 'SteamGameCloner.json'
    $legacyJson = '{"Games":[]}'
    [IO.File]::WriteAllText($script:LegacyDataFile, $legacyJson)
    $migrated = Read-GameData
    if (@($migrated.Games).Count -ne 0 -or [IO.File]::ReadAllText($script:DataFile) -ne $legacyJson -or
        [IO.File]::ReadAllText($script:LegacyDataFile) -ne $legacyJson) { throw 'Legacy data migration changed or lost saved data.' }
    $original = Join-Path $root 'steamapps\common\Demo'
    [IO.Directory]::CreateDirectory($original) | Out-Null
    [IO.File]::WriteAllText((Join-Path $original 'game.txt'), 'test content')
    $manifestPath = Join-Path $root 'steamapps\appmanifest_123.acf'
    [IO.File]::WriteAllText($manifestPath, '"AppState" { "appid" "123" "name" "Demo Game" "installdir" "Demo" }')
    $otherGame = Join-Path $other 'steamapps\common\AnotherGame'
    [IO.Directory]::CreateDirectory($otherGame) | Out-Null
    [IO.File]::WriteAllText((Join-Path $other 'steamapps\appmanifest_456.acf'), '"AppState" { "appid" "456" "name" "Another Game" "installdir" "AnotherGame" }')
    [IO.File]::WriteAllText((Join-Path $root 'steamapps\appmanifest_9.acf'), '"AppState" { "appid" "9" "name" "Alpha Game" "installdir" "Alpha" }')
    [IO.File]::WriteAllText((Join-Path $other 'steamapps\appmanifest_10.acf'), '"AppState" { "appid" "10" "name" "Zeta Game" "installdir" "Zeta" }')
    $found = @(Find-InstalledGames)
    if ($found.Count -ne 4) { throw 'Manifest discovery failed.' }
    $first = $found | Where-Object { $_.AppId -eq '123' } | Select-Object -First 1
    $second = $found | Where-Object { $_.AppId -eq '456' } | Select-Object -First 1
    if (-not $first -or -not $second) { throw 'Manifest identity was lost.' }
    if (-not $first.Exists -or ($found | Where-Object AppId -eq '9' | Select-Object -First 1).Exists) { throw 'Installed folder status is incorrect.' }
    if ((Get-LibraryDrive $first.Library) -ne ([IO.Path]::GetPathRoot($root).Substring(0,1))) { throw 'First drive is incorrect.' }
    if ((Get-LibraryDrive $second.Library) -ne ([IO.Path]::GetPathRoot($other).Substring(0,1))) { throw 'Second drive is incorrect.' }
    if (@(Find-GameChoices $found 'demo').Count -ne 1 -or (Find-GameChoices $found 'demo')[0].AppId -ne '123') { throw 'Name filtering failed.' }
    if (@(Find-GameChoices $found '456').Count -ne 1 -or (Find-GameChoices $found '456')[0].Library -ne $second.Library) { throw 'App ID filtering lost the selected library.' }
    if (@(Find-GameChoices $found '').Count -ne 4) { throw 'Empty search should show all games.' }
    $byName = @(Get-SortedGameChoices $found '' 0 $false)
    if (($byName.Name -join ',') -ne 'Alpha Game,Another Game,Demo Game,Zeta Game') { throw 'Game-name ascending sort failed.' }
    $byNameReverse = @(Get-SortedGameChoices $found '' 0 $true)
    if (($byNameReverse.Name -join ',') -ne 'Zeta Game,Demo Game,Another Game,Alpha Game') { throw 'Game-name descending sort failed.' }
    $byId = @(Get-SortedGameChoices $found '' 1 $false)
    if (($byId.AppId -join ',') -ne '9,10,123,456') { throw 'Numeric App ID sort failed.' }
    $byIdReverse = @(Get-SortedGameChoices $found '' 1 $true)
    if (($byIdReverse.AppId -join ',') -ne '456,123,10,9') { throw 'Numeric App ID descending sort failed.' }
    $byDrive = @(Get-SortedGameChoices $found '' 2 $false)
    if ((($byDrive | ForEach-Object { Get-LibraryDrive $_.Library }) -join ',') -ne 'C,C,D,D') { throw 'Drive ascending sort failed.' }
    $byDriveReverse = @(Get-SortedGameChoices $found '' 2 $true)
    if ((($byDriveReverse | ForEach-Object { Get-LibraryDrive $_.Library }) -join ',') -ne 'D,D,C,C') { throw 'Drive descending sort failed.' }
    $byFolder = @(Get-SortedGameChoices $found '' 3 $false)
    if (($byFolder.AppId -join ',') -ne '9,123,456,10') { throw 'Installed-folder ascending sort failed.' }
    $byFolderReverse = @(Get-SortedGameChoices $found '' 3 $true)
    if (($byFolderReverse.AppId -join ',') -ne '10,456,123,9') { throw 'Installed-folder descending sort failed.' }
    $filteredAndSorted = @(Get-SortedGameChoices $found '456' 2 $true)
    if ($filteredAndSorted.Count -ne 1 -or $filteredAndSorted[0].Path -ne $second.Path) { throw 'Sorting after search lost the selected manifest.' }
    $managedOrder = @(Get-SortedManagedGames @([pscustomobject]@{ Name='Zeta'; AppId='10' }, [pscustomobject]@{ Name='Alpha'; AppId='9' }) $false)
    if (($managedOrder.AppId -join ',') -ne '9,10') { throw 'Main game sorting lost identity.' }
    $data = Read-GameData
    $game = Add-ManagedGame $data $first 'Demo label'
    $savedBeforeLock = [IO.File]::ReadAllText($script:DataFile)
    $heldData = [IO.File]::Open($script:DataFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $saveRejected = $false
    try { Save-GameData $data } catch { $saveRejected = $_.Exception.Message -like '*file is in use*' }
    finally { $heldData.Dispose() }
    if (-not $saveRejected -or [IO.File]::ReadAllText($script:DataFile) -ne $savedBeforeLock -or
        (Test-Path -LiteralPath "$script:DataFile.tmp")) { throw 'Locked data save changed the file or did not report the lock clearly.' }
    $mismatched = [pscustomobject]@{ AppId = '123'; Name = '456'; Versions = $game.Versions }
    if (-not (Get-ManagedGameIdentityIssue $mismatched)) { throw 'Numeric label conflicting with App ID was not flagged.' }
    $beforeManifest = [IO.File]::ReadAllText($manifestPath)
    $identityRejected = $false
    try { Set-ActiveGameVersion $mismatched $game.Versions[0] } catch { $identityRejected = $true }
    if (-not $identityRejected -or [IO.File]::ReadAllText($manifestPath) -ne $beforeManifest) { throw 'Identity mismatch was allowed to modify a manifest.' }
    $badManifest = Join-Path $root 'steamapps\appmanifest_777.acf'
    [IO.File]::WriteAllText($badManifest, '"AppState" { "appid" "888" "name" "Wrong" "installdir" "Demo" }')
    $manifestRejected = $false
    try { Get-ManifestInfo $badManifest | Out-Null } catch { $manifestRejected = $true }
    if (-not $manifestRejected) { throw 'Filename and embedded App ID mismatch was accepted.' }
    [IO.File]::Delete($badManifest)
    $plan = Get-ClonePlan $game $game.Versions[0] $other '' ''
    if ($plan.Folder -ne 'Demo-copy' -or $plan.Name -ne 'Copy of Original' -or $plan.Library -ne $other) { throw 'Default clone plan is incorrect.' }
    [IO.Directory]::CreateDirectory($plan.Destination) | Out-Null
    $nextPlan = Get-ClonePlan $game $game.Versions[0] $other '' ''
    if ($nextPlan.Folder -ne 'Demo-copy-2') { throw 'Clone folder collision was not avoided.' }
    $conflictRejected = $false
    try { Get-ClonePlan $game $game.Versions[0] $other 'Demo-copy' '' | Out-Null } catch { $conflictRejected = $true }
    if (-not $conflictRejected) { throw 'Explicit clone folder conflict was accepted.' }
    $invalidRejected = $false
    try { Get-ClonePlan $game $game.Versions[0] $other '..\escape' '' | Out-Null } catch { $invalidRejected = $true }
    if (-not $invalidRejected) { throw 'Invalid clone folder name was accepted.' }
    $destination = Join-Path $other 'steamapps\common\DemoClone'
    $clone = Copy-GameVersion $data $game $game.Versions[0] 'Clone label' $destination
    if (-not (Test-Path (Join-Path $destination 'game.txt'))) { throw 'Clone copy failed.' }
    if (@((Read-GameData).Games[0].Versions).Count -ne 2) { throw 'Persistence failed.' }
    Set-ActiveGameVersion $game $clone
    if (Test-Path $manifestPath) { throw 'Old library still has active manifest.' }
    $moved = Join-Path $other 'steamapps\appmanifest_123.acf'
    if (-not (Test-Path $moved)) { throw 'Target library lacks manifest.' }
    if ((Get-ManifestInfo $moved).InstallDir -ne 'DemoClone') { throw 'Target install directory is wrong.' }
    Set-ActiveGameVersion $game $game.Versions[0]
    if (-not (Test-Path $manifestPath) -or (Test-Path $moved)) { throw 'Switch back failed.' }
    if ((Get-ManifestInfo $manifestPath).InstallDir -ne 'Demo') { throw 'Original install directory was not restored.' }
    $legacyFolder = Join-Path $legacy 'steamapps\common\LegacyGame'
    [IO.Directory]::CreateDirectory($legacyFolder) | Out-Null
    [IO.File]::WriteAllText((Join-Path $legacy 'steamapps\appmanifest_77.acf'), '"AppState" { "appid" "77" "name" "Legacy Game" "installdir" "LegacyGame" }')
    $withLegacy = @(Find-InstalledGames)
    $legacyOnly = @(Find-GameChoices $withLegacy '' $legacy)
    if ($legacyOnly.Count -ne 1 -or $legacyOnly[0].AppId -ne '77') { throw 'Library filter mixed two libraries on one drive.' }
    $cacheFolder = Join-Path $root 'appcache\librarycache\123\sample'
    [IO.Directory]::CreateDirectory($cacheFolder) | Out-Null
    $imagePath = Join-Path $cacheFolder 'library_capsule.png'
    [IO.File]::WriteAllBytes($imagePath, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg=='))
    if ((Get-LocalGameImagePath '123') -ne $imagePath) { throw 'Local image discovery failed.' }
    $bitmap = Get-GameImageBitmap '123'
    if (-not $bitmap -or $bitmap.Width -ne 1) { throw 'Local image load failed.' }
    Remove-Item -LiteralPath $imagePath -Force
    if (Test-Path $imagePath) { throw 'Image file remained locked.' }
    Dispose-GameImages
    function Get-FreeSpaceBytes { return 1 }
    $lowSpaceRejected = $false
    try { Get-ClonePlan $game $game.Versions[0] $other '' '' | Out-Null } catch { $lowSpaceRejected = $true }
    if (-not $lowSpaceRejected) { throw 'Insufficient clone space was accepted.' }
    'PASS: modern/legacy libraries, same-drive filter, image cache, clone defaults/collision/space, sorting, persistence, cross-library switch'
} finally {
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $projectBase = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
    if ([IO.Path]::GetFullPath($sandbox).StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $sandbox)) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force
    }
    foreach ($path in @($other, $legacy)) {
        if ([IO.Path]::GetFullPath($path).StartsWith($projectBase, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $path)) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}
