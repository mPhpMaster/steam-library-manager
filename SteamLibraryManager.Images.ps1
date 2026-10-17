$script:GameImages = @{}

function Get-LocalGameImagePath([string]$appId) {
    if ($appId -notmatch '^\d+$') { return $null }
    $root = Get-SteamRoot
    $cache = Join-Path $root "appcache\librarycache\$appId"
    if (Test-Path -LiteralPath $cache -PathType Container) {
        $icons = @(Get-ChildItem -LiteralPath $cache -Filter '*.ico' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 0 -and $_.Length -le 8MB } | Sort-Object Length -Descending)
        if ($icons.Count) { return $icons[0].FullName }
        foreach ($folder in @(Get-ChildItem -LiteralPath $cache -Directory -ErrorAction SilentlyContinue)) {
            foreach ($name in @('library_capsule.jpg', 'library_capsule.png', 'library_header.jpg', 'logo.png')) {
                $candidate = Join-Path $folder.FullName $name
                if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and (Get-Item -LiteralPath $candidate).Length -le 8MB) {
                    return $candidate
                }
            }
        }
    }
    foreach ($candidate in @(
        (Join-Path $root "appcache\librarycache\${appId}_icon.jpg"),
        (Join-Path $root "steam\games\$appId.ico")
    )) {
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and (Get-Item -LiteralPath $candidate).Length -le 8MB) {
            return $candidate
        }
    }
    return $null
}

function Get-GameImageBitmap([string]$appId) {
    if ($script:GameImages.ContainsKey($appId)) { return $script:GameImages[$appId] }
    $stream = $null; $original = $null; $icon = $null
    try {
        $path = Get-LocalGameImagePath $appId
        if (-not $path) { $script:GameImages[$appId] = $null; return $null }
        $stream = [IO.MemoryStream]::new([IO.File]::ReadAllBytes($path))
        if ([IO.Path]::GetExtension($path) -ieq '.ico') {
            $icon = [Drawing.Icon]::new($stream)
            $bitmap = $icon.ToBitmap()
        } else {
            $original = [Drawing.Image]::FromStream($stream)
            $bitmap = [Drawing.Bitmap]::new($original)
        }
        $script:GameImages[$appId] = $bitmap
        return $bitmap
    } catch {
        $script:GameImages[$appId] = $null
        return $null
    } finally {
        if ($icon) { $icon.Dispose() }
        if ($original) { $original.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

function Dispose-GameImages {
    foreach ($value in $script:GameImages.Values) { if ($value) { $value.Dispose() } }
    $script:GameImages.Clear()
}
