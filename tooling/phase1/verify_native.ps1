param(
    [string]$Executable = "$PSScriptRoot\..\..\build\windows\x64\runner\Debug\ephtodo.exe",
    [string]$OutFile = "$PSScriptRoot\..\..\.phase1\native-verification.json"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force (Split-Path $OutFile) | Out-Null
Get-Process ephtodo -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
$env:EPHTODO_PHASE1_NATIVE_VERIFY = '1'
$process = Start-Process -FilePath $Executable -ArgumentList '--phase1-native-verify' -PassThru

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class Phase1Win32Check {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    public const int GwlExStyle = -20;
    public const int WsExTopmost = 0x00000008;
    public const uint GwHwndNext = 2;
}
"@

function Get-AppWindows {
    $found = New-Object System.Collections.ArrayList
    $callback = {
        param($handle, $unused)
        $windowProcessId = [uint32]0
        [void][Phase1Win32Check]::GetWindowThreadProcessId($handle, [ref]$windowProcessId)
        $length = [Phase1Win32Check]::GetWindowTextLength($handle)
        if ($length -gt 0) {
            $text = New-Object System.Text.StringBuilder ($length + 1)
            [void][Phase1Win32Check]::GetWindowText($handle, $text, $text.Capacity)
            if ($text.ToString() -eq 'ephtodo' -or
                $text.ToString() -eq 'ephtodo sticky') {
                [void]$found.Add([pscustomobject]@{
                    Hwnd = $handle
                    ProcessId = $windowProcessId
                    Title = $text.ToString()
                })
            }
        }
        return $true
    }
    [void][Phase1Win32Check]::EnumWindows($callback, [IntPtr]::Zero)
    return $found
}

function Get-ZOrderIndex([IntPtr]$target) {
    $index = 0
    $handle = [Phase1Win32Check]::GetTopWindow([IntPtr]::Zero)
    while ($handle -ne [IntPtr]::Zero) {
        if ($handle -eq $target) { return $index }
        $index++
        $handle = [Phase1Win32Check]::GetWindow($handle, [Phase1Win32Check]::GwHwndNext)
    }
    return -1
}

try {
    $windows = @()
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 500
        $windows = @(Get-AppWindows)
        if (($windows | Where-Object { $_.Title -eq 'ephtodo' }) -and
            ($windows | Where-Object { $_.Title -eq 'ephtodo sticky' })) {
            break
        }
    }
    $stickyInfo = $windows | Where-Object { $_.Title -like '*sticky*' } | Select-Object -First 1
    $mainInfo = $windows | Where-Object { $_.Title -eq 'ephtodo' } | Select-Object -First 1
    if (-not $stickyInfo -or -not $mainInfo) {
        throw "Expected main and sticky HWNDs were not found: $($windows | ConvertTo-Json -Compress)"
    }
    Start-Sleep -Seconds 2

    $sticky = [IntPtr]$stickyInfo.Hwnd
    $main = [IntPtr]$mainInfo.Hwnd
    $stickyStyle = [Phase1Win32Check]::GetWindowLong(
        $sticky, [Phase1Win32Check]::GwlExStyle
    )
    $mainStyle = [Phase1Win32Check]::GetWindowLong(
        $main, [Phase1Win32Check]::GwlExStyle
    )
    [void][Phase1Win32Check]::SetForegroundWindow($main)
    Start-Sleep -Milliseconds 800
    $stickyZ = Get-ZOrderIndex $sticky
    $mainZ = Get-ZOrderIndex $main

    $result = [ordered]@{
        executable = 'production ephtodo Debug build'
        distinctHwnds = ($sticky -ne $main)
        sameProcess = ($stickyInfo.ProcessId -eq $mainInfo.ProcessId)
        stickyHasWsExTopmost = (($stickyStyle -band [Phase1Win32Check]::WsExTopmost) -ne 0)
        mainHasWsExTopmost = (($mainStyle -band [Phase1Win32Check]::WsExTopmost) -ne 0)
        stickyVisible = [Phase1Win32Check]::IsWindowVisible($sticky)
        stickyZIndex = $stickyZ
        foregroundMainZIndex = $mainZ
        stickyAboveForegroundMain = ($stickyZ -ge 0 -and $mainZ -ge 0 -and $stickyZ -lt $mainZ)
        checkedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    $result | ConvertTo-Json | Set-Content -Path $OutFile -Encoding UTF8
    $result | ConvertTo-Json
    if (-not $result.distinctHwnds -or
        -not $result.sameProcess -or
        -not $result.stickyHasWsExTopmost -or
        $result.mainHasWsExTopmost -or
        -not $result.stickyVisible -or
        -not $result.stickyAboveForegroundMain) {
        throw 'One or more native verification assertions failed.'
    }
} finally {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
}
