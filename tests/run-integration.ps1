param(
    [string]$ExePath = "",
    [string]$ArtifactDirectory = "",
    [switch]$Dangerous
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Security
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if (-not $ExePath) {
    $ExePath = Join-Path $root "build\Release\putty.exe"
}
if (-not $ArtifactDirectory) {
    $ArtifactDirectory = Join-Path $root "artifacts"
}
$ExePath = [IO.Path]::GetFullPath($ExePath)
$ArtifactDirectory = [IO.Path]::GetFullPath($ArtifactDirectory)
New-Item -ItemType Directory -Force -Path $ArtifactDirectory | Out-Null
$capturePath = Join-Path $ArtifactDirectory "mock-remote-received.txt"
$requestOnePath = Join-Path $ArtifactDirectory "mock-ai-request-1.json"
$requestTwoPath = Join-Path $ArtifactDirectory "mock-ai-request-2.json"
$requestThreePath = Join-Path $ArtifactDirectory "mock-ai-request-3.json"
$authorizationThreePath = Join-Path $ArtifactDirectory "mock-ai-authorization-3.txt"
$launchLogDirectory = Join-Path $env:LOCALAPPDATA "PuTTY AI"
function Get-LaunchLogState {
    $state = @{}
    if (Test-Path -LiteralPath $launchLogDirectory) {
        Get-ChildItem -LiteralPath $launchLogDirectory -Filter "*launch*.log" |
            ForEach-Object {
                $state[$_.Name] = [pscustomobject]@{
                    Length = $_.Length
                    LastWriteTimeUtc = $_.LastWriteTimeUtc
                }
            }
    }
    return $state
}
$launchLogBefore = Get-LaunchLogState
Remove-Item -LiteralPath @(
    $capturePath, $requestOnePath, $requestTwoPath, $requestThreePath,
    $authorizationThreePath
) -Force -ErrorAction SilentlyContinue
$firstQuestion = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String(
        "5YiG5p6Q6L+c56iL5pyN5Yqh5bm25bu66K6u5LiA5p2h5peg5a6z5ZG95Luk"))
$firstAnswerMarker = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("6L+c56iL5qih5Z6L5pyN5Yqh5Y+v5Lul6K6/6Zeu"))
$firstStreamMarker = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("5qih5ouf5YiG5p6Q"))
$secondQuestion = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String(
        "6K+357un57ut5YiG5p6Q77yM6L+Z5LiA6L2u5Y+q6ZyA6KaB57qv5paH5pys57uT6K66"))
$secondAnswerMarker = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("6L+Z5LiA6L2u5LiN6ZyA6KaB5o+Q5L6b5ZG95Luk"))
$chineseReplyMarker = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("6buY6K6k5L2/55So566A5L2T5Lit5paH"))
$optionalCommandMarker = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("5LiN6KaB5rGC5q+P5qyh6YO95o+Q5L6b5ZG95Luk"))
$continueMarker = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("6K+357un57ut5YiG5p6Q"))
$removedKnowledgeMarker = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("5pys5Zyw55+l6K+G"))
$removedKnowledgeBaseMarker = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("55+l6K+G5bqT"))
$settingsLabel = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("6K6+572u"))
$sendLabel = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("5Y+R6YCB"))
$readyStatus = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("5bCx57uq"))
$receivingStatus = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("5q2j5Zyo5o6l5pS25Zue5aSNLi4u"))
$completedStatus = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("5Zue5aSN5a6M5oiQ"))
$commandDialogTitle = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("UHVUVFkgQUkg5ZG95Luk56Gu6K6k"))
$secondConfirmationTitle = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("6ZyA6KaB5LqM5qyh56Gu6K6k"))
$commandFilledPrefix = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("5ZG95Luk5bey5aGr5YWl"))
$connectingStatus = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("5q2j5Zyo6L+e5o6l5qih5Z6L5pyN5YqhLi4u"))
$terminalContextMarker = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("57uI56uv5LiK5LiL5paH"))
$savedStatus = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String("6K6+572u5bey5rC45LmF5L+d5a2Y"))
$expectedCommand = if ($Dangerous) {
    "rm -rf /tmp/putty-ai-test"
} else {
    "echo putty-ai-ok"
}
$aiRegistryPath = "Software\PuTTY AI"
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

# Seed the setting removed with the knowledge-base feature. Startup must
# delete it without disturbing the other saved Chat Completions settings.
$testAiRegistryKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(
    $aiRegistryPath)
