$ErrorActionPreference = 'Stop'
$brokerDirectory = $PSScriptRoot
$gameRoot = (Get-Location).Path
if (-not (Test-Path -LiteralPath (Join-Path $gameRoot 'dfhack-config'))) {
    $probe = Get-Item -LiteralPath $brokerDirectory
    while ($probe -and -not (Test-Path -LiteralPath (Join-Path $probe.FullName 'dfhack-config'))) {
        $probe = $probe.Parent
    }
    if ($probe) { $gameRoot = $probe.FullName }
}
$stateDirectory = Join-Path $gameRoot 'dfhack-config\mods\df-local-zh-complete'
$env:DF_LOCAL_ZH_GAME_ROOT = $gameRoot
New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
$rimworldConfig = Join-Path $env:USERPROFILE 'AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\Mod_AI_TranslationCore_AutoTranslatorMod.xml'
if (Test-Path -LiteralPath $rimworldConfig) { $env:DF_LOCAL_ZH_RIMWORLD_CONFIG = $rimworldConfig }
$mutex = [Threading.Mutex]::new($false, 'Local\DFTraditionalBroker19753')
$locked = $false
try {
    $locked = $mutex.WaitOne(5000)
    if (-not $locked) { throw 'Translation broker startup is already in progress.' }
    $health = $null
    try { $health = Invoke-RestMethod -Uri 'http://127.0.0.1:19753/health' -TimeoutSec 2 }
    catch { }
    if ($health) {
        if ($health.service -ne 'df-local-zh' -or $health.language -notin @('zh-Hant', 'zh-Hans')) {
            throw 'Port 19753 belongs to another service.'
        }
        Write-Output 'Translation broker is ready.'
        return
    }
    $nodeExecutable = if ($env:DF_LOCAL_ZH_NODE) { $env:DF_LOCAL_ZH_NODE } else { (Get-Command node.exe -ErrorAction Stop).Source }
    $env:DF_LOCAL_ZH_STATE_DIRECTORY = $stateDirectory
    $stdout = Join-Path $stateDirectory 'server.stdout.log'
    $stderr = Join-Path $stateDirectory 'server.stderr.log'
    $arguments = @(('"' + (Join-Path $brokerDirectory 'server.mjs') + '"'), ('"' + (Join-Path $brokerDirectory 'config.json') + '"'), ('"' + $stateDirectory + '"'))
    $started = Start-Process -FilePath $nodeExecutable -ArgumentList $arguments -WorkingDirectory $brokerDirectory -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        Start-Sleep -Milliseconds 150
        try { $health = Invoke-RestMethod -Uri 'http://127.0.0.1:19753/health' -TimeoutSec 1 }
        catch { }
        $started.Refresh()
    } while (-not $health -and -not $started.HasExited -and [DateTime]::UtcNow -lt $deadline)
    if (-not $health -or $health.service -ne 'df-local-zh') { throw 'Translation broker failed to start. Check its local logs.' }
    Write-Output ('Translation broker ready. PID=' + $started.Id)
}
finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
