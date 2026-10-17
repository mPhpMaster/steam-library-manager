function Invoke-VersionCardActivation([string]$id) {
    Select-Version $id
    Activate-Version $id
}

function Register-CardClick($control, [string]$id) {
    if ($control -is [Windows.Forms.Button]) { return }
    $control.Add_Click({ Select-Version $id }.GetNewClosure())
    $control.Add_DoubleClick({
        try { Invoke-VersionCardActivation $id } catch {
            Write-Activity $_.Exception.Message 'err'
            [Windows.Forms.MessageBox]::Show($script:Form, $_.Exception.Message, 'Steam Library Manager', 'OK', 'Error') | Out-Null
        }
    }.GetNewClosure())
    foreach ($child in $control.Controls) { Register-CardClick $child $id }
}
