function Publish-CloneStatus([string]$workDir, $status) {
    if (-not $script:CloneStatusSequence) { $script:CloneStatusSequence = 0 }
    $script:CloneStatusSequence++
    $number = $script:CloneStatusSequence
    $final = Join-Path $workDir ('status-{0:D10}.json' -f $number)
    $temp = "$final.tmp"
    [IO.File]::WriteAllText($temp, (ConvertTo-Json $status -Compress), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temp, $final)
    if ($number -gt 20) {
        $old = Join-Path $workDir ('status-{0:D10}.json' -f ($number - 20))
        try { [IO.File]::Delete($old) } catch { }
    }
}

function Read-LatestCloneStatus([string]$workDir) {
    $latest = Get-ChildItem -LiteralPath $workDir -Filter 'status-*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { return $null }
    return (Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json)
}
