# Build-time template for the registered inline Windows hook command. This file is
# never loaded by PowerShell at runtime; the package builder embeds its contents.
$ErrorActionPreference = 'Stop'
$decision = 'BMU_CODEX_DENY_V1'
$child = $null
$clock = [Diagnostics.Stopwatch]::StartNew()
$deadline = 18000
try {
    # Read only the hook envelope, bounded in memory and by the same overall deadline.
    $inputText = [Text.StringBuilder]::new()
    $inputBuffer = New-Object char[] 4096
    while ($true) {
        $read = [Console]::In.ReadAsync($inputBuffer, 0, $inputBuffer.Length)
        while (-not $read.IsCompleted) {
            if ($clock.ElapsedMilliseconds -ge $deadline) { throw 'input timeout' }
            Start-Sleep -Milliseconds 10
        }
        $count = $read.GetAwaiter().GetResult()
        if ($count -eq 0) { break }
        if ($inputText.Length + $count -gt 262144) { throw 'input too large' }
        [void]$inputText.Append($inputBuffer, 0, $count)
    }

    $node = Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1
    if (-not $node -or -not [IO.Path]::IsPathRooted($node.Source)) { throw 'node unavailable' }
    if (-not $env:PLUGIN_ROOT -or -not [IO.Path]::IsPathRooted($env:PLUGIN_ROOT)) { throw 'plugin root unavailable' }
    $bridge = Join-Path $env:PLUGIN_ROOT 'skills/burn-my-usage/scripts/hook-codex.mjs'
    if (-not [IO.File]::Exists($bridge)) { throw 'bridge unavailable' }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $node.Source
    $info.Arguments = '"' + $bridge + '" --supervised'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [Text.Encoding]::UTF8
    $child = [Diagnostics.Process]::new()
    $child.StartInfo = $info
    if (-not $child.Start()) { throw 'launch failed' }
    $write = $child.StandardInput.WriteAsync($inputText.ToString())
    $inputClosed = $false
    $outBuffer = New-Object char[] 1024
    $errBuffer = New-Object char[] 1024
    $outText = [Text.StringBuilder]::new()
    $errCount = 0
    $outRead = $child.StandardOutput.ReadAsync($outBuffer, 0, $outBuffer.Length)
    $errRead = $child.StandardError.ReadAsync($errBuffer, 0, $errBuffer.Length)
    $outDone = $false
    $errDone = $false
    while ($true) {
        if ($clock.ElapsedMilliseconds -ge $deadline) { throw 'child timeout' }
        if (-not $inputClosed -and $write.IsCompleted) {
            [void]$write.GetAwaiter().GetResult()
            $child.StandardInput.Close()
            $inputClosed = $true
        }
        if (-not $outDone -and $outRead.IsCompleted) {
            $count = $outRead.GetAwaiter().GetResult()
            if ($count -eq 0) { $outDone = $true } else {
                if ($outText.Length + $count -gt 4096) { throw 'stdout too large' }
                [void]$outText.Append($outBuffer, 0, $count)
                $outRead = $child.StandardOutput.ReadAsync($outBuffer, 0, $outBuffer.Length)
            }
        }
        if (-not $errDone -and $errRead.IsCompleted) {
            $count = $errRead.GetAwaiter().GetResult()
            if ($count -eq 0) { $errDone = $true } else {
                $errCount += $count
                if ($errCount -gt 4096) { throw 'stderr too large' }
                $errRead = $child.StandardError.ReadAsync($errBuffer, 0, $errBuffer.Length)
            }
        }
        if ($child.HasExited -and $outDone -and $errDone -and $inputClosed) { break }
        Start-Sleep -Milliseconds 10
    }
    if ($child.ExitCode -ne 0) { throw 'child failed' }
    if ($outText.ToString() -ceq "BMU_CODEX_ALLOW_V1`n") { $decision = 'BMU_CODEX_ALLOW_V1' }
    elseif ($outText.ToString() -cne "BMU_CODEX_DENY_V1`n") { throw 'invalid response' }
} catch {
    $decision = 'BMU_CODEX_DENY_V1'
} finally {
    if ($child) {
        try {
            if (-not $child.HasExited) {
                $killer = [Diagnostics.ProcessStartInfo]::new()
                $killer.FileName = Join-Path $env:SystemRoot 'System32\taskkill.exe'
                $killer.Arguments = '/PID ' + $child.Id + ' /T /F'
                $killer.UseShellExecute = $false
                $killer.CreateNoWindow = $true
                $killer.RedirectStandardOutput = $true
                $killer.RedirectStandardError = $true
                $stopper = [Diagnostics.Process]::Start($killer)
                if (-not $stopper.WaitForExit(1500)) { $stopper.Kill() }
                if (-not $child.HasExited) { $child.Kill() }
            }
        } catch { $decision = 'BMU_CODEX_DENY_V1' }
        $child.Dispose()
    }
}
Write-Output $decision
