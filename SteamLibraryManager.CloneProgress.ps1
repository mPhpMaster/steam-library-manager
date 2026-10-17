function Start-CloneJob($game, $source, $choice) {
    $workDir = Join-Path ([IO.Path]::GetTempPath()) ('steamlibrarymanager-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($workDir) | Out-Null
    $requestPath = Join-Path $workDir 'request.json'
    $cancelPath = Join-Path $workDir 'cancel'
    $request = [pscustomobject]@{
        SteamRoot = Get-SteamRoot; Game = $game; Source = $source
        Library = $choice.Library; Name = $choice.Name; DelayMilliseconds = 0
    }
    [IO.File]::WriteAllText($requestPath, (ConvertTo-Json $request -Depth 12), [Text.UTF8Encoding]::new($false))
    $workerPath = Join-Path $PSScriptRoot 'SteamLibraryManager.CloneWorker.ps1'
    $process = $null
    $dialog = $null
    try {
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $workerPath + '"'), '-RequestPath', ('"' + $requestPath + '"')) -WindowStyle Hidden -PassThru
        $dialog = New-Object Windows.Forms.Form
        $dialog.Text = 'Cloning Version'; $dialog.ClientSize = New-Object Drawing.Size(620, 250)
        $dialog.StartPosition = 'CenterParent'; $dialog.FormBorderStyle = 'None'
        $dialog.BackColor = $script:Theme.Background; $dialog.ForeColor = $script:Theme.Text
        Add-TitleBar $dialog 'Cloning Version' | Out-Null
        [void](New-Label "Cloning $($source.Name)" 24 56 570 34 16 $true $dialog)
        $message = New-Label 'Checking source size and destination space...' 24 105 570 28 9 $false $dialog
        $bar = New-Object Windows.Forms.ProgressBar
        $bar.SetBounds(24, 146, 572, 20); $bar.Minimum = 0; $bar.Maximum = 100
        $bar.Style = 'Marquee'; $dialog.Controls.Add($bar)
        $cancel = New-Button 'Cancel' 496 190 100 $dialog 'normal' {
            [IO.File]::WriteAllText($cancelPath, 'cancel')
            $cancel.Enabled = $false; $message.Text = 'Cancelling and removing partial files...'
        }
        $state = @{ Result = $null; Finished = $false }
        $timer = New-Object Windows.Forms.Timer
        $timer.Interval = 200
        $timer.Add_Tick({
            try {
                $status = Read-LatestCloneStatus $workDir
                if ($status) {
                    $message.Text = $status.Message
                    if ($status.Phase -eq 'Copying') {
                        $bar.Style = 'Blocks'; $bar.Value = [Math]::Max(0, [Math]::Min(100, [int]$status.Percent))
                    }
                    if ($status.Phase -in @('Done', 'Error', 'Cancelled')) {
                        $state.Result = $status; $state.Finished = $true
                        $timer.Stop(); $dialog.Close(); return
                    }
                }
            } catch { }
            $process.Refresh()
            if ($process.HasExited) {
                $state.Result = [pscustomobject]@{ Phase = 'Error'; Message = 'Clone worker stopped without a final result.' }
                $state.Finished = $true; $timer.Stop(); $dialog.Close()
            }
        }.GetNewClosure())
        $dialog.Add_FormClosing({ param($sender, $event)
            if (-not $state.Finished) {
                $event.Cancel = $true
                [IO.File]::WriteAllText($cancelPath, 'cancel')
                $cancel.Enabled = $false
                $message.Text = 'Cancelling and removing partial files...'
            }
        }.GetNewClosure())
        $timer.Start()
        [void]$dialog.ShowDialog($script:Form)
        return $state.Result
    } finally {
        if ($timer) { $timer.Stop(); $timer.Dispose() }
        if ($dialog) { $dialog.Dispose() }
        if ($process) {
            if (-not $process.HasExited) {
                [IO.File]::WriteAllText($cancelPath, 'cancel')
                [void]$process.WaitForExit(5000)
            }
            $process.Dispose()
        }
        if ($workDir.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path $workDir -Leaf) -like 'steamlibrarymanager-*' -and
            (Test-Path -LiteralPath $workDir)) {
            Remove-Item -LiteralPath $workDir -Recurse -Force
        }
    }
}
