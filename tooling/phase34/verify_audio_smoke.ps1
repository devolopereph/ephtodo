param(
    [string]$Executable = "$PSScriptRoot\..\..\build\windows\x64\runner\Debug\ephtodo.exe",
    [string]$RuntimeRoot = "$PSScriptRoot\..\..\.phase34-audio"
)

$ErrorActionPreference = 'Stop'
Get-Process ephtodo -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
if (Test-Path $RuntimeRoot) { Remove-Item $RuntimeRoot -Recurse -Force }
New-Item -ItemType Directory -Force $RuntimeRoot | Out-Null
$env:EPHTODO_AUDIO_SMOKE_ROOT = $RuntimeRoot
$process = Start-Process -FilePath $Executable -PassThru `
    -RedirectStandardOutput "$RuntimeRoot\stdout.log" `
    -RedirectStandardError "$RuntimeRoot\stderr.log"
try {
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if (Test-Path "$RuntimeRoot\audio-smoke.json") { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not (Test-Path "$RuntimeRoot\audio-smoke.json")) {
        throw 'Timed out waiting for WAV recording evidence.'
    }
    $result = Get-Content "$RuntimeRoot\audio-smoke.json" -Raw | ConvertFrom-Json
    $result | ConvertTo-Json
    if (-not $result.recorded -or -not $result.pausedAndResumed -or
        -not $result.playedThroughWinmm -or $result.mimeType -ne 'audio/wav' -or
        $result.fileSize -le 44) {
        throw 'WAV record/playback smoke failed.'
    }
} finally {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\EPHTODO_AUDIO_SMOKE_ROOT -ErrorAction SilentlyContinue
}
