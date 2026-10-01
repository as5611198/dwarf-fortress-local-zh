param([Parameter(Mandatory)][string]$PackageRoot)
$ErrorActionPreference='Stop'
$fixtureDirectory=Join-Path ([IO.Path]::GetTempPath()) ('df-rust-launcher-'+[Guid]::NewGuid())
$fixtureBroker=Join-Path $fixtureDirectory 'broker'
$fixtureState=Join-Path $fixtureDirectory 'dfhack-config/mods/df-local-zh-complete'
$fixtureHost=$null
$originalPath=$env:PATH
try {
    New-Item -ItemType Directory -Path $fixtureBroker,$fixtureState -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PackageRoot 'broker/df-broker-launch.dll') -Destination $fixtureBroker
    Copy-Item -LiteralPath (Join-Path $PackageRoot 'broker/df-local-zh-broker.exe') -Destination $fixtureBroker
    $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $listener.Start();$fixturePort=$listener.LocalEndpoint.Port;$listener.Stop()
    [IO.File]::WriteAllText((Join-Path $fixtureBroker 'config.json'),(@{port=$fixturePort;language='zh-Hant'} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $fixtureState 'settings.json'),(@{version=1;defaults=@{officialAutoDownload=$false;apiEnabled=$false};saves=@{}} | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $hostExe=Join-Path $PSScriptRoot 'launcher-host.exe'
    $env:PATH=Join-Path $env:SystemRoot 'System32'
    $fixtureHost=Start-Process -FilePath $hostExe -ArgumentList ('"'+(Join-Path $fixtureBroker 'df-broker-launch.dll')+'"') -WorkingDirectory $fixtureDirectory -WindowStyle Hidden -PassThru
    $health=$null
    $deadline=[DateTime]::UtcNow.AddSeconds(3)
    do {
        try {$health=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$fixturePort+'/health') -TimeoutSec 1} catch {}
        if(-not $health){Start-Sleep -Milliseconds 50}
    } while(-not $health -and [DateTime]::UtcNow -lt $deadline)
    if($health.engine -ne 'rust'){throw 'Native launcher did not start bundled Rust Broker.'}
    if(-not $fixtureHost.WaitForExit(7000)){throw 'Fixture host did not exit.'}
    if($fixtureHost.ExitCode -ne 0){throw 'Fixture host failed.'}
    Start-Sleep -Milliseconds 100
    if(Get-NetTCPConnection -LocalPort $fixturePort -State Listen -ErrorAction SilentlyContinue){throw 'Rust Broker survived owning game process exit.'}
    Write-Output 'PASS: native launcher starts Rust without Node; Broker exits with owning process.'
} finally {
    $env:PATH=$originalPath
    if($fixtureHost -and -not $fixtureHost.HasExited){$fixtureHost.Kill();$fixtureHost.WaitForExit()}
    $target=[IO.Path]::GetFullPath($fixtureDirectory)
    $temporaryRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if($target.StartsWith($temporaryRoot,[StringComparison]::OrdinalIgnoreCase)) {Remove-Item -LiteralPath $target -Recurse -Force}
}