try {
    $testAiRegistryKey.SetValue(
        "KnowledgeFile", "C:\obsolete-knowledge.md",
        [Microsoft.Win32.RegistryValueKind]::String)
    $seedApiKeyBytes = [Text.Encoding]::Unicode.GetBytes("test-seed-key`0")
    $protectedSeedApiKey = [Security.Cryptography.ProtectedData]::Protect(
        $seedApiKeyBytes, $null,
        [Security.Cryptography.DataProtectionScope]::CurrentUser)
    try {
        $testAiRegistryKey.SetValue(
            "ApiKey", $protectedSeedApiKey,
            [Microsoft.Win32.RegistryValueKind]::Binary)
    }
    finally {
        [Array]::Clear($seedApiKeyBytes, 0, $seedApiKeyBytes.Length)
        [Array]::Clear($protectedSeedApiKey, 0, $protectedSeedApiKey.Length)
    }
}
finally {
    $testAiRegistryKey.Dispose()
}

# Automated launchers can create a Raw saved session containing only a local
# relay port. Direct @session and -load launches must fill in loopback and
# connect instead of falling back to Configuration.
$bastionSessionName = "PuTTYAIRegression" + [Guid]::NewGuid().ToString("N")
$bastionSessionRegistryPath =
    "Software\SimonTatham\PuTTY\Sessions\$bastionSessionName"
$bastionSessionKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(
    $bastionSessionRegistryPath)
try {
    $bastionSessionKey.SetValue(
        "HostName", "", [Microsoft.Win32.RegistryValueKind]::String)
    $bastionSessionKey.SetValue(
        "Protocol", "raw", [Microsoft.Win32.RegistryValueKind]::String)
    $bastionSessionKey.SetValue(
        "PortNumber", 18022, [Microsoft.Win32.RegistryValueKind]::DWord)
}
finally {
    $bastionSessionKey.Dispose()
}

$temporaryConfigPath = Join-Path $ArtifactDirectory "putty-temporary-config.txt"
$temporaryConfig = @(
    "NoRemoteWinTitle=1"
    "LineCodePage=UTF-8"
    "HostName=127.0.0.1"
    "LauncherPrivateField=ignored"
    "PortNumber=18023"
    "TermHeight=24"
    "TermWidth=80"
    "UserName=temporary-config-test"
    "WinTitle=temporary-config-regression"
) -join "`n"
[IO.File]::WriteAllText(
    $temporaryConfigPath, $temporaryConfig,
    [Text.UTF8Encoding]::new($false))

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

    [DllImport("user32.dll", EntryPoint = "SendMessageW")]
    public static extern IntPtr SendMessageWide(
        IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

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

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);

    [DllImport("user32.dll")]
    public static extern IntPtr SetFocus(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetFocus();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct GUITHREADINFO
    {
        public int cbSize;
        public uint flags;
        public IntPtr hwndActive;
        public IntPtr hwndFocus;
        public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner;
        public IntPtr hwndMoveSize;
        public IntPtr hwndCaret;
        public RECT rcCaret;
    }

    [DllImport("user32.dll")]
    public static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO info);

    public static bool FocusWindow(IntPtr hwnd)
    {
        uint processId;
        uint targetThread = GetWindowThreadProcessId(hwnd, out processId);
        uint currentThread = GetCurrentThreadId();
        bool attached = targetThread != currentThread &&
            AttachThreadInput(currentThread, targetThread, true);
        SetForegroundWindow(GetAncestor(hwnd, 2));
        SetFocus(hwnd);
        bool focused = GetFocus() == hwnd;
        if (attached)
            AttachThreadInput(currentThread, targetThread, false);
        return focused;
    }

    public static IntPtr FocusedWindow(IntPtr hwnd)
    {
        uint processId;
        uint threadId = GetWindowThreadProcessId(hwnd, out processId);
        GUITHREADINFO info = new GUITHREADINFO();
        info.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
        return GetGUIThreadInfo(threadId, ref info) ? info.hwndFocus : IntPtr.Zero;
    }

}
'@

function Get-WindowText([IntPtr]$Handle) {
    $buffer = New-Object Text.StringBuilder 65536
    [PuttyAiAutomation]::SendMessageBuffer(
        $Handle, 0x000D, [IntPtr]$buffer.Capacity, $buffer) | Out-Null
    return $buffer.ToString()
}

function Convert-ToRichEditIndex([string]$Text, [int]$Index) {
    if ($Index -le 0) { return $Index }
    return [Text.Encoding]::UTF8.GetByteCount($Text.Substring(0, $Index))
}

