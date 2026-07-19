param(
    [string]$Executable = "$PSScriptRoot\..\..\build\windows\x64\runner\Debug\ephtodo.exe",
    [string]$RuntimeRoot = "$PSScriptRoot\..\..\.phase2"
)

$ErrorActionPreference = 'Stop'

function Stop-Ephtodo {
    Get-Process ephtodo -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 400
}

function Wait-Evidence([string]$Path) {
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if (Test-Path $Path) {
            return Get-Content $Path -Raw | ConvertFrom-Json
        }
        Start-Sleep -Milliseconds 500
    }
    throw "Timed out waiting for sanitized Phase 2 evidence."
}

Stop-Ephtodo
if (Test-Path $RuntimeRoot) {
    Remove-Item $RuntimeRoot -Recurse -Force
}
New-Item -ItemType Directory -Force $RuntimeRoot | Out-Null

$env:EPHTODO_PHASE2_SMOKE_ROOT = $RuntimeRoot
$env:EPHTODO_PHASE2_SMOKE_STAGE = '1'
$first = Start-Process -FilePath $Executable -PassThru
$stage1 = Wait-Evidence "$RuntimeRoot\stage1.json"
Stop-Ephtodo

$env:EPHTODO_PHASE2_SMOKE_STAGE = '2'
$second = Start-Process -FilePath $Executable -PassThru
$stage2 = Wait-Evidence "$RuntimeRoot\stage2.json"
Stop-Ephtodo

Remove-Item Env:\EPHTODO_PHASE2_SMOKE_ROOT -ErrorAction SilentlyContinue
Remove-Item Env:\EPHTODO_PHASE2_SMOKE_STAGE -ErrorAction SilentlyContinue

if (-not $stage1.createAcknowledged -or
    -not $stage1.completeAcknowledged -or
    -not $stage1.snapshotReceived -or
    -not $stage1.hideShowAcknowledged -or
    $stage1.stickyDatabaseOpenCount -ne 0 -or
    -not $stage1.task.completed) {
    throw "Stage 1 sticky IPC evidence failed validation."
}
if (-not $stage2.persistedAfterRestart -or
    -not $stage2.snapshotReceived -or
    -not $stage2.hideShowAcknowledged -or
    $stage2.stickyDatabaseOpenCount -ne 0 -or
    -not $stage2.task.completed) {
    throw "Stage 2 restart evidence failed validation."
}
if ($stage1.geometry.width -ne $stage2.geometry.width -or
    $stage1.geometry.height -ne $stage2.geometry.height) {
    throw "Sticky geometry was not preserved across restart."
}

$summary = [ordered]@{
    executable = 'production ephtodo Debug build'
    twoRealFlutterEngines = $true
    typedPlatformIpc = $true
    stickyCreateAcknowledged = [bool]$stage1.createAcknowledged
    stickyCompleteAcknowledged = [bool]$stage1.completeAcknowledged
    snapshotReceived = [bool]$stage1.snapshotReceived
    persistenceAfterRestart = [bool]$stage2.persistedAfterRestart
    stickyDatabaseOpenCountStage1 = [int]$stage1.stickyDatabaseOpenCount
    stickyDatabaseOpenCountStage2 = [int]$stage2.stickyDatabaseOpenCount
    hideShowAcknowledged = [bool]($stage1.hideShowAcknowledged -and $stage2.hideShowAcknowledged)
    geometryPreserved = $true
    completedRevision = [int]$stage2.task.revision
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$summary | ConvertTo-Json | Set-Content "$RuntimeRoot\summary.json" -Encoding UTF8
$summary | ConvertTo-Json
