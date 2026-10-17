$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SteamLibraryManager.CloneStatus.ps1')
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('sgc-worker-test-' + [guid]::NewGuid().ToString('N'))
$root = Join-Path $sandbox 'Steam'
$destination = Join-Path $sandbox 'SecondLibrary'
$work = Join-Path $sandbox 'job'
try {
    foreach ($library in @($root, $destination)) {
        [IO.Directory]::CreateDirectory((Join-Path $library 'steamapps\common')) | Out-Null
    }
    [IO.Directory]::CreateDirectory($work) | Out-Null
    $vdf = '"libraryfolders" { "0" { "path" "' + $root.Replace('\','\\') + '" } "1" { "path" "' + $destination.Replace('\','\\') + '" } }'
    [IO.File]::WriteAllText((Join-Path $root 'steamapps\libraryfolders.vdf'), $vdf)
    $sourcePath = Join-Path $root 'steamapps\common\Demo'
    [IO.Directory]::CreateDirectory($sourcePath) | Out-Null
    $bytes = New-Object byte[] (8MB)
    [IO.File]::WriteAllBytes((Join-Path $sourcePath 'demo.bin'), $bytes)
    $source = [pscustomobject]@{ Name = 'Original'; Path = $sourcePath }
    $game = [pscustomobject]@{ AppId = '123'; Name = 'Demo'; Versions = @($source) }
    [IO.File]::WriteAllText((Join-Path $root 'steamapps\appmanifest_123.acf'), '"AppState" { "appid" "123" "name" "Demo" "installdir" "Demo" }')
    function Invoke-Worker([string]$name, [bool]$cancel) {
        $requestPath = Join-Path $work 'request.json'
        $cancelPath = Join-Path $work 'cancel'
        Get-ChildItem -LiteralPath $work -Filter 'status-*.json' -File -ErrorAction SilentlyContinue | Remove-Item -Force
        Remove-Item -LiteralPath $cancelPath -Force -ErrorAction SilentlyContinue
        $request = [pscustomobject]@{ SteamRoot = $root; Game = $game; Source = $source; Library = $destination; Name = $name; DelayMilliseconds = 50 }
        [IO.File]::WriteAllText($requestPath, (ConvertTo-Json $request -Depth 8))
        $worker = Join-Path $PSScriptRoot 'SteamLibraryManager.CloneWorker.ps1'
        $errorPath = Join-Path $work 'worker-error.txt'
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $worker + '"'),'-RequestPath',('"' + $requestPath + '"')) -PassThru -WindowStyle Hidden -RedirectStandardError $errorPath
        try {
            $deadline = (Get-Date).AddSeconds(30)
            $sawCopying = $false
            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 100
                try { $status = Read-LatestCloneStatus $work } catch { continue }
                if ($status) {
                    if ($status.Phase -eq 'Copying') {
                        $sawCopying = $true
                        if ($cancel) { [IO.File]::WriteAllText($cancelPath, 'cancel') }
                    }
                    if ($status.Phase -in @('Done','Error','Cancelled')) { break }
                }
                $process.Refresh()
                if ($process.HasExited) { break }
            }
            if (-not $process.WaitForExit(5000)) { throw 'Worker did not stop.' }
            if (-not $sawCopying) { throw "Worker did not report asynchronous copy progress: $($status.Phase): $($status.Message): $(Get-Content $errorPath -Raw)" }
            return $status
        } finally {
            if (-not $process.HasExited) { $process.Kill() }
            $process.Dispose()
        }
    }
    $done = Invoke-Worker 'Successful Copy' $false
    if ($done.Phase -ne 'Done' -or -not (Test-Path -LiteralPath (Join-Path $done.Destination 'demo.bin'))) { throw "Successful clone failed: $($done.Message)" }
    $cancelled = Invoke-Worker 'Cancelled Copy' $true
    if ($cancelled.Phase -ne 'Cancelled') { throw "Cancellation failed: $($cancelled.Phase): $($cancelled.Message)" }
    if (Test-Path -LiteralPath (Join-Path $destination 'steamapps\common\Cancelled Copy')) { throw 'Cancelled folder remained.' }
    if (@(Get-ChildItem -LiteralPath (Join-Path $destination 'steamapps\common') -Filter '.steamlibrarymanager-partial-*').Count) { throw 'Partial staging folder remained.' }
    $lockWork = Join-Path $sandbox 'locked-status'
    [IO.Directory]::CreateDirectory($lockWork) | Out-Null
    Publish-CloneStatus $lockWork ([pscustomobject]@{ Phase = 'First'; Message = 'Initial snapshot' })
    $firstStatus = Join-Path $lockWork 'status-0000000001.json'
    $lock = [IO.File]::Open($firstStatus, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        Publish-CloneStatus $lockWork ([pscustomobject]@{ Phase = 'Test'; Message = 'Locked older snapshot' })
        if ((Read-LatestCloneStatus $lockWork).Phase -ne 'Test') { throw 'New status could not be published while an older status was locked.' }
    } finally { $lock.Dispose() }
    Write-Output 'Clone worker PASS: progress, completed copy, cancellation cleanup.'
} finally {
    if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
