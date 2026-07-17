param(
    [string]$ExePath = "",
    [string]$ArtifactDirectory = "",
    [switch]$Dangerous
)

$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if (-not $ExePath) {
    $ExePath = Join-Path $root "build\Release\putty-ai.exe"
}
if (-not $ArtifactDirectory) {
    $ArtifactDirectory = Join-Path $root "artifacts"
}
$ExePath = [IO.Path]::GetFullPath($ExePath)
$ArtifactDirectory = [IO.Path]::GetFullPath($ArtifactDirectory)
New-Item -ItemType Directory -Force -Path $ArtifactDirectory | Out-Null
$capturePath = Join-Path $ArtifactDirectory "mock-remote-received.txt"
Remove-Item -LiteralPath $capturePath -Force -ErrorAction SilentlyContinue
$aiRegistryPath = "Software\SimonTatham\PuTTY\AI"
$aiRegistrySnapshot = @()
$aiRegistryExisted = $false
$aiRegistryKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($aiRegistryPath)
if ($aiRegistryKey) {
    $aiRegistryExisted = $true
    foreach ($name in $aiRegistryKey.GetValueNames()) {
        $aiRegistrySnapshot += [pscustomobject]@{
            Name = $name
            Value = $aiRegistryKey.GetValue(
                $name, $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            Kind = $aiRegistryKey.GetValueKind($name)
        }
    }
    $aiRegistryKey.Dispose()
}

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class PuttyAiAutomation
{
    public delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hwnd, StringBuilder text, int length);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int length);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool SetWindowText(IntPtr hwnd, string text);

    [DllImport("user32.dll")]
    public static extern IntPtr GetDlgItem(IntPtr hwnd, int id);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageW")]
    public static extern IntPtr SendMessageText(
        IntPtr hwnd, uint message, IntPtr wParam, string text);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageW")]
    public static extern IntPtr SendMessageBuffer(
        IntPtr hwnd, uint message, IntPtr wParam, StringBuilder text);

    [DllImport("user32.dll")]
    public static extern bool IsWindowEnabled(IntPtr hwnd);
}
'@

function Get-WindowText([IntPtr]$Handle) {
    $buffer = New-Object Text.StringBuilder 65536
    [PuttyAiAutomation]::SendMessageBuffer(
        $Handle, 0x000D, [IntPtr]$buffer.Capacity, $buffer) | Out-Null
    return $buffer.ToString()
}

function Find-Window([int]$ProcessId, [string]$ClassName, [string]$TitlePrefix = "") {
    $script:foundWindow = [IntPtr]::Zero
    [PuttyAiAutomation]::EnumWindows({
        param($hwnd, $lParam)
        $pidValue = 0
        [PuttyAiAutomation]::GetWindowThreadProcessId($hwnd, [ref]$pidValue) | Out-Null
        if ($pidValue -ne $ProcessId) { return $true }
        $class = New-Object Text.StringBuilder 256
        $title = New-Object Text.StringBuilder 512
        [PuttyAiAutomation]::GetClassName($hwnd, $class, $class.Capacity) | Out-Null
        [PuttyAiAutomation]::GetWindowText($hwnd, $title, $title.Capacity) | Out-Null
        if ($class.ToString() -eq $ClassName -and
            (!$TitlePrefix -or $title.ToString().StartsWith($TitlePrefix))) {
            $script:foundWindow = $hwnd
            return $false
        }
        return $true
    }, [IntPtr]::Zero) | Out-Null
    return $script:foundWindow
}

$mockScript = Join-Path $PSScriptRoot "mock-services.ps1"
$serverArguments = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $mockScript,
    "-CapturePath", $capturePath
)
if ($Dangerous) { $serverArguments += "-Dangerous" }
$server = Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -PassThru -ArgumentList $serverArguments
$putty = $null

