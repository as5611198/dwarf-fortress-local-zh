param([Parameter(Mandatory)][string]$LauncherPath)
$ErrorActionPreference = 'Stop'
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('df-launcher-test-' + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $testDirectory | Out-Null
$children = @()
try {
    Copy-Item -LiteralPath $LauncherPath -Destination (Join-Path $testDirectory 'launcher.dll')
    $probe = @'
$child = Start-Process powershell.exe -ArgumentList '-NoProfile -NonInteractive -WindowStyle Hidden -Command Start-Sleep -Seconds 60' -WindowStyle Hidden -PassThru
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'pids.txt') -Value @($PID, $child.Id)
Start-Sleep -Seconds 60
'@
    Set-Content -LiteralPath (Join-Path $testDirectory 'Start-Broker.ps1') -Value $probe -Encoding UTF8
    $compiler = 'C:\Program Files\AMD\ROCm\7.2\bin\clang++.exe'
    $hostPath = Join-Path $testDirectory 'host.exe'
    & $compiler '-std=c++17' (Join-Path $PSScriptRoot 'launcher-host.cpp') '-o' $hostPath
    if ($LASTEXITCODE -ne 0) { throw 'Test host compilation failed.' }
    $hostProcess = Start-Process -FilePath $hostPath -ArgumentList ('"' + (Join-Path $testDirectory 'launcher.dll') + '"') -WindowStyle Hidden -PassThru
    if (-not $hostProcess.WaitForExit(12000)) { throw 'Test host did not exit.' }
    if ($hostProcess.ExitCode -ne 0) { throw ('Test host failed: ' + $hostProcess.ExitCode) }
    $children = @(Get-Content -LiteralPath (Join-Path $testDirectory 'pids.txt') | ForEach-Object { Get-Process -Id ([int]$_) -ErrorAction SilentlyContinue })
    Start-Sleep -Milliseconds 500
    $survivors = @($children | Where-Object { -not $_.HasExited })
    if ($survivors.Count) { throw ('Launcher descendants survived host exit: ' + ($survivors.Id -join ', ')) }
    Write-Output 'PASS: launcher and grandchild exit with host.'
}
finally {
    foreach ($child in $children) { if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() } }
    $resolved = [IO.Path]::GetFullPath($testDirectory)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
