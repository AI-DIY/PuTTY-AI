param(
    [string]$ExePath = "",
    [string]$HostName = "ssh.github.com",
    [int]$Port = 443,
    [string]$UserName = "git"
)

$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if (-not $ExePath) {
    $ExePath = Join-Path $root "build\Release\putty.exe"
}
$ExePath = [IO.Path]::GetFullPath($ExePath)

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class PuttyRemoteAutomation
{
    public delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hwnd, EnumProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int length);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder text, int length);
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr hwnd, int id);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
}
'@

function Get-Text([IntPtr]$Handle) {
    $buffer = New-Object Text.StringBuilder 8192
    [PuttyRemoteAutomation]::GetWindowText($Handle, $buffer, $buffer.Capacity) | Out-Null
    return $buffer.ToString()
}

function Get-ProcessWindows([int]$ProcessId) {
    $items = New-Object System.Collections.Generic.List[object]
    [PuttyRemoteAutomation]::EnumWindows({
        param($hwnd, $lParam)
        $pidValue = 0
        [PuttyRemoteAutomation]::GetWindowThreadProcessId($hwnd, [ref]$pidValue) | Out-Null
        if ($pidValue -eq $ProcessId) {
            $title = New-Object Text.StringBuilder 1024
            $class = New-Object Text.StringBuilder 256
            [PuttyRemoteAutomation]::GetWindowText($hwnd, $title, $title.Capacity) | Out-Null
            [PuttyRemoteAutomation]::GetClassName($hwnd, $class, $class.Capacity) | Out-Null
            $items.Add([pscustomobject]@{
                Handle = $hwnd
                Title = $title.ToString()
                Class = $class.ToString()
            })
        }
        return $true
    }, [IntPtr]::Zero) | Out-Null
    return $items
}

function Get-ChildText([IntPtr]$Parent) {
    $texts = New-Object System.Collections.Generic.List[string]
    [PuttyRemoteAutomation]::EnumChildWindows($Parent, {
        param($hwnd, $lParam)
        $text = Get-Text $hwnd
        if ($text) { $texts.Add($text) }
        return $true
    }, [IntPtr]::Zero) | Out-Null
    return ($texts -join "`n")
}

$puttyArguments = @(
    "-ssh", "$UserName@$HostName", "-P", "$Port", "-noagent", "-noshare"
)
$putty = Start-Process -FilePath $ExePath -PassThru -ArgumentList $puttyArguments
$hostKeyObserved = $false
$hostKeyText = ""
$resultText = ""

try {
    $hostKeyWindow = $null
    for ($i = 0; $i -lt 150 -and -not $hostKeyWindow; $i++) {
        Start-Sleep -Milliseconds 100
        $hostKeyWindow = Get-ProcessWindows $putty.Id | Where-Object {
            $_.Class -eq "PuTTYHostKeyDialog" -or
            $_.Title -like "*Security Alert*"
        } | Select-Object -First 1
        if (-not (Get-Process -Id $putty.Id -ErrorAction SilentlyContinue)) {
            throw "PuTTY AI exited before SSH negotiation completed"
        }
    }

    if ($hostKeyWindow) {
        $hostKeyObserved = $true
        $hostKeyText = Get-ChildText $hostKeyWindow.Handle
        $connectOnce = [PuttyRemoteAutomation]::GetDlgItem(
            $hostKeyWindow.Handle, 1000)
        if ($connectOnce -eq [IntPtr]::Zero) {
            throw "SSH host-key dialog did not contain Connect Once"
        }
        [PuttyRemoteAutomation]::PostMessage(
            $hostKeyWindow.Handle, 0x0111, [IntPtr]1000, $connectOnce) | Out-Null
    }

    for ($i = 0; $i -lt 150; $i++) {
        Start-Sleep -Milliseconds 100
        $dialog = Get-ProcessWindows $putty.Id | Where-Object {
            $_.Title -like "*Fatal Error*" -or
            $_.Title -like "*Error*" -or
            $_.Title -like "*Connection*"
        } | Select-Object -First 1
        if ($dialog) {
            $resultText = Get-ChildText $dialog.Handle
            if ($resultText) { break }
        }
        if (-not (Get-Process -Id $putty.Id -ErrorAction SilentlyContinue)) {
            break
        }
    }

    if (-not $hostKeyObserved -and -not $resultText) {
        throw "No SSH host-key or authentication result was observed"
    }
    if ($resultText -and
        $resultText -notmatch
            "authentication|publickey|remote host|connection|host.?key") {
        throw "Unexpected SSH result: $resultText"
    }

    [pscustomobject]@{
        Endpoint = "$HostName`:$Port"
        HostKeyNegotiation = $(if ($hostKeyObserved) { "observed" } else { "cached" })
        AuthenticationStage = $(if ($resultText) { "reached" } else { "connection remained open" })
        Result = $(if ($resultText) { $resultText } else { "SSH session established beyond host-key verification" })
    } | Format-List
}
finally {
    if (Get-Process -Id $putty.Id -ErrorAction SilentlyContinue) {
        Stop-Process -Id $putty.Id -Force
    }
}