try {
    Start-Sleep -Milliseconds 700
    $putty = Start-Process -FilePath $ExePath -PassThru -ArgumentList @(
        "-raw", "127.0.0.1", "-P", "18022"
    )

    $main = [IntPtr]::Zero
    for ($i = 0; $i -lt 50 -and $main -eq [IntPtr]::Zero; $i++) {
        Start-Sleep -Milliseconds 100
        $main = Find-Window $putty.Id "PuTTY"
    }
    if ($main -eq [IntPtr]::Zero) { throw "PuTTY main window was not created" }

    $endpoint = $model = $transcript = $prompt = $ask = $apply = $status =
        [IntPtr]::Zero
    for ($i = 0; $i -lt 50; $i++) {
        $endpoint = [PuttyAiAutomation]::GetDlgItem($main, 0x710A)
        $model = [PuttyAiAutomation]::GetDlgItem($main, 0x710C)
        $transcript = [PuttyAiAutomation]::GetDlgItem($main, 0x7103)
        $prompt = [PuttyAiAutomation]::GetDlgItem($main, 0x7104)
        $ask = [PuttyAiAutomation]::GetDlgItem($main, 0x7105)
        $apply = [PuttyAiAutomation]::GetDlgItem($main, 0x7107)
        $status = [PuttyAiAutomation]::GetDlgItem($main, 0x7102)
        if (-not (@(
            $endpoint, $model, $transcript, $prompt, $ask, $apply, $status
        ) | Where-Object { $_ -eq [IntPtr]::Zero })) {
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (@($endpoint, $model, $transcript, $prompt, $ask, $apply, $status) |
        Where-Object { $_ -eq [IntPtr]::Zero }) {
        throw "One or more AI panel controls were not created"
    }

    # Exercise the real keyboard-message path. WM_SETTEXT alone would miss a
    # regression where PuTTY dispatches WM_KEYDOWN without producing WM_CHAR.
    [PuttyAiAutomation]::SendMessageText(
        $endpoint, 0x000C, [IntPtr]::Zero, "") | Out-Null
    [PuttyAiAutomation]::PostMessage(
        $endpoint, 0x0100, [IntPtr]0x58, [IntPtr]1) | Out-Null
    [PuttyAiAutomation]::PostMessage(
        $endpoint, 0x0101, [IntPtr]0x58, [IntPtr]0xC0000001L) | Out-Null
    Start-Sleep -Milliseconds 200
    if ((Get-WindowText $endpoint) -notmatch "^[xX]$") {
        throw "AI edit controls did not receive translated keyboard input"
    }

    [PuttyAiAutomation]::SendMessageText(
        $endpoint, 0x000C, [IntPtr]::Zero,
        "http://127.0.0.1:18080/v1/chat/completions") | Out-Null
    [PuttyAiAutomation]::SendMessageText(
        $model, 0x000C, [IntPtr]::Zero, "mock-model") | Out-Null
    [PuttyAiAutomation]::SendMessageText(
        $prompt, 0x000C, [IntPtr]::Zero,
        "Analyse the remote service and suggest a harmless command") | Out-Null
    [PuttyAiAutomation]::SendMessage(
        $main, 0x0111, [IntPtr]0x7105, $ask) | Out-Null

    $requestOk = $false
    for ($i = 0; $i -lt 100; $i++) {
        Start-Sleep -Milliseconds 100
        if ((Get-WindowText $status) -eq "Response received") {
            $requestOk = $true
            break
        }
    }
    if (-not $requestOk) {
        throw "AI request did not complete: $(Get-WindowText $status)"
    }

    $conversation = Get-WindowText $transcript
    if (-not $conversation.Contains("Remote model service is reachable")) {
        throw "AI response was not rendered in the transcript"
    }
    if (-not [PuttyAiAutomation]::IsWindowEnabled($apply)) {
        throw "Command candidate was not detected"
    }

    [PuttyAiAutomation]::PostMessage(
        $main, 0x0111, [IntPtr]0x7107, $apply) | Out-Null
    $confirmation = [IntPtr]::Zero
    for ($i = 0; $i -lt 30 -and $confirmation -eq [IntPtr]::Zero; $i++) {
        Start-Sleep -Milliseconds 100
        $confirmation = Find-Window $putty.Id "#32770" "PuTTY AI command confirmation"
    }
    if ($confirmation -eq [IntPtr]::Zero) {
        throw "Command confirmation dialog was not shown"
    }
    [PuttyAiAutomation]::SendMessage(
        $confirmation, 0x0111, [IntPtr]6, [IntPtr]::Zero) | Out-Null

    if ($Dangerous) {
        $secondConfirmation = [IntPtr]::Zero
        for ($i = 0; $i -lt 30 -and $secondConfirmation -eq [IntPtr]::Zero; $i++) {
            Start-Sleep -Milliseconds 100
            $secondConfirmation = Find-Window $putty.Id "#32770" "Second confirmation required"
        }
        if ($secondConfirmation -eq [IntPtr]::Zero) {
            throw "Dangerous command did not require a second confirmation"
        }
        [PuttyAiAutomation]::SendMessage(
            $secondConfirmation, 0x0111, [IntPtr]6, [IntPtr]::Zero) | Out-Null
    }

    Start-Sleep -Milliseconds 500
    if (-not (Get-WindowText $status).StartsWith("Command filled")) {
        throw "The application did not report a successful terminal fill"
    }

    $received = "(buffered by local line discipline)"
    if (Test-Path $capturePath) {
        $received = [Text.Encoding]::UTF8.GetString(
            [IO.File]::ReadAllBytes($capturePath))
        if ($received.Contains("`r") -or $received.Contains("`n")) {
            throw "PuTTY AI automatically sent Enter with the command"
        }
    }
    $expectedCommand = if ($Dangerous) {
        "rm -rf /tmp/putty-ai-test"
    } else {
        "echo putty-ai-ok"
    }
    if ($received -ne "(buffered by local line discipline)" -and
        $received -ne $expectedCommand) {
        throw "Unexpected terminal fill payload: '$received'"
    }

    [pscustomobject]@{
        AiRequest = "passed"
        MarkdownRender = "passed"
        CommandDetection = "passed"
        Confirmation = "passed"
        TerminalFill = "passed"
        AutoEnter = "not sent"
        RiskFlow = $(if ($Dangerous) { "double-confirmed" } else { "normal" })
        Payload = $received
    } | Format-List
}
finally {
    if ($putty -and (Get-Process -Id $putty.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $putty.Id -Force
    }
    if ($server -and (Get-Process -Id $server.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $server.Id -Force
    }

    $puttyRegistryKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        "Software\SimonTatham\PuTTY", $true)
    if ($puttyRegistryKey) {
        try {
            $puttyRegistryKey.DeleteSubKeyTree("AI", $false)
            if ($aiRegistryExisted) {
                $restoredKey = $puttyRegistryKey.CreateSubKey("AI")
                try {
                    foreach ($entry in $aiRegistrySnapshot) {
                        $restoredKey.SetValue($entry.Name, $entry.Value, $entry.Kind)
                    }
                }
                finally {
                    $restoredKey.Dispose()
                }
            }
        }
        finally {
            $puttyRegistryKey.Dispose()
        }
    }
}
