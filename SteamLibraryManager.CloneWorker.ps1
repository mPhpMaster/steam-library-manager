param([Parameter(Mandatory = $true)][string]$RequestPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SteamLibraryManager.Core.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.Clone.ps1')
. (Join-Path $PSScriptRoot 'SteamLibraryManager.CloneStatus.ps1')
$request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
function Get-SteamRoot { return $request.SteamRoot }
$workDir = Split-Path $RequestPath -Parent
$cancelPath = Join-Path $workDir 'cancel'
$stage = $null
$lastUpdate = [DateTime]::MinValue

function Write-CloneStatus([string]$phase, [string]$message, [long]$copied = 0, [long]$total = 0, [string]$destination = '', [string]$name = '') {
    $percent = if ($total -gt 0) { [Math]::Min(100, [int][Math]::Floor($copied * 100.0 / $total)) } else { 0 }
    $status = [pscustomobject]@{
        Phase = $phase; Message = $message; Percent = $percent
        Copied = $copied; Total = $total; Destination = $destination; Name = $name
    }
    Publish-CloneStatus $workDir $status
}
function Assert-NotCancelled {
    if (Test-Path -LiteralPath $cancelPath) { throw [OperationCanceledException]::new('Clone cancelled.') }
}
function Update-CopyProgress([long]$copied, [long]$total, [string]$fileName) {
    if (((Get-Date) - $script:lastUpdate).TotalMilliseconds -ge 200 -or $copied -eq $total) {
        Write-CloneStatus 'Copying' "Copying $fileName" $copied $total
        $script:lastUpdate = Get-Date
    }
}
try {
    Write-CloneStatus 'Scanning' 'Checking source size and destination space...'
    Assert-NotCancelled
    $plan = Get-ClonePlan $request.Game $request.Source $request.Library $request.Name $request.Name
    Assert-NotCancelled
    $common = Join-Path (Join-Path $plan.Library 'steamapps') 'common'
    $stage = Join-Path $common ('.steamlibrarymanager-partial-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($stage) | Out-Null
    $pending = New-Object 'System.Collections.Generic.Stack[object]'
    $pending.Push([pscustomobject]@{ Source = $request.Source.Path; Target = $stage })
    $copied = [long]0
    Write-CloneStatus 'Copying' 'Copying game files...' $copied $plan.Size
    while ($pending.Count -gt 0) {
        Assert-NotCancelled
        $pair = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $pair.Source -Force -ErrorAction Stop)) {
            Assert-NotCancelled
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Source contains a link or junction: $($item.FullName)" }
            $target = Join-Path $pair.Target $item.Name
            if ($item.PSIsContainer) {
                [IO.Directory]::CreateDirectory($target) | Out-Null
                $pending.Push([pscustomobject]@{ Source = $item.FullName; Target = $target })
                continue
            }
            $inputStream = $null; $outputStream = $null
            try {
                $inputStream = [IO.File]::OpenRead($item.FullName)
                $outputStream = [IO.File]::Create($target)
                $buffer = New-Object byte[] (1MB)
                while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    Assert-NotCancelled
                    $outputStream.Write($buffer, 0, $read)
                    $copied += $read
                    Update-CopyProgress $copied $plan.Size $item.Name
                    if ($request.DelayMilliseconds -gt 0) { Start-Sleep -Milliseconds ([int]$request.DelayMilliseconds) }
                }
            } finally {
                if ($outputStream) { $outputStream.Dispose() }
                if ($inputStream) { $inputStream.Dispose() }
            }
        }
    }
    Assert-NotCancelled
    if (Test-Path -LiteralPath $plan.Destination) { throw 'Destination folder was created while cloning; no files were overwritten.' }
    [IO.Directory]::Move($stage, $plan.Destination)
    $stage = $null
    Write-CloneStatus 'Done' 'Clone completed.' $copied $plan.Size $plan.Destination $plan.Name
    exit 0
} catch {
    $phase = if ($_.Exception -is [OperationCanceledException]) { 'Cancelled' } else { 'Error' }
    $message = $_.Exception.Message
    if ($stage -and (Test-Path -LiteralPath $stage)) {
        try {
            $full = [IO.Path]::GetFullPath($stage)
            $parent = [IO.Path]::GetFullPath((Split-Path $full -Parent))
            if ((Split-Path $parent -Leaf) -eq 'common' -and (Split-Path $full -Leaf) -like '.steamlibrarymanager-partial-*') {
                [IO.Directory]::Delete($full, $true)
            }
        } catch { $message += " Partial files remain at $stage" }
    }
    Write-CloneStatus $phase $message
    exit 1
}
