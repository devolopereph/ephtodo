param(
    [string]$Executable = "$PSScriptRoot\..\..\build\windows\x64\runner\Debug\ephtodo.exe",
    [string]$RuntimeRoot = "$PSScriptRoot\..\..\.phase34"
)

$ErrorActionPreference = 'Stop'

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class Phase34Win32 {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint command);
    public const int GwlExStyle = -20;
    public const int WsExTopmost = 8;
    public const uint GwHwndNext = 2;
}
"@

function Stop-App {
    Get-Process ephtodo -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

function Get-Windows {
    $found = New-Object System.Collections.ArrayList
    $callback = {
        param($handle, $unused)
        $length = [Phase34Win32]::GetWindowTextLength($handle)
        if ($length -gt 0) {
            $text = New-Object System.Text.StringBuilder ($length + 1)
            [void][Phase34Win32]::GetWindowText($handle, $text, $text.Capacity)
            if ($text.ToString() -like 'ephtodo*') {
                $pidValue = [uint32]0
                [void][Phase34Win32]::GetWindowThreadProcessId($handle, [ref]$pidValue)
                [void]$found.Add([pscustomobject]@{
                    Hwnd = $handle
                    ProcessId = $pidValue
                    Title = $text.ToString()
                    Visible = [Phase34Win32]::IsWindowVisible($handle)
                    Topmost = (([Phase34Win32]::GetWindowLong(
                        $handle, [Phase34Win32]::GwlExStyle
                    ) -band [Phase34Win32]::WsExTopmost) -ne 0)
                })
            }
        }
        return $true
    }
    [void][Phase34Win32]::EnumWindows($callback, [IntPtr]::Zero)
    return $found
}

function Get-ZOrderIndex([IntPtr]$Target) {
    $index = 0
    $handle = [Phase34Win32]::GetTopWindow([IntPtr]::Zero)
    while ($handle -ne [IntPtr]::Zero) {
        if ($handle -eq $Target) { return $index }
        $index++
        $handle = [Phase34Win32]::GetWindow($handle, [Phase34Win32]::GwHwndNext)
    }
    return -1
}

function Wait-Evidence([int]$Stage) {
    for ($attempt = 0; $attempt -lt 80; $attempt++) {
        if ((Test-Path "$RuntimeRoot\quick-note.json") -and
            (Test-Path "$RuntimeRoot\stage$Stage.json")) {
            $windows = @(Get-Windows)
            if ($windows.Count -ge 3) {
                return [ordered]@{
                    Windows = $windows
                    QuickNote = Get-Content "$RuntimeRoot\quick-note.json" -Raw | ConvertFrom-Json
                    Sticky = Get-Content "$RuntimeRoot\stage$Stage.json" -Raw | ConvertFrom-Json
                }
            }
        }
        Start-Sleep -Milliseconds 500
    }
    throw 'Timed out waiting for three production windows and Quick Note IPC evidence.'
}

Stop-App
if (Test-Path $RuntimeRoot) { Remove-Item $RuntimeRoot -Recurse -Force }
New-Item -ItemType Directory -Force $RuntimeRoot | Out-Null
$env:EPHTODO_PHASE34_SMOKE_ROOT = $RuntimeRoot
$env:EPHTODO_PHASE34_SMOKE_STAGE = '1'
$first = Start-Process -FilePath $Executable -PassThru
$stage1 = Wait-Evidence 1
Stop-App

Remove-Item "$RuntimeRoot\quick-note.json" -ErrorAction SilentlyContinue
$env:EPHTODO_PHASE34_SMOKE_STAGE = '2'
$second = Start-Process -FilePath $Executable -PassThru
$stage2 = Wait-Evidence 2
Remove-Item Env:\EPHTODO_PHASE34_SMOKE_ROOT -ErrorAction SilentlyContinue
Remove-Item Env:\EPHTODO_PHASE34_SMOKE_STAGE -ErrorAction SilentlyContinue

$main = $stage2.Windows | Where-Object { $_.Title -eq 'ephtodo' } | Select-Object -First 1
$sticky = $stage2.Windows | Where-Object { $_.Title -like '*sticky*' } | Select-Object -First 1
$quick = $stage2.Windows | Where-Object { $_.Title -like '*quick note*' } | Select-Object -First 1
[void][Phase34Win32]::SetForegroundWindow($main.Hwnd)
Start-Sleep -Milliseconds 500
$settledWindows = @(Get-Windows)
$mainIndex = Get-ZOrderIndex ([IntPtr]$main.Hwnd)
$stickyIndex = Get-ZOrderIndex ([IntPtr]$sticky.Hwnd)
$result = [ordered]@{
    productionDebugExecutable = $true
    threeDistinctHwnds = (@($stage2.Windows.Hwnd | Select-Object -Unique).Count -ge 3)
    sameProcess = (@($stage2.Windows.ProcessId | Select-Object -Unique).Count -eq 1)
    stickyTopmost = [bool]$sticky.Topmost
    mainNotTopmost = -not [bool]$main.Topmost
    quickNoteNotTopmost = -not [bool]$quick.Topmost
    allVisible = [bool]($main.Visible -and $sticky.Visible -and $quick.Visible)
    stickyAboveForegroundMain = ($stickyIndex -ge 0 -and $mainIndex -ge 0 -and
        $stickyIndex -lt $mainIndex)
    stickyZIndex = $stickyIndex
    foregroundMainZIndex = $mainIndex
    stickyDatabaseOpenCount = [int]$stage2.Sticky.stickyDatabaseOpenCount
    stickyTaskCreatedAndCompletedThroughTypedIpc = [bool](
        $stage1.Sticky.createAcknowledged -and
        $stage1.Sticky.completeAcknowledged -and
        $stage1.Sticky.task.completed
    )
    stickyTaskPresentAfterRestart = [bool]$stage2.Sticky.persistedAfterRestart
    stickyHideShowAcknowledged = [bool]$stage2.Sticky.hideShowAcknowledged
    stickyGeometryRestored = [bool](
        [double]$stage1.Sticky.geometry.x -eq [double]$stage2.Sticky.geometry.x -and
        [double]$stage1.Sticky.geometry.y -eq [double]$stage2.Sticky.geometry.y -and
        [double]$stage1.Sticky.geometry.width -eq [double]$stage2.Sticky.geometry.width -and
        [double]$stage1.Sticky.geometry.height -eq [double]$stage2.Sticky.geometry.height
    )
    quickNoteDatabaseOpenCount = [int]$stage2.QuickNote.secondaryDatabaseOpenCount
    noteCreatedThroughTypedIpc = [bool]$stage1.QuickNote.noteCreatedThroughTypedIpc
    notePresentAfterRestart = [bool]$stage2.QuickNote.noteIdPresent
    noteRevisionAfterRestart = [int]$stage2.QuickNote.revision
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$result | ConvertTo-Json | Set-Content "$RuntimeRoot\summary.json" -Encoding UTF8
$result | ConvertTo-Json
Stop-App

if (-not $result.threeDistinctHwnds -or -not $result.sameProcess -or
    -not $result.stickyTopmost -or -not $result.mainNotTopmost -or
    -not $result.quickNoteNotTopmost -or -not $result.allVisible -or
    -not $result.stickyAboveForegroundMain -or
    $result.stickyDatabaseOpenCount -ne 0 -or
    -not $result.stickyTaskCreatedAndCompletedThroughTypedIpc -or
    -not $result.stickyTaskPresentAfterRestart -or
    -not $result.stickyHideShowAcknowledged -or
    -not $result.stickyGeometryRestored -or
    $result.quickNoteDatabaseOpenCount -ne 0 -or
    -not $result.noteCreatedThroughTypedIpc -or
    -not $result.notePresentAfterRestart) {
    throw 'Phase 3/4 production window verification failed.'
}