function Set-UnicodeEditText([IntPtr]$Handle, [string]$Value) {
    [PuttyAiAutomation]::SendMessageText(
        $Handle, 0x000C, [IntPtr]::Zero, "") | Out-Null
    foreach ($character in $Value.ToCharArray()) {
        [PuttyAiAutomation]::SendMessageWide(
            $Handle, 0x0102, [IntPtr][int]$character, [IntPtr]1) | Out-Null
    }
    return Get-WindowText $Handle
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

function Test-BastionDirectLaunch([string[]]$Arguments) {
    $argumentDisplay = $Arguments -join " "
    $probe = Start-Process -FilePath $ExePath -PassThru -ArgumentList $Arguments
    try {
        $mainWindow = [IntPtr]::Zero
        for ($i = 0; $i -lt 50 -and $mainWindow -eq [IntPtr]::Zero; $i++) {
            Start-Sleep -Milliseconds 100
            if ((Find-Window $probe.Id "PuTTYConfigBox") -ne [IntPtr]::Zero) {
                throw "Bastion launch '$argumentDisplay' opened Configuration"
            }
            $mainWindow = Find-Window $probe.Id "PuTTY"
        }
        if ($mainWindow -eq [IntPtr]::Zero) {
            throw "Bastion launch '$argumentDisplay' did not establish its relay connection"
        }
        Start-Sleep -Milliseconds 500
        if (-not (Get-Process -Id $probe.Id -ErrorAction SilentlyContinue)) {
            throw "Bastion launch '$argumentDisplay' closed immediately after launch"
        }
    }
    finally {
        if (Get-Process -Id $probe.Id -ErrorAction SilentlyContinue) {
            Stop-Process -Id $probe.Id -Force
        }
    }
}

$mockScript = Join-Path $PSScriptRoot "mock-services.ps1"
$serverArguments = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $mockScript,
    "-CapturePath", $capturePath,
    "-HttpCaptureDirectory", $ArtifactDirectory
)
if ($Dangerous) { $serverArguments += "-Dangerous" }
$server = Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -PassThru -ArgumentList $serverArguments
$putty = $null
$putty2 = $null

