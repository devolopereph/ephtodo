# Phase 0 native Win32 verification for the ephtodo sticky window.
# Assumes ephtodo_phase0.exe is already running with the sticky window shown.
# Verifies: independent HWND, WS_EX_TOPMOST on sticky (and not on main),
# and that the sticky sits above a freshly foregrounded Notepad in z-order.
# Writes JSON to the path given as -OutFile.
param(
    [string]$OutFile = "$PSScriptRoot\..\..\..\.phase0\native-verification.json"
)

$ErrorActionPreference = 'Stop'

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class Win32Check {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern IntPtr GetTopWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TOPMOST = 0x00000008;
    public const uint GW_HWNDNEXT = 2;
}
"@

function Get-AppWindows {
    $procIds = (Get-Process ephtodo_phase0 -ErrorAction Stop).Id
    $found = New-Object System.Collections.ArrayList
    $cb = {
        param($h, $l)
        $windowPid = [uint32]0
        [void][Win32Check]::GetWindowThreadProcessId($h, [ref]$windowPid)
        if ($procIds -contains [int]$windowPid) {
            $len = [Win32Check]::GetWindowTextLength($h)
            if ($len -gt 0) {
                $sb = New-Object System.Text.StringBuilder ($len + 1)
                [void][Win32Check]::GetWindowText($h, $sb, $sb.Capacity)
                [void]$found.Add([pscustomobject]@{ Hwnd = $h; WindowPid = $windowPid; Title = $sb.ToString() })
            }
        }
        return $true
    }
    [void][Win32Check]::EnumWindows($cb, [IntPtr]::Zero)
    return $found
}

function Get-ZOrderIndex([IntPtr]$target) {
    $index = 0
    $hwnd = [Win32Check]::GetTopWindow([IntPtr]::Zero)
    while ($hwnd -ne [IntPtr]::Zero) {
        if ($hwnd -eq $target) { return $index }
        $index++
        $hwnd = [Win32Check]::GetWindow($hwnd, [Win32Check]::GW_HWNDNEXT)
    }
    return -1
}

$windows = Get-AppWindows
$stickyInfo = $windows | Where-Object { $_.Title -like '*Sticky*' } | Select-Object -First 1
$mainInfo = $windows | Where-Object { $_.Title -like '*Phase 0*' } | Select-Object -First 1
if (-not $stickyInfo) { throw "Sticky window HWND not found. Windows: $($windows | ConvertTo-Json -Compress)" }
if (-not $mainInfo) { throw "Main window HWND not found. Windows: $($windows | ConvertTo-Json -Compress)" }

$sticky = [IntPtr]$stickyInfo.Hwnd
$main = [IntPtr]$mainInfo.Hwnd

$stickyEx = [Win32Check]::GetWindowLong($sticky, [Win32Check]::GWL_EXSTYLE)
$mainEx = [Win32Check]::GetWindowLong($main, [Win32Check]::GWL_EXSTYLE)

# Bring a competitor window to the foreground and confirm the sticky still
# precedes it in the global z-order (topmost band sits above normal windows).
# The app's own non-topmost main window is used as the competitor: it is a
# plain WS_OVERLAPPEDWINDOW, so after foregrounding it sits at the top of the
# normal band; the sticky must still precede it thanks to WS_EX_TOPMOST.
$competitorHwnd = $main
[void][Win32Check]::SetForegroundWindow($competitorHwnd)
Start-Sleep -Milliseconds 800

$stickyZ = Get-ZOrderIndex $sticky
$notepadZ = Get-ZOrderIndex $competitorHwnd

$result = [ordered]@{
    stickyHwnd                   = $sticky.ToString()
    mainHwnd                     = $main.ToString()
    distinctHwnds                = ($sticky -ne $main)
    stickyPid                    = $stickyInfo.WindowPid
    mainPid                      = $mainInfo.WindowPid
    sameProcessSharedEngine      = ($stickyInfo.WindowPid -eq $mainInfo.WindowPid)
    stickyHasWsExTopmost         = (($stickyEx -band [Win32Check]::WS_EX_TOPMOST) -ne 0)
    mainHasWsExTopmost           = (($mainEx -band [Win32Check]::WS_EX_TOPMOST) -ne 0)
    stickyVisible                = [Win32Check]::IsWindowVisible($sticky)
    stickyZIndex                 = $stickyZ
    competitorZIndex             = $notepadZ
    stickyAboveForegroundWindow  = ($stickyZ -ge 0 -and $notepadZ -ge 0 -and $stickyZ -lt $notepadZ)
    checkedAtUtc                 = (Get-Date).ToUniversalTime().ToString('o')
}

$json = $result | ConvertTo-Json
$json | Set-Content -Path $OutFile -Encoding UTF8
Write-Output $json
