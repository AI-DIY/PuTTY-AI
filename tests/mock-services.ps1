param(
    [int]$HttpPort = 18080,
    [int]$RawPort = 18022,
    [int]$SshHoldPort = 18023,
    [Parameter(Mandatory = $true)]
    [string]$CapturePath,
    [Parameter(Mandatory = $true)]
    [string]$HttpCaptureDirectory,
    [switch]$Dangerous
)

$source = @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public static class PuttyAiMockServices
{
    public static void Run(
        int httpPort, int rawPort, int sshHoldPort, string capturePath,
        string httpCaptureDirectory, bool dangerous)
    {
        Task http = Task.Run(() => RunHttp(
            httpPort, httpCaptureDirectory, dangerous));
        Task raw = Task.Run(() => RunRaw(rawPort, capturePath));
        Task sshHold = Task.Run(() => RunSshHold(sshHoldPort));
        if (!Task.WaitAll(
                new[] { http, raw, sshHold }, TimeSpan.FromSeconds(120)))
            throw new TimeoutException("Mock services timed out");
    }

    private static string ReadHttpBody(
        NetworkStream stream, out string authorization)
    {
        MemoryStream headerBytes = new MemoryStream();
        int matched = 0;
        byte[] marker = new byte[] { 13, 10, 13, 10 };
        while (matched < marker.Length)
        {
            int value = stream.ReadByte();
            if (value < 0) throw new EndOfStreamException();
            headerBytes.WriteByte((byte)value);
            if (value == marker[matched])
                matched++;
            else
                matched = value == marker[0] ? 1 : 0;
        }

        string headers = Encoding.ASCII.GetString(headerBytes.ToArray());
        int contentLength = 0;
        authorization = "";
        foreach (string line in headers.Split(new[] { "\r\n" },
                                               StringSplitOptions.None))
        {
            if (line.StartsWith("Content-Length:",
                                StringComparison.OrdinalIgnoreCase))
                int.TryParse(line.Substring(15).Trim(), out contentLength);
            if (line.StartsWith("Authorization:",
                                StringComparison.OrdinalIgnoreCase))
                authorization = line.Substring(14).Trim();
        }

        byte[] body = new byte[contentLength];
        int total = 0;
        while (total < body.Length)
        {
            int count = stream.Read(body, total, body.Length - total);
            if (count <= 0) throw new EndOfStreamException();
            total += count;
        }
        return Encoding.UTF8.GetString(body);
    }

    private static void RunHttp(
        int port, string captureDirectory, bool dangerous)
    {
        TcpListener listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        try
        {
            for (int requestIndex = 1; requestIndex <= 3; requestIndex++)
            {
                using (TcpClient client = listener.AcceptTcpClient())
                using (NetworkStream stream = client.GetStream())
                {
                    string authorization;
                    string body = ReadHttpBody(stream, out authorization);
                    string requestPath = Path.Combine(
                        captureDirectory,
                        "mock-ai-request-" + requestIndex + ".json");
                    File.WriteAllText(
                        requestPath, body, new UTF8Encoding(false));
                    string authorizationPath = Path.Combine(
                        captureDirectory,
                        "mock-ai-authorization-" + requestIndex + ".txt");
                    File.WriteAllText(
                        authorizationPath, authorization,
                        new UTF8Encoding(false));

                    string[] deltas;
                    if (requestIndex == 1)
                    {
                        string command = dangerous ?
                            "rm -rf /tmp/putty-ai-test" : "echo putty-ai-ok";
                        deltas = new[] {
                            "## \u6a21\u62df\u5206\u6790\\n",
                            "- **\u8fdc\u7a0b\u6a21\u578b\u670d\u52a1\u53ef\u4ee5\u8bbf\u95ee**\u3002\\n\\n",
                            "> quote\\n\\n" +
                            "1. item with *italic*, ~~removed~~, `inline`, " +
                            "[docs](https://example.com)\\n\\n" +
                            "| col | value |\\n| --- | --- |\\n| A | B |\\n\\n",
                            "```bash\\n" + command + "\\n```"
                        };
                    }
                    else
                    {
                        deltas = new[] {
                            "\u53ef\u4ee5\u7ee7\u7eed\u5206\u6790\u3002",
                            "\u5f53\u524d\u4fe1\u606f\u8868\u660e\u670d\u52a1\u53ef\u8fbe\u3002",
                            "\u8fd9\u4e00\u8f6e\u4e0d\u9700\u8981\u63d0\u4f9b\u547d\u4ee4\u3002"
                        };
                    }
                    byte[] responseHeaders = Encoding.ASCII.GetBytes(
                        "HTTP/1.1 200 OK\r\n" +
                        "Content-Type: text/event-stream; charset=utf-8\r\n" +
                        "Cache-Control: no-cache\r\n" +
                        "Connection: close\r\n\r\n");
                    stream.Write(responseHeaders, 0, responseHeaders.Length);
                    foreach (string delta in deltas)
                    {
                        string json =
                            "data: {\"choices\":[{\"delta\":{\"content\":\"" +
                            delta + "\"}}]}\n\n";
                        byte[] payload = Encoding.UTF8.GetBytes(json);
                        stream.Write(payload, 0, payload.Length);
                        stream.Flush();
                        Thread.Sleep(350);
                    }
                    byte[] done = Encoding.ASCII.GetBytes("data: [DONE]\n\n");
                    stream.Write(done, 0, done.Length);
                    stream.Flush();
                }
            }
        }
        finally
        {
            listener.Stop();
        }
    }

    private static void RunRaw(int port, string capturePath)
    {
        TcpListener listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        try
        {
            Task[] sessions = new Task[5];
            for (int index = 0; index < sessions.Length; index++)
            {
                TcpClient client = listener.AcceptTcpClient();
                string sessionCapturePath = index == 0 ? capturePath : null;
                sessions[index] = Task.Run(() => RunRawSession(
                    client, sessionCapturePath));
            }
            Task.WaitAll(sessions);
        }
        finally
        {
            listener.Stop();
        }
    }

    private static void RunRawSession(TcpClient client, string capturePath)
    {
        using (client)
        using (NetworkStream stream = client.GetStream())
        {
            byte[] greeting = Encoding.UTF8.GetBytes(
                "PuTTY AI mock remote service ready\r\n$ ");
            stream.Write(greeting, 0, greeting.Length);
            stream.Flush();
            stream.ReadTimeout = 60000;
            byte[] buffer = new byte[8192];
            try
            {
                int count = stream.Read(buffer, 0, buffer.Length);
                if (capturePath != null && count > 0)
                {
                    byte[] received = new byte[count];
                    Buffer.BlockCopy(buffer, 0, received, 0, count);
                    File.WriteAllBytes(capturePath, received);
                }
            }
            catch (IOException)
            {
            }
        }
    }

    private static void RunSshHold(int port)
    {
        TcpListener listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        try
        {
            using (TcpClient client = listener.AcceptTcpClient())
            using (NetworkStream stream = client.GetStream())
            {
                byte[] banner = Encoding.ASCII.GetBytes(
                    "SSH-2.0-PuTTYAIRegression_1.0\r\n");
                stream.Write(banner, 0, banner.Length);
                stream.Flush();
                stream.ReadTimeout = 60000;
                byte[] buffer = new byte[8192];
                try
                {
                    while (stream.Read(buffer, 0, buffer.Length) > 0)
                    {
                    }
                }
                catch (IOException)
                {
                }
            }
        }
        finally
        {
            listener.Stop();
        }
    }
}
'@

Add-Type -TypeDefinition $source
[PuttyAiMockServices]::Run(
    $HttpPort, $RawPort, $SshHoldPort, $CapturePath, $HttpCaptureDirectory,
    $Dangerous.IsPresent)