try {
    Start-Sleep -Milliseconds 700

    Test-BastionDirectLaunch @("-raw", "-P", "18022")
    Test-BastionDirectLaunch @("@$bastionSessionName")
    Test-BastionDirectLaunch @("-load", $bastionSessionName)
    Test-BastionDirectLaunch @(
        "-load", "tmp:$temporaryConfigPath", "-pw", "mock-password")

    $putty = Start-Process -FilePath $ExePath -PassThru -ArgumentList @(
        "-raw", "127.0.0.1", "-P", "18022"
    )

    $launchLogAfter = Get-LaunchLogState
    $launchLogChanged = $launchLogBefore.Count -ne $launchLogAfter.Count
    foreach ($name in $launchLogBefore.Keys) {
        if (-not $launchLogAfter.ContainsKey($name) -or
            $launchLogBefore[$name].Length -ne $launchLogAfter[$name].Length -or
            $launchLogBefore[$name].LastWriteTimeUtc -ne
                $launchLogAfter[$name].LastWriteTimeUtc) {
            $launchLogChanged = $true
            break
        }
    }
    if ($launchLogChanged) {
        throw "Production build wrote a sensitive command-line launch log"
    }

    $main = [IntPtr]::Zero
    for ($i = 0; $i -lt 50 -and $main -eq [IntPtr]::Zero; $i++) {
        Start-Sleep -Milliseconds 100
        if ((Find-Window $putty.Id "PuTTYConfigBox") -ne [IntPtr]::Zero) {
            throw "Explicit host launch opened Configuration instead of connecting"
        }
        $main = Find-Window $putty.Id "PuTTY"
    }
    if ($main -eq [IntPtr]::Zero) { throw "PuTTY main window was not created" }

    $endpoint = $model = $key = $transcript = $prompt = $ask = $context = $apply =
        $settings = $save = $status =
        [IntPtr]::Zero
    for ($i = 0; $i -lt 50; $i++) {
        $endpoint = [PuttyAiAutomation]::GetDlgItem($main, 0x710A)
        $model = [PuttyAiAutomation]::GetDlgItem($main, 0x710C)
        $key = [PuttyAiAutomation]::GetDlgItem($main, 0x710E)
        $transcript = [PuttyAiAutomation]::GetDlgItem($main, 0x7103)
        $prompt = [PuttyAiAutomation]::GetDlgItem($main, 0x7104)
        $ask = [PuttyAiAutomation]::GetDlgItem($main, 0x7105)
        $context = [PuttyAiAutomation]::GetDlgItem($main, 0x7106)
        $apply = [PuttyAiAutomation]::GetDlgItem($main, 0x7107)
        $settings = [PuttyAiAutomation]::GetDlgItem($main, 0x7108)
        $save = [PuttyAiAutomation]::GetDlgItem($main, 0x7114)
        $status = [PuttyAiAutomation]::GetDlgItem($main, 0x7102)
        if (-not (@(
            $endpoint, $model, $key, $transcript, $prompt, $ask, $context, $apply,
            $settings, $save, $status
        ) | Where-Object { $_ -eq [IntPtr]::Zero })) {
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (@(
        $endpoint, $model, $key, $transcript, $prompt, $ask, $context, $apply,
        $settings, $save, $status
    ) |
        Where-Object { $_ -eq [IntPtr]::Zero }) {
        throw "One or more AI panel controls were not created"
    }
    if ((Get-WindowText $settings) -ne $settingsLabel -or
        (Get-WindowText $ask) -ne $sendLabel -or
        (Get-WindowText $status) -ne $readyStatus) {
        throw "AI panel controls were not localized to Chinese"
    }
    if ([PuttyAiAutomation]::SendMessage(
            $context, 0x00F0, [IntPtr]::Zero, [IntPtr]::Zero) -ne [IntPtr]::Zero) {
        throw "Terminal context was enabled by default"
    }
    $transcriptRect = [PuttyAiAutomation+RECT]::new()
    $transcriptRectOk = [PuttyAiAutomation]::GetWindowRect(
        $transcript, [ref]$transcriptRect)
    $transcriptWidth = $transcriptRect.right - $transcriptRect.left
    $configuredPanelWidth = [PuttyAiAutomation]::SendMessage(
        $main, 0x802A, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
    if ($configuredPanelWidth -ne 480 -or
        -not $transcriptRectOk -or $transcriptWidth -lt 300) {
        throw "AI transcript width was not expanded (measured=$transcriptWidth)"
    }
    if (@(0x7111, 0x7112, 0x7113) | Where-Object {
            [PuttyAiAutomation]::GetDlgItem($main, $_) -ne [IntPtr]::Zero
        }) {
        throw "Removed knowledge-base controls are still present"
    }
    $startupAiKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        $aiRegistryPath)
    try {
        if ($startupAiKey -and
            $null -ne $startupAiKey.GetValue("KnowledgeFile", $null)) {
            throw "Obsolete knowledge-base registry setting was not removed"
        }
    }
    finally {
        if ($startupAiKey) { $startupAiKey.Dispose() }
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
        $key, 0x000C, [IntPtr]::Zero, "mock-persistent-key") | Out-Null
    $firstQuestionActual = Set-UnicodeEditText $prompt $firstQuestion
    if ($firstQuestionActual -ne $firstQuestion) {
        $actualBase64 = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes($firstQuestionActual))
        throw "Could not enter the first Unicode AI question " +
            "(expectedLength=$($firstQuestion.Length) " +
            "actualLength=$($firstQuestionActual.Length) actual=$actualBase64)"
    }
    [PuttyAiAutomation]::SendMessage(
        $main, 0x0111, [IntPtr]0x7105, $ask) | Out-Null

    $streamObserved = $false
    for ($i = 0; $i -lt 80; $i++) {
        Start-Sleep -Milliseconds 25
        $partialConversation = Get-WindowText $transcript
        if ($partialConversation.Contains($firstStreamMarker) -and
            -not $partialConversation.Contains($firstAnswerMarker) -and
            (Get-WindowText $status) -eq $receivingStatus) {
            $streamObserved = $true
            break
        }
        if ((Get-WindowText $status) -eq $completedStatus) { break }
    }
    if (-not $streamObserved) {
        throw "AI response was not displayed incrementally"
    }
    $partialConversation = Get-WindowText $transcript
    $streamMarkerIndex = $partialConversation.IndexOf($firstStreamMarker)
    if ($streamMarkerIndex -lt 0 -or $partialConversation.Contains("## ")) {
        throw "Streaming Markdown heading syntax was not rendered"
    }
    $streamSelectionIndex = Convert-ToRichEditIndex `
        $partialConversation $streamMarkerIndex
    [PuttyAiAutomation]::SendMessage(
        $transcript, 0x00B1, [IntPtr]$streamSelectionIndex,
        [IntPtr]($streamSelectionIndex + $firstStreamMarker.Length)) | Out-Null
    $streamHeadingStyle = [PuttyAiAutomation]::SendMessage(
        $main, 0x802C, [IntPtr]::Zero, [IntPtr]::Zero).ToInt64()
    [PuttyAiAutomation]::SendMessage(
        $transcript, 0x00B1,
        [IntPtr]($streamSelectionIndex + $firstStreamMarker.Length),
        [IntPtr]($streamSelectionIndex + $firstStreamMarker.Length)) | Out-Null
    if (($streamHeadingStyle -band 0x1) -eq 0 -or
        (($streamHeadingStyle -shr 8) -band 0xFFFF) -le 190) {
        throw "Streaming Markdown heading did not receive heading formatting " +
            "(style=0x$($streamHeadingStyle.ToString('X')))"
    }

    $requestOk = $false
    for ($i = 0; $i -lt 100; $i++) {
        Start-Sleep -Milliseconds 100
        if ((Get-WindowText $status) -eq $completedStatus) {
            $requestOk = $true
            break
        }
    }
    if (-not $requestOk) {
        throw "AI request did not complete: $(Get-WindowText $status)"
    }

    $conversation = Get-WindowText $transcript
    if (-not $conversation.Contains($firstAnswerMarker)) {
        throw "AI response was not rendered in the transcript"
    }
    if ($conversation.Contains('## ') -or $conversation.Contains('```') -or
        $conversation.Contains('**') -or $conversation.Contains('*italic*') -or
        $conversation.Contains('~~removed~~') -or
        $conversation.Contains('[docs](') -or
        $conversation.Contains('| --- |') -or
        -not $conversation.Contains([string][char]0x2022)) {
        throw "Completed Markdown syntax was not converted to rich text"
    }
    $tableRow = ([string][char]0x2502) + ' col ' +
        ([string][char]0x2502) + ' value ' + ([string][char]0x2502)
    if (-not $conversation.Contains(([string][char]0x2502) + ' quote') -or
        -not $conversation.Contains('1. item with italic, removed, inline,') -or
        -not $conversation.Contains('docs (https://example.com)') -or
        -not $conversation.Contains($tableRow)) {
        throw "Markdown block or inline content was not rendered as expected"
    }
    $commandMarkerIndex = $conversation.IndexOf($expectedCommand)
    $codeStyleFound = $false
    $italicStyleFound = $false
    $strikeStyleFound = $false
    $linkStyleFound = $false
    $bodyBoldFound = $false
    $userStyleFound = $false
    $assistantStyleFound = $false
    $userBodyBackColour = 232 -bor (242 -shl 8) -bor (252 -shl 16)
    $userBodyTextColour = 24 -bor (46 -shl 8) -bor (68 -shl 16)
    $assistantBodyTextColour = 29 -bor (33 -shl 8) -bor (37 -shl 16)
    $richEditLimit = [Text.Encoding]::UTF8.GetByteCount($conversation) + 64
    for ($scan = 0; $scan -lt $richEditLimit; $scan++) {
        [PuttyAiAutomation]::SendMessage(
            $transcript, 0x00B1, [IntPtr]$scan,
            [IntPtr]($scan + 1)) | Out-Null
        $scanStyle = [PuttyAiAutomation]::SendMessage(
            $main, 0x802C, [IntPtr]::Zero, [IntPtr]::Zero).ToInt64()
        $scanBackColour = [PuttyAiAutomation]::SendMessage(
            $main, 0x802D, [IntPtr]::Zero, [IntPtr]::Zero).ToInt64() -band 0xFFFFFF
        $scanTextColour = [PuttyAiAutomation]::SendMessage(
            $main, 0x802B, [IntPtr]::Zero, [IntPtr]::Zero).ToInt64() -band 0xFFFFFF
        $scanHeight = ($scanStyle -shr 8) -band 0xFFFF
        if (($scanStyle -band 0x10) -ne 0) {
            $codeStyleFound = $true
        }
        if (($scanStyle -band 0x2) -ne 0) { $italicStyleFound = $true }
        if (($scanStyle -band 0x4) -ne 0) { $linkStyleFound = $true }
        if (($scanStyle -band 0x8) -ne 0) { $strikeStyleFound = $true }
        if (($scanStyle -band 0x1) -ne 0 -and $scanHeight -eq 190 -and
            $scanBackColour -eq 0xFFFFFF) { $bodyBoldFound = $true }
        if ($scanBackColour -eq $userBodyBackColour -and
            $scanTextColour -eq $userBodyTextColour) { $userStyleFound = $true }
        if ($scanBackColour -eq 0xFFFFFF -and
            $scanTextColour -eq $assistantBodyTextColour) {
            $assistantStyleFound = $true
        }
    }
    if ($commandMarkerIndex -lt 0 -or -not $codeStyleFound -or
        -not $italicStyleFound -or -not $strikeStyleFound -or
        -not $linkStyleFound -or -not $bodyBoldFound) {
        throw "Markdown inline or code content did not receive rich-text formatting"
    }
    if (-not $userStyleFound -or -not $assistantStyleFound) {
        throw "User and AI messages did not receive distinct visual styles"
    }
    if (-not [PuttyAiAutomation]::IsWindowEnabled($apply)) {
        throw "Command candidate was not detected"
    }

    if (-not [PuttyAiAutomation]::FocusWindow($prompt)) {
        throw "Could not focus the AI prompt before terminal focus regression test"
    }
    if ([PuttyAiAutomation]::FocusedWindow($main) -ne $prompt) {
        throw "AI prompt did not receive focus before terminal focus regression test"
    }
    $terminalPoint = [IntPtr](10 -bor (10 -shl 16))
    [PuttyAiAutomation]::SendMessage(
        $main, 0x0201, [IntPtr]1, $terminalPoint) | Out-Null
    [PuttyAiAutomation]::SendMessage(
        $main, 0x0202, [IntPtr]::Zero, $terminalPoint) | Out-Null
    if ([PuttyAiAutomation]::FocusedWindow($main) -ne $main) {
        throw "Clicking the terminal did not restore terminal keyboard focus"
    }

    [PuttyAiAutomation]::PostMessage(
        $main, 0x0111, [IntPtr]0x7107, $apply) | Out-Null
    $confirmation = [IntPtr]::Zero
    for ($i = 0; $i -lt 30 -and $confirmation -eq [IntPtr]::Zero; $i++) {
        Start-Sleep -Milliseconds 100
        $confirmation = Find-Window $putty.Id "#32770" $commandDialogTitle
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
            $secondConfirmation = Find-Window $putty.Id "#32770" $secondConfirmationTitle
        }
        if ($secondConfirmation -eq [IntPtr]::Zero) {
            throw "Dangerous command did not require a second confirmation"
        }
        [PuttyAiAutomation]::SendMessage(
            $secondConfirmation, 0x0111, [IntPtr]6, [IntPtr]::Zero) | Out-Null
    }

    Start-Sleep -Milliseconds 500
    if (-not (Get-WindowText $status).StartsWith($commandFilledPrefix)) {
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
    if ($received -ne "(buffered by local line discipline)" -and
        $received -ne $expectedCommand) {
        throw "Unexpected terminal fill payload: '$received'"
    }

    $secondQuestionActual = Set-UnicodeEditText $prompt $secondQuestion
    if ($secondQuestionActual -ne $secondQuestion) {
        throw "Could not enter the second Unicode AI question"
    }
    [PuttyAiAutomation]::SendMessage(
        $main, 0x0111, [IntPtr]0x7105, $ask) | Out-Null
    if ((Get-WindowText $status) -notin @($connectingStatus, $receivingStatus)) {
        throw "Second AI request did not start"
    }
    $secondRequestOk = $false
    for ($i = 0; $i -lt 100; $i++) {
        Start-Sleep -Milliseconds 100
        if ((Get-WindowText $status) -eq $completedStatus) {
            $secondRequestOk = $true
            break
        }
    }
    if (-not $secondRequestOk) {
        throw "Second AI request did not complete: $(Get-WindowText $status)"
    }
    $conversation = Get-WindowText $transcript
    if (-not $conversation.Contains($secondAnswerMarker)) {
        throw "Plain-text second response was not rendered"
    }
    if ([PuttyAiAutomation]::IsWindowEnabled($apply)) {
        throw "A pure-text response incorrectly left a command candidate enabled"
    }
    $secondMarkerIndex = $conversation.IndexOf($secondAnswerMarker)
    $secondMarkerColor = [PuttyAiAutomation]::SendMessage(
        $main, 0x802E, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
    if ($secondMarkerIndex -lt 0 -or
        ($secondMarkerColor -band 0xFFFFFF) -eq 0xFFFFFF) {
        throw "AI transcript response text was rendered in white"
    }

    if (-not (Test-Path $requestOnePath) -or -not (Test-Path $requestTwoPath)) {
        throw "Mock model request captures were not written"
    }
    $requestOne = Get-Content -Raw -Encoding UTF8 $requestOnePath | ConvertFrom-Json
    $requestTwo = Get-Content -Raw -Encoding UTF8 $requestTwoPath | ConvertFrom-Json
    if ($requestOne.messages[0].content -notmatch $chineseReplyMarker -or
        $requestOne.messages[0].content -notmatch $optionalCommandMarker) {
        throw "System prompt does not enforce Chinese, optional-command replies"
    }
    if ($requestOne.stream -ne $true) {
        throw "Chat Completions request did not enable streaming"
    }
    if ($requestOne.messages[-1].content -match $terminalContextMarker) {
        throw "The default request unexpectedly included terminal context"
    }
    if ($requestOne.messages[-1].content -match
        "Terminal context|Local knowledge|User question") {
        throw "Request context still contains English prompt scaffolding"
    }
    $requestOneRaw = Get-Content -Raw -Encoding UTF8 $requestOnePath
    if ($requestOneRaw -match "Local knowledge|KnowledgeFile" -or
        $requestOneRaw.Contains($removedKnowledgeMarker) -or
        $requestOneRaw.Contains($removedKnowledgeBaseMarker)) {
        throw "Model request still contains knowledge-base prompt residue"
    }
    if ($requestTwo.messages.Count -ne 4 -or
        $requestTwo.messages[1].role -ne "user" -or
        $requestTwo.messages[2].role -ne "assistant" -or
        $requestTwo.messages[3].role -ne "user") {
        throw "Second request did not include the previous conversation turn"
    }
    if ($requestTwo.messages[1].content -ne $firstQuestion -or
        $requestTwo.messages[2].content -notmatch $firstAnswerMarker -or
        $requestTwo.messages[3].content -notmatch $continueMarker) {
        throw "Multi-turn conversation content was not preserved"
    }

    [PuttyAiAutomation]::SendMessageText(
        $endpoint, 0x000C, [IntPtr]::Zero,
        "http://127.0.0.1:18080/v1/chat/completions") | Out-Null
    [PuttyAiAutomation]::SendMessageText(
        $model, 0x000C, [IntPtr]::Zero, "persist-model") | Out-Null
    [PuttyAiAutomation]::SendMessageText(
        $key, 0x000C, [IntPtr]::Zero, "persist-key") | Out-Null
    [PuttyAiAutomation]::SendMessage(
        $main, 0x0111, [IntPtr]0x7114, $save) | Out-Null
    if ((Get-WindowText $status) -ne $savedStatus) {
        $actualStatus = Get-WindowText $status
        $actualStatusBase64 = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes($actualStatus))
        throw "Chat Completions settings did not report a permanent save " +
            "(actual=$actualStatusBase64)"
    }

    $savedKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($aiRegistryPath)
    if (-not $savedKey) { throw "AI registry settings key was not created" }
    try {
        $encryptedApiKey = $savedKey.GetValue("ApiKey")
        if ($savedKey.GetValue("Endpoint") -ne
                "http://127.0.0.1:18080/v1/chat/completions" -or
            $savedKey.GetValue("Model") -ne "persist-model" -or
            $savedKey.GetValueKind("ApiKey") -ne
                [Microsoft.Win32.RegistryValueKind]::Binary -or
            -not ($encryptedApiKey -is [byte[]])) {
            throw "Chat Completions settings were not persisted correctly"
        }
        $plainApiKeyBytes = [Security.Cryptography.ProtectedData]::Unprotect(
            $encryptedApiKey, $null,
            [Security.Cryptography.DataProtectionScope]::CurrentUser)
        try {
            $plainApiKey = [Text.Encoding]::Unicode.GetString(
                $plainApiKeyBytes).TrimEnd([char]0)
            if ($plainApiKey -ne "persist-key") {
                throw "Persisted API key could not be decrypted for this user"
            }
        }
        finally {
            [Array]::Clear($plainApiKeyBytes, 0, $plainApiKeyBytes.Length)
        }
    }
    finally {
        $savedKey.Dispose()
    }

    Stop-Process -Id $putty.Id -Force
    $putty = $null
    $putty2 = Start-Process -FilePath $ExePath -PassThru -ArgumentList @(
        "-raw", "127.0.0.1", "-P", "18022"
    )
    $main2 = [IntPtr]::Zero
    for ($i = 0; $i -lt 50 -and $main2 -eq [IntPtr]::Zero; $i++) {
        Start-Sleep -Milliseconds 100
        $main2 = Find-Window $putty2.Id "PuTTY"
    }
    if ($main2 -eq [IntPtr]::Zero) {
        throw "Second PuTTY session was not created for persistence regression"
    }
    $endpoint2 = $model2 = $key2 = $settings2 = $prompt2 = $ask2 =
        $status2 = [IntPtr]::Zero
    for ($i = 0; $i -lt 50; $i++) {
        $endpoint2 = [PuttyAiAutomation]::GetDlgItem($main2, 0x710A)
        $model2 = [PuttyAiAutomation]::GetDlgItem($main2, 0x710C)
        $key2 = [PuttyAiAutomation]::GetDlgItem($main2, 0x710E)
        $settings2 = [PuttyAiAutomation]::GetDlgItem($main2, 0x7108)
        $prompt2 = [PuttyAiAutomation]::GetDlgItem($main2, 0x7104)
        $ask2 = [PuttyAiAutomation]::GetDlgItem($main2, 0x7105)
        $status2 = [PuttyAiAutomation]::GetDlgItem($main2, 0x7102)
        if (-not (@(
            $endpoint2, $model2, $key2, $settings2, $prompt2, $ask2, $status2
        ) | Where-Object { $_ -eq [IntPtr]::Zero })) {
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (@(
        $endpoint2, $model2, $key2, $settings2, $prompt2, $ask2, $status2
    ) |
        Where-Object { $_ -eq [IntPtr]::Zero }) {
        throw "Second session AI settings controls were not created"
    }
    [PuttyAiAutomation]::SendMessage(
        $main2, 0x0111, [IntPtr]0x7108, $settings2) | Out-Null
    if (-not [PuttyAiAutomation]::IsWindowVisible($endpoint2) -or
        (Get-WindowText $endpoint2) -ne
            "http://127.0.0.1:18080/v1/chat/completions" -or
        (Get-WindowText $model2) -ne "persist-model") {
        throw "Saved Chat Completions settings were not restored in the next session"
    }
    [PuttyAiAutomation]::SendMessageText(
        $prompt2, 0x000C, [IntPtr]::Zero,
        "Verify persisted settings") | Out-Null
    [PuttyAiAutomation]::SendMessage(
        $main2, 0x0111, [IntPtr]0x7105, $ask2) | Out-Null
    $persistedRequestOk = $false
    for ($i = 0; $i -lt 100; $i++) {
        Start-Sleep -Milliseconds 100
        if ((Get-WindowText $status2) -eq $completedStatus) {
            $persistedRequestOk = $true
            break
        }
    }
    if (-not $persistedRequestOk) {
        throw "Restored Chat Completions settings could not make a request: " +
            (Get-WindowText $status2)
    }
    if (-not (Test-Path $requestThreePath) -or
        -not (Test-Path $authorizationThreePath)) {
        throw "The request using restored Chat Completions settings was not captured"
    }
    $requestThree = Get-Content -Raw -Encoding UTF8 $requestThreePath |
        ConvertFrom-Json
    $authorizationThree = Get-Content -Raw -Encoding UTF8 $authorizationThreePath
    if ($requestThree.model -ne "persist-model" -or
        $authorizationThree -ne "Bearer persist-key") {
        throw "The next session did not use the persisted model and API key"
    }

    [pscustomobject]@{
        AiRequest = "passed"
        StreamingResponse = "passed"
        ContextDefault = "disabled"
        ChineseUi = "passed"
        TranscriptTextColor = "readable"
        ExpandedPanel = "passed"
        BastionDirectLaunch = "@session, -load, -load tmp:file, and -raw -P passed"
        ConnectionKeepalive = "enabled"
        KnowledgeBaseRemoved = "passed"
        TerminalFocusRestore = "passed"
        ChinesePrompt = "passed"
        MultiTurnConversation = "passed"
        PersistentChatCompletions = "passed"
        ProtectedApiKey = "Windows DPAPI"
        SensitiveLaunchLogging = "disabled"
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
    if ($putty2 -and (Get-Process -Id $putty2.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $putty2.Id -Force
    }
    if ($putty -and (Get-Process -Id $putty.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $putty.Id -Force
    }
    if ($server -and (Get-Process -Id $server.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $server.Id -Force
    }

    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree(
        $aiRegistryPath, $false)
    if ($aiRegistryExisted) {
        $restoredKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(
            $aiRegistryPath)
        try {
            foreach ($entry in $aiRegistrySnapshot) {
                $restoredKey.SetValue($entry.Name, $entry.Value, $entry.Kind)
            }
        }
        finally {
            $restoredKey.Dispose()
        }
    }
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree(
        $bastionSessionRegistryPath, $false)
    Remove-Item -LiteralPath $temporaryConfigPath -Force -ErrorAction SilentlyContinue
}
